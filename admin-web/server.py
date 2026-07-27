#!/usr/bin/env python3
"""
IGProxy local web admin.

The service is intentionally bound to 127.0.0.1:1984. Operators reach it
through an SSH tunnel; it must never be exposed directly on the public network.
"""

from __future__ import annotations

import csv
import concurrent.futures
import fcntl
import hashlib
import ipaddress
import json
import math
import mimetypes
import os
import re
import secrets
import shlex
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


ADMIN_DIR = Path(os.getenv("GOTELEGRAM_ADMIN_DIR", "/opt/gotelegram-admin"))
STATIC_DIR = Path(os.getenv("GOTELEGRAM_ADMIN_STATIC", str(ADMIN_DIR / "static")))

GOTELEGRAM_CONFIG = Path(os.getenv("GOTELEGRAM_CONFIG", "/opt/gotelegram/config.json"))
TELEMT_CONFIG = Path(os.getenv("TELEMT_CONFIG", "/etc/telemt/config.toml"))
TELEMT_BIN = Path(os.getenv("TELEMT_BIN", "/usr/local/bin/telemt"))
TELEMT_PROXY_CONFIG_V4 = Path(os.getenv(
    "TELEMT_PROXY_CONFIG_V4",
    "/var/lib/telemt/cache/proxy-config-v4.txt",
))
HISTORY_FILE = Path(os.getenv("GOTELEGRAM_STATS_HISTORY", "/opt/gotelegram/stats_history.csv"))
USER_HISTORY_FILE = Path(os.getenv("GOTELEGRAM_USER_STATS_HISTORY", "/opt/gotelegram/user_stats_history.csv"))
CURRENT_STATS = Path(os.getenv("GOTELEGRAM_STATS_CURRENT", "/run/gotelegram/stats_current.json"))
BACKUP_DIR = Path(os.getenv("GOTELEGRAM_BACKUP_DIR", "/opt/gotelegram/backups"))
INSTALL_DIR = Path(os.getenv("GOTELEGRAM_DIR", "/opt/gotelegram"))
BOT_DIR = Path(os.getenv("GOTELEGRAM_BOT_DIR", "/opt/gotelegram-bot"))
DISABLED_USERS_FILE = Path(os.getenv("GOTELEGRAM_DISABLED_USERS", "/opt/gotelegram/disabled_users.json"))
USER_LOCK_FILE = Path(os.getenv("GOTELEGRAM_USER_LOCK", "/run/gotelegram/admin-users.lock"))
SHARED_443_CONFIG = Path(os.getenv("GOTELEGRAM_SHARED_443", "/opt/gotelegram/shared-443.json"))
BACKUP_SCHEDULE_FILE = Path(os.getenv("GOTELEGRAM_BACKUP_SCHEDULE", "/opt/gotelegram/backup_schedule.json"))
BACKUP_RESTORE_LOG = Path(os.getenv("GOTELEGRAM_BACKUP_RESTORE_LOG", "/var/log/gotelegram-restore.log"))
WEBSITE_ROOT = Path(os.getenv("GOTELEGRAM_WEBSITE_ROOT", "/var/www/gotelegram-site"))
SITE_PRESETS_DIR = Path(os.getenv("GOTELEGRAM_SITE_PRESETS", "/opt/gotelegram/current/site-presets"))
HOST = os.getenv("GOTELEGRAM_ADMIN_HOST", "127.0.0.1")
PORT = int(os.getenv("GOTELEGRAM_ADMIN_PORT", "1984"))
VERSION = "2.12.1"  # fallback only; live value read from config.json
RUNTIME_COMMON_PATHS = (
    INSTALL_DIR / "current" / "lib" / "common.sh",
    Path(__file__).resolve().parents[1] / "lib" / "common.sh",
)
USER_RE = re.compile(r"^[A-Za-z0-9_.-]{1,48}$")
LANG_RE = re.compile(r"^(en|ru)$")
SENSITIVE_CONFIG_KEYS = {"secret"}
BACKUP_NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+\.tar\.gz(\.(enc|gpg))?$")
MAX_UNIQUE_IP_LIMIT = 1000000
TELEMT_RESTART_DEBOUNCE_SECONDS = float(os.getenv("GOTELEGRAM_TELEMT_RESTART_DEBOUNCE", "8"))
_LAST_TELEMT_RESTART = 0.0
_HEALTH_CACHE: dict[str, Any] | None = None
_HEALTH_CACHE_AT = 0.0
_HEALTH_CACHE_SECONDS = float(os.getenv("GOTELEGRAM_HEALTH_CACHE_SECONDS", "15"))
_HEALTH_LOCK = threading.Lock()
TELEMT_DC_MAX_CONFIG_BYTES = 1024 * 1024
TELEMT_DC_MAX_ENDPOINTS = 64
TELEMT_DC_ALLOWED_PORTS = {443, 8888}
TRAFFIC_WINDOWS = {
    "15m": 15 * 60,
    "1h": 60 * 60,
    "6h": 6 * 60 * 60,
    "24h": 24 * 60 * 60,
    "7d": 7 * 24 * 60 * 60,
    "month": 30 * 24 * 60 * 60,
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def system_metrics() -> dict[str, Any]:
    """Return a small, dependency-free Linux host snapshot."""
    cpu_count = max(1, os.cpu_count() or 1)
    try:
        load_1, load_5, load_15 = os.getloadavg()
    except OSError:
        load_1 = load_5 = load_15 = 0.0

    memory: dict[str, int] = {}
    try:
        for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
            key, raw = line.split(":", 1)
            memory[key] = int(raw.strip().split()[0]) * 1024
    except (OSError, ValueError, IndexError):
        pass

    mem_total = memory.get("MemTotal", 0)
    mem_available = memory.get("MemAvailable", memory.get("MemFree", 0))
    mem_used = max(0, mem_total - mem_available)
    swap_total = memory.get("SwapTotal", 0)
    swap_free = memory.get("SwapFree", 0)
    swap_used = max(0, swap_total - swap_free)

    try:
        disk_total, disk_used, disk_free = shutil.disk_usage("/")
    except OSError:
        disk_total = disk_used = disk_free = 0

    try:
        uptime_seconds = int(float(Path("/proc/uptime").read_text().split()[0]))
    except (OSError, ValueError, IndexError):
        uptime_seconds = 0

    return {
        "hostname": socket.gethostname(),
        "cpu_count": cpu_count,
        "cpu_percent": round(min(100.0, max(0.0, load_1 / cpu_count * 100)), 1),
        "load": [round(load_1, 2), round(load_5, 2), round(load_15, 2)],
        "memory": {
            "total": mem_total,
            "used": mem_used,
            "percent": round(mem_used / mem_total * 100, 1) if mem_total else 0,
        },
        "swap": {
            "total": swap_total,
            "used": swap_used,
            "percent": round(swap_used / swap_total * 100, 1) if swap_total else 0,
        },
        "disk": {
            "total": disk_total,
            "used": disk_used,
            "free": disk_free,
            "percent": round(disk_used / disk_total * 100, 1) if disk_total else 0,
        },
        "uptime_seconds": uptime_seconds,
    }


def run(cmd: list[str], timeout: int = 8) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except Exception as exc:  # pragma: no cover - system dependent
        return 125, "", str(exc)


def run_bytes(cmd: list[str], timeout: int = 8) -> tuple[int, bytes, str]:
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout, proc.stderr.decode("utf-8", errors="replace")
    except Exception as exc:  # pragma: no cover - system dependent
        return 125, b"", str(exc)


class FileLock:
    def __init__(self, path: Path):
        self.path = path
        self.handle: Any = None

    def __enter__(self) -> "FileLock":
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.handle = self.path.open("w", encoding="utf-8")
        fcntl.flock(self.handle.fileno(), fcntl.LOCK_EX)
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        if self.handle:
            fcntl.flock(self.handle.fileno(), fcntl.LOCK_UN)
            self.handle.close()


def load_json(path: Path, fallback: Any = None) -> Any:
    try:
        with path.open("r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return fallback


def save_json(path: Path, data: Any, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")
    os.chmod(tmp, mode)
    tmp.replace(path)


def read_language(config: dict[str, Any] | None = None) -> str:
    config = config or load_json(GOTELEGRAM_CONFIG, {}) or {}
    lang = str(config.get("language") or config.get("lang") or "").strip().lower()
    marker = INSTALL_DIR / ".language"
    if lang not in {"en", "ru"} and marker.exists():
        try:
            lang = marker.read_text(encoding="utf-8", errors="ignore").strip().lower()[:2]
        except OSError:
            lang = ""
    return lang if lang in {"en", "ru"} else "en"


def public_config(config: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in config.items() if key not in SENSITIVE_CONFIG_KEYS}


def appearance_payload(config: dict[str, Any] | None = None) -> dict[str, Any]:
    config = config or load_json(GOTELEGRAM_CONFIG, {}) or {}
    brand_name = str(config.get("brand_name") or "IGProxy").strip()[:48]
    sponsor_name = str(config.get("sponsor_name") or "Спонсорский канал").strip()[:64]
    sponsor_url = str(config.get("sponsor_url") or "").strip()
    return {
        "brand_enabled": bool(config.get("brand_enabled", True)),
        "brand_name": brand_name or "IGProxy",
        "sponsor_enabled": bool(config.get("sponsor_enabled", False)),
        "sponsor_name": sponsor_name or "Спонсорский канал",
        "sponsor_url": sponsor_url,
    }


def _validate_public_url(value: str, *, telegram_only: bool = False) -> str:
    value = value.strip()
    if not value:
        return ""
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("нужна публичная HTTPS-ссылка")
    if telegram_only and parsed.hostname.lower() not in {"t.me", "telegram.me", "telegram.dog"}:
        raise ValueError("канал должен быть ссылкой вида https://t.me/...")
    return value


def client_servers_payload(config: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    config = config or load_json(GOTELEGRAM_CONFIG, {}) or {}
    raw = config.get("client_servers")
    if not isinstance(raw, list):
        return []
    result: list[dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        label = str(item.get("label") or "").strip()[:48]
        url = str(item.get("url") or "").strip()
        item_id = re.sub(r"[^a-z0-9_-]", "", str(item.get("id") or "").lower())[:24]
        if label and url:
            result.append({
                "id": item_id or hashlib.sha256(f"{label}\0{url}".encode()).hexdigest()[:8],
                "label": label,
                "url": url,
                "enabled": bool(item.get("enabled", True)),
            })
    return result


def save_client_servers(raw: Any) -> list[dict[str, Any]]:
    if not isinstance(raw, list):
        raise ValueError("servers must be a list")
    if len(raw) > 32:
        raise ValueError("можно добавить не более 32 серверов")
    servers: list[dict[str, Any]] = []
    used_ids: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            raise ValueError("некорректная запись сервера")
        label = str(item.get("label") or "").strip()
        if not label or len(label) > 48:
            raise ValueError("подпись сервера должна содержать от 1 до 48 символов")
        url = _validate_public_url(str(item.get("url") or ""))
        item_id = re.sub(r"[^a-z0-9_-]", "", str(item.get("id") or "").lower())[:24]
        while not item_id or item_id in used_ids:
            item_id = secrets.token_hex(4)
        used_ids.add(item_id)
        servers.append({
            "id": item_id,
            "label": label,
            "url": url,
            "enabled": bool(item.get("enabled", True)),
        })
    config = load_json(GOTELEGRAM_CONFIG, {}) or {}
    config["client_servers"] = servers
    config["updated_at"] = utc_now()
    save_json(GOTELEGRAM_CONFIG, config)
    return servers


MINI_APP_BRIDGE = """<!-- igproxy-mini-app -->
<script src="https://telegram.org/js/telegram-web-app.js"></script>
<script>
(()=>{const w=window.Telegram&&window.Telegram.WebApp,a=document.getElementById("connect");
if(!w||!a)return;w.ready();w.expand();a.addEventListener("click",e=>{
const u=a.href;if(/^https:\\/\\/t\\.me\\/proxy\\?/i.test(u)){e.preventDefault();w.openTelegramLink(u);}
});})();
</script>"""


def add_mini_app_bridge(source: str) -> str:
    if "igproxy-mini-app" in source:
        return source
    if re.search(r"</body\s*>", source, flags=re.IGNORECASE):
        return re.sub(
            r"</body\s*>",
            MINI_APP_BRIDGE + "\n</body>",
            source,
            count=1,
            flags=re.IGNORECASE,
        )
    return source + "\n" + MINI_APP_BRIDGE


SITE_PRESETS = {
    "random-gallery": {
        "name": "Рандомный сайт",
        "description": "При каждом открытии выбирается самостоятельная композиция со своим стилем.",
        "source": "random-gallery",
        "layout": "auto",
    },
    "story-editorial": {
        "name": "Ночная редакция",
        "description": "Светлая газетная обложка с крупной антиквой и заметками на полях.",
        "source": "random-gallery",
        "layout": "editorial",
    },
    "story-transit": {
        "name": "Лунное депо",
        "description": "Контрастное транспортное табло с маршрутной схемой и вагоном.",
        "source": "random-gallery",
        "layout": "transit",
    },
    "story-cartography": {
        "name": "Картографы дождя",
        "description": "Бумажная карта с координатами, штампами и новой линией маршрута.",
        "source": "random-gallery",
        "layout": "cartography",
    },
    "story-terminal": {
        "name": "Тихая мастерская",
        "description": "Инженерный терминал с зелёным свечением и журналом маршрута.",
        "source": "random-gallery",
        "layout": "terminal",
    },
    "story-botanical": {
        "name": "Оранжерея мостов",
        "description": "Мягкий ботанический атлас с органическими формами и гербарием.",
        "source": "random-gallery",
        "layout": "botanical",
    },
    "story-postcard": {
        "name": "Облачная почта",
        "description": "Воздушная почтовая открытка с марками, конвертом и чистым небом.",
        "source": "random-gallery",
        "layout": "postcard",
    },
    "story-tearoom": {
        "name": "Чайная у перевала",
        "description": "Тёплое меню старой чайной с картой второго перевала.",
        "source": "random-gallery",
        "layout": "tearoom",
    },
    "story-beacon": {
        "name": "Бумажный маяк",
        "description": "Морская сигнальная панель с сильной геометрией и лучом маяка.",
        "source": "random-gallery",
        "layout": "beacon",
    },
    "story-poster": {
        "name": "Оркестр обходных нот",
        "description": "Яркий музыкальный постер с типографикой и ритмичными формами.",
        "source": "random-gallery",
        "layout": "poster",
    },
    "story-playground": {
        "name": "Сад воздушных троп",
        "description": "Игровая иллюстрация с улиткой, мягкими карточками и тропой.",
        "source": "random-gallery",
        "layout": "playground",
    },
    "route-workshop": {
        "name": "Маршрутная мастерская",
        "description": "Playful 3D-заглушка с улитками, картой и светящимися маршрутами.",
    },
    "glass-garden": {
        "name": "Сад за стеклом",
        "description": "Светлая басня о хранителях дверей и бумажных птицах.",
    },
    "open-library": {
        "name": "Библиотека открытых окон",
        "description": "Ночная история о совах, ставнях и книгах-лодках.",
    },
}


def site_settings_payload() -> dict[str, Any]:
    config = load_json(GOTELEGRAM_CONFIG, {}) or {}
    records = read_user_records()
    return {
        "preset": str(config.get("site_preset") or "random-gallery"),
        "key": str(config.get("site_key") or ("main" if "main" in records else "")),
        "presets": [
            {
                "id": key,
                "name": value["name"],
                "description": value["description"],
                "available": (
                    SITE_PRESETS_DIR / str(value.get("source") or key) / "index.html"
                ).exists(),
            }
            for key, value in SITE_PRESETS.items()
        ],
        "keys": [
            {"name": name, "enabled": bool(record.get("enabled"))}
            for name, record in sorted(records.items(), key=lambda item: (item[0] != "main", item[0]))
        ],
    }


def _enabled_site_key(key_name: str) -> tuple[dict[str, Any], str]:
    records = read_user_records()
    record = records.get(key_name)
    if not record or not record.get("enabled"):
        raise ValueError("select an enabled key")
    return record, proxy_link(str(record["secret"]))


def _publish_site_stage(stage: Path, preset: str, key_name: str) -> dict[str, Any]:
    previous = WEBSITE_ROOT.parent / ".igproxy-site-previous"
    os.chmod(stage, 0o755)
    for root, dirs, files in os.walk(stage):
        for dirname in dirs:
            os.chmod(Path(root) / dirname, 0o755)
        for filename in files:
            os.chmod(Path(root) / filename, 0o644)
    if previous.exists():
        shutil.rmtree(previous)
    if WEBSITE_ROOT.exists():
        WEBSITE_ROOT.replace(previous)
    stage.replace(WEBSITE_ROOT)
    config = load_json(GOTELEGRAM_CONFIG, {}) or {}
    config["site_preset"] = preset
    config["site_key"] = key_name
    config["template_id"] = f"igproxy-{preset}"
    config["updated_at"] = utc_now()
    save_json(GOTELEGRAM_CONFIG, config)
    return site_settings_payload()


def apply_site_preset(preset: str, key_name: str) -> dict[str, Any]:
    if preset not in SITE_PRESETS:
        raise ValueError("unknown site preset")
    _, link = _enabled_site_key(key_name)
    definition = SITE_PRESETS[preset]
    source = SITE_PRESETS_DIR / str(definition.get("source") or preset)
    if not (source / "index.html").is_file():
        raise FileNotFoundError("site preset is not installed")
    WEBSITE_ROOT.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".igproxy-site-", dir=str(WEBSITE_ROOT.parent)))
    previous = WEBSITE_ROOT.parent / ".igproxy-site-previous"
    try:
        shutil.copytree(source, stage, dirs_exist_ok=True)
        for page in stage.rglob("*.html"):
            rendered = (
                page.read_text(encoding="utf-8")
                .replace("__PROXY_LINK__", link)
                .replace("__LAYOUT__", str(definition.get("layout") or "auto"))
            )
            page.write_text(add_mini_app_bridge(rendered), encoding="utf-8")
        return _publish_site_stage(stage, preset, key_name)
    except Exception:
        if not WEBSITE_ROOT.exists() and previous.exists():
            previous.replace(WEBSITE_ROOT)
        raise
    finally:
        if stage.exists():
            shutil.rmtree(stage, ignore_errors=True)


def apply_custom_site(html_source: str, key_name: str) -> dict[str, Any]:
    """Publish a single static HTML page from the local admin."""
    source = str(html_source or "")
    encoded = source.encode("utf-8")
    if not 80 <= len(encoded) <= 512 * 1024:
        raise ValueError("HTML must be between 80 bytes and 512 KB")
    lowered = source.lower()
    if "<html" not in lowered or "</html>" not in lowered:
        raise ValueError("upload a complete HTML document")
    if "__PROXY_LINK__" not in source:
        raise ValueError("HTML must contain __PROXY_LINK__")
    if "<?php" in lowered or "<!--#include" in lowered or "<!--#exec" in lowered:
        raise ValueError("server-side code is not allowed")
    _, link = _enabled_site_key(key_name)
    WEBSITE_ROOT.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".igproxy-site-", dir=str(WEBSITE_ROOT.parent)))
    previous = WEBSITE_ROOT.parent / ".igproxy-site-previous"
    try:
        (stage / "index.html").write_text(
            add_mini_app_bridge(source.replace("__PROXY_LINK__", link)),
            encoding="utf-8",
        )
        return _publish_site_stage(stage, "custom", key_name)
    except Exception:
        if not WEBSITE_ROOT.exists() and previous.exists():
            previous.replace(WEBSITE_ROOT)
        raise
    finally:
        if stage.exists():
            shutil.rmtree(stage, ignore_errors=True)


def write_language(lang: str) -> dict[str, Any]:
    lang = str(lang or "").strip().lower()
    if not LANG_RE.match(lang):
        raise ValueError("unsupported language")
    config = load_json(GOTELEGRAM_CONFIG, {}) or {}
    if not isinstance(config, dict):
        config = {}
    config["language"] = lang
    config["updated_at"] = utc_now()
    save_json(GOTELEGRAM_CONFIG, config)
    INSTALL_DIR.mkdir(parents=True, exist_ok=True)
    (INSTALL_DIR / ".language").write_text(lang + "\n", encoding="utf-8")
    bot_env = BOT_DIR / ".env"
    if bot_env.exists():
        lines = bot_env.read_text(encoding="utf-8", errors="ignore").splitlines()
        found = False
        out = []
        for line in lines:
            if line.startswith("BOT_LANG="):
                out.append(f"BOT_LANG={lang}")
                found = True
            else:
                out.append(line)
        if not found:
            out.append(f"BOT_LANG={lang}")
        bot_env.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
        os.chmod(bot_env, 0o600)
    return {"language": lang}


def read_telemt_users() -> dict[str, str]:
    if not TELEMT_CONFIG.exists():
        return {}
    users: dict[str, str] = {}
    in_users = False
    for raw in TELEMT_CONFIG.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if line == "[access.users]":
            in_users = True
            continue
        if in_users and line.startswith("["):
            break
        if not in_users or not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        name = parse_toml_key(name)
        value = value.strip().split("#", 1)[0].strip()
        if value.startswith('"') and '"' in value[1:]:
            value = value[1:].split('"', 1)[0]
        elif value.startswith("'") and "'" in value[1:]:
            value = value[1:].split("'", 1)[0]
        if USER_RE.match(name) and value:
            users[name] = value
    return users


def read_toml_int_table(table: str) -> dict[str, int]:
    if not TELEMT_CONFIG.exists():
        return {}
    values: dict[str, int] = {}
    section = f"[{table}]"
    in_table = False
    for raw in TELEMT_CONFIG.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if line == section:
            in_table = True
            continue
        if in_table and line.startswith("["):
            break
        if not in_table or not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        name = parse_toml_key(name)
        if not USER_RE.match(name):
            continue
        raw_value = value.strip().split("#", 1)[0].strip().strip('"').strip("'")
        try:
            number = int(raw_value)
        except ValueError:
            continue
        values[name] = max(0, number)
    return values


def read_user_max_unique_ips() -> dict[str, int]:
    return read_toml_int_table("access.user_max_unique_ips")


def read_disabled_users() -> dict[str, str]:
    raw = load_json(DISABLED_USERS_FILE, {}) or {}
    if not isinstance(raw, dict):
        return {}
    users = raw.get("users") if isinstance(raw.get("users"), dict) else raw
    if not isinstance(users, dict):
        return {}
    clean: dict[str, str] = {}
    for name, secret in users.items():
        if name in {"version", "updated_at"}:
            continue
        name_s = str(name).strip()
        secret_s = str(secret or "").strip()
        if USER_RE.match(name_s) and secret_s:
            clean[name_s] = secret_s
    return clean


def write_disabled_users(users: dict[str, str]) -> None:
    payload = {
        "version": 1,
        "updated_at": utc_now(),
        "users": {name: users[name] for name in sorted(users)},
    }
    save_json(DISABLED_USERS_FILE, payload)


def read_user_records() -> dict[str, dict[str, Any]]:
    active = read_telemt_users()
    disabled = read_disabled_users()
    ip_limits = read_user_max_unique_ips()
    records: dict[str, dict[str, Any]] = {}
    for name, secret in disabled.items():
        records[name] = {"secret": secret, "enabled": False, "max_unique_ips": ip_limits.get(name, 0)}
    for name, secret in active.items():
        records[name] = {"secret": secret, "enabled": True, "max_unique_ips": ip_limits.get(name, 0)}
    return records


def _ordered_user_lines(users: dict[str, str]) -> list[str]:
    names = []
    if "main" in users:
        names.append("main")
    names.extend(sorted(n for n in users if n != "main"))
    return [f'{quote_toml_key(name)} = "{users[name]}"' for name in names]


def _ordered_user_int_lines(values: dict[str, int]) -> list[str]:
    positive: dict[str, int] = {}
    for name, value in values.items():
        name_s = str(name)
        if not USER_RE.match(name_s):
            continue
        try:
            number = int(value)
        except (TypeError, ValueError):
            continue
        if number > 0:
            positive[name_s] = number
    names = []
    if "main" in positive:
        names.append("main")
    names.extend(sorted(n for n in positive if n != "main"))
    return [f'{quote_toml_key(name)} = {positive[name]}' for name in names]


def parse_toml_key(raw: str) -> str:
    key = raw.strip()
    if len(key) >= 2 and key[0] == key[-1] == '"':
        try:
            return json.loads(key)
        except json.JSONDecodeError:
            return key[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    if len(key) >= 2 and key[0] == key[-1] == "'":
        return key[1:-1]
    return key


def quote_toml_key(name: str) -> str:
    escaped = name.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def write_telemt_users(users: dict[str, str]) -> None:
    TELEMT_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    lines = TELEMT_CONFIG.read_text(encoding="utf-8", errors="ignore").splitlines() if TELEMT_CONFIG.exists() else []
    rendered = _ordered_user_lines(users)
    out: list[str] = []
    in_users = False
    found = False

    for raw in lines:
        if raw.strip() == "[access.users]":
            found = True
            in_users = True
            out.append(raw)
            out.extend(rendered)
            continue
        if in_users and raw.strip().startswith("["):
            in_users = False
        if in_users:
            continue
        out.append(raw)

    if not found:
        if out and out[-1].strip():
            out.append("")
        out.append("[access.users]")
        out.extend(rendered)

    tmp = TELEMT_CONFIG.with_name(TELEMT_CONFIG.name + ".tmp")
    tmp.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(TELEMT_CONFIG)


def write_toml_int_table(table: str, values: dict[str, int]) -> None:
    TELEMT_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    lines = TELEMT_CONFIG.read_text(encoding="utf-8", errors="ignore").splitlines() if TELEMT_CONFIG.exists() else []
    rendered = _ordered_user_int_lines(values)
    header = f"[{table}]"
    out: list[str] = []
    in_table = False
    found = False

    for raw in lines:
        if raw.strip() == header:
            found = True
            in_table = True
            if rendered:
                out.append(raw)
                out.extend(rendered)
            continue
        if in_table and raw.strip().startswith("["):
            in_table = False
        if in_table:
            continue
        out.append(raw)

    if not found and rendered:
        if out and out[-1].strip():
            out.append("")
        out.append(header)
        out.extend(rendered)

    tmp = TELEMT_CONFIG.with_name(TELEMT_CONFIG.name + ".tmp")
    tmp.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(TELEMT_CONFIG)


def write_user_max_unique_ips(values: dict[str, int]) -> None:
    write_toml_int_table("access.user_max_unique_ips", values)


def normalize_max_unique_ips(value: Any) -> int:
    try:
        number = int(value)
    except (TypeError, ValueError):
        raise ValueError("max_unique_ips must be an integer") from None
    if number < 0 or number > MAX_UNIQUE_IP_LIMIT:
        raise ValueError(f"max_unique_ips must be between 0 and {MAX_UNIQUE_IP_LIMIT}")
    return number


def restart_service(name: str) -> bool:
    code, _, _ = run(["systemctl", "restart", name], timeout=25)
    if code != 0:
        return False
    if name == "telemt":
        return wait_tcp_port(read_telemt_port(), timeout=90)
    return True


def request_service_restart(name: str) -> bool:
    global _LAST_TELEMT_RESTART
    if name == "telemt":
        now = time.monotonic()
        if _LAST_TELEMT_RESTART > 0 and now - _LAST_TELEMT_RESTART < TELEMT_RESTART_DEBOUNCE_SECONDS:
            status = service_status(name)
            if status in {"running", "activating"}:
                return True
        run(["systemctl", "reset-failed", name], timeout=5)
        _LAST_TELEMT_RESTART = now
    code, _, _ = run(["systemctl", "--no-block", "restart", name], timeout=5)
    return code == 0


def service_status(name: str) -> str:
    code, stdout, _ = run(["systemctl", "is-active", name], timeout=3)
    value = stdout.strip()
    if code == 0 and value == "active":
        return "running"
    code, stdout, _ = run(["systemctl", "list-unit-files", f"{name}.service", "--no-legend"], timeout=3)
    if code != 0 or not stdout.strip():
        return "not_installed"
    if value in {"failed", "inactive", "activating", "deactivating"}:
        return value
    return "stopped"


def read_telemt_port() -> int:
    if not TELEMT_CONFIG.exists():
        return 443
    in_server = False
    for raw in TELEMT_CONFIG.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if line == "[server]":
            in_server = True
            continue
        if in_server and line.startswith("["):
            break
        if in_server and line.startswith("port") and "=" in line:
            try:
                return int(line.split("=", 1)[1].strip().split("#", 1)[0])
            except ValueError:
                return 443
    return 443


def _is_port_addr(value: str, port: int) -> bool:
    token = value.strip()
    if token.startswith("[") and "]:" in token:
        return token.rsplit(":", 1)[-1] == str(port)
    return token.rsplit(":", 1)[-1] == str(port) if ":" in token else False


def _process_role(process: str) -> str:
    lowered = process.lower()
    if "telemt" in lowered or "mtproto" in lowered:
        return "mtproxy"
    if "nginx" in lowered or "apache" in lowered or "caddy" in lowered:
        return "site"
    if "xray" in lowered or "x-ui" in lowered or "3x-ui" in lowered or "xui" in lowered:
        return "xray"
    if "amnezia" in lowered or "awg" in lowered or "wireguard" in lowered or re.search(r"\bwg\b", lowered):
        return "amneziawg"
    return "other"


def parse_ss_listeners(output: str, proto: str, port: int = 443) -> list[dict[str, Any]]:
    listeners: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str]] = set()
    for line in output.splitlines():
        parts = line.split()
        address = next((part for part in parts if _is_port_addr(part, port)), "")
        if not address:
            continue
        matches = re.findall(r'\("([^"]+)",pid=(\d+)', line)
        if matches:
            process_names = []
            pids = []
            for proc, pid in matches:
                if proc not in process_names:
                    process_names.append(proc)
                if pid not in pids:
                    pids.append(pid)
            process = ", ".join(process_names)
            pid_text = ", ".join(pids)
        else:
            process = "unknown"
            pid_text = ""
        key = (proto, address, process)
        if key in seen:
            continue
        seen.add(key)
        listeners.append({
            "proto": proto.upper(),
            "address": address,
            "process": process,
            "pid": pid_text,
            "role": _process_role(process),
        })
    return listeners


