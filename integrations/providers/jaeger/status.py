"""JaegerAI readiness across all three of its execution paths.

JaegerAI is the hardest case in the provider layout, and the reason the status
contract is deliberately transport-agnostic: it can serve a turn through an HTTP
gateway, through a local ``jaeger bridge`` subprocess speaking NDJSON over
stdio, or not at all. ``gateway_streaming`` picks between the first two at turn
time, preferring the **local bridge** whenever no gateway URL is configured.

The previous check (``api.backend_selector.is_jros_available``) only probed the
gateway, and its docstring stated the intent plainly: "A local checkout alone is
install-detected, not available." That was wrong in practice — the bridge is the
default execution path, not a fallback — so a perfectly working bridge-only
install reported "JaegerAI is not installed or reachable." and was filtered out
of the model picker entirely.

This module reports on whichever transport would actually run the next turn.
"""
from __future__ import annotations

import logging
import os
import time

from api.providers.status_contract import (
    ProviderStatus,
    connected,
    not_installed,
    offline,
)

logger = logging.getLogger(__name__)

# Health is polled on hot paths (every connection listing, every chat start), so
# results are cached briefly. Mirrors the TTL the old backend_selector used.
_CACHE_TTL = 5.0
_cached: ProviderStatus | None = None
_cached_at = 0.0


def _bridge_launcher_ready(root) -> bool:
    """Whether ``root`` holds a ``jaeger`` launcher this process could execute.

    Checked inside the *discovered* root rather than at the env-derived home,
    because that root is exactly what ``_get_or_start_bridge_client`` passes to
    ``JrosClient`` as its jaeger home — checking anywhere else would answer a
    question about a different install.

    Deliberately a filesystem check rather than a subprocess spawn: this runs on
    every health poll, and starting JaegerAI to ask whether it can start would
    be both slow and side-effecting.
    """
    try:
        launcher = root / "jaeger"
        return launcher.is_file() and os.access(launcher, os.X_OK)
    except Exception:
        logger.debug("JaegerAI launcher probe failed", exc_info=True)
        return False


def _uncached_status() -> ProviderStatus:
    from api.providers.jaeger.gateway_streaming import (
        jros_gateway_base_url,
        jros_gateway_health,
        local_jros_root,
    )

    gateway_url = ""
    try:
        gateway_url = jros_gateway_base_url()
    except Exception:
        logger.debug("JaegerAI gateway URL resolution failed", exc_info=True)

    # 1. A configured gateway is an explicit operator choice, so it is checked
    #    first and its failure is reported rather than silently masked by the
    #    bridge.
    if gateway_url:
        try:
            reply = jros_gateway_health(timeout=1.0)
        except Exception:
            logger.debug("JaegerAI gateway health probe failed", exc_info=True)
            reply = None
        if reply is not None:
            return connected(
                "JaegerAI gateway is responding.",
                mode="gateway",
                gateway_url=gateway_url,
                model=reply.get("model"),
                provider=reply.get("provider"),
                instance=reply.get("instance"),
                booted=bool(reply.get("booted")),
            )
        return offline(
            f"JaegerAI gateway is configured at {gateway_url} but is not responding. "
            "Start it with `jaeger gateway`, or clear the endpoint to use the local bridge.",
            mode="gateway",
            gateway_url=gateway_url,
        )

    # 2. No gateway configured: the local bridge is what actually runs turns.
    try:
        root = local_jros_root()
    except Exception:
        logger.debug("JaegerAI local root discovery failed", exc_info=True)
        root = None

    if root is None:
        return not_installed(
            "JaegerAI is not installed. Install it, or set ARES_JAEGER_HOME / "
            "ARES_JAEGER_GATEWAY_URL to point at an existing instance.",
        )

    if not _bridge_launcher_ready(root):
        # A source checkout or partial install is detected but cannot execute a
        # turn: the bridge has no launcher to spawn. Reported as not installed
        # rather than needs_attention, because nothing here is runnable —
        # "detected on disk" is not the same as "can serve a request".
        return not_installed(
            f"JaegerAI was found at {root} but has no runnable `jaeger` launcher. "
            "Complete the install, or run `jaeger gateway` and set "
            "ARES_JAEGER_GATEWAY_URL.",
            mode="bridge",
            root=str(root),
        )

    return connected(
        "JaegerAI is available through the local bridge.",
        mode="bridge",
        root=str(root),
    )


def check_status(*, use_cache: bool = True) -> ProviderStatus:
    """Current JaegerAI readiness, cached for a few seconds."""
    global _cached, _cached_at

    now = time.monotonic()
    if use_cache and _cached is not None and (now - _cached_at) < _CACHE_TTL:
        return _cached

    try:
        status = _uncached_status()
    except Exception as exc:
        logger.debug("JaegerAI status probe failed", exc_info=True)
        status = offline(f"JaegerAI status could not be determined: {exc}")

    _cached = status
    _cached_at = now
    return status


def reset_cache() -> None:
    """Drop the cached status (used by tests and after config changes)."""
    global _cached, _cached_at

    _cached = None
    _cached_at = 0.0
