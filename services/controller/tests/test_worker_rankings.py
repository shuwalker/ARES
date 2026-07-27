"""Companion worker effectiveness rankings."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from api.worker_rankings import (
    compute_effectiveness,
    list_rankings,
    record_evaluation,
    RankingError,
)


def test_compute_effectiveness_weighted():
    score = compute_effectiveness(
        {
            "task_success": 100,
            "safety": 100,
            "latency": 50,
            "cost": 50,
            "faithfulness": 80,
            "tool_efficiency": 80,
            "user_preference": 90,
        }
    )
    assert 70 <= score <= 100


def test_record_and_rank(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setenv("HERMES_HOME", str(tmp_path))

    def _home(_profile):
        return tmp_path

    monkeypatch.setattr("api.profiles.get_ares_home_for_profile", _home)

    event = record_evaluation(
        "default",
        worker_id="ollama_local",
        metrics={"task_success": 100, "user_preference": 90, "safety": 100},
        session_id="sess-1",
        task_kind="chat",
    )
    assert event["worker_id"] == "ollama_local"
    assert event["effectiveness"] > 0

    record_evaluation(
        "default",
        worker_id="hermes_local",
        metrics={"task_success": 40, "user_preference": 30, "safety": 100},
        task_kind="chat",
    )

    payload = list_rankings("default")
    assert payload["source_of_truth"] == "companion_journal_sessions"
    assert len(payload["rankings"]) == 2
    assert payload["rankings"][0]["worker_id"] == "ollama_local"
    assert payload["rankings"][0]["effectiveness_avg"] >= payload["rankings"][1]["effectiveness_avg"]

    store_path = tmp_path / "webui" / "worker-rankings.json"
    assert store_path.is_file()
    data = json.loads(store_path.read_text(encoding="utf-8"))
    assert len(data["events"]) == 2


def test_rejects_empty_metrics(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr("api.profiles.get_ares_home_for_profile", lambda _p: tmp_path)
    with pytest.raises(RankingError):
        record_evaluation("default", worker_id="ollama_local", metrics={})