def collect_port_listeners(port: int) -> tuple[list[dict[str, Any]], list[str]]:
    listeners: list[dict[str, Any]] = []
    errors: list[str] = []
    for proto, args in {
        "tcp": ["ss", "-H", "-ltnp"],
        "udp": ["ss", "-H", "-lunp"],
    }.items():
        code, stdout, stderr = run(args, timeout=2)
        if code == 0:
            listeners.extend(parse_ss_listeners(stdout, proto, port))
        elif stderr.strip():
            errors.append(stderr.strip())
    listeners.sort(key=lambda item: (item["proto"], item["address"], item["process"]))
    return listeners, errors


def read_telemt_edge_settings() -> dict[str, Any]:
    settings: dict[str, Any] = {"tls_domain": "", "mask_port": 0, "dns_overrides": []}
    if not TELEMT_CONFIG.exists():
        return settings
    section = ""
    for raw in TELEMT_CONFIG.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line.strip("[]")
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().split("#", 1)[0].strip()
        if section == "censorship" and key == "tls_domain":
            settings["tls_domain"] = value.strip('"').strip("'")
        elif section == "censorship" and key == "mask_port":
            try:
                settings["mask_port"] = int(value)
            except ValueError:
                settings["mask_port"] = 0
        elif section == "network" and key == "dns_overrides":
            settings["dns_overrides"] = re.findall(r'"([^"]+)"', value)
    return settings


