"""Tests for api.context_store: reindex_source(), retrieve(), and the
degrade-to-empty contract every failure mode must satisfy."""
from __future__ import annotations

from pathlib import Path

import pytest

from api import context_store
from api.context_embeddings import DEFAULT_EMBEDDING_DIMS, EmbeddingClientError

ENABLED_CONFIG = {"context_store_enabled": True}


def _unit_vector(dim: int) -> list[float]:
    vector = [0.0] * DEFAULT_EMBEDDING_DIMS
    vector[dim] = 1.0
    return vector


def _install_deterministic_embeddings(monkeypatch, mapping: dict[str, list[float]]):
    def fake_embed(self, texts):
        return [mapping[text] for text in texts]

    monkeypatch.setattr("api.context_embeddings.OllamaEmbeddingsClient.embed", fake_embed)


def test_retrieve_ranks_closest_chunk_first(tmp_path: Path, monkeypatch):
    home = tmp_path / "home"
    # Separate headings so the chunker splits these into two distinct chunks
    # rather than merging them into one (they're small enough to otherwise fit).
    mapping = {
        "# FastAPI\n\nAbout FastAPI": _unit_vector(0),
        "# React\n\nAbout React": _unit_vector(1),
        "query about fastapi": _unit_vector(0),
    }
    _install_deterministic_embeddings(monkeypatch, mapping)

    ok = context_store.reindex_source(
        "memory", "memory", "MEMORY.md", "# FastAPI\n\nAbout FastAPI\n\n# React\n\nAbout React",
        home=home, config_data=ENABLED_CONFIG,
    )
    assert ok is True

    results = context_store.retrieve("query about fastapi", home=home, config_data=ENABLED_CONFIG, top_k=2)
    assert len(results) == 2
    assert results[0].heading == "# FastAPI"
    assert results[0].distance < results[1].distance


def test_retrieve_respects_top_k(tmp_path: Path, monkeypatch):
    home = tmp_path / "home"
    text = "\n\n".join(f"# Note {i}\n\nContent {i}" for i in range(5))
    mapping = {f"# Note {i}\n\nContent {i}": _unit_vector(i) for i in range(5)}
    mapping["a query"] = _unit_vector(0)
    _install_deterministic_embeddings(monkeypatch, mapping)

    context_store.reindex_source("memory", "memory", "MEMORY.md", text, home=home, config_data=ENABLED_CONFIG)
    results = context_store.retrieve("a query", home=home, config_data=ENABLED_CONFIG, top_k=2)
    assert len(results) == 2


def test_reindex_replaces_rather_than_duplicates(tmp_path: Path, monkeypatch):
    home = tmp_path / "home"
    mapping = {"First version": _unit_vector(0), "Second version": _unit_vector(1)}
    _install_deterministic_embeddings(monkeypatch, mapping)

    context_store.reindex_source("memory", "memory", "MEMORY.md", "First version", home=home, config_data=ENABLED_CONFIG)
    context_store.reindex_source("memory", "memory", "MEMORY.md", "Second version", home=home, config_data=ENABLED_CONFIG)

    status = context_store.store_status(home=home)
    assert status["chunk_count"] == 1
    assert status["sources"][0]["chunk_count"] == 1


def test_retrieve_disabled_by_default_returns_empty(tmp_path: Path, monkeypatch):
    home = tmp_path / "home"
    mapping = {"Some note": _unit_vector(0), "a query": _unit_vector(0)}
    _install_deterministic_embeddings(monkeypatch, mapping)
    context_store.reindex_source("memory", "memory", "MEMORY.md", "Some note", home=home, config_data=ENABLED_CONFIG)

    # No config_data / not enabled -> must not even attempt an embedding call.
    assert context_store.retrieve("a query", home=home) == []
    assert context_store.retrieve("a query", home=home, config_data={"context_store_enabled": False}) == []


def test_retrieve_empty_query_returns_empty(tmp_path: Path):
    home = tmp_path / "home"
    assert context_store.retrieve("", home=home, config_data=ENABLED_CONFIG) == []
    assert context_store.retrieve("   ", home=home, config_data=ENABLED_CONFIG) == []


def test_retrieve_on_empty_store_returns_empty(tmp_path: Path, monkeypatch):
    home = tmp_path / "home"
    _install_deterministic_embeddings(monkeypatch, {"a query": _unit_vector(0)})
    assert context_store.retrieve("a query", home=home, config_data=ENABLED_CONFIG) == []


def test_retrieve_degrades_when_sqlite_vec_unavailable(tmp_path: Path, monkeypatch):
    home = tmp_path / "home"
    _install_deterministic_embeddings(monkeypatch, {"a query": _unit_vector(0)})
    monkeypatch.setattr(
        context_store, "_import_sqlite_vec",
        lambda: (_ for _ in ()).throw(context_store.ContextStoreUnavailable("sqlite-vec is not installed")),
    )
    assert context_store.retrieve("a query", home=home, config_data=ENABLED_CONFIG) == []


def test_retrieve_degrades_when_embedding_fails(tmp_path: Path, monkeypatch):
    home = tmp_path / "home"

    def failing_embed(self, texts):
        raise EmbeddingClientError("ollama unreachable")

    monkeypatch.setattr("api.context_embeddings.OllamaEmbeddingsClient.embed", failing_embed)
    assert context_store.retrieve("a query", home=home, config_data=ENABLED_CONFIG) == []


def test_reindex_degrades_when_embedding_fails(tmp_path: Path, monkeypatch):
    home = tmp_path / "home"

    def failing_embed(self, texts):
        raise EmbeddingClientError("ollama unreachable")

    monkeypatch.setattr("api.context_embeddings.OllamaEmbeddingsClient.embed", failing_embed)
    ok = context_store.reindex_source("memory", "memory", "MEMORY.md", "some content", home=home, config_data=ENABLED_CONFIG)
    assert ok is False
    assert context_store.store_status(home=home)["chunk_count"] == 0


def test_reindex_skips_chunks_with_wrong_embedding_width(tmp_path: Path, monkeypatch):
    home = tmp_path / "home"

    def wrong_width_embed(self, texts):
        return [[0.1] * 3 for _ in texts]  # not DEFAULT_EMBEDDING_DIMS

    monkeypatch.setattr("api.context_embeddings.OllamaEmbeddingsClient.embed", wrong_width_embed)
    ok = context_store.reindex_source("memory", "memory", "MEMORY.md", "some content", home=home, config_data=ENABLED_CONFIG)
    assert ok is True  # the reindex call itself succeeds...
    assert context_store.store_status(home=home)["chunk_count"] == 0  # ...but nothing usable was stored


def test_build_context_block_empty_and_nonempty():
    assert context_store.build_context_block([]) == ""
    chunk = context_store.RetrievedChunk(text="hello", source_key="memory", source_type="memory", path="MEMORY.md", heading="", distance=0.1)
    block = context_store.build_context_block([chunk])
    assert "MEMORY.md" in block
    assert "hello" in block


def test_store_status_unavailable_when_sqlite_vec_missing(tmp_path: Path, monkeypatch):
    home = tmp_path / "home"
    monkeypatch.setattr(
        context_store, "_import_sqlite_vec",
        lambda: (_ for _ in ()).throw(context_store.ContextStoreUnavailable("sqlite-vec is not installed")),
    )
    status = context_store.store_status(home=home)
    assert status["available"] is False
    assert "sqlite-vec" in status["reason"]
