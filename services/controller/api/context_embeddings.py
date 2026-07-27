"""Compatibility shim: implementation lives in core.memory.context_embeddings."""
from __future__ import annotations

import sys
from pathlib import Path

_MONOREPO_ROOT = Path(__file__).resolve().parents[3]
if str(_MONOREPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_MONOREPO_ROOT))

from core.memory.context_embeddings import *  # noqa: E402,F401,F403
# Re-export module for `import api.X as X` attribute parity where needed.
import core.memory.context_embeddings as _impl  # noqa: E402
sys.modules[__name__] = _impl
