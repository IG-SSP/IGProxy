#!/usr/bin/env python3
"""IGProxy node agent: outbound enrollment and heartbeat to one Hub."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


CONFIG_PATH = Path(os.getenv("IGPROXY_NODE_CONFIG", "/var/lib/igproxy-node/node.json"))
IGPROXY_CONFIG = Path(os.getenv("GOTELEGRAM_CONFIG", "/opt/gotelegram/config.json"))
TIMEOUT = 12


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


HTTP_OPENER = urllib.request.build_opener(NoRedirectHandler())


class HubRequestError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status


def load_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default


def atomic_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, raw = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    temp = Path(raw)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, 0o600)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def service_active(name: str) -> bool:
    return (
        subprocess.run(
            ["systemctl", "is-active", "--quiet", name],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def public_ip() -> str:
    config = load_json(IGPROXY_CONFIG, {})
    domain = str(config.get("domain") or "").strip()
    if config.get("mode") == "pro" and domain:
        return domain
    node_config = load_json(CONFIG_PATH, {})
    configured_ip = str(node_config.get("public_ip") or "").strip()
    if configured_ip:
        return configured_ip
    try:
        with urllib.request.urlopen("https://api.ipify.org", timeout=TIMEOUT) as response:
            return response.read(128).decode("ascii").strip()
    except (OSError, urllib.error.URLError):
        return socket.getfqdn()


def proxy_url() -> str:
    config = load_json(IGPROXY_CONFIG, {})
    secret = str(config.get("secret") or "")
    port = int(config.get("port") or 443)
    mode = str(config.get("mode") or "lite")
    domain = str(config.get("domain") or "").strip()
    mask_host = str(config.get("mask_host") or "").strip()
    server = domain if mode == "pro" and domain else public_ip()
    if mask_host:
        secret = "ee" + secret + mask_host.encode("utf-8").hex()
    query = urllib.parse.urlencode({"server": server, "port": port, "secret": secret})
    return f"https://t.me/proxy?{query}"


def memory_percent() -> float:
    values: dict[str, int] = {}
    try:
        for line in Path("/proc/meminfo").read_text(encoding="ascii").splitlines():
            key, _, raw = line.partition(":")
            values[key] = int(raw.strip().split()[0])
    except (OSError, ValueError, IndexError):
        return 0.0
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", 0)
    return round((1 - available / total) * 100, 1) if total else 0.0


def status_payload() -> dict[str, Any]:
    config = load_json(IGPROXY_CONFIG, {})
    try:
        load_1m = round(os.getloadavg()[0], 2)
    except OSError:
        load_1m = 0.0
    try:
        uptime_seconds = int(float(Path("/proc/uptime").read_text().split()[0]))
    except (OSError, ValueError, IndexError):
        uptime_seconds = 0
    return {
        "version": str(config.get("version") or ""),
        "hostname": socket.gethostname(),
        "telemt": service_active("telemt"),
        "admin": service_active("gotelegram-admin"),
        "port": int(config.get("port") or 0),
        "load_1m": load_1m,
        "memory_percent": memory_percent(),
        "uptime_seconds": uptime_seconds,
    }


def request(config: dict[str, Any], endpoint: str, payload: dict[str, Any], token: str = "") -> Any:
    base = str(config.get("hub_url") or "").rstrip("/")
    if not base.startswith("https://"):
        raise ValueError("hub_url must use HTTPS")
    headers = {"Content-Type": "application/json", "User-Agent": "IGProxyNode/1"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    req = urllib.request.Request(f"{base}/{endpoint.lstrip('/')}", raw, headers, method="POST")
    # Bearer must never follow a redirect to another origin.
    try:
        with HTTP_OPENER.open(req, timeout=TIMEOUT) as response:
            body = json.loads(response.read(MAX_RESPONSE))
    except urllib.error.HTTPError as exc:
        message = f"hub returned HTTP {exc.code}"
        try:
            error_body = json.loads(exc.read(MAX_RESPONSE))
            if isinstance(error_body, dict) and error_body.get("error"):
                message = str(error_body["error"])
        except (OSError, ValueError, json.JSONDecodeError):
            pass
        raise HubRequestError(int(exc.code), message) from exc
    if not body.get("ok"):
        raise HubRequestError(0, str(body.get("error") or "hub rejected request"))
    return body.get("data") or {}


MAX_RESPONSE = 64 * 1024


def ensure_install_id(config: dict[str, Any]) -> None:
    if config.get("install_id"):
        return
    seed = f"{socket.gethostname()}\0{time.time_ns()}\0{os.getpid()}".encode()
    config["install_id"] = hashlib.sha256(seed).hexdigest()[:20]
    atomic_json(CONFIG_PATH, config)


def enroll(config: dict[str, Any]) -> dict[str, Any]:
    result = request(
        config,
        "v1/enroll",
        {
            "pairing_code": "".join(str(config.get("pairing_code") or "").split()),
            "install_id": config["install_id"],
            "label": str(config.get("label") or socket.gethostname()),
            "proxy_url": proxy_url(),
            "status": status_payload(),
        },
    )
    config["node_id"] = result["node_id"]
    config["node_token"] = result["node_token"]
    config["hub_id"] = result.get("hub_id", "")
    config["heartbeat_interval"] = int(result.get("heartbeat_interval") or 30)
    config.pop("pairing_code", None)
    atomic_json(CONFIG_PATH, config)
    return config


def sync_once() -> dict[str, Any]:
    config = load_json(CONFIG_PATH, {})
    ensure_install_id(config)
    if not config.get("node_token"):
        config = enroll(config)
    request(
        config,
        "v1/heartbeat",
        {
            "label": str(config.get("label") or socket.gethostname()),
            "proxy_url": proxy_url(),
            "status": status_payload(),
        },
        str(config.get("node_token") or ""),
    )
    return config


def run() -> None:
    failures = 0
    while True:
        try:
            config = sync_once()
            failures = 0
            delay = max(15, min(int(config.get("heartbeat_interval") or 30), 300))
        except (OSError, ValueError, KeyError, RuntimeError, urllib.error.URLError) as exc:
            failures += 1
            delay = min(15 * (2 ** min(failures, 5)), 300)
            print(f"IGProxy node sync failed: {type(exc).__name__}: {exc}", flush=True)
        time.sleep(delay)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--once",
        action="store_true",
        help="perform enrollment/heartbeat once and exit",
    )
    args = parser.parse_args()
    if not args.once:
        run()
        return 0
    try:
        config = sync_once()
        print(f"IGProxy node connected as {config.get('node_id')}", flush=True)
        return 0
    except HubRequestError as exc:
        print(f"IGProxy node rejected: {exc}", file=sys.stderr, flush=True)
        return 10 if exc.status == 401 else 1
    except (OSError, ValueError, KeyError, RuntimeError, urllib.error.URLError) as exc:
        print(
            f"IGProxy node connection failed: {type(exc).__name__}: {exc}",
            file=sys.stderr,
            flush=True,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
