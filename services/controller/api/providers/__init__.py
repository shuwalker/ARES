"""Compatibility package: sources live under integrations/providers."""
from __future__ import annotations

import importlib
import sys
from pathlib import Path

_MONOREPO_ROOT = Path(__file__).resolve().parents[4]
_REAL_DIR = _MONOREPO_ROOT / "integrations" / "providers"
if str(_MONOREPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_MONOREPO_ROOT))

__path__ = [str(_REAL_DIR)]  # type: ignore[name-defined]

from integrations.providers import *  # noqa: E402,F401,F403
