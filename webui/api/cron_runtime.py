"""Cron runtime import isolation independent of HTTP routing."""

from __future__ import annotations

import os
from pathlib import Path
import sys
import threading


_AGENT_CRON_IMPORT_PATH_LOCK = threading.Lock()
_AGENT_CRON_IMPORT_PATH_READY: str | None = None


def ensure_agent_cron_import_path() -> None:
    """Prefer the configured agent cron package over unrelated packages."""
    from api import config

    agent_dir = getattr(config, "_AGENT_DIR", None)
    if not agent_dir:
        return
    agent_path = str(Path(agent_dir).expanduser().resolve())
    agent_cron_path = str(Path(agent_path) / "cron")
    global _AGENT_CRON_IMPORT_PATH_READY
    with _AGENT_CRON_IMPORT_PATH_LOCK:
        cron_module = sys.modules.get("cron")
        cron_file = str(getattr(cron_module, "__file__", "") or "") if cron_module else ""
        cron_is_agent = bool(cron_module is not None and cron_file.startswith(agent_cron_path + os.sep))
        if _AGENT_CRON_IMPORT_PATH_READY == agent_path and (cron_module is None or cron_is_agent):
            return
        while agent_path in sys.path:
            sys.path.remove(agent_path)
        shadows = [
            index
            for index, entry in enumerate(sys.path)
            if entry
            and Path(entry).resolve() != Path(agent_path)
            and (Path(entry) / "cron" / "__init__.py").exists()
        ]
        sys.path.insert(min(shadows), agent_path) if shadows else sys.path.append(agent_path)
        _AGENT_CRON_IMPORT_PATH_READY = agent_path
        if cron_module is not None and cron_file and not cron_is_agent:
            for name in list(sys.modules):
                if name == "cron" or name.startswith("cron."):
                    sys.modules.pop(name, None)


_ensure_agent_cron_import_path = ensure_agent_cron_import_path


__all__ = ["ensure_agent_cron_import_path"]
