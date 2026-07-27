"""
goTelegram Pro Bot — i18n module
Provides per-user language preferences and a simple t()/tf() API.

Usage:
    from i18n import t, tf, set_user_lang, get_user_lang, get_language_name

    msg = t(user_id, "menu_status")
    msg = tf(user_id, "backup_created_fmt", filename)

Language files live next to this module in lang/<code>.json.
Per-user choices are persisted to USER_LANG_FILE (one JSON dict: user_id -> code).
"""

import json
import logging
import os
from pathlib import Path
from typing import Dict, Optional

logger = logging.getLogger(__name__)

# ── Paths ─────────────────────────────────────────────────────────────────
_MODULE_DIR = Path(__file__).resolve().parent
LANG_DIR = _MODULE_DIR / "lang"
USER_LANG_FILE = Path("/opt/gotelegram-bot/user_langs.json")
GOTELEGRAM_CONFIG = Path("/opt/gotelegram/config.json")
GOTELEGRAM_LANG_MARKER = Path("/opt/gotelegram/.language")

# Операторский интерфейс фиксирован на русском; старые пользовательские
# настройки языка игнорируются ради предсказуемого единого интерфейса.
SUPPORTED_LANGS = ("ru",)


def _detect_default_lang() -> str:
    candidates = []
    try:
        if GOTELEGRAM_CONFIG.exists():
            with open(GOTELEGRAM_CONFIG, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                candidates.extend([data.get("language"), data.get("lang")])
    except Exception as e:
        logger.warning("failed to read goTelegram Pro language config: %s", e)
    try:
        if GOTELEGRAM_LANG_MARKER.exists():
            candidates.append(GOTELEGRAM_LANG_MARKER.read_text(encoding="utf-8").strip()[:2])
    except Exception as e:
        logger.warning("failed to read goTelegram Pro language marker: %s", e)
    candidates.append(os.getenv("BOT_LANG", ""))
    for raw in candidates:
        code = str(raw or "").strip().lower()
        if code in SUPPORTED_LANGS:
            return code
    return "ru"


DEFAULT_LANG = _detect_default_lang()

LANG_NAMES = {
    "en": "English",
    "ru": "Русский",
}

# ── Caches ────────────────────────────────────────────────────────────────
_LANG_CACHE: Dict[str, Dict[str, str]] = {}
_USER_LANGS: Dict[int, str] = {}
_USER_LANGS_LOADED = False


def _load_lang_file(code: str) -> Dict[str, str]:
    """Load lang/<code>.json into the cache and return it."""
    if code in _LANG_CACHE:
        return _LANG_CACHE[code]
    path = LANG_DIR / f"{code}.json"
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("lang file must contain a top-level object")
        _LANG_CACHE[code] = data
        return data
    except FileNotFoundError:
        logger.warning("lang file not found: %s", path)
    except Exception as e:
        logger.warning("failed to load %s: %s", path, e)
    _LANG_CACHE[code] = {}
    return _LANG_CACHE[code]


def _load_user_langs() -> None:
    """Load per-user language preferences from USER_LANG_FILE."""
    global _USER_LANGS, _USER_LANGS_LOADED
    _USER_LANGS_LOADED = True
    try:
        if USER_LANG_FILE.exists():
            with open(USER_LANG_FILE, "r", encoding="utf-8") as f:
                raw = json.load(f)
            if isinstance(raw, dict):
                _USER_LANGS = {
                    int(k): v for k, v in raw.items()
                    if isinstance(v, str) and v in SUPPORTED_LANGS
                }
    except Exception as e:
        logger.warning("failed to load user_langs: %s", e)
        _USER_LANGS = {}


def _save_user_langs() -> None:
    """Persist per-user language preferences."""
    try:
        USER_LANG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(USER_LANG_FILE, "w", encoding="utf-8") as f:
            json.dump(
                {str(k): v for k, v in _USER_LANGS.items()},
                f, ensure_ascii=False, indent=2,
            )
    except Exception as e:
        logger.warning("failed to save user_langs: %s", e)


# ── Public API ────────────────────────────────────────────────────────────

def get_user_lang(user_id: Optional[int]) -> str:
    """Return the only supported operator language."""
    return "ru"


def set_user_lang(user_id: int, code: str) -> bool:
    """Set the per-user language preference and persist it."""
    if not _USER_LANGS_LOADED:
        _load_user_langs()
    code = (code or "").strip().lower()
    if code != "ru":
        return False
    _USER_LANGS[int(user_id)] = code
    _save_user_langs()
    return True


def get_language_name(code: str) -> str:
    return LANG_NAMES.get(code, code)


def t(user_id: Optional[int], key: str, default: Optional[str] = None) -> str:
    """Translate a key using the Russian operator dictionary."""
    table = _load_lang_file("ru")
    if key in table:
        return table[key]
    return default if default is not None else key


def tf(user_id: Optional[int], key: str, *args, default: Optional[str] = None) -> str:
    """Format a translated string with positional args using %-formatting."""
    template = t(user_id, key, default=default)
    try:
        return template % args if args else template
    except (TypeError, ValueError):
        return template
