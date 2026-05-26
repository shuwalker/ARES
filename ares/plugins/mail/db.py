"""ARES Mail Triage — SQLite learning database.

Tracks learned junk/keep patterns over time.
"""

from __future__ import annotations

import os
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING

from ares.core.db import connect_sqlite

if TYPE_CHECKING:
    from .models import EmailMessage, SenderRecord, KeepRecord


_DB_VERSION = 1


def get_db_path() -> str:
    return str(Path.home() / ".ares" / "mail_triage.db")


def _ensure_dir():
    Path.home().joinpath(".ares").mkdir(parents=True, exist_ok=True)


def init_db():
    _ensure_dir()
    db_path = get_db_path()
    conn = connect_sqlite(db_path)
    cursor = conn.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS junk_senders (
            address TEXT PRIMARY KEY,
            domain  TEXT NOT NULL,
            count   INTEGER DEFAULT 1,
            first_seen TEXT,
            last_seen  TEXT
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS keep_senders (
            address TEXT PRIMARY KEY,
            count   INTEGER DEFAULT 1,
            last_seen TEXT
        )
    """)

    conn.commit()
    conn.close()


def _now() -> str:
    return datetime.utcnow().isoformat()


def load_junk_addresses() -> set[str]:
    db_path = get_db_path()
    if not os.path.exists(db_path):
        return set()
    try:
        conn = connect_sqlite(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT address FROM junk_senders")
        addresses = {row[0].lower() for row in cursor.fetchall()}
        conn.close()
        return addresses
    except Exception as e:
        import warnings
        warnings.warn(f"mail db: error loading junk addresses: {e}")
        return set()


def load_junk_domains(threshold: int = 3) -> set[str]:
    db_path = get_db_path()
    if not os.path.exists(db_path):
        return set()
    try:
        conn = connect_sqlite(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT domain FROM junk_senders WHERE count >= ?", (threshold,))
        domains = {row[0].lower() for row in cursor.fetchall()}
        conn.close()
        return domains
    except Exception as e:
        import warnings
        warnings.warn(f"mail db: error loading junk domains: {e}")
        return set()


def load_keep_addresses() -> set[str]:
    db_path = get_db_path()
    if not os.path.exists(db_path):
        return set()
    try:
        conn = connect_sqlite(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT address FROM keep_senders")
        addresses = {row[0].lower() for row in cursor.fetchall()}
        conn.close()
        return addresses
    except Exception as e:
        import warnings
        warnings.warn(f"mail db: error loading keep addresses: {e}")
        return set()


def record_junked(msgs: list[EmailMessage]) -> None:
    if not msgs:
        return

    from .rules import extract_real_domain

    _ensure_dir()
    db_path = get_db_path()
    conn = connect_sqlite(db_path)
    cursor = conn.cursor()
    now = _now()

    for msg in msgs:
        sender_lower = msg.sender_lower
        domain = extract_real_domain(sender_lower)
        cursor.execute("SELECT count FROM junk_senders WHERE address = ?", (sender_lower,))
        result = cursor.fetchone()
        if result:
            new_count = result[0] + 1
            cursor.execute(
                "UPDATE junk_senders SET count = ?, last_seen = ? WHERE address = ?",
                (new_count, now, sender_lower),
            )
        else:
            cursor.execute(
                "INSERT INTO junk_senders (address, domain, count, first_seen, last_seen) "
                "VALUES (?, ?, 1, ?, ?)",
                (sender_lower, domain, now, now),
            )

    conn.commit()
    conn.close()


def record_rescued(msgs: list[EmailMessage]) -> None:
    if not msgs:
        return

    _ensure_dir()
    db_path = get_db_path()
    conn = connect_sqlite(db_path)
    cursor = conn.cursor()
    now = _now()

    for msg in msgs:
        sender_lower = msg.sender_lower
        cursor.execute("SELECT count FROM keep_senders WHERE address = ?", (sender_lower,))
        result = cursor.fetchone()
        if result:
            new_count = result[0] + 1
            cursor.execute(
                "UPDATE keep_senders SET count = ?, last_seen = ? WHERE address = ?",
                (new_count, now, sender_lower),
            )
        else:
            cursor.execute(
                "INSERT INTO keep_senders (address, count, last_seen) VALUES (?, 1, ?)",
                (sender_lower, now),
            )
        # Remove from junk_senders if it exists
        cursor.execute("DELETE FROM junk_senders WHERE address = ?", (sender_lower,))

    conn.commit()
    conn.close()


def fix_db() -> None:
    """Fix corrupted entries (brackets, wrong domains)."""
    db_path = get_db_path()
    if not os.path.exists(db_path):
        return
    conn = connect_sqlite(db_path)
    cursor = conn.cursor()
    fixed = 0

    # Fix angle brackets in addresses
    for table in ("junk_senders", "keep_senders"):
        cursor.execute(
            f"SELECT address, count FROM {table} WHERE address LIKE '%<%' OR address LIKE '%>%'"
        )
        for addr, count_val in cursor.fetchall():
            clean = addr.strip("<>").strip()
            cursor.execute(f"SELECT count FROM {table} WHERE address = ?", (clean,))
            existing = cursor.fetchone()
            if existing:
                new_count = existing[0] + count_val
                cursor.execute(
                    f"UPDATE {table} SET count = ? WHERE address = ?",
                    (new_count, clean),
                )
                cursor.execute(f"DELETE FROM {table} WHERE address = ?", (addr,))
            else:
                cursor.execute(
                    f"UPDATE {table} SET address = ? WHERE address = ?",
                    (clean, addr),
                )
            fixed += 1

    # Recalculate domains for iCloud relay addresses
    from .rules import extract_real_domain
    cursor.execute("SELECT address, domain FROM junk_senders")
    for addr, old_domain in cursor.fetchall():
        real_domain = extract_real_domain(addr.lower())
        if real_domain != old_domain.lower():
            cursor.execute(
                "UPDATE junk_senders SET domain = ? WHERE address = ?",
                (real_domain, addr),
            )
            fixed += 1

    # Remove entries with bad addresses
    cursor.execute(
        "DELETE FROM junk_senders WHERE address NOT LIKE '%@%' AND address NOT LIKE '%_at_%'"
    )
    deleted = cursor.rowcount

    conn.commit()
    conn.close()

    import warnings
    warnings.warn(f"mail db: fixed {fixed} entries, removed {deleted} invalid")


def get_stats() -> dict:
    """Return current DB stats."""
    db_path = get_db_path()
    if not os.path.exists(db_path):
        return {"junk_senders": 0, "keep_senders": 0, "junk_domains": 0}
    conn = connect_sqlite(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM junk_senders")
    jnk = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM keep_senders")
    kp = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(DISTINCT domain) FROM junk_senders")
    doms = cursor.fetchone()[0]
    conn.close()
    return {"junk_senders": jnk, "keep_senders": kp, "junk_domains": doms}
