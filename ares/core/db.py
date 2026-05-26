"""Shared SQLite connection helper for ARES.

All ARES databases use the same PRAGMAs:
    journal_mode=WAL    concurrent readers + single writer
    synchronous=NORMAL  fsync at checkpoint only (safe under WAL)
    busy_timeout=5000   retry on lock contention before raising
"""

from __future__ import annotations

import sqlite3
from pathlib import Path


def connect_sqlite(
    path: str | Path,
    *,
    check_same_thread: bool = True,
    **kwargs,
) -> sqlite3.Connection:
    """Open a SQLite connection with ARES's standard PRAGMAs applied."""
    conn = sqlite3.connect(str(path), check_same_thread=check_same_thread, **kwargs)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    conn.execute("PRAGMA busy_timeout=5000;")
    return conn
