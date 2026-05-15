"""TestClient coverage of the Memory Inspector endpoints."""

import pytest


@pytest.fixture
def api_client(monkeypatch, tmp_path):
    pytest.importorskip("fastapi")
    pytest.importorskip("fastapi.testclient")

    monkeypatch.setattr("ares.api.SERVICES", [])

    from ares.api import create_app
    from ares.core.memory_store import DeterministicEmbedder, InMemoryVectorStore, MemoryStore
    from ares.runtime.session_store import SessionStore
    from fastapi.testclient import TestClient

    memory = MemoryStore(
        db_path=tmp_path / "memory.db",
        vectors=InMemoryVectorStore(),
        embedder=DeterministicEmbedder(dim=64),
    )
    sessions = SessionStore()
    app = create_app(memory=memory, sessions=sessions)
    with TestClient(app) as client:
        client._test_memory = memory  # type: ignore[attr-defined]
        yield client


def test_episodics_endpoint_lists_recent(api_client):
    memory = api_client._test_memory
    memory.record_episodic("a fact about Mars")
    memory.record_episodic("a fact about Venus")
    resp = api_client.get("/api/memory/episodics")
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 2
    texts = [i["text"] for i in body["items"]]
    assert "a fact about Venus" in texts


def test_recall_endpoint_returns_hits(api_client):
    memory = api_client._test_memory
    memory.record_episodic("matthew building cognitive os")
    memory.record_episodic("metal shader uniforms binding")

    resp = api_client.post("/api/memory/recall", json={"query": "cognitive", "k": 5})
    assert resp.status_code == 200
    hits = resp.json()["hits"]
    assert hits
    assert hits[0]["text"].startswith("matthew building")
    assert hits[0]["score"] > 0


def test_delete_endpoint_removes_episodic(api_client):
    memory = api_client._test_memory
    eid = memory.record_episodic("delete me")
    resp = api_client.delete(f"/api/memory/episodics/{eid}")
    assert resp.status_code == 200
    assert resp.json() == {"deleted": eid}
    assert memory.list_episodics() == []


def test_facts_endpoint(api_client):
    memory = api_client._test_memory
    ep = memory.record_episodic("origin")
    memory.add_fact("Matthew", "builds", "ARES", source_episodic_id=ep)
    body = api_client.get("/api/memory/facts").json()
    assert len(body["items"]) == 1
    assert body["items"][0]["predicate"] == "builds"
