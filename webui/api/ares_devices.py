"""ARES device mesh primitives.

This module is intentionally small and additive. It gives ARES a stable way to
answer: is this install the primary AI body, or a device joined to an existing
AI? Later resource sharing and offline sync can build on this registry without
rewriting chat, Hermes, or JROS.
"""

from __future__ import annotations

import ipaddress
import os
import platform
import re
import shutil
import socket
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen

import yaml


VALID_ROLES = {"primary", "device"}
DEFAULT_AI_ID = "ares-main"
DEFAULT_CONTINUITY_DIR = Path("~/Desktop/ARES/00_System/ares").expanduser()


def _clean(value: Any) -> str:
    return str(value or "").strip()


def _slug(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9_.-]+", "-", value.strip().lower()).strip("-._")
    return slug or "ares-device"


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _env_or_config(config: dict[str, Any] | None, env_key: str, config_key: str, default: str = "") -> str:
    env_value = _clean(os.environ.get(env_key))
    if env_value:
        return env_value
    if isinstance(config, dict):
        return _clean(config.get(config_key))
    return default


def normalize_role(value: Any) -> str:
    role = _clean(value).lower()
    return role if role in VALID_ROLES else "primary"


def local_hostname() -> str:
    return _clean(socket.gethostname()) or _clean(platform.node()) or "ares-device"


def default_device_id() -> str:
    return _slug(local_hostname().split(".")[0])


def continuity_dir(config: dict[str, Any] | None = None) -> Path:
    raw = _env_or_config(config, "ARES_CONTINUITY_DIR", "ares_continuity_dir")
    if raw:
        return Path(os.path.expandvars(raw)).expanduser()
    return DEFAULT_CONTINUITY_DIR


def registry_path(config: dict[str, Any] | None = None) -> Path:
    return continuity_dir(config) / "devices.yaml"


def load_registry(config: dict[str, Any] | None = None) -> dict[str, Any]:
    path = registry_path(config)
    try:
        if path.exists():
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
            if isinstance(data, dict):
                devices = data.get("devices")
                if not isinstance(devices, dict):
                    data["devices"] = {}
                return data
    except Exception:
        pass
    return {"ai_id": DEFAULT_AI_ID, "primary_device_id": "", "devices": {}}


def save_registry(registry: dict[str, Any], config: dict[str, Any] | None = None) -> dict[str, Any]:
    path = registry_path(config)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = dict(registry or {})
    payload.setdefault("ai_id", DEFAULT_AI_ID)
    payload.setdefault("primary_device_id", "")
    payload.setdefault("devices", {})
    path.write_text(yaml.safe_dump(payload, sort_keys=True), encoding="utf-8")
    return payload


def _tailscale_ip() -> str:
    tailscale = shutil.which("tailscale")
    if not tailscale:
        return ""
    try:
        result = subprocess.run(
            [tailscale, "ip", "-4"],
            check=False,
            capture_output=True,
            text=True,
            timeout=1.0,
        )
    except Exception:
        return ""
    for line in result.stdout.splitlines():
        value = line.strip()
        try:
            ip = ipaddress.ip_address(value)
        except ValueError:
            continue
        if ip.version == 4:
            return value
    return ""


def _local_lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            return sock.getsockname()[0]
    except Exception:
        return ""


def _webui_url() -> str:
    try:
        from api.config import HOST, PORT

        return f"http://{HOST}:{PORT}"
    except Exception:
        host = os.environ.get("HERMES_WEBUI_HOST", "127.0.0.1")
        port = os.environ.get("HERMES_WEBUI_PORT", "8787")
        return f"http://{host}:{port}"


def detect_capabilities(config: dict[str, Any] | None = None) -> dict[str, bool]:
    try:
        from api.backend_selector import backend_status

        backend = backend_status()
    except Exception:
        backend = {}
    system = platform.system().lower()
    return {
        "mac_app": system == "darwin",
        "webui": True,
        "jros": bool(backend.get("jros")),
        "hermes": bool(backend.get("hermes")),
        "hybrid": bool(backend.get("hybrid")),
        "local_tools": True,
        "filesystem": True,
        "terminal": True,
        "offline_mode": True,
        "compute_worker": shutil.which("python") is not None or shutil.which("python3") is not None,
        "rendering": shutil.which("ffmpeg") is not None or shutil.which("blender") is not None,
        "xcode_builds": shutil.which("xcodebuild") is not None,
    }


