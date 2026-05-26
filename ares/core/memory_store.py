"""Tiered memory store for ARES.

Three tiers, one entry point:

  * **Volatile** lives in `runtime.session_store.SessionStore` (turn-level,
    process-lifetime).
  * **Episodic** lives here as SQLite rows + a swappable `VectorStore` for
    similarity. Each significant exchange becomes a row.
  * **Semantic** lives here as a tiny triple store (subject/predicate/object)
    with provenance back to the episodic that produced it.

The `VectorStore` and `Embedder` protocols are the swap points. Today's
default is `InMemoryVectorStore` + `DeterministicEmbedder` — both work with
zero external dependencies so the store is testable and offline-safe.
`OllamaEmbedder` and `SqliteVssStore` (future) can drop in behind the same
interface without touching callers.
"""

from __future__ import annotations

import json
import math
import sqlite3
import time
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Optional, Protocol

# ---------------------------------------------------------------------------
# Public dataclasses
# ---------------------------------------------------------------------------


@dataclass
class VectorHit:
    """A raw similarity hit from a VectorStore."""

    id: str
    score: float
    metadata: dict = field(default_factory=dict)


@dataclass
class MemoryHit:
    """A hit returned by MemoryStore.recall — includes the source text."""

    id: str
    score: float
    text: str
    kind: str  # "episodic" | "semantic"
    metadata: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class Fact:
    """A semantic triple with provenance."""

    id: str
    subject: str
    predicate: str
    object: str
    source_episodic_id: Optional[str] = None
    created_at: float = field(default_factory=time.time)

    def to_dict(self) -> dict:
        return asdict(self)


# ---------------------------------------------------------------------------
# Protocols
# ---------------------------------------------------------------------------


class Embedder(Protocol):
    """Turn text into a fixed-length vector."""

    dim: int

    def embed(self, text: str) -> list[float]: ...


class VectorStore(Protocol):
    """Persist + query embeddings. Backend-agnostic by design."""

    def add(self, id: str, embedding: list[float], metadata: dict) -> None: ...
    def query(self, embedding: list[float], k: int) -> list[VectorHit]: ...
    def delete(self, id: str) -> None: ...
    def count(self) -> int: ...


# ---------------------------------------------------------------------------
# Default Embedder — deterministic, zero dependencies
# ---------------------------------------------------------------------------


class DeterministicEmbedder:
    """Hash-based embedder. Deterministic, fast, no external service.

    Far weaker than a real embedding model — token co-occurrence rather than
    semantic similarity — but good enough for cold-start, tests, and offline
    smoke runs. Swap in `OllamaEmbedder` for real semantics.
    """

    def __init__(self, dim: int = 128):
        self.dim = dim

    def embed(self, text: str) -> list[float]:
        vec = [0.0] * self.dim
        tokens = text.lower().split()
        for tok in tokens:
            # Cheap deterministic hash → multiple dimensions to spread signal.
            h = hash(tok)
            for shift in range(3):
                idx = ((h >> (shift * 8)) & 0xFFFF) % self.dim
                vec[idx] += 1.0
        return _normalize(vec)


class OllamaEmbedder:
    """Calls Ollama's /api/embeddings endpoint. Lazy httpx import."""

    def __init__(
        self,
        base_url: str = "http://localhost:11434",
        model: str = "nomic-embed-text",
        dim: int = 768,
        timeout: float = 30.0,
    ):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.dim = dim
        self.timeout = timeout

    def embed(self, text: str) -> list[float]:
        import httpx

        resp = httpx.post(
            f"{self.base_url}/api/embeddings",
            json={"model": self.model, "prompt": text},
            timeout=self.timeout,
        )
        resp.raise_for_status()
        return resp.json()["embedding"]


# ---------------------------------------------------------------------------
# Default VectorStore — in-memory cosine
# ---------------------------------------------------------------------------


class InMemoryVectorStore:
    """Pure-Python cosine similarity store.

    Linear scan; fine for personal-scale (thousands of entries). Larger
    stores should swap in a real backend (sqlite-vss, lancedb, chromadb)
    behind the same VectorStore protocol.
    """

    def __init__(self):
        self._items: dict[str, tuple[list[float], dict]] = {}

    def add(self, id: str, embedding: list[float], metadata: dict) -> None:
        self._items[id] = (list(embedding), dict(metadata))

    def query(self, embedding: list[float], k: int) -> list[VectorHit]:
        if not self._items:
            return []
        q = embedding
        hits = [VectorHit(id=mid, score=_cosine(q, vec), metadata=meta) for mid, (vec, meta) in self._items.items()]
        hits.sort(key=lambda h: h.score, reverse=True)
        return hits[:k]

    def delete(self, id: str) -> None:
        self._items.pop(id, None)

    def count(self) -> int:
        return len(self._items)


# ---------------------------------------------------------------------------
# MemoryStore — episodic + semantic, backed by SQLite + injectable VectorStore
# ---------------------------------------------------------------------------


_EPISODIC_DDL = """
CREATE TABLE IF NOT EXISTS episodics (
    id TEXT PRIMARY KEY,
    text TEXT NOT NULL,
    metadata TEXT NOT NULL,
    created_at REAL NOT NULL
)
"""

_FACTS_DDL = """
CREATE TABLE IF NOT EXISTS facts (
    id TEXT PRIMARY KEY,
    subject TEXT NOT NULL,
    predicate TEXT NOT NULL,
    object TEXT NOT NULL,
    source_episodic_id TEXT,
    created_at REAL NOT NULL
)
"""


