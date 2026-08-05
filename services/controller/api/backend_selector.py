"""ARES Backend Selector — routes agent execution to any registered backend.

Paperclip pattern: flat registry, agnostic naming. Each backend is
{name}_{deployment}. No roles, no opinions. The UI iterates the map.
"""
from __future__ import annotations

import logging

from .backends.router import get_router
from .backend_catalog import (
    JAEGER_BACKEND_ID,
    VALID_BACKEND_IDS,
    backend_display_name,
    normalize_backend_id,
)

logger = logging.getLogger(__name__)

BACKEND_JAEGER = JAEGER_BACKEND_ID
VALID_BACKENDS = VALID_BACKEND_IDS

def normalize_backend(value: object, *, fallback: str = "") -> str:
    return normalize_backend_id(value, fallback=fallback)


def get_active_backend(config: dict) -> str:
    """Return the explicitly elected external runtime, or an empty string."""
    return normalize_backend((config or {}).get("ares_backend", ""))


def get_session_backend(session: object, config: dict) -> str:
    default_backend = get_active_backend(config)
    return normalize_backend(getattr(session, "ares_backend", None), fallback=default_backend)


def is_jros_available() -> bool:
    """Whether JaegerAI can run a turn right now, by any of its transports.

    Thin wrapper over :func:`api.providers.jaeger.status.check_status` so legacy
    boolean callers keep working. It used to probe only the HTTP gateway and
    treat a local install as "detected, not available" — but the local bridge is
    the path ``gateway_streaming`` actually executes through when no gateway URL
    is set, so a working bridge-only install was reported as not installed.
    """

    from api.providers.jaeger.status import check_status

    return check_status().available


def jros_gateway_details() -> dict:
    """Non-secret details from the last JaegerAI status probe.

    Includes ``mode`` (``gateway`` or ``bridge``) so callers can tell which
    transport answered.
    """

    from api.providers.jaeger.status import check_status

    return dict(check_status().details or {})


def backend_status() -> dict:
    """Return current backend availability for UI display.

    Note: this probes *every* registered backend and is intentionally not used
    on the chat start hot path (use :func:`is_jros_available` /
    per-backend ``is_available`` instead).
    """
    router = get_router()
    status = {
        name: backend.is_available()
        for name, backend in router.list_all().items()
        if normalize_backend(name) != JAEGER_BACKEND_ID
    }
    jros_available = is_jros_available()
    status[JAEGER_BACKEND_ID] = jros_available
    if jros_available:
        for key, value in jros_gateway_details().items():
            status[f"jaeger_{key}"] = value
    return status


def backend_label(backend: str) -> str:
    """Human-readable label for the backend selector dropdown."""
    return backend_display_name(backend) or backend
