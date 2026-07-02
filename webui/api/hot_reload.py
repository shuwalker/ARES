"""
ARES WebUI Hot-Reload — automatic server restart + live static reload.

Two-tier hot-reload:

1. **Python source (.py)** — full process restart via os._exit(0).
   launchd KeepAlive restarts the process in ~2 seconds. The browser's
   SSE reconnect logic handles the brief downtime transparently.
   This is the nuclear option: guaranteed clean state, no stale modules.

2. **Static files (.css, .js, .html)** — instant browser reload via SSE.
   No server restart needed. The watcher broadcasts a `hot_reload` SSE
   event to all connected sessions, and the frontend reloads itself.
   Zero downtime, zero connection loss.

Enable via environment variable:
    ARES_WEBUI_RELOAD=1

The watcher runs in a daemon thread and is designed to be fire-and-forget:
start it once in main(), and it handles the rest.
"""

import logging
import os
import signal
import sys
import threading
import time
from pathlib import Path

logger = logging.getLogger(__name__)

# Directory to watch — the webui repo root (parent of api/)
_WATCH_ROOT = Path(__file__).resolve().parent.parent

# Debounce: wait this long after the last change event before restarting,
# so a multi-file save (editor atomic write) doesn't trigger N restarts.
_DEBOUNCE_SECONDS = 0.8

# Debounce for static-file reload (shorter — just needs to coalesce a save).
_STATIC_DEBOUNCE_SECONDS = 0.3

# Grace period before os._exit to let in-flight responses drain.
_EXIT_GRACE_SECONDS = 0.3

# Static file extensions that trigger a browser-only reload (no server restart).
_STATIC_EXTENSIONS = {".css", ".js", ".html", ".svg", ".png", ".ico", ".webmanifest"}

# Directories we don't watch for static changes (build artifacts, venv, etc.)
_IGNORE_DIRS = {"__pycache__", ".venv", "venv", ".git", "node_modules", ".pytest_cache"}


def _is_python_source(path: str) -> bool:
    """True if the path is a .py file we should watch."""
    return path.endswith(".py")


def _is_static_file(path: str) -> bool:
    """True if the path is a static asset that can be browser-reloaded."""
    suffix = Path(path).suffix.lower()
    return suffix in _STATIC_EXTENSIONS


def _should_ignore(path: str) -> bool:
    """True if the path is in a directory we don't watch."""
    return any(ignored in path for ignored in _IGNORE_DIRS)


def _is_relevant_change(path: str) -> bool:
    """Filter out changes to files outside our watch root or temp files."""
    if _should_ignore(path):
        return False
    if _is_python_source(path):
        return True
    if _is_static_file(path):
        return True
    return False


class _ReloadHandler:
    """Watchdog event handler with separate debounce timers for .py vs static."""

    def __init__(self):
        self._py_timer: threading.Timer | None = None
        self._static_timer: threading.Timer | None = None
        self._lock = threading.Lock()
        self._armed = True

    def on_any_event(self, event):
        if not self._armed:
            return
        if event.is_directory:
            return
        if not _is_relevant_change(event.src_path):
            return

        if _is_python_source(event.src_path):
            self._schedule_restart(event.src_path)
        elif _is_static_file(event.src_path):
            self._schedule_static_reload(event.src_path)

    def _schedule_restart(self, path: str):
        """Schedule a full server restart (debounced)."""
        logger.info("[hot-reload] Python source change: %s", path)

        with self._lock:
            if self._py_timer is not None:
                self._py_timer.cancel()
            self._py_timer = threading.Timer(_DEBOUNCE_SECONDS, self._trigger_restart)
            self._py_timer.daemon = True
            self._py_timer.start()

    def _schedule_static_reload(self, path: str):
        """Schedule a browser-only reload via SSE (debounced, shorter)."""
        logger.info("[hot-reload] Static file change: %s", path)

        with self._lock:
            if self._static_timer is not None:
                self._static_timer.cancel()
            self._static_timer = threading.Timer(_STATIC_DEBOUNCE_SECONDS, self._trigger_static_reload)
            self._static_timer.daemon = True
            self._static_timer.start()

    def _trigger_restart(self):
        """Gracefully exit so launchd restarts the process."""
        logger.info("[hot-reload] Restarting server (graceful exit)...")
        print(
            "\n[hot-reload] Python source changed — restarting server...\n",
            flush=True,
        )

        # Brief grace period to let in-flight HTTP responses drain
        time.sleep(_EXIT_GRACE_SECONDS)

        # os._exit bypasses atexit handlers and thread cleanup — launchd
        # KeepAlive will restart the process cleanly. Using SIGTERM on
        # ourselves would trigger the server's shutdown handlers which
        # could hang; os._exit is the fast, reliable path.
        os._exit(0)

    def _trigger_static_reload(self):
        """Broadcast a hot_reload SSE event to all connected browser sessions.

        This triggers a browser-side reload without killing the server.
        The frontend listens for the 'hot_reload' event and does a
        location.reload() to pick up the new CSS/JS/HTML.
        """
        try:
            from api.background_process import SESSION_CHANNELS, SESSION_CHANNELS_LOCK

            with SESSION_CHANNELS_LOCK:
                channels = list(SESSION_CHANNELS.values())

            delivered = 0
            for ch in channels:
                try:
                    delivered += ch.emit("hot_reload", {"type": "static_reload"})
                except Exception:
                    pass

            logger.info(
                "[hot-reload] Static reload signal sent to %d/%d sessions",
                delivered,
                len(channels),
            )
            print(
                f"[hot-reload] Static files changed — "
                f"notified {delivered} browser session(s) to reload",
                flush=True,
            )
        except Exception as e:
            logger.warning("[hot-reload] Failed to broadcast static reload: %s", e)
            print(f"[hot-reload] WARNING: Static reload broadcast failed: {e}", flush=True)


def start_watcher() -> threading.Thread | None:
    """
    Start the hot-reload file watcher in a daemon thread.

    Returns the thread (for testing), or None if watchdog isn't available.
    """
    try:
        from watchdog.observers import Observer
        from watchdog.events import FileSystemEventHandler
    except ImportError:
        print(
            "[hot-reload] WARNING: watchdog library not installed — "
            "hot-reload disabled. Install with: pip install watchdog",
            flush=True,
        )
        return None

    handler = _ReloadHandler()

    # Adapt our handler to watchdog's FileSystemEventHandler interface
    class _Adapter(FileSystemEventHandler):
        def on_any_event(self, event):
            handler.on_any_event(event)

    adapter = _Adapter()
    observer = Observer()
    observer.schedule(adapter, str(_WATCH_ROOT), recursive=True)

    def _run():
        observer.start()
        logger.info(
            "[hot-reload] Watching %s for .py + static changes (debounce=%.1fs)",
            _WATCH_ROOT,
            _DEBOUNCE_SECONDS,
        )
        print(
            f"[hot-reload] Watching {_WATCH_ROOT} for .py + static changes "
            f"(py debounce={_DEBOUNCE_SECONDS}s, static debounce={_STATIC_DEBOUNCE_SECONDS}s)",
            flush=True,
        )
        try:
            observer.join()
        except Exception:
            pass

    t = threading.Thread(target=_run, daemon=True)
    t.start()
    return t