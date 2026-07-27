"""Standalone semantic-search endpoint over the Context Store."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest
from starlette.testclient import TestClient

WEBUI = Path(__file__).resolve().parents[1]
if str(WEBUI) not in sys.path:
    sys.path.insert(0, str(WEBUI))

from fastapi_app.main import create_app  # noqa: E402

SEARCH = "/api/memory/context-store/search"


@pytest.fixture
def client():
    return TestClient(create_app(enable_lifecycle=False))


def test_missing_query_is_rejected(client):
    response = client.get(SEARCH)
    assert response.status_code == 400
    assert "query" in response.json()["error"].lower()


def test_disabled_store_reports_honestly(client, monkeypatch):
    monkeypatch.setattr("api.context_store.is_enabled", lambda *a, **k: False)
    response = client.get(SEARCH, params={"query": "anything"})
    assert response.status_code == 400
    assert "disabled" in response.json()["error"].lower()


def test_returns_ranked_results(client, monkeypatch):
    from api.context_store import RetrievedChunk

    chunks = [
        RetrievedChunk(
            text="closer match", source_key="memory", source_type="memory",
            path="/m.md", heading="H1", distance=0.1,
        ),
        RetrievedChunk(
            text="farther match", source_key="user", source_type="user",
            path="/u.md", heading="H2", distance=0.9,
        ),
    ]
    monkeypatch.setattr("api.context_store.is_enabled", lambda *a, **k: True)
    monkeypatch.setattr("api.context_store.retrieve", lambda *a, **k: chunks)

    response = client.get(SEARCH, params={"query": "find me"})
    assert response.status_code == 200
    payload = response.json()
    assert payload["query"] == "find me"
    assert [row["text"] for row in payload["results"]] == ["closer match", "farther match"]
    assert payload["results"][0]["distance"] == 0.1
    assert payload["results"][0]["source_type"] == "memory"


def test_top_k_is_clamped(client, monkeypatch):
    captured = {}

    def fake_retrieve(query, *, top_k=5, **kwargs):
        captured["top_k"] = top_k
        return []

    monkeypatch.setattr("api.context_store.is_enabled", lambda *a, **k: True)
    monkeypatch.setattr("api.context_store.retrieve", fake_retrieve)

    client.get(SEARCH, params={"query": "q", "top_k": 9999})
    assert captured["top_k"] == 50

    client.get(SEARCH, params={"query": "q", "top_k": 0})
    assert captured["top_k"] == 1
