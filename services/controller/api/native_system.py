"""Device-global contract between the controller and the native ARES shell.

The controller persists user intent and accepts authenticated commands. The
native macOS app is the only process allowed to apply native preferences or
own the controller lifecycle. Runtime state is a heartbeat written by that app;
desired and effective values are deliberately reported separately.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import time
from typing import Any
from uuid import uuid4


NATIVE_HEARTBEAT_TTL_SECONDS = 6.0
DEFAULT_NATIVE_SETTINGS: dict[str, Any] = {
    "menu_bar_enabled": True,
    "launch_at_login": False,
    "quick_launch_enabled": True,
    "quick_launch_shortcut": "command+shift+space",
    "background_operation": True,
}
NATIVE_CAPABILITIES = (
    "menu_bar",
    "launch_at_login",
    "quick_launch",
    "background_operation",
    "server_restart",
)


@dataclass
class NativeSystemContractError(Exception):
    status_code: int
    message: str

    def __str__(self) -> str:
        return self.message


def native_state_directory() -> Path:
    configured = os.getenv("ARES_NATIVE_STATE_DIR", "").strip()
    if configured:
        return Path(configured).expanduser().resolve()
    return Path(os.getenv("ARES_HOME") or (Path.home() / ".ares")).expanduser().resolve()


def native_settings_path() -> Path:
    return native_state_directory() / "native-system-settings.json"


def native_runtime_path() -> Path:
    return native_state_directory() / "native-runtime.json"


def native_command_path() -> Path:
    return native_state_directory() / "native-command.json"


def _read_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.{uuid4().hex}.tmp")
    temporary.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def load_native_settings() -> dict[str, Any]:
    stored = _read_json(native_settings_path())
    return {**DEFAULT_NATIVE_SETTINGS, **{key: stored[key] for key in DEFAULT_NATIVE_SETTINGS if key in stored}}


def save_native_settings(patch: dict[str, Any]) -> dict[str, Any]:
    current = load_native_settings()
    current.update({key: value for key, value in patch.items() if key in DEFAULT_NATIVE_SETTINGS})
    _write_json(native_settings_path(), current)
    return current


def _runtime_snapshot(now: float | None = None) -> tuple[dict[str, Any], bool]:
    runtime = _read_json(native_runtime_path())
    heartbeat = runtime.get("heartbeat_unix")
    expected_instance = os.getenv("ARES_RUNTIME_INSTANCE_ID", "").strip()
    actual_instance = str(runtime.get("instance_id") or "").strip()
    current_time = time.time() if now is None else now
    fresh = isinstance(heartbeat, (int, float)) and current_time - float(heartbeat) <= NATIVE_HEARTBEAT_TTL_SECONDS
    matches = bool(expected_instance and actual_instance == expected_instance)
    managed = os.getenv("ARES_RUNTIME_OWNER", "").strip() == "mac_app"
    return runtime, bool(managed and fresh and matches)


def native_system_status(*, now: float | None = None) -> dict[str, Any]:
    runtime, connected = _runtime_snapshot(now=now)
    desired = load_native_settings()
    capabilities = runtime.get("capabilities") if connected else None
    if not isinstance(capabilities, dict):
        capabilities = {name: False for name in NATIVE_CAPABILITIES}
    else:
        capabilities = {name: bool(capabilities.get(name, False)) for name in NATIVE_CAPABILITIES}

    effective = runtime.get("effective") if connected else None
    if not isinstance(effective, dict):
        effective = {key: None for key in DEFAULT_NATIVE_SETTINGS}

    host = os.getenv("ARES_WEBUI_HOST", "127.0.0.1")
    try:
        port = int(os.getenv("ARES_WEBUI_PORT", "8788"))
    except ValueError:
        port = 8788

    return {
        "contract_version": 1,
        "native_app": {
            "connected": connected,
            "instance_id": str(runtime.get("instance_id") or "") if connected else "",
            "pid": runtime.get("app_pid") if connected else None,
            "last_seen_unix": runtime.get("heartbeat_unix") if connected else None,
        },
        "controller": {
            "running": True,
            "pid": os.getpid(),
            "host": host,
            "port": port,
            "owner": os.getenv("ARES_RUNTIME_OWNER", "standalone") or "standalone",
            "managed_by_mac_app": os.getenv("ARES_RUNTIME_OWNER", "") == "mac_app",
            "instance_id": os.getenv("ARES_RUNTIME_INSTANCE_ID", ""),
        },
        "desired": desired,
        "effective": effective,
        "capabilities": capabilities,
        "last_action": runtime.get("last_action") if connected else None,
        "message": (
            "Native ARES app connected."
            if connected
            else "Native controls are unavailable. Launch the ARES Mac app to manage this computer."
        ),
    }


def require_native_app() -> dict[str, Any]:
    status = native_system_status()
    if not status["native_app"]["connected"]:
        raise NativeSystemContractError(
            409,
            "The ARES Mac app is not connected; native settings were not changed.",
        )
    return status


def update_native_settings(patch: dict[str, Any]) -> dict[str, Any]:
    require_native_app()
    save_native_settings(patch)
    return native_system_status()


def enqueue_native_action(action: str) -> dict[str, Any]:
    status = require_native_app()
    if action != "restart_server":
        raise NativeSystemContractError(400, f"Unsupported native action: {action}")
    if not status["capabilities"].get("server_restart"):
        raise NativeSystemContractError(409, "The connected ARES Mac app cannot restart the controller.")
    command = {
        "contract_version": 1,
        "id": uuid4().hex,
        "action": action,
        "requested_at_unix": time.time(),
        "instance_id": status["native_app"]["instance_id"],
    }
    _write_json(native_command_path(), command)
    return {"accepted": True, "command_id": command["id"], "action": action}
