"""Provider packages for the workers ARES routes turns to.

ARES is the Companion: it never executes inference itself, it routes turns to
workers (Hermes, JaegerAI, Ollama, cloud models). Each worker owns a
subpackage here containing its backend, its execution/streaming code, and a
``status.py`` exposing ``check_status()``.

Two rules hold this together:

* **No provider imports another provider.** Anything genuinely universal lives
  in this package's own modules (:mod:`api.providers.status_contract` for the
  status contract, :mod:`api.providers.agentic_backend` for ``AgenticBackend``),
  never inside a provider folder.
* **Only status is standardized.** Execution shapes differ irreconcilably —
  JaegerAI has three (HTTP gateway, local bridge subprocess, native app),
  Ollama is a plain HTTP server, cloud providers are authenticated REST — so
  each provider implements execution however it must.

Provider *credential* management is a separate concern and lives in
:mod:`api.provider_credentials`. It is deliberately not a submodule here: many
tests monkeypatch that module's globals directly, which only works if it stays a
real module rather than a name re-exported through a package.
"""
from __future__ import annotations

from .status_contract import (
    BLOCKING_STATES,
    ProviderProbe,
    ProviderStatus,
    ProviderStatusState,
    connected,
    needs_attention,
    not_configured,
    not_installed,
    offline,
)

__all__ = [
    "BLOCKING_STATES",
    "ProviderProbe",
    "ProviderStatus",
    "ProviderStatusState",
    "connected",
    "needs_attention",
    "not_configured",
    "not_installed",
    "offline",
]