def device_config(config: dict[str, Any] | None = None) -> dict[str, Any]:
    cfg = config or {}
    role = normalize_role(_env_or_config(cfg, "ARES_ROLE", "ares_role", "primary"))
    device_id = _env_or_config(cfg, "ARES_DEVICE_ID", "ares_device_id") or default_device_id()
    device_name = _env_or_config(cfg, "ARES_DEVICE_NAME", "ares_device_name") or local_hostname()
    ai_id = _env_or_config(cfg, "ARES_AI_ID", "ares_ai_id", DEFAULT_AI_ID) or DEFAULT_AI_ID
    primary_url = _env_or_config(cfg, "ARES_PRIMARY_URL", "ares_primary_url")
    primary_device_id = _env_or_config(cfg, "ARES_PRIMARY_DEVICE_ID", "ares_primary_device_id")
    if role == "primary" and not primary_device_id:
        primary_device_id = device_id
    return {
        "role": role,
        "device_id": _slug(device_id),
        "device_name": device_name,
        "ai_id": _slug(ai_id),
        "primary_url": primary_url,
        "primary_device_id": _slug(primary_device_id) if primary_device_id else "",
        "continuity_dir": str(continuity_dir(cfg)),
    }


def _primary_reachable(primary_url: str) -> bool | None:
    url = _clean(primary_url).rstrip("/")
    if not url:
        return None
    try:
        request = Request(f"{url}/health", method="GET")
        with urlopen(request, timeout=1.5) as response:
            return 200 <= int(response.status) < 500
    except Exception:
        return False


def local_device_record(config: dict[str, Any] | None = None) -> dict[str, Any]:
    dev = device_config(config)
    tailscale_ip = _tailscale_ip()
    lan_ip = _local_lan_ip()
    record = {
        **dev,
        "hostname": local_hostname(),
        "platform": platform.platform(),
        "system": platform.system(),
        "machine": platform.machine(),
        "tailscale_ip": tailscale_ip,
        "lan_ip": lan_ip,
        "webui_url": _webui_url(),
        "capabilities": detect_capabilities(config),
        "last_seen": _now_iso(),
    }
    return record


def device_status(config: dict[str, Any] | None = None) -> dict[str, Any]:
    record = local_device_record(config)
    registry = load_registry(config)
    primary_url = record.get("primary_url") or ""
    return {
        "ai_id": record["ai_id"],
        "role": record["role"],
        "is_primary": record["role"] == "primary",
        "device": record,
        "primary": {
            "device_id": record.get("primary_device_id") or registry.get("primary_device_id") or "",
            "url": primary_url,
            "reachable": _primary_reachable(primary_url) if record["role"] == "device" else True,
        },
        "continuity_dir": record["continuity_dir"],
        "registry_path": str(registry_path(config)),
        "registered": record["device_id"] in (registry.get("devices") or {}),
        "registry_device_count": len(registry.get("devices") or {}),
        "server_time": _now_iso(),
    }


def register_device(record: dict[str, Any] | None = None, config: dict[str, Any] | None = None) -> dict[str, Any]:
    current = local_device_record(config)
    incoming = dict(record or current)
    device_id = _slug(_clean(incoming.get("device_id")) or current["device_id"])
    incoming["device_id"] = device_id
    incoming.setdefault("last_seen", _now_iso())
    incoming.setdefault("capabilities", {})

    registry = load_registry(config)
    registry["ai_id"] = _slug(_clean(incoming.get("ai_id")) or _clean(registry.get("ai_id")) or DEFAULT_AI_ID)
    if incoming.get("role") == "primary" or not _clean(registry.get("primary_device_id")):
        registry["primary_device_id"] = device_id
    registry.setdefault("devices", {})
    hostname = _clean(incoming.get("hostname"))
    if hostname:
        for existing_id, existing in list(registry["devices"].items()):
            if existing_id == device_id or not isinstance(existing, dict):
                continue
            if _clean(existing.get("hostname")) == hostname and _clean(existing.get("role")) == _clean(incoming.get("role")):
                registry["devices"].pop(existing_id, None)
    registry["devices"][device_id] = incoming
    registry["updated_at"] = _now_iso()
    saved = save_registry(registry, config)
    return {"ok": True, "device": incoming, "registry": saved, "registry_path": str(registry_path(config))}


def normalize_config_update(body: dict[str, Any] | None, current: dict[str, Any] | None = None) -> dict[str, Any]:
    data = body or {}
    cfg = current or {}
    updates: dict[str, Any] = {}
    if "role" in data:
        updates["ares_role"] = normalize_role(data.get("role"))
    if "device_id" in data:
        updates["ares_device_id"] = _slug(_clean(data.get("device_id")) or default_device_id())
    if "device_name" in data:
        updates["ares_device_name"] = _clean(data.get("device_name")) or local_hostname()
    if "ai_id" in data:
        updates["ares_ai_id"] = _slug(_clean(data.get("ai_id")) or DEFAULT_AI_ID)
    if "primary_url" in data:
        updates["ares_primary_url"] = _clean(data.get("primary_url"))
    if "primary_device_id" in data:
        updates["ares_primary_device_id"] = _slug(_clean(data.get("primary_device_id")))
    if "continuity_dir" in data:
        updates["ares_continuity_dir"] = str(Path(os.path.expandvars(_clean(data.get("continuity_dir")))).expanduser())

    merged = {**cfg, **updates}
    dev = device_config(merged)
    if dev["role"] == "primary":
        updates.setdefault("ares_primary_device_id", dev["device_id"])
    return updates
