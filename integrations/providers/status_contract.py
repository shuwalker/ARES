"""Shared status contract every ARES provider implements.

ARES is the Companion: it routes turns to workers (Hermes, JaegerAI, Ollama,
cloud models) and never executes inference itself. Providers differ wildly in
how they run a turn -- JaegerAI has three execution modes (HTTP gateway, local
bridge subprocess over NDJSON, native app), Ollama is a plain local HTTP server,
cloud providers are authenticated REST APIs. Execution therefore stays
free-form inside each ``api/providers/<name>/`` package.

What every provider *does* owe the product is an honest answer to "can I run a
turn right now, and if not, why not". That is this module's only concern:
:func:`check_status`-shaped functions returning :class:`ProviderStatus`.

Both registries (``fastapi_app.adapters.registry.AdapterRegistry`` and the older
``api.backends.router.BackendRouter``) delegate their per-provider health to
these functions, so they cannot drift into disagreeing about the same provider.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Protocol, runtime_checkable


class ProviderStatusState(str, Enum):
    """Why a provider can or cannot run a turn.

    The distinction matters to users, not just to code: "you never set this up"
    and "this is installed but crashed" need different actions, and collapsing
    them into a single ``offline`` (as ARES did previously) tells the user
    nothing about what to do next.
    """

    #: Software is present but required configuration is missing -- an API key,
    #: an endpoint URL. Fix is to configure it.
    NOT_CONFIGURED = "not_configured"

    #: Required software is absent -- CLI not on PATH, runtime not installed.
    #: Fix is to install it.
    NOT_INSTALLED = "not_installed"

    #: Installed and configured, but unreachable right now -- process down,
    #: connection refused, probe timed out. Fix is to start it.
    OFFLINE = "offline"

    #: Reachable but not fully usable -- e.g. running with no companion agent
    #: created, or no model loaded. Usable for some operations, not all.
    NEEDS_ATTENTION = "needs_attention"

    #: Ready to run turns.
    CONNECTED = "connected"


#: States a provider can be in without being able to accept a turn. Callers that
#: need to gate sending should test ``status.available`` rather than comparing
#: against this set; it exists for UI grouping and for explaining *why*.
BLOCKING_STATES = frozenset(
    {
        ProviderStatusState.NOT_CONFIGURED,
        ProviderStatusState.NOT_INSTALLED,
        ProviderStatusState.OFFLINE,
    }
)


@dataclass(frozen=True)
class ProviderStatus:
    """A provider's readiness, with enough detail for the UI to explain it."""

    state: ProviderStatusState
    message: str
    details: dict[str, Any] = field(default_factory=dict)

    @property
    def available(self) -> bool:
        """Whether a turn can be dispatched to this provider right now.

        Derived rather than stored so ``state`` and ``available`` cannot
        contradict each other. ``NEEDS_ATTENTION`` counts as available: the
        provider answers, and refusing to dispatch would hide a runtime that
        can in fact serve some requests.
        """
        return self.state in (
            ProviderStatusState.CONNECTED,
            ProviderStatusState.NEEDS_ATTENTION,
        )

    def as_dict(self) -> dict[str, Any]:
        """Serialize for the adapter/connection REST contract."""
        return {
            "state": self.state.value,
            "available": self.available,
            "message": self.message,
            "details": dict(self.details),
        }


def connected(message: str, **details: Any) -> ProviderStatus:
    return ProviderStatus(ProviderStatusState.CONNECTED, message, details)


def needs_attention(message: str, **details: Any) -> ProviderStatus:
    return ProviderStatus(ProviderStatusState.NEEDS_ATTENTION, message, details)


def offline(message: str, **details: Any) -> ProviderStatus:
    return ProviderStatus(ProviderStatusState.OFFLINE, message, details)


def not_installed(message: str, **details: Any) -> ProviderStatus:
    return ProviderStatus(ProviderStatusState.NOT_INSTALLED, message, details)


def not_configured(message: str, **details: Any) -> ProviderStatus:
    return ProviderStatus(ProviderStatusState.NOT_CONFIGURED, message, details)


@runtime_checkable
class ProviderProbe(Protocol):
    """The one contract a provider package must satisfy."""

    def check_status(self) -> ProviderStatus: ...