def load_shared443_config() -> dict[str, Any]:
    raw = load_json(SHARED_443_CONFIG, {}) or {}
    if not isinstance(raw, dict):
        return {}
    routes = raw.get("xray_routes") if isinstance(raw.get("xray_routes"), list) else []
    clean_routes = []
    for item in routes:
        if not isinstance(item, dict):
            continue
        public = str(item.get("public") or item.get("domain") or "").strip()
        target = str(item.get("target") or "").strip()
        if public and target:
            clean_routes.append({"public": public, "target": target})
    return {
        "enabled": bool(raw.get("enabled")),
        "dispatcher": str(raw.get("dispatcher") or "nginx-stream"),
        "public_port": _int_value(raw.get("public_port") or 443) or 443,
        "telemt_target": str(raw.get("telemt_target") or "127.0.0.1:7443"),
        "site_target": str(raw.get("site_target") or ""),
        "xray_routes": clean_routes,
        "updated_at": str(raw.get("updated_at") or ""),
    }


def listener_for_target(target: str) -> dict[str, Any] | None:
    try:
        port = int(target.rsplit(":", 1)[-1])
    except ValueError:
        return None
    listeners, _ = collect_port_listeners(port)
    return listeners[0] if listeners else None


def routed_behind_443() -> list[dict[str, Any]]:
    config = load_json(GOTELEGRAM_CONFIG, {}) or {}
    mode = str(config.get("mode") or "")
    domain = str(config.get("domain") or "")
    public_port = _int_value(config.get("port") or 443) or 443
    settings = read_telemt_edge_settings()
    shared = load_shared443_config()
    mask_port = int(settings.get("mask_port") or 0)
    tls_domain = str(settings.get("tls_domain") or domain)
    routes: list[dict[str, Any]] = []
    if shared.get("enabled"):
        telemt_target = str(shared.get("telemt_target") or "127.0.0.1:7443")
        telemt_listener = listener_for_target(telemt_target)
        routes.append({
            "role": "mtproxy",
            "proto": "MTProxy",
            "public": f"{domain or tls_domain or 'default'}:443",
            "target": telemt_target,
            "process": (telemt_listener or {}).get("process") or "telemt",
            "pid": (telemt_listener or {}).get("pid") or "",
            "status": service_status("telemt"),
            "via": "nginx stream ssl_preread",
            "tls_domain": tls_domain,
            "details": ["default -> telemt"] if not shared.get("xray_routes") else [],
        })
        for item in shared.get("xray_routes", []):
            target = item.get("target", "")
            listener = listener_for_target(target)
            public = item.get("public", "")
            if public and ":" not in public:
                public = f"{public}:443"
            routes.append({
                "role": "xray",
                "proto": "VLESS",
                "public": public or "xray:443",
                "target": target,
                "process": (listener or {}).get("process") or "xray",
                "pid": (listener or {}).get("pid") or "",
                "status": "running" if listener else "not_installed",
                "via": "nginx stream ssl_preread",
                "tls_domain": public.split(":", 1)[0] if public else "",
                "details": [],
            })
    if mode == "pro" and domain and mask_port and mask_port != 443:
        internal, _ = collect_port_listeners(mask_port)
        site_listener = next((item for item in internal if item.get("role") == "site"), None)
        routes.append({
            "role": "site",
            "proto": "HTTPS",
            "public": f"{domain}:{public_port}",
            "target": f"127.0.0.1:{mask_port}",
            "process": (site_listener or {}).get("process") or "nginx",
            "pid": (site_listener or {}).get("pid") or "",
            "status": service_status("nginx"),
            "via": "telemt dns_overrides",
            "tls_domain": tls_domain,
            "details": settings.get("dns_overrides") or [],
        })
    return routes


