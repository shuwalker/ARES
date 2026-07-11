"""
ARES Execution Backend Router.

Pure ARES code. Decides whether to use Hermes, JROS, or both (hybrid)
without modifying either framework.
"""

from __future__ import annotations

from typing import Dict

from .base import AgenticBackend, BackendRouter
from .hermes import HermesBackend
from .jros import JROSBackend
from .hybrid import HybridBackend


def get_default_router() -> BackendRouter:
    """Factory that returns the canonical ARES router with peer backends."""
    backends: Dict[str, AgenticBackend] = {
        "hermes": HermesBackend(),
        "jros": JROSBackend(),
        "hybrid": HybridBackend(),
    }
    return BackendRouter(backends)


# Singleton for the running WebUI instance
_router: BackendRouter | None = None


def get_router() -> BackendRouter:
    global _router
    if _router is None:
        _router = get_default_router()
    return _router
