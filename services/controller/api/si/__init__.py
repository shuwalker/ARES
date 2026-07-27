"""Compatibility package: sources live under core/si."""
from __future__ import annotations

import importlib
import sys
from pathlib import Path

_MONOREPO_ROOT = Path(__file__).resolve().parents[4]
_REAL_DIR = _MONOREPO_ROOT / "core" / "si"
if str(_MONOREPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_MONOREPO_ROOT))

__path__ = [str(_REAL_DIR)]  # type: ignore[name-defined]

# Bind submodules on this package so `hasattr(api.si, "protocols")` and
# `import api.si.X` keep working after the physical move.
_SI_SUBMODULES = (
    "types",
    "protocols",
    "worker_registry",
    "trust_engine",
    "context_compiler",
    "identity",
    "memory",
    "orchestrator",
    "planner",
    "router",
    "evaluator",
    "response_composer",
    "user_model",
    "migration",
    "bridge",
)
for _name in _SI_SUBMODULES:
    _mod = importlib.import_module(f"core.si.{_name}")
    sys.modules[f"{__name__}.{_name}"] = _mod
    globals()[_name] = _mod

from core.si import *  # noqa: E402,F401,F403
