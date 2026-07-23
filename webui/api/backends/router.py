"""ARES Backend Router — dynamic registry with fallback chains.

Backends register themselves via ``BackendRegistry.register()`` at import time.
The router queries the registry for available backends and supports fallback
chains so if the primary backend is unavailable, alternatives are tried.

Paperclip pattern: every adapter is just {name}_{deployment}. No roles, no opinions.
"""
from __future__ import annotations

from typing import Dict, List

from .base import AgenticBackend
from .cli_backends import BackendRegistry


class BackendRouter:
    """Dynamic backend registry with fallback chains.

    Backends register themselves at import time. The router only
    instantiates backends that are currently available.
    """

    def __init__(self):
        self._backends: dict[str, AgenticBackend] = {}
        # Instances added via register() (hatched workers, plugins). Kept
        # separately because _refresh() rebuilds _backends from the class
        # registry — without this, every select() silently dropped them.
        self._runtime_backends: dict[str, AgenticBackend] = {}
        self._refresh()

    def _refresh(self) -> None:
        """Re-scan the registry for available backends."""
        backends = BackendRegistry.get_available()
        for name, backend in self._runtime_backends.items():
            try:
                if backend.is_available():
                    backends[name] = backend
            except Exception:
                continue
        self._backends = backends

    def select(self, requested: str, fallbacks: list[str] | None = None) -> AgenticBackend | None:
        """Select a backend by name, with optional fallback chain.

        If the requested backend is unavailable, tries each fallback in order.
        If none are available, returns None.
        """
        # Refresh availability cache
        self._refresh()

        # Try requested backend
        backend = self._backends.get(requested)
        if backend is not None:
            return backend

        # Try fallbacks in order
        if fallbacks:
            for name in fallbacks:
                fb = self._backends.get(name)
                if fb is not None:
                    return fb

        return None

    def select_worker(self, requested: str, fallbacks: list[str] | None = None) -> tuple:
        """Select a backend and return its worker target.

        Raises LookupError if no backend in the chain is available.
        """
        backend = self.select(requested, fallbacks=fallbacks)
        if backend is None:
            chain = [requested] + (fallbacks or [])
            raise LookupError(f"None of the requested runtimes are available: {', '.join(chain)}")
        return backend.get_worker_target()

    def register(self, name: str, backend: AgenticBackend) -> None:
        """Register a backend instance at runtime (plugin pattern)."""
        self._runtime_backends[name] = backend
        self._backends[name] = backend

    def unregister(self, name: str) -> None:
        self._runtime_backends.pop(name, None)
        self._backends.pop(name, None)

    def list_available(self) -> Dict[str, AgenticBackend]:
        """Return only backends that are currently available."""
        self._refresh()
        return dict(self._backends)

    def list_all(self) -> Dict[str, AgenticBackend]:
        """Return all registered backends (available or not)."""
        all_backends = BackendRegistry.get_all()
        # Merge in any runtime-registered backends (available or not).
        for name, backend in self._runtime_backends.items():
            if name not in all_backends:
                all_backends[name] = backend
        return all_backends

    @property
    def backends(self) -> Dict[str, AgenticBackend]:
        """Public accessor for backward compatibility."""
        self._refresh()
        return dict(self._backends)


_router: BackendRouter | None = None


def get_router() -> BackendRouter:
    """Get or create the singleton router."""
    global _router
    if _router is None:
        _router = BackendRouter()
    return _router


def get_default_router() -> BackendRouter:
    """Factory returning a fresh router (for testing)."""
    return BackendRouter()
