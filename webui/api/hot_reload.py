"""
ARES WebUI Hot-Reload — live static reload (browser SSE) + .py change logging.

Two-tier hot-reload:

1. **Python source (.py)** — LOGGED ONLY, no server restart.
   .py changes are logged so the agent knows when code was modified, but
   the server is NOT killed. This prevents session interruptions caused by
   os._exit(0) → launchd restart → SSE connection drop.
   To apply .py changes, restart the server manually:
       launchctl kickstart -k gui/$(id -u)/com.ares.ares-webui
   Or set ARES_WEBUI_PY_RELOAD=1 to re-enable auto-restart for development.

2. **Static files (.css, .js, .html)** — instant browser reload via SSE.
   No server restart needed. The watcher broadcasts a `hot_reload` SSE
   event to all connected sessions, and the frontend reloads itself.
   Zero downtime, zero connection loss.

Enable via environment variable:
    ARES_WEBUI_RELOAD=1           — static reload (always on when set)
    ARES_WEBUI_PY_RELOAD=1        — also auto-restart on .py changes (dev only)

The watcher runs in a daemon thread and is designed to be fire-and-forget:
start it once in main(), and it handles the rest.
"""

from __future__ import annotations

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

# Whether .py changes should trigger a full server restart (os._exit(0)).
# Default: False — .py changes are logged only, server stays alive.
# Set ARES_WEBUI_PY_RELOAD=1 to enable auto-restart for development.
_PY_RELOAD_ENABLED = os.getenv("ARES_WEBUI_PY_RELOAD", "0") == "1"


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


def _syntax_check_files(paths: list[str]) -> list[tuple[str, str]]:
    """Compile-check .py files. Returns list of (path, error_message) for failures.

    Uses py_compile which catches syntax errors without importing the module
    (so no side effects, no circular import risk). A clean compile doesn't
    guarantee the code is correct, but it guarantees the server won't crash
    on import — which is the crash-loop scenario we're preventing.
    """
    import py_compile

    failed = []
    for path in paths:
        try:
            py_compile.compile(path, doraise=True)
        except py_compile.PyCompileError as e:
            # Extract the useful line from the error message
            msg = str(e)
            # py_compile wraps the message; try to extract the SyntaxError line
            if "SyntaxError" in msg:
                # Keep it concise — just the error type and line
                for line in msg.split("\n"):
                    if "SyntaxError" in line or "Error" in line:
                        msg = line.strip()
                        break
            failed.append((path, msg))
        except Exception as e:
            failed.append((path, str(e)))
    return failed


def _files_are_stable(paths: list[str], snapshots: dict[str, tuple[int, float]]) -> bool:
    """Check if files have stopped changing.

    Compares current (size, mtime) against snapshots taken at the last
    watchdog event. If any file is still being written (size or mtime
    changed since the snapshot), returns False — the caller should wait
    and retry.

    This catches:
    - Partial writes (editor still flushing to disk)
    - Atomic saves (temp file → rename fires multiple events)
    - Multi-file refactors (save-all saves files 200ms apart)
    """
    import os

    for path in paths:
        try:
            stat = os.stat(path)
            current = (stat.st_size, stat.st_mtime)
            snap = snapshots.get(path)
            if snap is None or snap != current:
                return False
        except OSError:
            # File deleted or inaccessible — treat as unstable
            return False
    return True


def _snapshot_files(paths: list[str]) -> dict[str, tuple[int, float]]:
    """Capture (size, mtime) for each file path."""
    import os

    snapshots = {}
    for path in paths:
        try:
            stat = os.stat(path)
            snapshots[path] = (stat.st_size, stat.st_mtime)
        except OSError:
            pass
    return snapshots


class _ReloadHandler:
    """Watchdog event handler with separate debounce timers for .py vs static."""

    def __init__(self):
        self._py_timer: threading.Timer | None = None
        self._static_timer: threading.Timer | None = None
        self._lock = threading.Lock()
        self._armed = True
        self._pending_py_changes: set[str] = set()
        self._py_snapshots: dict[str, tuple[int, float]] = {}

    def on_any_event(self, event):
        if not self._armed:
            return
        if event.is_directory:
            return
        if not _is_relevant_change(event.src_path):
            return

        if _is_python_source(event.src_path):
            if _PY_RELOAD_ENABLED:
                self._schedule_restart(event.src_path)
            else:
                logger.info("[hot-reload] .py change (restart disabled): %s", event.src_path)
        elif _is_static_file(event.src_path):
            self._schedule_static_reload(event.src_path)

    def _schedule_restart(self, path: str):
        """Schedule a full server restart (debounced)."""
        logger.info("[hot-reload] Python source change: %s", path)

        with self._lock:
            self._pending_py_changes.add(path)
            # Snapshot the file's (size, mtime) so we can detect
            # if it's still being written when the debounce fires.
            snap = _snapshot_files([path])
            self._py_snapshots.update(snap)
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
        """Gracefully exit so launchd restarts the process.

        Three-stage pre-flight:
        1. File stability — are all changed files done being written?
        2. Syntax check — do all changed files compile?
        3. Only then exit — launchd restarts with the new code.

        If any stage fails, the restart is aborted and the server keeps
        running on the old code. The user fixes the issue and saves again.
        """
        if not hasattr(self, '_pending_py_changes'):
            logger.warning("[hot-reload] _trigger_restart called before __init__ completed — skipping")
            return
        with self._lock:
            changed = list(self._pending_py_changes)
            snapshots = dict(self._py_snapshots)

        if not changed:
            return

        # Stage 1: File stability check
        if not _files_are_stable(changed, snapshots):
            logger.info("[hot-reload] Files still being written — waiting 0.3s...")
            # Re-snapshot and retry once more after a short wait
            time.sleep(0.3)
            new_snapshots = _snapshot_files(changed)
            if not _files_are_stable(changed, new_snapshots):
                print(
                    "\n[hot-reload] ⚠ Restart ABORTED — files still being written. "
                    "Save again when the write is complete.\n",
                    flush=True,
                )
                with self._lock:
                    self._pending_py_changes.clear()
                    self._py_snapshots.clear()
                return
            # Files stabilized — update snapshots for the syntax check
            snapshots = new_snapshots

        # Stage 2: Syntax check
        failed = _syntax_check_files(changed)
        if failed:
            print(
                f"\n[hot-reload] ⚠ Restart ABORTED — syntax errors in "
                f"{len(failed)} file(s):",
                flush=True,
            )
            for path, err in failed:
                print(f"  ✗ {path}: {err}", flush=True)
            print("[hot-reload] Fix the errors and save again to retry.\n", flush=True)
            with self._lock:
                self._pending_py_changes.clear()
                self._py_snapshots.clear()
            return

        # Stage 3: All clear — restart
        logger.info("[hot-reload] Restarting server (graceful exit)...")
        print(
            "\n[hot-reload] Python source changed — restarting server...\n",
            flush=True,
        )

        # Clear pending changes — the restart will pick up the new code
        with self._lock:
            self._pending_py_changes.clear()
            self._py_snapshots.clear()

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