class MemoryStore:
    """High-level API combining episodic (vector-recallable) and semantic
    (triple-store with provenance) tiers.
    """

    def __init__(
        self,
        db_path: Path,
        vectors: VectorStore,
        embedder: Embedder,
    ):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.vectors = vectors
        self.embedder = embedder

        from ares.core.db import connect_sqlite

        self._conn = connect_sqlite(self.db_path, check_same_thread=False)
        self._conn.execute(_EPISODIC_DDL)
        self._conn.execute(_FACTS_DDL)
        self._conn.commit()

        # Rehydrate vector store from disk so it survives restart.
        self._rehydrate_vectors()

    def _rehydrate_vectors(self) -> None:
        if self.vectors.count() > 0:
            return  # caller wired up an already-populated store
        rows = self._conn.execute("SELECT id, text, metadata FROM episodics").fetchall()
        for ep_id, text, metadata_json in rows:
            try:
                meta = json.loads(metadata_json or "{}")
            except json.JSONDecodeError:
                meta = {}
            self.vectors.add(ep_id, self.embedder.embed(text), meta)

    # -- Episodic ---------------------------------------------------------

    def record_episodic(self, text: str, metadata: Optional[dict] = None) -> str:
        ep_id = uuid.uuid4().hex
        meta = dict(metadata or {})
        created_at = time.time()
        self._conn.execute(
            "INSERT INTO episodics (id, text, metadata, created_at) VALUES (?, ?, ?, ?)",
            (ep_id, text, json.dumps(meta), created_at),
        )
        self._conn.commit()
        embedding = self.embedder.embed(text)
        self.vectors.add(ep_id, embedding, {**meta, "created_at": created_at})
        return ep_id

    def recall(self, query: str, k: int = 5) -> list[MemoryHit]:
        if not query.strip():
            return []
        q_vec = self.embedder.embed(query)
        raw_hits = self.vectors.query(q_vec, k)
        hits: list[MemoryHit] = []
        for h in raw_hits:
            row = self._conn.execute("SELECT text FROM episodics WHERE id = ?", (h.id,)).fetchone()
            if row is None:
                continue
            hits.append(
                MemoryHit(
                    id=h.id,
                    score=h.score,
                    text=row[0],
                    kind="episodic",
                    metadata=h.metadata,
                )
            )
        return hits

    def list_episodics(self, limit: int = 50) -> list[dict]:
        rows = self._conn.execute(
            "SELECT id, text, metadata, created_at FROM episodics " "ORDER BY created_at DESC LIMIT ?",
            (limit,),
        ).fetchall()
        return [
            {
                "id": r[0],
                "text": r[1],
                "metadata": json.loads(r[2] or "{}"),
                "created_at": r[3],
            }
            for r in rows
        ]

    def delete_episodic(self, ep_id: str) -> None:
        self._conn.execute("DELETE FROM episodics WHERE id = ?", (ep_id,))
        self._conn.commit()
        self.vectors.delete(ep_id)

    # -- Semantic ---------------------------------------------------------

    def add_fact(
        self,
        subject: str,
        predicate: str,
        obj: str,
        source_episodic_id: Optional[str] = None,
    ) -> str:
        fid = uuid.uuid4().hex
        self._conn.execute(
            "INSERT INTO facts (id, subject, predicate, object, source_episodic_id, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (fid, subject, predicate, obj, source_episodic_id, time.time()),
        )
        self._conn.commit()
        return fid

    def list_facts(self, limit: int = 100) -> list[Fact]:
        rows = self._conn.execute(
            "SELECT id, subject, predicate, object, source_episodic_id, created_at "
            "FROM facts ORDER BY created_at DESC LIMIT ?",
            (limit,),
        ).fetchall()
        return [
            Fact(
                id=r[0],
                subject=r[1],
                predicate=r[2],
                object=r[3],
                source_episodic_id=r[4],
                created_at=r[5],
            )
            for r in rows
        ]

    def delete_fact(self, fact_id: str) -> None:
        self._conn.execute("DELETE FROM facts WHERE id = ?", (fact_id,))
        self._conn.commit()

    # -- Lifecycle --------------------------------------------------------

    def close(self) -> None:
        self._conn.close()


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------


def default_memory_store(
    db_path: Optional[Path] = None,
    vectors: Optional[VectorStore] = None,
    embedder: Optional[Embedder] = None,
) -> MemoryStore:
    """Construct a MemoryStore with sensible defaults.

    db_path: defaults to ~/.ares/memory.db
    vectors: defaults to InMemoryVectorStore
    embedder: defaults to DeterministicEmbedder (no external service)
    """
    if db_path is None:
        import os

        ares_home = Path(os.environ.get("ARES_HOME", Path.home() / ".ares"))
        db_path = ares_home / "memory.db"
    if embedder is None:
        embedder = DeterministicEmbedder()
    if vectors is None:
        vectors = InMemoryVectorStore()
    return MemoryStore(db_path=db_path, vectors=vectors, embedder=embedder)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


def _normalize(v: list[float]) -> list[float]:
    norm = math.sqrt(sum(x * x for x in v))
    if norm == 0:
        return v
    return [x / norm for x in v]


def _cosine(a: list[float], b: list[float]) -> float:
    if len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(x * x for x in b))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)