def port_443_status() -> dict[str, Any]:
    configured_port = read_telemt_port()
    listeners, errors = collect_port_listeners(configured_port)
    shared = load_shared443_config()
    if shared.get("enabled") and configured_port == 443:
        for item in listeners:
            if item.get("role") == "site" and "nginx" in str(item.get("process", "")).lower():
                item["role"] = "edge"
                item["details"] = "nginx stream ssl_preread"
    return {
        "checked_at": int(time.time()),
        "configured_port": configured_port,
        "listeners": listeners,
        "routes": routed_behind_443(),
        "shared_443": shared,
        "ok": not errors,
        "error": "; ".join(errors[:2]),
    }


def wait_tcp_port(port: int, timeout: int = 90) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if service_status("telemt") not in {"running", "activating"}:
            return False
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.6):
                return True
        except OSError:
            time.sleep(1)
    return False


def public_ip() -> str:
    code, stdout, _ = run(["curl", "-s", "-4", "--max-time", "3", "https://api.ipify.org"], timeout=5)
    ip = stdout.strip()
    if code == 0 and re.match(r"^\d{1,3}(\.\d{1,3}){3}$", ip):
        return ip
    code, stdout, _ = run(["hostname", "-I"], timeout=3)
    return stdout.split()[0] if code == 0 and stdout.split() else "0.0.0.0"


def proxy_link(secret: str) -> str:
    config = load_json(GOTELEGRAM_CONFIG, {}) or {}
    mode = str(config.get("mode", "lite"))
    port = int(config.get("port", 443) or 443)
    domain = str(config.get("domain", "") or "")
    mask_host = str(config.get("mask_host", "") or "")

    if mode == "pro" and domain:
        host_hex = domain.encode().hex()
        return f"https://t.me/proxy?server={domain}&port={port}&secret=ee{secret}{host_hex}"

    server = public_ip()
    if mask_host:
        host_hex = mask_host.encode().hex()
        return f"https://t.me/proxy?server={server}&port={port}&secret=ee{secret}{host_hex}"
    return f"https://t.me/proxy?server={server}&port={port}&secret={secret}"


def telemt_api(path: str) -> Any:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:9091{path}", timeout=1.8) as resp:
            payload = resp.read(256 * 1024)
        return json.loads(payload.decode("utf-8"))
    except Exception:
        return None


def read_telemt_health_settings() -> dict[str, Any]:
    settings: dict[str, Any] = {
        "use_middle_proxy": False,
        "client_mss": "",
        "client_mss_bulk": "",
        "port": read_telemt_port(),
    }
    if not TELEMT_CONFIG.exists():
        return settings
    section = ""
    for raw in TELEMT_CONFIG.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line.strip("[]")
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.split("#", 1)[0].strip().strip('"').strip("'")
        if section == "general" and key == "use_middle_proxy":
            settings["use_middle_proxy"] = value.lower() == "true"
        elif section == "server" and key in {"client_mss", "client_mss_bulk"}:
            settings[key] = value
        elif section == "server" and key == "port":
            settings["port"] = _int_value(value) or settings["port"]
    return settings


def telemt_binary_version() -> str:
    code, stdout, stderr = run([str(TELEMT_BIN), "--version"], timeout=3)
    if code != 0:
        return ""
    match = re.search(r"\b(\d+\.\d+\.\d+)\b", stdout or stderr)
    return match.group(1) if match else ""


def _mss_number(value: Any) -> int:
    raw = str(value or "").strip().lower()
    presets = {"extreme-low": 88, "tspu": 92, "2in8": 256}
    if raw in presets:
        return presets[raw]
    return _int_value(raw)


def parse_telemt_metrics(text: str) -> dict[str, float]:
    wanted = {
        "telemt_connections_total",
        "telemt_connections_bad_total",
        "telemt_handshake_timeouts_total",
        "telemt_upstream_connect_attempt_total",
        "telemt_upstream_connect_success_total",
        "telemt_upstream_connect_fail_total",
        "telemt_me_reconnect_attempts_total",
        "telemt_me_reconnect_success_total",
    }
    values: dict[str, float] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 2:
            continue
        metric = parts[0].split("{", 1)[0]
        if metric not in wanted:
            continue
        try:
            value = float(parts[1])
        except ValueError:
            continue
        if math.isfinite(value):
            values[metric] = values.get(metric, 0.0) + value
    return values


def telemt_metrics_snapshot() -> dict[str, float]:
    try:
        with urllib.request.urlopen("http://127.0.0.1:9090/metrics", timeout=1.8) as resp:
            payload = resp.read(512 * 1024)
        return parse_telemt_metrics(payload.decode("utf-8", errors="replace"))
    except Exception:
        return {}


def parse_telemt_dc_endpoints(text: str) -> list[dict[str, Any]]:
    endpoints: list[dict[str, Any]] = []
    seen: set[tuple[int, str, int]] = set()
    pattern = re.compile(r"^\s*proxy_for\s+(-?\d+)\s+(\d{1,3}(?:\.\d{1,3}){3}):(\d+)\s*;")
    for raw in text.splitlines():
        match = pattern.match(raw)
        if not match:
            continue
        dc = int(match.group(1))
        host = match.group(2)
        port = int(match.group(3))
        try:
            parsed = ipaddress.ip_address(host)
        except ValueError:
            continue
        if parsed.version != 4 or not parsed.is_global or port not in TELEMT_DC_ALLOWED_PORTS:
            continue
        key = (dc, host, port)
        if key in seen:
            continue
        seen.add(key)
        endpoints.append({"dc": dc, "host": host, "port": port})
        if len(endpoints) >= TELEMT_DC_MAX_ENDPOINTS:
            break
    return endpoints


def _probe_dc_endpoint(host: str, port: int, timeout: float = 0.9) -> dict[str, Any]:
    started = time.monotonic()
    try:
        with socket.create_connection((host, port), timeout=timeout):
            latency_ms = max(1, round((time.monotonic() - started) * 1000))
        return {"reachable": True, "latency_ms": latency_ms, "error": ""}
    except OSError as exc:
        reason = "timeout" if isinstance(exc, TimeoutError) else "connect_failed"
        return {"reachable": False, "latency_ms": 0, "error": reason}


def telemt_dc_health() -> dict[str, Any]:
    try:
        with TELEMT_PROXY_CONFIG_V4.open("rb") as stream:
            payload = stream.read(TELEMT_DC_MAX_CONFIG_BYTES + 1)
    except OSError:
        return {"available": False, "groups": [], "reachable": 0, "total": 0}
    if len(payload) > TELEMT_DC_MAX_CONFIG_BYTES:
        return {"available": False, "groups": [], "reachable": 0, "total": 0, "error": "config_too_large"}
    source = payload.decode("utf-8", errors="ignore")
    endpoints = parse_telemt_dc_endpoints(source)
    unique = sorted({(item["host"], item["port"]) for item in endpoints})
    results: dict[tuple[str, int], dict[str, Any]] = {}
    if unique:
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(unique))) as executor:
            futures = {
                executor.submit(_probe_dc_endpoint, host, port): (host, port)
                for host, port in unique
            }
            for future, key in futures.items():
                try:
                    results[key] = future.result(timeout=1.5)
                except Exception:
                    results[key] = {"reachable": False, "latency_ms": 0, "error": "probe_failed"}

    groups: list[dict[str, Any]] = []
    for dc in sorted({item["dc"] for item in endpoints}, key=lambda value: (abs(value), value < 0)):
        items = [item for item in endpoints if item["dc"] == dc]
        checked = []
        for item in items:
            result = results.get((item["host"], item["port"]), {})
            checked.append({
                "address": f'{item["host"]}:{item["port"]}',
                "reachable": bool(result.get("reachable")),
                "latency_ms": _int_value(result.get("latency_ms")),
            })
        reachable = sum(1 for item in checked if item["reachable"])
        groups.append({
            "dc": dc,
            "media": dc < 0,
            "endpoints": checked,
            "reachable": reachable,
            "total": len(checked),
            "status": "ok" if reachable else "error",
        })
    reachable_total = sum(1 for value in results.values() if value.get("reachable"))
    return {
        "available": True,
        "groups": groups,
        "reachable": reachable_total,
        "total": len(unique),
    }


def _me_pool_snapshot() -> dict[str, Any]:
    raw = telemt_api("/v1/runtime/me_pool_state")
    if not isinstance(raw, dict):
        return {"available": False}
    outer = raw.get("data") if isinstance(raw.get("data"), dict) else raw
    data = outer.get("data") if isinstance(outer.get("data"), dict) else outer
    writers = data.get("writers") if isinstance(data.get("writers"), dict) else {}
    generations = data.get("generations") if isinstance(data.get("generations"), dict) else {}
    hardswap = data.get("hardswap") if isinstance(data.get("hardswap"), dict) else {}
    health = writers.get("health") if isinstance(writers.get("health"), dict) else {}
    return {
        "available": True,
        "enabled": bool(outer.get("enabled", True)),
        "writers_total": _int_value(writers.get("total")),
        "writers_healthy": _int_value(health.get("healthy")),
        "writers_degraded": _int_value(health.get("degraded")),
        "writers_draining": _int_value(health.get("draining")),
        "active_generation": _int_value(generations.get("active_generation")),
        "warm_generation": _int_value(generations.get("warm_generation")),
        "hardswap_pending": bool(hardswap.get("pending")),
        "hardswap_pending_age_secs": _int_value(generations.get("pending_hardswap_age_secs")),
    }


