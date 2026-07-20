"""Registry for schedule/result channel-delivery adapters.

Channel delivery (Telegram/Discord/Slack/Feishu/etc.) is adapter-owned and
detected, never hardcoded — ARES ships no platform credentials. A delivery
adapter is a callable registered for a platform name; when none is registered,
`get_delivery_adapter` returns None and callers treat the destination as "not
configured" rather than silently claiming a delivery succeeded.

An adapter is called as `adapter(target=..., content=..., job=...)` and should
raise on failure. Adapters are registered by whatever integration configures a
real delivery connection for the active profile.
"""

from __future__ import annotations

from typing import Any, Callable

DeliveryAdapter = Callable[..., None]

_ADAPTERS: dict[str, DeliveryAdapter] = {}


def register_delivery_adapter(platform: str, adapter: DeliveryAdapter) -> None:
    """Register a delivery adapter for a platform (e.g. 'telegram')."""
    key = str(platform or "").strip().lower()
    if not key:
        raise ValueError("platform is required")
    _ADAPTERS[key] = adapter


def unregister_delivery_adapter(platform: str) -> None:
    _ADAPTERS.pop(str(platform or "").strip().lower(), None)


def get_delivery_adapter(platform: str) -> DeliveryAdapter | None:
    """Return the adapter for a platform, or None if none is configured."""
    return _ADAPTERS.get(str(platform or "").strip().lower())


def registered_platforms() -> list[str]:
    return sorted(_ADAPTERS)


def _reset_for_tests() -> None:
    """Clear all registered adapters (test isolation helper)."""
    _ADAPTERS.clear()
