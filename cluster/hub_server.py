#!/usr/bin/env python3
"""IGProxy Hub node registry.

The service is intentionally bound to loopback and is exposed only through the
hub site's HTTPS reverse proxy. Pairing codes are one-time, short-lived tokens;
node bearer tokens are stored as SHA-256 digests.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import hmac
import json
import os
import re
import secrets
import tempfile
import threading
import time
import urllib.parse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


HOST = os.getenv("IGPROXY_HUB_HOST", "127.0.0.1")
PORT = int(os.getenv("IGPROXY_HUB_PORT", "1990"))
STATE_DIR = Path(os.getenv("IGPROXY_HUB_STATE", "/opt/gotelegram"))
REGISTRY_PATH = STATE_DIR / "hub-registry.json"
CONFIG_PATH = Path(os.getenv("GOTELEGRAM_CONFIG", "/opt/gotelegram/config.json"))
LOCK_PATH = STATE_DIR / ".hub-registry.lock"
CONFIG_LOCK_PATH = Path(os.getenv("IGPROXY_CONFIG_LOCK", "/run/gotelegram/config.lock"))
MAX_BODY = 64 * 1024
ENROLLMENT_TTL = 30 * 60
NODE_STALE_AFTER = 180
MIN_HEARTBEAT_INTERVAL = 10
MAX_CONCURRENT_REQUESTS = 32


def now_epoch() -> int:
    return int(time.time())


def token_digest(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def atomic_json(path: Path, payload: Any, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, raw = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    temp = Path(raw)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def default_registry() -> dict[str, Any]:
    return {
        "schema": 1,
        "hub_id": secrets.token_hex(8),
        "enrollments": [],
        "nodes": [],
        "updated_at": now_epoch(),
    }


def load_registry() -> dict[str, Any]:
    try:
        data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        data = default_registry()
    if not isinstance(data, dict):
        data = default_registry()
    data.setdefault("schema", 1)
    data.setdefault("hub_id", secrets.token_hex(8))
    data.setdefault("enrollments", [])
    data.setdefault("nodes", [])
    return data


class RegistryLock:
    def __enter__(self) -> dict[str, Any]:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        self.stream = LOCK_PATH.open("a+", encoding="utf-8")
        os.chmod(LOCK_PATH, 0o600)
        fcntl.flock(self.stream.fileno(), fcntl.LOCK_EX)
        return load_registry()

    def __exit__(self, exc_type, exc, traceback) -> None:
        fcntl.flock(self.stream.fileno(), fcntl.LOCK_UN)
        self.stream.close()


class ConfigLock:
    def __enter__(self) -> None:
        CONFIG_LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
        self.stream = CONFIG_LOCK_PATH.open("a+", encoding="utf-8")
        os.chmod(CONFIG_LOCK_PATH, 0o600)
        fcntl.flock(self.stream.fileno(), fcntl.LOCK_EX)

    def __exit__(self, exc_type, exc, traceback) -> None:
        fcntl.flock(self.stream.fileno(), fcntl.LOCK_UN)
        self.stream.close()


def is_proxy_url(value: str) -> bool:
    try:
        parsed = urllib.parse.urlparse(value)
        query = urllib.parse.parse_qs(parsed.query)
    except ValueError:
        return False
    return (
        parsed.scheme == "https"
        and (parsed.hostname or "").lower() in {"t.me", "telegram.me", "telegram.dog"}
        and parsed.path.rstrip("/") == "/proxy"
        and all(query.get(key, [""])[0] for key in ("server", "port", "secret"))
    )


def clean_label(value: Any) -> str:
    label = re.sub(r"\s+", " ", str(value or "")).strip()
    if not 1 <= len(label) <= 48:
        raise ValueError("label must contain 1-48 characters")
    return label


def clean_node_id(value: Any) -> str:
    node_id = re.sub(r"[^a-z0-9_-]", "", str(value or "").lower())[:32]
    if not node_id:
        raise ValueError("invalid node id")
    return node_id


def public_node(node: dict[str, Any]) -> dict[str, Any]:
    last_seen = int(node.get("last_seen") or 0)
    return {
        "id": str(node.get("id") or ""),
        "label": str(node.get("label") or ""),
        "enabled": bool(node.get("enabled", True)),
        "approved": bool(node.get("approved", True)),
        "online": bool(last_seen and now_epoch() - last_seen <= NODE_STALE_AFTER),
        "last_seen": last_seen,
        "status": node.get("status") if isinstance(node.get("status"), dict) else {},
        "created_at": int(node.get("created_at") or 0),
    }


def sync_client_servers(registry: dict[str, Any]) -> None:
    with ConfigLock():
        try:
            config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            config = {}
        if not isinstance(config, dict):
            config = {}
        manual = [
            item
            for item in (config.get("client_servers") or [])
            if isinstance(item, dict) and not str(item.get("id") or "").startswith("node-")
        ]
        managed = []
        for node in registry.get("nodes") or []:
            if not isinstance(node, dict) or not node.get("approved", True):
                continue
            proxy_url = str(node.get("proxy_url") or "")
            if not is_proxy_url(proxy_url):
                continue
            managed.append(
                {
                    "id": f"node-{clean_node_id(node.get('id'))}",
                    "label": clean_label(node.get("label")),
                    "url": proxy_url,
                    "enabled": bool(node.get("enabled", True)),
                    "managed": True,
                }
            )
        config["client_servers"] = manual + managed
        config["cluster_nodes"] = [public_node(node) for node in registry.get("nodes") or []]
        atomic_json(CONFIG_PATH, config)


def create_enrollment_code(ttl: int = ENROLLMENT_TTL) -> tuple[str, int]:
    code = secrets.token_urlsafe(32)
    expires_at = now_epoch() + max(300, min(int(ttl), 86400))
    with RegistryLock() as registry:
        current = now_epoch()
        registry["enrollments"] = [
            item
            for item in registry.get("enrollments") or []
            if isinstance(item, dict) and int(item.get("expires_at") or 0) > current
        ]
        registry["enrollments"].append(
            {"digest": token_digest(code), "expires_at": expires_at, "created_at": current}
        )
        registry["updated_at"] = current
        atomic_json(REGISTRY_PATH, registry)
    return code, expires_at


def enroll_node(payload: dict[str, Any]) -> dict[str, Any]:
    # Codes are commonly copied from Telegram. Ignore formatting whitespace
    # added by the client while keeping the token itself exact.
    pairing_code = re.sub(r"\s+", "", str(payload.get("pairing_code") or ""))
    label = clean_label(payload.get("label"))
    proxy_url = str(payload.get("proxy_url") or "").strip()
    if not is_proxy_url(proxy_url):
        raise ValueError("invalid Telegram proxy URL")
    requested_id = re.sub(r"[^a-z0-9_-]", "", str(payload.get("install_id") or "").lower())[:24]
    pairing_digest = token_digest(pairing_code)
    current = now_epoch()
    with RegistryLock() as registry:
        matched = None
        valid = []
        for item in registry.get("enrollments") or []:
            if not isinstance(item, dict) or int(item.get("expires_at") or 0) <= current:
                continue
            if matched is None and hmac.compare_digest(
                str(item.get("digest") or ""), pairing_digest
            ):
                matched = item
                continue
            valid.append(item)
        if matched is None:
            raise PermissionError("pairing code is invalid or expired")

        node_id = requested_id or secrets.token_hex(8)
        if any(str(item.get("id")) == node_id for item in registry.get("nodes") or []):
            node_id = secrets.token_hex(8)
        node_token = secrets.token_urlsafe(48)
        node = {
            "id": node_id,
            "label": label,
            "token_digest": token_digest(node_token),
            "proxy_url": proxy_url,
            "enabled": True,
            "approved": True,
            "created_at": current,
            "last_seen": current,
            "status": payload.get("status") if isinstance(payload.get("status"), dict) else {},
        }
        registry["enrollments"] = valid
        registry["nodes"] = [
            item
            for item in registry.get("nodes") or []
            if isinstance(item, dict) and str(item.get("id")) != node_id
        ] + [node]
        registry["updated_at"] = current
        atomic_json(REGISTRY_PATH, registry)
        sync_client_servers(registry)
        return {
            "node_id": node_id,
            "node_token": node_token,
            "hub_id": registry["hub_id"],
            "heartbeat_interval": 30,
        }


def authenticate_node(registry: dict[str, Any], authorization: str) -> dict[str, Any]:
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise PermissionError("missing bearer token")
    digest = token_digest(token)
    for node in registry.get("nodes") or []:
        if isinstance(node, dict) and hmac.compare_digest(
            str(node.get("token_digest") or ""), digest
        ):
            return node
    raise PermissionError("invalid node token")


def heartbeat(payload: dict[str, Any], authorization: str) -> dict[str, Any]:
    current = now_epoch()
    # Reject invalid bearers before contending for the registry write lock.
    authenticate_node(load_registry(), authorization)
    with RegistryLock() as registry:
        node = authenticate_node(registry, authorization)
        previous_seen = int(node.get("last_seen") or 0)
        if previous_seen and current - previous_seen < MIN_HEARTBEAT_INTERVAL:
            return {
                "ok": True,
                "enabled": bool(node.get("enabled", True)),
                "server_time": current,
                "next_poll": MIN_HEARTBEAT_INTERVAL,
                "rate_limited": True,
            }
        if "label" in payload:
            node["label"] = clean_label(payload.get("label"))
        proxy_url = str(payload.get("proxy_url") or node.get("proxy_url") or "")
        if not is_proxy_url(proxy_url):
            raise ValueError("invalid Telegram proxy URL")
        node["proxy_url"] = proxy_url
        node["last_seen"] = current
        node["status"] = payload.get("status") if isinstance(payload.get("status"), dict) else {}
        registry["updated_at"] = current
        atomic_json(REGISTRY_PATH, registry)
        sync_client_servers(registry)
        return {
            "ok": True,
            "enabled": bool(node.get("enabled", True)),
            "server_time": current,
            "next_poll": 30,
        }


class HubHandler(BaseHTTPRequestHandler):
    server_version = "IGProxyHub/1"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"{self.client_address[0]} {fmt % args}")

    def send_payload(self, status: int, payload: dict[str, Any]) -> None:
        raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def read_payload(self) -> dict[str, Any]:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as exc:
            raise ValueError("invalid content length") from exc
        if length <= 0 or length > MAX_BODY:
            raise ValueError("invalid request size")
        try:
            value = json.loads(self.rfile.read(length))
        except json.JSONDecodeError as exc:
            raise ValueError("invalid JSON") from exc
        if not isinstance(value, dict):
            raise ValueError("JSON object expected")
        return value

    def do_GET(self) -> None:  # noqa: N802
        if urllib.parse.urlparse(self.path).path == "/v1/health":
            self.send_payload(HTTPStatus.OK, {"ok": True, "service": "igproxy-hub"})
            return
        self.send_payload(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        path = urllib.parse.urlparse(self.path).path
        try:
            payload = self.read_payload()
            if path == "/v1/enroll":
                result = enroll_node(payload)
            elif path == "/v1/heartbeat":
                result = heartbeat(payload, self.headers.get("Authorization", ""))
            else:
                self.send_payload(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found"})
                return
            self.send_payload(HTTPStatus.OK, {"ok": True, "data": result})
        except PermissionError as exc:
            self.send_payload(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": str(exc)})
        except ValueError as exc:
            self.send_payload(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
        except OSError:
            self.send_payload(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {"ok": False, "error": "registry unavailable"},
            )


class BoundedThreadingHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 64

    def __init__(self, server_address, handler_class):
        super().__init__(server_address, handler_class)
        self._request_slots = threading.BoundedSemaphore(MAX_CONCURRENT_REQUESTS)

    def process_request(self, request, client_address):
        if not self._request_slots.acquire(blocking=False):
            request.close()
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self._request_slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._request_slots.release()


def serve() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if not REGISTRY_PATH.exists():
        atomic_json(REGISTRY_PATH, default_registry())
    server = BoundedThreadingHTTPServer((HOST, PORT), HubHandler)
    print(f"IGProxy Hub listening on http://{HOST}:{PORT}")
    server.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command")
    create = sub.add_parser("create-code")
    create.add_argument("--ttl", type=int, default=ENROLLMENT_TTL)
    sub.add_parser("list-nodes")
    args = parser.parse_args()
    if args.command == "create-code":
        code, expires_at = create_enrollment_code(args.ttl)
        print(json.dumps({"code": code, "expires_at": expires_at}, separators=(",", ":")))
    elif args.command == "list-nodes":
        print(
            json.dumps(
                [public_node(node) for node in load_registry().get("nodes") or []],
                ensure_ascii=False,
                separators=(",", ":"),
            )
        )
    else:
        serve()


if __name__ == "__main__":
    main()
