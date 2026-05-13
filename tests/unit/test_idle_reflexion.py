"""Unit tests for idle reflexion handlers + orchestrator."""

from pathlib import Path

import pytest

from ares.core.idle import (
    consolidate_episodics,
    dedupe_facts,
    run_idle_pass,
    surface_open_questions,
)
from ares.memory_store import (
    DeterministicEmbedder,
    InMemoryVectorStore,
    MemoryStore,
)


@pytest.fixture
def store(tmp_path: Path) -> MemoryStore:
    return MemoryStore(
        db_path=tmp_path / "memory.db",
        vectors=InMemoryVectorStore(),
        embedder=DeterministicEmbedder(dim=64),
    )


# ---------------------------------------------------------------------------
# consolidate_episodics
# ---------------------------------------------------------------------------


def test_consolidate_emits_one_fact_per_session(store: MemoryStore):
    for i in range(3):
        store.record_episodic(f"about metal shaders {i}", metadata={"session_id": "s1"})
    for i in range(2):
        store.record_episodic(f"about ollama models {i}", metadata={"session_id": "s2"})
    # Untagged should be ignored
    store.record_episodic("loose entry")

    sessions, fact_ids = consolidate_episodics(store, max_episodics=20)
    assert sessions == 2
    assert len(fact_ids) == 2

    facts = store.list_facts()
    summaries = [f.object for f in facts]
    assert any("metal" in s.lower() or "shaders" in s.lower() for s in summaries)
    assert any("ollama" in s.lower() or "models" in s.lower() for s in summaries)


def test_consolidate_no_sessions_is_noop(store: MemoryStore):
    store.record_episodic("no metadata")
    sessions, fact_ids = consolidate_episodics(store)
    assert sessions == 0
    assert fact_ids == []


# ---------------------------------------------------------------------------
# dedupe_facts
# ---------------------------------------------------------------------------


def test_dedupe_collapses_exact_duplicates(store: MemoryStore):
    # Determinstic embedder gives identical vectors for identical text.
    store.add_fact("Matthew", "builds", "ARES")
    store.add_fact("Matthew", "builds", "ARES")
    store.add_fact("Matthew", "builds", "ARES")
    deleted = dedupe_facts(store, threshold=0.99)
    assert deleted == 2
    assert len(store.list_facts()) == 1


def test_dedupe_preserves_distinct(store: MemoryStore):
    store.add_fact("Matthew", "builds", "ARES")
    store.add_fact("Matthew", "uses", "Hermes")
    deleted = dedupe_facts(store, threshold=0.99)
    assert deleted == 0
    assert len(store.list_facts()) == 2


# ---------------------------------------------------------------------------
# surface_open_questions
# ---------------------------------------------------------------------------


def test_surfaces_question_without_followup(store: MemoryStore):
    store.record_episodic("USER: how should we ship Phase 1?", metadata={"session_id": "s1"})
    # No follow-up in s1
    qs = surface_open_questions(store)
    assert any("how should we ship" in q.lower() for q in qs)


def test_followup_in_same_session_resolves_question(store: MemoryStore):
    store.record_episodic("USER: should we use sqlite-vss?", metadata={"session_id": "s1"})
    store.record_episodic("ARES: yes, behind the VectorStore protocol", metadata={"session_id": "s1"})
    qs = surface_open_questions(store)
    assert qs == []


def test_open_in_one_session_unaffected_by_other(store: MemoryStore):
    store.record_episodic("USER: should I ship this today?", metadata={"session_id": "s1"})
    store.record_episodic("USER: hello", metadata={"session_id": "s2"})
    store.record_episodic("ARES: hi", metadata={"session_id": "s2"})
    qs = surface_open_questions(store)
    assert len(qs) == 1
    assert "should i ship" in qs[0].lower()


# ---------------------------------------------------------------------------
# orchestrator
# ---------------------------------------------------------------------------


def test_run_idle_pass_combines_all_handlers(store: MemoryStore):
    store.record_episodic("about ARES design", metadata={"session_id": "s1"})
    store.record_episodic("about ARES rendering", metadata={"session_id": "s1"})
    store.record_episodic("USER: should we add a force-directed graph?", metadata={"session_id": "s2"})
    store.add_fact("ARES", "is", "an agent")
    store.add_fact("ARES", "is", "an agent")  # duplicate

    report = run_idle_pass(store)
    assert report.consolidated_sessions == 1  # only s1 has multiple entries; s2 has 1
    assert report.duplicates_merged == 1
    assert any("force-directed" in q.lower() for q in report.open_questions)


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------


@pytest.fixture
def api_client(monkeypatch, tmp_path):
    pytest.importorskip("fastapi")
    pytest.importorskip("fastapi.testclient")

    monkeypatch.setattr("ares.api.SERVICES", [])
    from ares.api import create_app
    from ares.runtime.session_store import SessionStore
    from fastapi.testclient import TestClient

    memory = MemoryStore(
        db_path=tmp_path / "memory.db",
        vectors=InMemoryVectorStore(),
        embedder=DeterministicEmbedder(dim=64),
    )
    app = create_app(memory=memory, sessions=SessionStore())
    with TestClient(app) as client:
        client._test_memory = memory  # type: ignore[attr-defined]
        yield client


def test_idle_run_endpoint_returns_report(api_client):
    memory = api_client._test_memory
    memory.record_episodic("about phase 3", metadata={"session_id": "s1"})
    memory.record_episodic("more about phase 3", metadata={"session_id": "s1"})

    resp = api_client.post("/api/idle/run")
    assert resp.status_code == 200
    body = resp.json()
    assert "consolidated_sessions" in body
    assert "duplicates_merged" in body
    assert "open_questions" in body
    assert "summary_fact_ids" in body


def test_last_report_returns_empty_when_never_run(api_client):
    body = api_client.get("/api/idle/last_report").json()
    assert body["consolidated_sessions"] == 0
    assert body["summary_fact_ids"] == []
