"""
ARES execution backend router. JaegerAI/JROS owns conversation turns.
"""

from __future__ import annotations

from typing import Dict

from .base import AgenticBackend, BackendRouter
from .jros import JROSBackend


def get_default_router() -> BackendRouter:
    """Return the canonical router with Jaeger as the sole turn owner."""
    backends: Dict[str, AgenticBackend] = {
        "jros": JROSBackend(),
    }
    return BackendRouter(backends)


# Singleton for the running WebUI instance
_router: BackendRouter | None = None


def get_router() -> BackendRouter:
    global _router
    if _router is None:
        _router = get_default_router()
    return _router
