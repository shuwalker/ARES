"""Unit tests for the tiered memory store.

Verifies the swappable VectorStore / Embedder protocols and the
SQLite-backed MemoryStore wrapper. No external services required.
"""

from pathlib import Path

import pytest

from ares.memory_store import (
    DeterministicEmbedder,
    InMemoryVectorStore,
    MemoryStore,
)

# ---------------------------------------------------------------------------
# InMemoryVectorStore + DeterministicEmbedder
# ---------------------------------------------------------------------------


def test_embedder_is_deterministic():
    e = DeterministicEmbedder(dim=64)
    a = e.embed("ares persistent agent")
    b = e.embed("ares persistent agent")
    assert a == b
    assert len(a) == 64


def test_embedder_normalizes():
    e = DeterministicEmbedder(dim=32)
    v = e.embed("hello world")
    norm = sum(x * x for x in v) ** 0.5
    assert abs(norm - 1.0) < 1e-6 or norm == 0.0


def test_vector_store_returns_top_k_sorted_descending():
    e = DeterministicEmbedder(dim=64)
    store = InMemoryVectorStore()
    store.add("a", e.embed("metal shader pipeline"), {})
    store.add("b", e.embed("cognitive loop perceive think"), {})
    store.add("c", e.embed("metal shader uniform binding"), {})
    hits = store.query(e.embed("metal shader uniform"), k=2)
    assert [h.id for h in hits] == ["c", "a"]
    assert hits[0].score >= hits[1].score


def test_vector_store_empty_returns_empty():
    store = InMemoryVectorStore()
    assert store.query([0.0] * 4, k=5) == []


def test_vector_store_delete():
    e = DeterministicEmbedder(dim=32)
    store = InMemoryVectorStore()
    store.add("a", e.embed("first"), {})
    store.add("b", e.embed("second"), {})
    assert store.count() == 2
    store.delete("a")
    assert store.count() == 1
    assert all(h.id != "a" for h in store.query(e.embed("first"), k=2))


# ---------------------------------------------------------------------------
# MemoryStore — episodics
# ---------------------------------------------------------------------------


@pytest.fixture
def store(tmp_path: Path) -> MemoryStore:
    return MemoryStore(
        db_path=tmp_path / "memory.db",
        vectors=InMemoryVectorStore(),
        embedder=DeterministicEmbedder(dim=64),
    )


def test_record_and_recall_round_trip(store: MemoryStore):
    eid = store.record_episodic("Matthew loves typed Python", metadata={"src": "test"})
    hits = store.recall("Matthew typed Python", k=3)
    assert hits, "expected at least one recall hit"
    assert hits[0].id == eid
    assert "Matthew" in hits[0].text
    assert hits[0].kind == "episodic"
    assert hits[0].score > 0


def test_recall_empty_query_returns_empty(store: MemoryStore):
    store.record_episodic("anything")
    assert store.recall("", k=3) == []
    assert store.recall("   ", k=3) == []


def test_list_episodics_newest_first(store: MemoryStore):
    store.record_episodic("first")
    store.record_episodic("second")
    store.record_episodic("third")
    items = store.list_episodics(limit=10)
    assert [i["text"] for i in items] == ["third", "second", "first"]


def test_delete_removes_from_db_and_vectors(store: MemoryStore):
    eid = store.record_episodic("ephemeral")
    assert store.vectors.count() == 1
    store.delete_episodic(eid)
    assert store.vectors.count() == 0
    assert store.list_episodics() == []


def test_rehydrate_repopulates_vectors_from_disk(tmp_path: Path):
    db = tmp_path / "memory.db"
    e = DeterministicEmbedder(dim=64)
    store_a = MemoryStore(db_path=db, vectors=InMemoryVectorStore(), embedder=e)
    eid = store_a.record_episodic("cognitive os heartbeat")
    store_a.close()

    # Fresh process: same DB, empty vector store — rehydrate must repopulate.
    store_b = MemoryStore(db_path=db, vectors=InMemoryVectorStore(), embedder=e)
    assert store_b.vectors.count() == 1
    hits = store_b.recall("heartbeat", k=1)
    assert hits and hits[0].id == eid


# ---------------------------------------------------------------------------
# MemoryStore — semantic facts
# ---------------------------------------------------------------------------


def test_add_and_list_facts(store: MemoryStore):
    ep = store.record_episodic("Matthew is building ARES")
    fid = store.add_fact("Matthew", "is_building", "ARES", source_episodic_id=ep)
    facts = store.list_facts(limit=10)
    assert len(facts) == 1
    assert facts[0].id == fid
    assert facts[0].subject == "Matthew"
    assert facts[0].source_episodic_id == ep


def test_delete_fact(store: MemoryStore):
    fid = store.add_fact("a", "rel", "b")
    store.delete_fact(fid)
    assert store.list_facts() == []