def health_payload(force: bool = False) -> dict[str, Any]:
    global _HEALTH_CACHE, _HEALTH_CACHE_AT
    now = time.monotonic()
    if not force and _HEALTH_CACHE is not None and now - _HEALTH_CACHE_AT < _HEALTH_CACHE_SECONDS:
        return _HEALTH_CACHE
    with _HEALTH_LOCK:
        now = time.monotonic()
        if not force and _HEALTH_CACHE is not None and now - _HEALTH_CACHE_AT < _HEALTH_CACHE_SECONDS:
            return _HEALTH_CACHE

        service = service_status("telemt")
        version = telemt_binary_version()
        settings = read_telemt_health_settings()
        handshake_mss = _mss_number(settings.get("client_mss"))
        bulk_mss = _mss_number(settings.get("client_mss_bulk"))
        multiplier = math.ceil(1460 / handshake_mss) if handshake_mss else 1
        metrics = telemt_metrics_snapshot()
        attempts = metrics.get("telemt_upstream_connect_attempt_total", 0.0)
        success = metrics.get("telemt_upstream_connect_success_total", 0.0)
        upstream_success_percent = round(success / attempts * 100, 1) if attempts else 0.0
        connections = metrics.get("telemt_connections_total", 0.0)
        handshake_timeouts = metrics.get("telemt_handshake_timeouts_total", 0.0)
        handshake_timeout_percent = round(handshake_timeouts / connections * 100, 1) if connections else 0.0
        me_pool = _me_pool_snapshot()
        dc = telemt_dc_health()

        issues: list[dict[str, str]] = []
        if service != "running":
            issues.append({
                "level": "error",
                "title": "Ядро telemt не работает",
                "detail": "Прокси не принимает новые подключения.",
                "action": "Проверьте службу telemt и журнал запуска.",
            })
        if version and version != "3.4.25":
            issues.append({
                "level": "warn",
                "title": f"Установлен telemt {version}",
                "detail": "Для IGProxy 2.12.1 проверена версия 3.4.25.",
                "action": "Обновите ядро с резервной копией бинарника и конфига.",
            })
        if handshake_mss and not bulk_mss:
            issues.append({
                "level": "warn",
                "title": "Узкий MSS применяется к медиа",
                "detail": f"MSS {handshake_mss} увеличивает число пакетов примерно в {multiplier} раз.",
                "action": "Задайте client_mss_bulk = 1400.",
            })
        failed_groups = [item for item in dc.get("groups", []) if item.get("status") == "error"]
        for item in failed_groups:
            label = f'DC {item["dc"]}'
            issues.append({
                "level": "warn",
                "title": f"{label}: маршрут не ответил",
                "detail": "Ни один опубликованный Telegram endpoint этой группы не ответил на текущую TCP-проверку.",
                "action": "Если предупреждение держится постоянно и ME-пул деградирует, проверьте маршрут VPS или резервный egress.",
            })
        if me_pool.get("writers_degraded", 0) > 0:
            issues.append({
                "level": "warn",
                "title": "Есть деградировавшие ME-каналы",
                "detail": f'{me_pool["writers_degraded"]} из {me_pool.get("writers_total", 0)} writers требуют внимания.',
                "action": "Сопоставьте недоступные DC и рост upstream timeout.",
            })
        if me_pool.get("hardswap_pending") and me_pool.get("hardswap_pending_age_secs", 0) > 300:
            issues.append({
                "level": "warn",
                "title": "Обновление ME-пула задержалось",
                "detail": f'Ожидание длится {me_pool["hardswap_pending_age_secs"]} с.',
                "action": "Причина обычно в недоступном DC; перезапуск без исправления маршрута не поможет.",
            })
        if attempts and upstream_success_percent < 60:
            issues.append({
                "level": "warn",
                "title": "Низкая успешность upstream",
                "detail": f"Успешно {upstream_success_percent}% попыток подключения к Telegram.",
                "action": "Проверьте недоступные DC и маршрут VPS до Telegram.",
            })

        overall = "ok"
        if any(item["level"] == "error" for item in issues):
            overall = "error"
        elif issues:
            overall = "warn"
        payload = {
            "checked_at": int(time.time()),
            "overall": overall,
            "service": service,
            "kernel": {
                "current": version,
                "target": "3.4.25",
                "ok": version == "3.4.25",
            },
            "transport": {
                "port": settings.get("port", 443),
                "use_middle_proxy": bool(settings.get("use_middle_proxy")),
                "handshake_mss": handshake_mss,
                "bulk_mss": bulk_mss,
                "packet_multiplier": multiplier,
                "split_mss": bool(handshake_mss and bulk_mss and bulk_mss > handshake_mss),
            },
            "upstream": {
                "attempts": int(attempts),
                "success": int(success),
                "fail": int(metrics.get("telemt_upstream_connect_fail_total", 0.0)),
                "success_percent": upstream_success_percent,
                "handshake_timeouts": int(handshake_timeouts),
                "handshake_timeout_percent": handshake_timeout_percent,
            },
            "me_pool": me_pool,
            "dc": dc,
            "issues": issues,
        }
        _HEALTH_CACHE = payload
        _HEALTH_CACHE_AT = time.monotonic()
        return payload


def site_status(config: dict[str, Any] | None = None) -> dict[str, Any]:
    config = config or load_json(GOTELEGRAM_CONFIG, {}) or {}
    host = str(config.get("domain") or "").strip()
    if not host:
        return {"host": "", "url": "", "http_code": 0, "ok": False, "checked": False, "error": "domain_missing"}
    if not re.match(r"^[A-Za-z0-9.-]{1,253}$", host) or ".." in host or host.startswith(".") or host.endswith("."):
        return {"host": host, "url": "", "http_code": 0, "ok": False, "checked": False, "error": "invalid_domain"}
    port = _int_value(config.get("port") or 443) or 443
    url = f"https://{host}{'' if port == 443 else f':{port}'}/"
    code, stdout, stderr = run(["curl", "-k", "-L", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "8", url], timeout=10)
    raw_code = stdout.strip()
    try:
        http_code = int(raw_code)
    except ValueError:
        http_code = 0
    return {
        "host": host,
        "url": url,
        "http_code": http_code,
        "ok": code == 0 and http_code == 200,
        "checked": True,
        "error": "" if code == 0 else (stderr.strip() or f"curl exit {code}"),
        "checked_at": int(time.time()),
    }


def load_stats_history(limit: int | None = 240) -> list[dict[str, int]]:
    if not HISTORY_FILE.exists():
        return []
    rows: list[dict[str, int]] = []
    try:
        with HISTORY_FILE.open("r", encoding="utf-8", newline="") as fh:
            for row in csv.DictReader(fh):
                try:
                    rows.append({
                        "epoch": int(row.get("epoch") or 0),
                        "proxy_bytes": int(row.get("proxy_bytes") or 0),
                        "site_bytes": int(row.get("site_bytes") or 0),
                    })
                except ValueError:
                    continue
    except OSError:
        return []
    if limit:
        rows = rows[-limit:]
    previous = None
    enriched: list[dict[str, int]] = []
    for row in rows:
        item = dict(row)
        if previous:
            item["proxy_delta"] = (
                row["proxy_bytes"] - previous["proxy_bytes"]
                if row["proxy_bytes"] >= previous["proxy_bytes"]
                else row["proxy_bytes"]
            )
            item["site_delta"] = (
                row["site_bytes"] - previous["site_bytes"]
                if row["site_bytes"] >= previous["site_bytes"]
                else row["site_bytes"]
            )
        else:
            item["proxy_delta"] = 0
            item["site_delta"] = 0
        enriched.append(item)
        previous = row
    return enriched


