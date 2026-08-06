"""Uvicorn-owned startup and shutdown lifecycle for ARES."""

from __future__ import annotations

import asyncio
import sys
from contextlib import asynccontextmanager
from pathlib import Path
import logging
import os
from typing import AsyncIterator

from fastapi import FastAPI


logger = logging.getLogger(__name__)

# Same guarded pattern used throughout services/controller/api/*.py (e.g.
# context_chunker.py) — integrations.* lives at the monorepo root, one level
# above services/controller, so it is not on sys.path by default here.
_MONOREPO_ROOT = Path(__file__).resolve().parents[3]
if str(_MONOREPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_MONOREPO_ROOT))


def _autoload_hatched_sis() -> None:
    """Auto-register any previously hatched SIs from the hatchery directory."""
    try:
        from api.backends.ollama_hatchery import hatchery_autoload
        hatchery_autoload()
    except Exception:
        logger.warning("Hatchery auto-load failed", exc_info=True)


async def _best_effort(label: str, function, *args, timeout: float | None = None):
    try:
        call = asyncio.to_thread(function, *args)
        return await asyncio.wait_for(call, timeout=timeout) if timeout else await call
    except TimeoutError:
        logger.warning("%s is still initializing; startup will continue", label)
    except Exception:
        logger.warning("%s failed", label, exc_info=True)
    return None


async def startup_runtime() -> None:
    """Initialize the same state owners used by the former HTTP launcher."""
    from api.config import (
        DEFAULT_WORKSPACE,
        SESSION_DIR,
        STATE_DIR,
        _ARES_FOUND,
        print_startup_config,
        verify_ares_imports,
    )
    from api.crash_visibility import install_crash_visibility
    from api.process_runtime import configure_process_runtime
    from api.startup import auto_install_agent_deps, fix_credential_permissions

    from api.log_config import configure_logging

    install_crash_visibility()
    configure_logging()
    process_status = configure_process_runtime()
    if process_status["file_descriptors"].get("status") == "error":
        logger.warning("Could not raise file descriptor limit: %s", process_status["file_descriptors"].get("error"))
    print_startup_config()
    fix_credential_permissions()
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    SESSION_DIR.mkdir(parents=True, exist_ok=True)
    DEFAULT_WORKSPACE.mkdir(parents=True, exist_ok=True)

    async def recover_sessions() -> None:
        from api.models import _active_state_db_path
        from api.session_recovery import recover_all_sessions_on_startup

        result = await asyncio.to_thread(
            recover_all_sessions_on_startup,
            SESSION_DIR,
            rebuild_index=True,
            state_db_path=_active_state_db_path(),
        )
        if result.get("restored"):
            logger.info(
                "Restored %s/%s sessions from backup",
                result["restored"],
                result["scanned"],
            )

    try:
        await recover_sessions()
    except Exception:
        logger.warning("Session recovery failed", exc_info=True)

    ok, missing, errors = verify_ares_imports()
    if not ok and _ARES_FOUND:
        logger.warning("Ares Agent modules are unavailable: %s (%s)", missing, errors)
        installed = await _best_effort("Agent dependency installation", auto_install_agent_deps)
        if installed:
            ok, missing, errors = verify_ares_imports()
            if not ok:
                logger.warning("Ares Agent modules remain unavailable: %s (%s)", missing, errors)

    from api.auth import get_oidc_startup_warning, is_auth_enabled
    from api.config import HOST

    if HOST not in {"127.0.0.1", "::1", "localhost"} and not is_auth_enabled():
        logger.warning(
            "ARES is bound to %s without authentication; filesystem and runtime APIs are exposed",
            HOST,
        )
    oidc_warning = get_oidc_startup_warning()
    if oidc_warning:
        logger.warning("%s", oidc_warning)

    from api.background_process import start_drain_thread, start_session_channel_reaper
    from api.gateway_watcher import start_watcher
    from api.plugins import load_plugins

    await _best_effort("Gateway watcher", start_watcher, timeout=5.0)
    await _best_effort("Background completion drain", start_drain_thread)
    await _best_effort("Session activity reaper", start_session_channel_reaper)
    await _best_effort("Plugin loading", load_plugins)

    # Auto-register any previously hatched SIs
    await _best_effort("Hatchery auto-load", _autoload_hatched_sis)

    # First run discovery
    from api.config import load_settings, save_settings
    from api.ai_framework_discovery import discover_summary
    current_settings = load_settings()
    if not current_settings.get("connections"):
        discovery = discover_summary()
        connections = {}
        for adapter in discovery.get("adapters", []):
            connections[adapter["adapter_id"]] = {
                "detected": adapter["detected"],
                "default_model": adapter.get("default_model", ""),
                "default_provider": adapter.get("default_provider", ""),
            }
        current_settings["connections"] = connections
        save_settings(current_settings)

    if os.environ.get("ARES_WEBUI_RELOAD", "").strip().lower() in {"1", "true", "yes"}:
        try:
            from api.hot_reload import start_watcher as start_hot_reload

            await _best_effort("Hot-reload watcher", start_hot_reload)
        except ImportError:
            logger.warning("Hot-reload support is unavailable")


async def shutdown_runtime() -> None:
    """Flush and stop ARES-owned background services in dependency order."""
    try:
        from api.gateway_watcher import stop_watcher

        await _best_effort("Gateway watcher shutdown", stop_watcher)
    except ImportError:
        pass
    try:
        from api.session_lifecycle import drain_all_on_shutdown

        await _best_effort("Session lifecycle drain", drain_all_on_shutdown)
    except ImportError:
        pass
    try:
        from api.context_store import drain_background_index_threads

        await _best_effort("Context Store reindex drain", drain_background_index_threads)
    except ImportError:
        pass
    try:
        from api.background_process import stop_drain_thread, stop_session_channel_reaper

        await _best_effort("Background completion drain shutdown", stop_drain_thread)
        await _best_effort("Session activity reaper shutdown", stop_session_channel_reaper)
    except ImportError:
        pass
    try:
        from integrations.workers.jros_session_manager import close_all as close_all_jaeger_bridges

        # Each JrosClient owns a real subprocess that loaded an LLM + tool +
        # voice model at boot (multi-second cold start). Without this, a
        # restarted or crashed ARES process leaves those orphaned in the
        # background indefinitely instead of exiting with the server.
        await _best_effort("Jaeger bridge session shutdown", close_all_jaeger_bridges)
    except ImportError:
        pass
    from api.shutdown_audit import log_shutdown_audit

    log_shutdown_audit()


@asynccontextmanager
async def ares_lifespan(_application: FastAPI) -> AsyncIterator[None]:
    await startup_runtime()
    try:
        yield
    finally:
        await shutdown_runtime()


__all__ = ["ares_lifespan", "shutdown_runtime", "startup_runtime"]
