"""
ARES SI — Journal sensitivity migration.

Adds sensitivity, importance, tags, and is_decision columns to the
Journal conversations and documents tables. These columns enable the
Trust Engine and Context Compiler to filter data appropriately.
"""

from __future__ import annotations

import sqlite3


def migrate_journal_sensitivity(db: "sqlite3.Connection") -> dict:
    """Add SI-related columns to the Journal database.

    Returns a dict of migration results.
    """
    results = {}

    # Conversations table
    for col, col_type, default in [
        ("sensitivity", "TEXT", "'personal'"),
        ("importance", "REAL", "0.5"),
        ("tags", "TEXT", "'[]'"),
        ("is_decision", "INTEGER", "0"),
    ]:
        try:
            db.execute(f"ALTER TABLE conversations ADD COLUMN {col} {col_type} DEFAULT {default}")
            results[f"conversations.{col}"] = "added"
        except Exception as e:
            if "duplicate column" in str(e).lower():
                results[f"conversations.{col}"] = "already_exists"
            else:
                results[f"conversations.{col}"] = f"error: {e}"

    # Messages table
    for col, col_type, default in [
        ("sensitivity", "TEXT", "'personal'"),
    ]:
        try:
            db.execute(f"ALTER TABLE messages ADD COLUMN {col} {col_type} DEFAULT {default}")
            results[f"messages.{col}"] = "added"
        except Exception as e:
            if "duplicate column" in str(e).lower():
                results[f"messages.{col}"] = "already_exists"
            else:
                results[f"messages.{col}"] = f"error: {e}"

    # Documents table
    for col, col_type, default in [
        ("sensitivity", "TEXT", "'personal'"),
        ("importance", "REAL", "0.5"),
        ("tags", "TEXT", "'[]'"),
        ("is_decision", "INTEGER", "0"),
    ]:
        try:
            db.execute(f"ALTER TABLE documents ADD COLUMN {col} {col_type} DEFAULT {default}")
            results[f"documents.{col}"] = "added"
        except Exception as e:
            if "duplicate column" in str(e).lower():
                results[f"documents.{col}"] = "already_exists"
            else:
                results[f"documents.{col}"] = f"error: {e}"

    # Plans table (new)
    try:
        db.execute("""
            CREATE TABLE IF NOT EXISTS plans (
                plan_id TEXT PRIMARY KEY,
                goal TEXT,
                status TEXT DEFAULT 'pending',
                conversation_id TEXT,
                created_at REAL,
                updated_at REAL,
                FOREIGN KEY (conversation_id) REFERENCES conversations(id)
            )
        """)
        results["plans_table"] = "created"
    except Exception as e:
        results["plans_table"] = f"error: {e}"

    # Steps table (new)
    try:
        db.execute("""
            CREATE TABLE IF NOT EXISTS steps (
                step_id TEXT PRIMARY KEY,
                plan_id TEXT,
                objective TEXT,
                dependencies TEXT DEFAULT '[]',
                required_capabilities TEXT DEFAULT '[]',
                assigned_worker TEXT,
                status TEXT DEFAULT 'pending',
                result TEXT,
                evaluation TEXT,
                retry_count INTEGER DEFAULT 0,
                max_retries INTEGER DEFAULT 2,
                requires_approval INTEGER DEFAULT 0,
                FOREIGN KEY (plan_id) REFERENCES plans(plan_id)
            )
        """)
        results["steps_table"] = "created"
    except Exception as e:
        results["steps_table"] = f"error: {e}"

    db.commit()
    return results