def _int_value(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def load_user_stats_history(name: str | None = None, limit: int | None = 240) -> list[dict[str, Any]]:
    if not USER_HISTORY_FILE.exists():
        return []
    rows: list[dict[str, Any]] = []
    try:
        with USER_HISTORY_FILE.open("r", encoding="utf-8", newline="") as fh:
            for row in csv.DictReader(fh):
                user = str(row.get("user") or "").strip()
                if name is not None and user != name:
                    continue
                if not USER_RE.match(user):
                    continue
                rows.append({
                    "epoch": _int_value(row.get("epoch")),
                    "user": user,
                    "total_octets": _int_value(row.get("total_octets")),
                    "current_connections": _int_value(row.get("current_connections")),
                    "active_unique_ips": _int_value(row.get("active_unique_ips")),
                    "recent_unique_ips": _int_value(row.get("recent_unique_ips")),
                })
    except OSError:
        return []
    rows.sort(key=lambda item: (item["user"], item["epoch"]))
    if limit and name is not None:
        rows = rows[-limit:]

    previous_by_user: dict[str, dict[str, Any]] = {}
    enriched: list[dict[str, Any]] = []
    for row in rows:
        item = dict(row)
        previous = previous_by_user.get(row["user"])
        if previous:
            item["total_delta"] = (
                row["total_octets"] - previous["total_octets"]
                if row["total_octets"] >= previous["total_octets"]
                else row["total_octets"]
            )
        else:
            item["total_delta"] = 0
        enriched.append(item)
        previous_by_user[row["user"]] = row
    if limit and name is None:
        enriched = enriched[-limit:]
    return enriched


def latest_user_stats() -> dict[str, dict[str, Any]]:
    latest: dict[str, dict[str, Any]] = {}
    if not USER_HISTORY_FILE.exists():
        return latest
    try:
        with USER_HISTORY_FILE.open("r", encoding="utf-8", newline="") as fh:
            for row in csv.DictReader(fh):
                user = str(row.get("user") or "").strip()
                if not USER_RE.match(user):
                    continue
                item = {
                    "epoch": _int_value(row.get("epoch")),
                    "user": user,
                    "total_octets": _int_value(row.get("total_octets")),
                    "current_connections": _int_value(row.get("current_connections")),
                    "active_unique_ips": _int_value(row.get("active_unique_ips")),
                    "recent_unique_ips": _int_value(row.get("recent_unique_ips")),
                }
                if item["epoch"] >= latest.get(user, {}).get("epoch", 0):
                    latest[user] = item
    except OSError:
        return {}
    return latest


def runtime_user_traffic(name: str, enabled: bool = True) -> dict[str, Any]:
    if not enabled:
        return {"ok": False, "enabled": False, "total_octets": 0, "current_connections": 0, "active_unique_ips": 0, "recent_unique_ips": 0}
    payload = telemt_api(f"/v1/users/{urllib.parse.quote(name, safe='')}")
    data = payload.get("data", payload) if isinstance(payload, dict) else {}
    if not isinstance(data, dict):
        data = {}
    return {
        "ok": bool(payload),
        "enabled": True,
        "total_octets": _int_value(data.get("total_octets")),
        "current_connections": _int_value(data.get("current_connections")),
        "active_unique_ips": _int_value(data.get("active_unique_ips")),
        "recent_unique_ips": _int_value(data.get("recent_unique_ips")),
        "in_runtime": bool(data.get("in_runtime")) if data else False,
    }


def current_user_traffic_snapshot(
    name: str,
    enabled: bool,
    history_snapshot: dict[str, Any] | None = None,
    now: int | None = None,
) -> dict[str, Any]:
    """Return live counters for key cards, preserving only total bytes from history.

    History rows are minute snapshots. They are useful for charts, but stale
    connection/IP values make the keys list look like users are still online.
    """
    history_snapshot = history_snapshot or {}
    fallback = {
        "epoch": _int_value(history_snapshot.get("epoch")),
        "total_octets": _int_value(history_snapshot.get("total_octets")),
        "current_connections": 0,
        "active_unique_ips": 0,
        "recent_unique_ips": 0,
    }
    if not enabled:
        return fallback
    runtime = runtime_user_traffic(name, enabled)
    if not runtime.get("ok"):
        return fallback
    return {
        "epoch": _int_value(now if now is not None else time.time()),
        "total_octets": _int_value(runtime.get("total_octets")),
        "current_connections": _int_value(runtime.get("current_connections")),
        "active_unique_ips": _int_value(runtime.get("active_unique_ips")),
        "recent_unique_ips": _int_value(runtime.get("recent_unique_ips")),
    }


def history_limit_for_range(range_key: str) -> int:
    return {
        "15m": 180,
        "1h": 240,
        "6h": 600,
        "24h": 1800,
        "7d": 11000,
        "month": 50000,
    }.get(range_key, 240)


def normalize_range(range_key: str) -> str:
    return range_key if range_key in TRAFFIC_WINDOWS else "1h"


def filter_history_by_range(rows: list[dict[str, int]], range_key: str) -> list[dict[str, int]]:
    if not rows:
        return []
    seconds = TRAFFIC_WINDOWS[normalize_range(range_key)]
    latest = max(row.get("epoch", 0) for row in rows)
    cutoff = latest - seconds
    return [row for row in rows if row.get("epoch", 0) >= cutoff]


def traffic_interval_summaries(rows: list[dict[str, int]]) -> list[dict[str, Any]]:
    if not rows:
        return [
            {"range": key, "points": 0, "from": 0, "to": 0, "proxy_delta": 0, "site_delta": 0, "proxy_total": 0, "site_total": 0}
            for key in TRAFFIC_WINDOWS
        ]
    latest = max(row.get("epoch", 0) for row in rows)
    summaries = []
    for key, seconds in TRAFFIC_WINDOWS.items():
        window = [row for row in rows if row.get("epoch", 0) >= latest - seconds]
        if not window:
            summaries.append({"range": key, "points": 0, "from": 0, "to": latest, "proxy_delta": 0, "site_delta": 0, "proxy_total": 0, "site_total": 0})
            continue
        first = window[0]
        last = window[-1]
        summaries.append({
            "range": key,
            "points": len(window),
            "from": first.get("epoch", 0),
            "to": last.get("epoch", 0),
            "proxy_delta": sum(max(0, int(item.get("proxy_delta", 0))) for item in window),
            "site_delta": sum(max(0, int(item.get("site_delta", 0))) for item in window),
            "proxy_total": int(last.get("proxy_bytes", 0)),
            "site_total": int(last.get("site_bytes", 0)),
        })
    return summaries


def user_traffic_interval_summaries(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not rows:
        return [
            {"range": key, "points": 0, "from": 0, "to": 0, "total_delta": 0, "total_octets": 0}
            for key in TRAFFIC_WINDOWS
        ]
    latest = max(row.get("epoch", 0) for row in rows)
    summaries = []
    for key, seconds in TRAFFIC_WINDOWS.items():
        window = [row for row in rows if row.get("epoch", 0) >= latest - seconds]
        if not window:
            summaries.append({"range": key, "points": 0, "from": 0, "to": latest, "total_delta": 0, "total_octets": 0})
            continue
        first = window[0]
        last = window[-1]
        summaries.append({
            "range": key,
            "points": len(window),
            "from": first.get("epoch", 0),
            "to": last.get("epoch", 0),
            "total_delta": sum(max(0, int(item.get("total_delta", 0))) for item in window),
            "total_octets": int(last.get("total_octets", 0)),
        })
    return summaries


def count_history_rows() -> int:
    if not HISTORY_FILE.exists():
        return 0
    try:
        with HISTORY_FILE.open("r", encoding="utf-8", errors="ignore") as fh:
            return sum(1 for line in fh if line and line[0].isdigit())
    except OSError:
        return 0


def count_user_history_rows(name: str | None = None) -> int:
    if not USER_HISTORY_FILE.exists():
        return 0
    try:
        with USER_HISTORY_FILE.open("r", encoding="utf-8", errors="ignore") as fh:
            if name is None:
                return sum(1 for line in fh if line and line[0].isdigit())
            return sum(1 for line in fh if line.startswith(tuple(str(d) for d in range(10))) and f",{name}," in line)
    except OSError:
        return 0


def stats_status(current: dict[str, Any] | None = None, history: list[dict[str, int]] | None = None) -> dict[str, Any]:
    current = current if current is not None else (load_json(CURRENT_STATS, {}) or {})
    history = history if history is not None else load_stats_history(limit=2)
    service = service_status("gotelegram-stats")
    now = int(time.time())
    ts = int(current.get("ts") or 0) if isinstance(current, dict) else 0
    age = max(0, now - ts) if ts else None
    error = str(current.get("error") or "") if isinstance(current, dict) else ""
    history_rows = count_history_rows()
    if error:
        health = "error"
    elif service == "running" and current and age is not None and age <= 180:
        health = "ok"
    elif service == "running":
        health = "stale"
    elif service == "not_installed":
        health = "not_installed"
    else:
        health = "stopped"
    return {
        "health": health,
        "service": service,
        "current_exists": CURRENT_STATS.exists(),
        "history_exists": HISTORY_FILE.exists(),
        "history_rows": history_rows,
        "history_points": len(history or []),
        "last_ts": ts,
        "age_seconds": age,
        "error": error,
    }


def run_stats_action(action: str) -> tuple[bool, str, dict[str, Any]]:
    if action == "repair":
        body = (
            "source /opt/gotelegram/current/lib/common.sh; "
            "source /opt/gotelegram/current/lib/i18n.sh; "
            "source /opt/gotelegram/current/lib/stats.sh; "
            "load_language \"$(detect_language 2>/dev/null || echo en)\"; "
            "install_stats_collector; "
            "stats_collect"
        )
        timeout = 180
    else:
        body = (
            "source /opt/gotelegram/current/lib/common.sh; "
            "source /opt/gotelegram/current/lib/stats.sh; "
            "stats_init >/dev/null 2>&1 || true; "
            "stats_collect"
        )
        timeout = 30
    code, stdout, stderr = run(["bash", "-lc", body], timeout=timeout)
    message = (stdout.strip().splitlines()[-1:] or stderr.strip().splitlines()[-1:] or [""])[0]
    current = load_json(CURRENT_STATS, {}) or {}
    history = load_stats_history()
    return code == 0, message, {"current": current, "history": history, "status": stats_status(current, history)}


def list_backups() -> list[dict[str, Any]]:
    if not BACKUP_DIR.exists():
        return []
    items = []
    for path in sorted(BACKUP_DIR.glob("*.tar.gz*"), key=lambda p: p.stat().st_mtime, reverse=True):
        if path.name.endswith(".sha256"):
            continue
        try:
            st = path.stat()
        except OSError:
            continue
        items.append({
            "name": path.name,
            "path": str(path),
            "size": st.st_size,
            "mtime": int(st.st_mtime),
            "encrypted": path.name.endswith((".enc", ".gpg")),
            "restorable": not path.name.endswith(".enc"),
        })
    return items[:30]


def backup_schedule_calendar(frequency: str) -> str | None:
    calendars = {
        "off": None,
        "daily": "*-*-* 03:20:00",
        "weekly": "Sun 03:20:00",
        "monthly": "*-*-01 03:20:00",
    }
    if frequency not in calendars:
        raise ValueError("unsupported backup schedule")
    return calendars[frequency]


def backup_schedule_status() -> dict[str, Any]:
    raw = load_json(BACKUP_SCHEDULE_FILE, {}) or {}
    if not isinstance(raw, dict):
        raw = {}
    frequency = str(raw.get("frequency") or "off")
    try:
        calendar = backup_schedule_calendar(frequency)
    except ValueError:
        frequency = "off"
        calendar = None
    active_code, active, _ = run(["systemctl", "is-active", "gotelegram-backup.timer"], timeout=5)
    enabled_code, enabled, _ = run(["systemctl", "is-enabled", "gotelegram-backup.timer"], timeout=5)
    _, next_run, _ = run(["systemctl", "show", "gotelegram-backup.timer", "--property=NextElapseUSecRealtime", "--value"], timeout=5)
    return {
        "frequency": frequency,
        "calendar": calendar,
        "enabled": enabled_code == 0 and enabled.strip() == "enabled",
        "active": active_code == 0 and active.strip() == "active",
        "next": next_run.strip(),
        "updated_at": raw.get("updated_at") or "",
    }


def set_backup_schedule(frequency: str) -> tuple[bool, str, dict[str, Any]]:
    backup_schedule_calendar(frequency)
    script = (
        "source /opt/gotelegram/current/lib/common.sh; "
        "source /opt/gotelegram/current/lib/i18n.sh; "
        "source /opt/gotelegram/current/lib/backup.sh; "
        "load_language \"$(detect_language 2>/dev/null || echo en)\"; "
        f"set_backup_schedule {shlex.quote(frequency)}"
    )
    code, stdout, stderr = run(["bash", "-lc", script], timeout=120)
    message = (stdout.strip().splitlines()[-1:] or stderr.strip().splitlines()[-1:] or [""])[0]
    return code == 0, message, backup_schedule_status()


def create_backup() -> tuple[bool, str]:
    script = (
        "source /opt/gotelegram/current/lib/common.sh; "
        "source /opt/gotelegram/current/lib/i18n.sh; "
        "source /opt/gotelegram/current/lib/telemt.sh; "
        "source /opt/gotelegram/current/lib/website.sh; "
        "source /opt/gotelegram/current/lib/backup.sh; "
        "load_language ru; "
        "ensure_backup_passphrase_file; "
        "create_backup_from_password_file; "
        "cleanup_old_backups 30"
    )
    code, stdout, stderr = run(["bash", "-lc", script], timeout=180)
    text = (stdout.strip().splitlines()[-1:] or stderr.strip().splitlines()[-1:] or [""])[0]
    return code == 0, text


def safe_backup_path(name: str) -> Path:
    raw = str(name or "").strip()
    if not raw or raw != os.path.basename(raw) or not BACKUP_NAME_RE.match(raw) or raw.endswith(".sha256"):
        raise ValueError("invalid backup name")
    candidate = (BACKUP_DIR / raw).resolve()
    base = BACKUP_DIR.resolve()
    if base != candidate.parent:
        raise ValueError("invalid backup path")
    if not candidate.exists():
        raise FileNotFoundError("backup not found")
    return candidate


def launch_restore_backup(name: str, password: str = "") -> dict[str, Any]:
    backup_path = safe_backup_path(name)
    if backup_path.name.endswith(".enc"):
        raise ValueError("legacy encrypted backups are restored from CLI")
    if password:
        raise ValueError("password input is not accepted by the web panel")
    BACKUP_RESTORE_LOG.parent.mkdir(parents=True, exist_ok=True)
    quoted_path = shlex.quote(str(backup_path))
    quoted_log = shlex.quote(str(BACKUP_RESTORE_LOG))
    if backup_path.name.endswith(".gpg"):
        restore_command = (
            f"restore_backup_from_password_file {quoted_path} "
            "\"$BACKUP_PASSPHRASE_FILE\" yes"
        )
    else:
        restore_command = f"restore_backup {quoted_path} '' yes"
    script = (
        "sleep 1; "
        "source /opt/gotelegram/current/lib/common.sh; "
        "source /opt/gotelegram/current/lib/i18n.sh; "
        "source /opt/gotelegram/current/lib/telemt.sh; "
        "source /opt/gotelegram/current/lib/website.sh; "
        "source /opt/gotelegram/current/lib/backup.sh; "
        "load_language ru; "
        "ensure_backup_passphrase_file; "
        "create_backup_from_password_file >/dev/null 2>&1 || true; "
        f"{restore_command}; "
        "cleanup_old_backups 30"
    )
    with BACKUP_RESTORE_LOG.open("ab") as log:
        log.write(f"\n[{utc_now()}] restore requested for {backup_path.name}\n".encode("utf-8"))
        subprocess.Popen(
            ["bash", "-lc", f"{script} >> {quoted_log} 2>&1"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    return {"name": backup_path.name, "started": True, "log": str(BACKUP_RESTORE_LOG)}


def user_qr_png(name: str) -> tuple[bytes, str]:
    users = read_user_records()
    record = users.get(name)
    if not record:
        raise FileNotFoundError("user not found")
    link = proxy_link(str(record.get("secret", "")))
    code, image, error = run_bytes(["qrencode", "-t", "PNG", "-s", "8", "-m", "2", "-o", "-", link], timeout=8)
    if code != 0 or not image:
        raise RuntimeError(error.strip() or "qrencode is not installed")
    return image, link


def read_log_payload(service: str) -> dict[str, Any]:
    allowed = {"telemt", "nginx", "gotelegram-bot", "gotelegram-stats", "gotelegram-admin"}
    if service not in allowed:
        raise ValueError("unsupported service")
    code, stdout, stderr = run(["journalctl", "-u", service, "-n", "180", "--no-pager", "-o", "short-iso"], timeout=10)
    text = stdout if code == 0 else stderr
    lines = text.splitlines()
    if code == 0 and not lines:
        text = f"No journal entries for {service}."
        lines = [text]
    return {
        "service": service,
        "ok": code == 0,
        "exit_code": code,
        "line_count": len(lines),
        "text": text,
    }


def user_payload(
    name: str,
    secret: str,
    enabled: bool = True,
    max_unique_ips: int = 0,
    include_runtime: bool = False,
    traffic_snapshot: dict[str, Any] | None = None,
) -> dict[str, Any]:
    item: dict[str, Any] = {
        "name": name,
        "secret": secret,
        "link": proxy_link(secret),
        "main": name == "main",
        "enabled": bool(enabled),
        "max_unique_ips": _int_value(max_unique_ips),
    }
    if traffic_snapshot:
        item["traffic"] = {
            "epoch": traffic_snapshot.get("epoch", 0),
            "total_octets": traffic_snapshot.get("total_octets", 0),
            "current_connections": traffic_snapshot.get("current_connections", 0),
            "active_unique_ips": traffic_snapshot.get("active_unique_ips", 0),
            "recent_unique_ips": traffic_snapshot.get("recent_unique_ips", 0),
        }
    if include_runtime and enabled:
        item["runtime"] = telemt_api(f"/v1/users/{urllib.parse.quote(name, safe='')}")
    return item


def runtime_version(config: dict[str, Any] | None = None) -> str:
    """Read the activated release version before falling back to saved state."""
    pattern = re.compile(r'^GOTELEGRAM_VERSION="([^"]+)"\s*$')
    for path in RUNTIME_COMMON_PATHS:
        try:
            for line in path.read_text(encoding="utf-8").splitlines():
                match = pattern.match(line)
                if match:
                    return match.group(1)
        except OSError:
            continue
    saved = config or {}
    return str(saved.get("version") or saved.get("gotelegram_version") or VERSION)


def overview_payload() -> dict[str, Any]:
    config = load_json(GOTELEGRAM_CONFIG, {}) or {}
    language = read_language(config)
    users = read_user_records()
    current = load_json(CURRENT_STATS, {}) or {}
    history = load_stats_history()
    summary = telemt_api("/v1/stats/summary")
    services = {
        "telemt": service_status("telemt"),
        "nginx": service_status("nginx"),
        "bot": service_status("gotelegram-bot"),
        "stats": service_status("gotelegram-stats"),
        "admin": service_status("gotelegram-admin"),
    }
    return {
        "version": runtime_version(config),
        "time": utc_now(),
        "language": language,
        "admin_bind": {"host": HOST, "port": PORT},
        "system": system_metrics(),
        "config": public_config(config),
        "site_status": site_status(config),
        "users_count": len(users),
        "services": services,
        "port_443": port_443_status(),
        "stats_current": current,
        "stats_history": history,
        "stats_status": stats_status(current, history),
        "runtime_summary": summary,
        "backups": list_backups(),
        "backup_schedule": backup_schedule_status(),
    }


class AdminHandler(BaseHTTPRequestHandler):
    server_version = f"IGProxyAdmin/{VERSION}"

    def log_message(self, fmt: str, *args: Any) -> None:
        print("%s - %s" % (self.address_string(), fmt % args))

    def send_json(self, payload: Any, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_bytes(self, body: bytes, content_type: str, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, status: int, message: str) -> None:
        self.send_json({"ok": False, "error": message}, status)

    def read_json_body(self) -> Any:
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length > 1024 * 1024:
            raise ValueError("request body too large")
        if length <= 0:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def require_write_guard(self) -> bool:
        if self.command in {"POST", "PUT", "PATCH", "DELETE"} and self.headers.get("X-GoTelegram-Admin") != "1":
            self.send_error_json(403, "missing write guard")
            return False
        return True

    def route_get_api(self, parsed: urllib.parse.ParseResult) -> None:
        path = parsed.path
        if path == "/api/overview":
            self.send_json({"ok": True, "data": overview_payload()})
        elif path == "/api/health":
            self.send_json({"ok": True, "data": health_payload()})
        elif path == "/api/users":
            users = read_user_records()
            latest = latest_user_stats()
            items = []
            for name in sorted(users, key=lambda item: (item != "main", item)):
                record = users[name]
                items.append(user_payload(
                    name,
                    record["secret"],
                    record["enabled"],
                    record.get("max_unique_ips", 0),
                    traffic_snapshot=current_user_traffic_snapshot(name, record["enabled"], latest.get(name)),
                ))
            self.send_json({"ok": True, "data": items})
        elif path.startswith("/api/users/") and path.endswith("/qr"):
            name = urllib.parse.unquote(path[len("/api/users/"):-len("/qr")])
            try:
                png, link = user_qr_png(name)
            except FileNotFoundError:
                self.send_error_json(404, "user not found")
                return
            except Exception as exc:
                self.send_error_json(503, str(exc))
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Proxy-Link", urllib.parse.quote(link, safe=""))
            self.send_header("Content-Length", str(len(png)))
            self.end_headers()
            self.wfile.write(png)
        elif path.startswith("/api/users/") and path.endswith("/traffic"):
            name = urllib.parse.unquote(path[len("/api/users/"):-len("/traffic")])
            users = read_user_records()
            if name not in users:
                self.send_error_json(404, "user not found")
                return
            qs = urllib.parse.parse_qs(parsed.query)
            range_key = normalize_range(qs.get("range", ["1h"])[0])
            all_history = load_user_stats_history(name, limit=history_limit_for_range("month"))
            history = filter_history_by_range(all_history[-history_limit_for_range(range_key):], range_key)
            current = runtime_user_traffic(name, bool(users[name].get("enabled")))
            self.send_json({
                "ok": True,
                "data": {
                    "name": name,
                    "range": range_key,
                    "current": current,
                    "history": history,
                    "summary_rows": user_traffic_interval_summaries(all_history),
                    "status": {
                        "history_exists": USER_HISTORY_FILE.exists(),
                        "history_rows": count_user_history_rows(name),
                        "history_points": len(history),
                        "last_ts": history[-1]["epoch"] if history else 0,
                        "runtime_ok": current.get("ok", False),
                    },
                },
            })
        elif path.startswith("/api/users/"):
            name = urllib.parse.unquote(path[len("/api/users/"):])
            users = read_user_records()
            if name not in users:
                self.send_error_json(404, "user not found")
                return
            record = users[name]
            self.send_json({"ok": True, "data": user_payload(
                name,
                record["secret"],
                record["enabled"],
                record.get("max_unique_ips", 0),
                include_runtime=True,
                traffic_snapshot=current_user_traffic_snapshot(name, record["enabled"], latest_user_stats().get(name)),
            )})
        elif path == "/api/backups":
            self.send_json({"ok": True, "data": list_backups()})
        elif path == "/api/backups/schedule":
            self.send_json({"ok": True, "data": backup_schedule_status()})
        elif path == "/api/stats":
            qs = urllib.parse.parse_qs(parsed.query)
            range_key = normalize_range(qs.get("range", ["1h"])[0])
            current = load_json(CURRENT_STATS, {}) or {}
            all_history = load_stats_history(limit=history_limit_for_range("month"))
            history = filter_history_by_range(all_history[-history_limit_for_range(range_key):], range_key)
            self.send_json({
                "ok": True,
                "data": {
                    "range": range_key,
                    "current": current,
                    "history": history,
                    "summary_rows": traffic_interval_summaries(all_history),
                    "status": stats_status(current, history),
                },
            })
        elif path == "/api/site/check":
            self.send_json({"ok": True, "data": site_status()})
        elif path == "/api/site/settings":
            self.send_json({"ok": True, "data": site_settings_payload()})
        elif path == "/api/client-servers":
            self.send_json({"ok": True, "data": client_servers_payload()})
        elif path == "/api/logs":
            qs = urllib.parse.parse_qs(parsed.query)
            service = qs.get("service", ["telemt"])[0]
            try:
                payload = read_log_payload(service)
            except ValueError:
                self.send_error_json(400, "unsupported service")
                return
            self.send_json({"ok": True, "data": payload})
        elif path == "/api/site/custom":
            try:
                payload = apply_custom_site(
                    str(body.get("html") or ""),
                    str(body.get("key") or "").strip(),
                )
            except ValueError as exc:
                self.send_error_json(400, str(exc))
                return
            except Exception as exc:
                self.send_error_json(500, str(exc))
                return
            self.send_json({"ok": True, "data": payload})
        else:
            self.send_error_json(404, "not found")

    def route_post_api(self, parsed: urllib.parse.ParseResult) -> None:
        if not self.require_write_guard():
            return
        path = parsed.path
        try:
            body = self.read_json_body()
        except Exception as exc:
            self.send_error_json(400, str(exc))
            return

        if path == "/api/users":
            name = str(body.get("name", "")).strip()
            if not USER_RE.match(name):
                self.send_error_json(400, "invalid user name")
                return
            try:
                with FileLock(USER_LOCK_FILE):
                    records = read_user_records()
                    if name in records:
                        self.send_error_json(409, "user already exists")
                        return
                    users = read_telemt_users()
                    seed = f"{name}:{time.time()}:{secrets.token_hex(32)}".encode()
                    secret = hashlib.sha256(seed).hexdigest()[:32]
                    users[name] = secret
                    write_telemt_users(users)
            except Exception as exc:
                self.send_error_json(500, f"failed to save config: {exc}")
                return
            restart_requested = request_service_restart("telemt")
            self.send_json({"ok": True, "data": user_payload(name, secret, True, 0), "restart": {"mode": "async", "requested": restart_requested}})
        elif path.startswith("/api/users/") and path.endswith("/max-ips"):
            name = urllib.parse.unquote(path[len("/api/users/"):-len("/max-ips")])
            try:
                limit = normalize_max_unique_ips(body.get("max_unique_ips"))
            except ValueError as exc:
                self.send_error_json(400, str(exc))
                return
            try:
                with FileLock(USER_LOCK_FILE):
                    records = read_user_records()
                    if name not in records:
                        self.send_error_json(404, "user not found")
                        return
                    limits = read_user_max_unique_ips()
                    if limit > 0:
                        limits[name] = limit
                    else:
                        limits.pop(name, None)
                    write_user_max_unique_ips(limits)
                    record = read_user_records()[name]
            except Exception as exc:
                self.send_error_json(500, f"failed to save config: {exc}")
                return
            restart_requested = request_service_restart("telemt")
            self.send_json({"ok": True, "data": user_payload(
                name,
                record["secret"],
                record["enabled"],
                record.get("max_unique_ips", 0),
                traffic_snapshot=current_user_traffic_snapshot(name, record["enabled"], latest_user_stats().get(name)),
            ), "restart": {"mode": "async", "requested": restart_requested}})
        elif path.startswith("/api/users/") and path.endswith("/enabled"):
            name = urllib.parse.unquote(path[len("/api/users/"):-len("/enabled")])
            if name == "main":
                self.send_error_json(400, "main user cannot be disabled")
                return
            enabled = bool(body.get("enabled"))
            try:
                with FileLock(USER_LOCK_FILE):
                    active = read_telemt_users()
                    disabled = read_disabled_users()
                    records = read_user_records()
                    if name not in records:
                        self.send_error_json(404, "user not found")
                        return
                    if enabled:
                        secret = disabled.pop(name, records[name]["secret"])
                        active[name] = secret
                    else:
                        secret = active.pop(name, records[name]["secret"])
                        disabled[name] = secret
                    if enabled:
                        write_telemt_users(active)
                        write_disabled_users(disabled)
                    else:
                        write_disabled_users(disabled)
                        write_telemt_users(active)
            except Exception as exc:
                self.send_error_json(500, f"failed to save config: {exc}")
                return
            restart_requested = request_service_restart("telemt")
            self.send_json({"ok": True, "data": user_payload(
                name,
                secret,
                enabled,
                records[name].get("max_unique_ips", 0),
                traffic_snapshot=current_user_traffic_snapshot(name, enabled, latest_user_stats().get(name)),
            ), "restart": {"mode": "async", "requested": restart_requested}})
        elif path == "/api/backups":
            ok, result = create_backup()
            self.send_json({"ok": ok, "data": {"path": result, "backups": list_backups()}}, 200 if ok else 500)
        elif path == "/api/backups/schedule":
            try:
                frequency = str(body.get("frequency") or "off").strip().lower()
                ok, message, status = set_backup_schedule(frequency)
            except ValueError as exc:
                self.send_error_json(400, str(exc))
                return
            self.send_json({"ok": ok, "data": {"message": message, "schedule": status}}, 200 if ok else 500)
        elif path == "/api/backups/restore":
            try:
                payload = launch_restore_backup(str(body.get("name") or ""), str(body.get("password") or ""))
            except FileNotFoundError:
                self.send_error_json(404, "backup not found")
                return
            except ValueError as exc:
                self.send_error_json(400, str(exc))
                return
            except Exception as exc:
                self.send_error_json(500, str(exc))
                return
            self.send_json({"ok": True, "data": payload}, 202)
        elif path == "/api/stats/collect":
            ok, message, payload = run_stats_action("collect")
            payload["message"] = message
            self.send_json({"ok": ok, "data": payload}, 200 if ok else 500)
        elif path == "/api/stats/repair":
            ok, message, payload = run_stats_action("repair")
            payload["message"] = message
            self.send_json({"ok": ok, "data": payload}, 200 if ok else 500)
        elif path == "/api/settings/language":
            try:
                lang_payload = write_language(str(body.get("language", "")))
            except Exception as exc:
                self.send_error_json(400, str(exc))
                return
            self.send_json({"ok": True, "data": lang_payload})
        elif path == "/api/settings/general":
            try:
                network_dc_count = int(body.get("network_dc_count") or 1)
                if network_dc_count < 1 or network_dc_count > 999:
                    raise ValueError("network_dc_count must be between 1 and 999")
                config = load_json(GOTELEGRAM_CONFIG, {}) or {}
                config["network_dc_count"] = network_dc_count
                brand_name = str(body.get("brand_name") or "IGProxy").strip()
                if len(brand_name) > 48:
                    raise ValueError("название должно быть не длиннее 48 символов")
                sponsor_name = str(body.get("sponsor_name") or "Спонсорский канал").strip()
                if len(sponsor_name) > 64:
                    raise ValueError("название канала должно быть не длиннее 64 символов")
                sponsor_url = _validate_public_url(
                    str(body.get("sponsor_url") or ""),
                    telegram_only=True,
                )
                sponsor_enabled = bool(body.get("sponsor_enabled", False))
                if sponsor_enabled and not sponsor_url:
                    raise ValueError("для включения спонсора укажите ссылку на канал")
                config["brand_enabled"] = bool(body.get("brand_enabled", True))
                config["brand_name"] = brand_name or "IGProxy"
                config["sponsor_enabled"] = sponsor_enabled
                config["sponsor_name"] = sponsor_name or "Спонсорский канал"
                config["sponsor_url"] = sponsor_url
                config["updated_at"] = utc_now()
                save_json(GOTELEGRAM_CONFIG, config)
            except (TypeError, ValueError) as exc:
                self.send_error_json(400, str(exc))
                return
            self.send_json({
                "ok": True,
                "data": {
                    "network_dc_count": network_dc_count,
                    **appearance_payload(config),
                },
            })
        elif path == "/api/client-servers":
            try:
                payload = save_client_servers(body.get("servers"))
            except (TypeError, ValueError) as exc:
                self.send_error_json(400, str(exc))
                return
            self.send_json({"ok": True, "data": payload})
        elif path == "/api/site/settings":
            try:
                payload = apply_site_preset(
                    str(body.get("preset") or "").strip(),
                    str(body.get("key") or "").strip(),
                )
            except FileNotFoundError as exc:
                self.send_error_json(404, str(exc))
                return
            except ValueError as exc:
                self.send_error_json(400, str(exc))
                return
            except Exception as exc:
                self.send_error_json(500, str(exc))
                return
            self.send_json({"ok": True, "data": payload})
        elif path.startswith("/api/services/") and path.endswith("/restart"):
            service = path[len("/api/services/"):-len("/restart")]
            allowed = {"telemt", "nginx", "gotelegram-bot", "gotelegram-stats"}
            if service not in allowed:
                self.send_error_json(400, "unsupported service")
                return
            ok = restart_service(service)
            self.send_json({"ok": ok, "status": service_status(service)}, 200 if ok else 500)
        else:
            self.send_error_json(404, "not found")

    def route_delete_api(self, parsed: urllib.parse.ParseResult) -> None:
        if not self.require_write_guard():
            return
        path = parsed.path
        if not path.startswith("/api/users/"):
            self.send_error_json(404, "not found")
            return
        name = urllib.parse.unquote(path[len("/api/users/"):])
        if name == "main":
            self.send_error_json(400, "main user cannot be deleted")
            return
        try:
            with FileLock(USER_LOCK_FILE):
                active = read_telemt_users()
                disabled = read_disabled_users()
                records = read_user_records()
                if name not in records:
                    self.send_error_json(404, "user not found")
                    return
                active.pop(name, None)
                disabled.pop(name, None)
                limits = read_user_max_unique_ips()
                limits.pop(name, None)
                write_telemt_users(active)
                write_disabled_users(disabled)
                write_user_max_unique_ips(limits)
        except Exception as exc:
            self.send_error_json(500, f"failed to save config: {exc}")
            return
        restart_requested = request_service_restart("telemt")
        self.send_json({"ok": True, "restart": {"mode": "async", "requested": restart_requested}})

    def send_static(self, parsed: urllib.parse.ParseResult) -> None:
        rel = parsed.path.lstrip("/") or "index.html"
        if rel.startswith("api/") or ".." in rel.split("/"):
            self.send_error(404)
            return
        path = STATIC_DIR / rel
        if path.is_dir():
            path = path / "index.html"
        if not path.exists():
            path = STATIC_DIR / "index.html"
        try:
            body = path.read_bytes()
        except OSError:
            self.send_error(404)
            return
        mime = mimetypes.guess_type(str(path))[0] or "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path.startswith("/api/"):
            self.route_get_api(parsed)
        else:
            self.send_static(parsed)

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path.startswith("/api/"):
            self.route_post_api(parsed)
        else:
            self.send_error(404)

    def do_DELETE(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path.startswith("/api/"):
            self.route_delete_api(parsed)
        else:
            self.send_error(404)


def main() -> None:
    if not STATIC_DIR.exists():
        raise SystemExit(f"static dir not found: {STATIC_DIR}")
    published_index = WEBSITE_ROOT / "index.html"
    if not published_index.exists():
        records = read_user_records()
        default_key = "main" if records.get("main", {}).get("enabled") else next(
            (name for name, record in records.items() if record.get("enabled")),
            "",
        )
        if default_key and (SITE_PRESETS_DIR / "random-gallery" / "index.html").exists():
            try:
                apply_site_preset("random-gallery", default_key)
            except Exception as exc:
                print(f"IGProxy default site was not published: {exc}")
    else:
        try:
            source = published_index.read_text(encoding="utf-8")
            upgraded = add_mini_app_bridge(source)
            if upgraded != source:
                published_index.write_text(upgraded, encoding="utf-8")
                os.chmod(published_index, 0o644)
        except OSError as exc:
            print(f"IGProxy Mini App bridge was not added: {exc}")
    httpd = ThreadingHTTPServer((HOST, PORT), AdminHandler)
    print(f"IGProxy admin listening on http://{HOST}:{PORT}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
