"""Process-level hardening used by the Uvicorn lifecycle."""

from __future__ import annotations

import signal
import os
import re
import socket
from typing import Any

try:
    import resource
except ImportError:  # pragma: no cover - Windows
    resource = None


_NETWORK_ISOLATION_INSTALLED = False


def _test_address_is_local(host: object) -> bool:
    """Bounded allowlist used only by the isolated subprocess test server."""

    if not isinstance(host, str):
        return False
    value = host.strip().lower()
    if not value:
        return False
    if value in {"::1", "0:0:0:0:0:0:0:1", "localhost"}:
        return True
    if value.startswith("fe80:") or re.match(r"^f[cd][0-9a-f]{0,2}:", value):
        return True
    if value.endswith((".localhost", ".local", ".test", ".invalid", ".example")):
        return True
    if value in {"example.com", "example.net", "example.org"}:
        return True
    if value.endswith((".example.com", ".example.net", ".example.org")):
        return True
    try:
        octets = [int(part) for part in value.split(".")]
    except ValueError:
        return False
    if len(octets) != 4 or any(part < 0 or part > 255 for part in octets):
        return False
    first, second, _third, _fourth = octets
    return (
        first in {10, 127}
        or (first == 192 and second == 168)
        or (first == 172 and 16 <= second <= 31)
        or (first == 169 and second == 254)
        or (first == 203 and second == 0)
    )


def install_test_network_isolation() -> bool:
    """Block outbound sockets in explicitly isolated test subprocesses.

    The environment switch is set only by the test harness. Keeping this at
    the ASGI process boundary preserves hermetic HTTP integration tests after
    removal of the former ``BaseHTTPRequestHandler`` launcher.
    """

    global _NETWORK_ISOLATION_INSTALLED
    enabled = os.getenv("ARES_WEBUI_TEST_NETWORK_BLOCK", "").strip().lower()
    if enabled not in {"1", "true", "yes", "on"} or _NETWORK_ISOLATION_INSTALLED:
        return False
    real_create_connection = socket.create_connection
    real_socket_connect = socket.socket.connect

    def blocked_create_connection(address, *args, **kwargs):
        host = address[0] if isinstance(address, tuple) and address else ""
        if _test_address_is_local(host):
            return real_create_connection(address, *args, **kwargs)
        raise OSError(f"ares test network isolation: outbound socket to {address!r} is blocked")

    def blocked_socket_connect(instance, address):
        host = address[0] if isinstance(address, tuple) and address else ""
        if _test_address_is_local(host):
            return real_socket_connect(instance, address)
        raise OSError(f"ares test network isolation: socket.connect to {address!r} is blocked")

    socket.create_connection = blocked_create_connection
    socket.socket.connect = blocked_socket_connect
    _NETWORK_ISOLATION_INSTALLED = True
    return True


def ignore_sigpipe() -> bool:
    sigpipe = getattr(signal, "SIGPIPE", None)
    if sigpipe is None:
        return False
    try:
        signal.signal(sigpipe, signal.SIG_IGN)
    except (OSError, ValueError):
        return False
    return True


def raise_fd_soft_limit(target: int = 4096) -> dict[str, Any]:
    if resource is None:
        return {"status": "unsupported"}
    try:
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    except Exception as exc:
        return {"status": "error", "error": str(exc)}
    desired = int(target)
    infinity = getattr(resource, "RLIM_INFINITY", -1)
    if hard not in {-1, infinity}:
        desired = min(desired, int(hard))
    if soft >= desired:
        return {"status": "unchanged", "soft": soft, "hard": hard}
    try:
        resource.setrlimit(resource.RLIMIT_NOFILE, (desired, hard))
    except Exception as exc:
        return {"status": "error", "soft": soft, "hard": hard, "error": str(exc)}
    return {"status": "raised", "soft": desired, "hard": hard, "previous_soft": soft}


def configure_process_runtime() -> dict[str, Any]:
    return {
        "sigpipe_ignored": ignore_sigpipe(),
        "file_descriptors": raise_fd_soft_limit(),
        "test_network_isolation": install_test_network_isolation(),
    }


__all__ = [
    "configure_process_runtime",
    "ignore_sigpipe",
    "install_test_network_isolation",
    "raise_fd_soft_limit",
]
