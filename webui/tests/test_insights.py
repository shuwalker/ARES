"""Tests for api.insights.build_insights() — the Usage & Cost dashboard aggregator.

Covers the provider breakdown and duration ("session span") aggregate added
alongside the JaegerAI usage-persistence fix in api/jros_gateway_chat.py.
"""
from __future__ import annotations

import json
import sqlite3
import time

import pytest


def _write_index(session_dir, rows):
    session_dir.mkdir(parents=True, exist_ok=True)
    (session_dir / "_index.json").write_text(json.dumps(rows), encoding="utf-8")


def _missing_db_path(tmp_path):
    return tmp_path / "no_such_state.db"


def test_provider_breakdown_from_index_rows(monkeypatch, tmp_path):
    from api import config
    from api.insights import build_insights

    session_dir = tmp_path / "sessions"
    now = time.time()
    rows = [
        {
            "model": "gpt-4o", "model_provider": "OpenAI", "input_tokens": 100,
            "output_tokens": 50, "cache_read_tokens": 0, "estimated_cost": 1.0,
            "message_count": 2, "created_at": now, "updated_at": now,
        },
        {
            "model": "claude-sonnet", "model_provider": "anthropic", "input_tokens": 200,
            "output_tokens": 100, "cache_read_tokens": 10, "estimated_cost": 2.0,
            "message_count": 4, "created_at": now, "updated_at": now,
        },
        {
            "model": "gpt-4o-mini", "model_provider": "openai", "input_tokens": 50,
            "output_tokens": 25, "cache_read_tokens": 0, "estimated_cost": 0.5,
            "message_count": 1, "created_at": now, "updated_at": now,
        },
    ]
    _write_index(session_dir, rows)
    monkeypatch.setattr(config, "SESSION_DIR", session_dir)
    monkeypatch.setattr("api.models._active_state_db_path", lambda: _missing_db_path(tmp_path))

    result = build_insights(days=1)

    # "OpenAI" and "openai" fold to the same lowercase provider bucket.
    providers = {row["provider"]: row for row in result["providers"]}
    assert set(providers) == {"openai", "anthropic"}
    assert providers["openai"]["sessions"] == 2
    assert providers["openai"]["cost"] == pytest.approx(1.5)
    assert providers["anthropic"]["sessions"] == 1
    assert providers["anthropic"]["cost"] == pytest.approx(2.0)
    # The parallel `models` breakdown is unaffected by provider grouping.
    assert {row["model"] for row in result["models"]} == {"gpt-4o", "claude-sonnet", "gpt-4o-mini"}


def test_duration_aggregation_from_index_rows(monkeypatch, tmp_path):
    from api import config
    from api.insights import build_insights

    session_dir = tmp_path / "sessions"
    now = time.time()
    rows = [
        # Normal 120s span.
        {
            "model": "m1", "model_provider": "p1", "input_tokens": 10, "output_tokens": 5,
            "message_count": 1, "created_at": now - 120, "updated_at": now,
        },
        # created_at == updated_at: 0 duration, but still counted in the average's denominator.
        {
            "model": "m1", "model_provider": "p1", "input_tokens": 10, "output_tokens": 5,
            "message_count": 1, "created_at": now, "updated_at": now,
        },
        # No updated_at: excluded from the average entirely (not treated as 0).
        {
            "model": "m1", "model_provider": "p1", "input_tokens": 10, "output_tokens": 5,
            "message_count": 1, "created_at": now, "updated_at": 0,
        },
    ]
    _write_index(session_dir, rows)
    monkeypatch.setattr(config, "SESSION_DIR", session_dir)
    monkeypatch.setattr("api.models._active_state_db_path", lambda: _missing_db_path(tmp_path))

    result = build_insights(days=1)

    assert result["total_sessions"] == 3
    assert result["total_duration_seconds"] == 120
    # 120s / 2 known-duration sessions, not / 3 total sessions.
    assert result["average_session_duration_seconds"] == 60

    assert len(result["models"]) == 1
    assert result["models"][0]["duration_seconds"] == 120
    assert result["models"][0]["average_duration_seconds"] == 60


def _create_sessions_table(db_path, *, with_provider_column: str | None):
    """with_provider_column: None, "model_provider", or "provider"."""
    provider_column_sql = f", {with_provider_column} TEXT" if with_provider_column else ""
    conn = sqlite3.connect(str(db_path))
    conn.execute(
        f"""
        CREATE TABLE sessions (
            model TEXT, message_count INTEGER, input_tokens INTEGER,
            output_tokens INTEGER, estimated_cost_usd REAL, cache_read_tokens INTEGER,
            started_at REAL, ended_at REAL{provider_column_sql}
        )
        """
    )
    return conn


def test_sqlite_provider_probe_prefers_model_provider_column(monkeypatch, tmp_path):
    from api import config
    from api.insights import build_insights

    monkeypatch.setattr(config, "SESSION_DIR", tmp_path / "sessions")
    db_path = tmp_path / "state.db"
    now = time.time()
    conn = _create_sessions_table(db_path, with_provider_column="model_provider")
    conn.execute(
        "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ("cli-model", 3, 30, 15, 0.3, 0, now - 60, now, "OpenAI"),
    )
    conn.commit()
    conn.close()
    monkeypatch.setattr("api.models._active_state_db_path", lambda: db_path)

    result = build_insights(days=1)

    assert result["total_sessions"] == 1
    assert result["providers"][0]["provider"] == "openai"
    assert result["providers"][0]["duration_seconds"] == 60


def test_sqlite_provider_probe_defaults_to_unknown_without_column(monkeypatch, tmp_path):
    """No model_provider/provider column exists — must degrade to 'unknown', not raise.

    The `sessions` table is owned by an external runtime (CLI/Telegram agent),
    so its schema can't be assumed; this pins the defensive PRAGMA probe.
    """
    from api import config
    from api.insights import build_insights

    monkeypatch.setattr(config, "SESSION_DIR", tmp_path / "sessions")
    db_path = tmp_path / "state.db"
    now = time.time()
    conn = _create_sessions_table(db_path, with_provider_column=None)
    conn.execute(
        "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        ("cli-model", 3, 30, 15, 0.3, 0, now - 60, now),
    )
    conn.commit()
    conn.close()
    monkeypatch.setattr("api.models._active_state_db_path", lambda: db_path)

    result = build_insights(days=1)

    assert result["total_sessions"] == 1
    assert result["providers"][0]["provider"] == "unknown"


def test_sqlite_open_session_excluded_from_duration(monkeypatch, tmp_path):
    from api import config
    from api.insights import build_insights

    monkeypatch.setattr(config, "SESSION_DIR", tmp_path / "sessions")
    db_path = tmp_path / "state.db"
    now = time.time()
    conn = _create_sessions_table(db_path, with_provider_column="model_provider")
    conn.execute(
        "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ("cli-model", 1, 10, 5, 0.1, 0, now, None, "anthropic"),
    )
    conn.commit()
    conn.close()
    monkeypatch.setattr("api.models._active_state_db_path", lambda: db_path)

    result = build_insights(days=1)

    assert result["total_sessions"] == 1
    assert result["total_duration_seconds"] == 0
    assert result["average_session_duration_seconds"] == 0
