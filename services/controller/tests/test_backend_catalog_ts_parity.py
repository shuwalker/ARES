"""Ensure backend_catalog.py and backend-catalog.ts stay in sync."""

from __future__ import annotations

import re
from pathlib import Path

from api.backend_catalog import BACKEND_ALIASES, VALID_BACKEND_IDS


def _extract_ts_keys(ts_file: str, pattern: str) -> set[str]:
    """Extract top-level keys from a TypeScript Record literal via regex."""
    keys: set[str] = set()
    # Match lines like `  keyname:   { ... },`
    for match in re.finditer(pattern, ts_file, re.MULTILINE):
        keys.add(match.group(1))
    return keys


def test_backend_meta_keys_match() -> None:
    """BACKEND_META in backend-catalog.ts must include all VALID_BACKEND_IDS."""
    ts_file = (Path(__file__).parent.parent.parent.parent / "apps" / "web" / "src" / "shared" / "backend-catalog.ts").read_text()

    # Extract BACKEND_META keys: `keyname:   { label:...` (after the opening brace)
    backend_meta_keys = _extract_ts_keys(ts_file, r"^\s*(\w+):\s*\{\s*label:")

    # Extract BACKEND_ALIASES keys: `alias:.*,`
    aliases_keys = _extract_ts_keys(ts_file, r"^\s*(\w+):\s*(?:JAEGER_BACKEND_ID|\"[\w_]+\")")

    python_backends = set(VALID_BACKEND_IDS)
    python_aliases = set(BACKEND_ALIASES.keys())

    assert backend_meta_keys == python_backends, (
        f"BACKEND_META mismatch:\n"
        f"  Only in TS: {backend_meta_keys - python_backends}\n"
        f"  Only in Python: {python_backends - backend_meta_keys}"
    )

    assert aliases_keys == python_aliases, (
        f"BACKEND_ALIASES mismatch:\n"
        f"  Only in TS: {aliases_keys - python_aliases}\n"
        f"  Only in Python: {python_aliases - aliases_keys}"
    )
