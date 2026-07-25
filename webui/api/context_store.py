"""Local retrieval store for ARES-owned Local Profile / project-context content.

This is NOT a competing conversational memory. JaegerAI's gateway keeps its
own per-session context server-side, and the external ares-agent package owns
SOUL.md/persona loading and cross-turn memory entirely outside this repo.
This module only indexes files ARES already owns and shows in Settings
(MEMORY.md, USER.md, SOUL.md, project-context files) so relevant snippets can
be supplied to a turn as one additional system message -- augmentation, not a
second memory implementation.

Every public function here degrades to an empty/false result on any failure
(sqlite-vec not installed, DB issue, embeddings endpoint unreachable) -- never
raises into a chat-turn code path.

Off by default: see is_enabled(). Changing CONTEXT_STORE_EMBEDDING_DIMS (i.e.
switching embedding models) requires deleting context_store.db -- the vec0
table's fixed width will simply reject mismatched vectors, which every writer
here already treats as a degrade condition.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import logging
import os
from pathlib import Path
import sqlite3
import threading
import time
from typing import Any

from api.context_embeddings import (
    DEFAULT_EMBEDDING_DIMS,
    DEFAULT_EMBEDDING_MODEL,
    EmbeddingClientError,
    OllamaEmbeddingsClient,
)

logger = logging.getLogger(__name__)


class ContextStoreUnavailable(RuntimeError):
    """The context store (sqlite-vec, or its DB) can't be used right now."""


@dataclass(frozen=True)
class RetrievedChunk:
    text: str
    source_key: str
    source_type: str
    path: str
    heading: str
    distance: float


def _active_home() -> Path:
    try:
        from api.profiles import get_active_ares_home

        return Path(get_active_ares_home()).expanduser()
    except ImportError:
        return Path.home() / ".ares"


def _db_path(home: Path | None) -> Path:
    return (home or _active_home()) / "context_store.db"


def is_enabled(config_data: dict | None = None) -> bool:
    def truthy(value: Any) -> bool:
        return str(value or "").strip().lower() in {"1", "true", "yes", "on"}

    env_value = os.getenv("ARES_WEBUI_CONTEXT_STORE_ENABLED", "")
    if env_value:
        return truthy(env_value)
    if config_data is None:
        try:
            from api.config import get_config

            config_data = get_config()
        except Exception:
            return False
    if not isinstance(config_data, dict):
        return False
    return truthy(config_data.get("context_store_enabled"))


def _import_sqlite_vec():
    try:
        import sqlite_vec

        return sqlite_vec
    except ImportError as exc:
        raise ContextStoreUnavailable("sqlite-vec is not installed") from exc


_CONNECT_RETRY_ATTEMPTS = 5
_CONNECT_RETRY_DELAY = 0.1


def _connect(home: Path | None = None) -> sqlite3.Connection:
    # A brand-new db file being bootstrapped (first CREATE TABLE / WAL-mode
    # switch) by two callers at once (e.g. a background reindex and a
    # concurrent status/retrieve read) can transiently raise "database is
    # locked" even with a busy_timeout PRAGMA set on the connection -- retry
    # the whole open+schema sequence a few times rather than surfacing a
    # spurious ContextStoreUnavailable for what is normal, expected
    # concurrent-first-access contention.
    for attempt in range(_CONNECT_RETRY_ATTEMPTS):
        try:
            return _connect_once(home)
        except ContextStoreUnavailable as exc:
            if "locked" not in str(exc).lower() or attempt == _CONNECT_RETRY_ATTEMPTS - 1:
                raise
            time.sleep(_CONNECT_RETRY_DELAY * (attempt + 1))
    raise ContextStoreUnavailable("context store unavailable: retry attempts exhausted")


def _connect_once(home: Path | None) -> sqlite3.Connection:
    sqlite_vec = _import_sqlite_vec()
    db_path = _db_path(home)
    try:
        db_path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(db_path))
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=5000")
        conn.enable_load_extension(True)
        sqlite_vec.load(conn)
        conn.enable_load_extension(False)
        # Skip the schema-creation statements once the tables already exist --
        # every one of them (even CREATE TABLE IF NOT EXISTS) takes a brief
        # write lock, and a read-only caller (store_status/retrieve) opening a
        # fresh connection on every call would otherwise contend with a
        # concurrent writer (a background reindex thread) for no reason.
        existing = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
        if not {"sources", "chunks", "vec_chunks"}.issubset(existing):
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS sources (
                    source_key TEXT PRIMARY KEY,
                    source_type TEXT NOT NULL,
                    path TEXT NOT NULL,
                    last_mtime REAL,
                    last_hash TEXT,
                    last_indexed_at REAL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS chunks (
                    id INTEGER PRIMARY KEY,
                    source_key TEXT NOT NULL,
                    source_type TEXT NOT NULL,
                    path TEXT NOT NULL,
                    chunk_index INTEGER NOT NULL,
                    heading TEXT,
                    text TEXT NOT NULL,
                    embedding_model TEXT NOT NULL,
                    embedded_at REAL NOT NULL
                )
                """
            )
            conn.execute(
                f"CREATE VIRTUAL TABLE IF NOT EXISTS vec_chunks USING vec0(embedding float[{int(DEFAULT_EMBEDDING_DIMS)}])"
            )
            conn.commit()
    except (sqlite3.Error, AttributeError, OSError) as exc:
        raise ContextStoreUnavailable(f"context store unavailable: {exc}") from exc
    return conn


def reindex_source(
    source_key: str,
    source_type: str,
    path: str,
    text: str,
    *,
    home: Path | None = None,
    config_data: dict | None = None,
    mtime: float | None = None,
) -> bool:
    """Chunk, embed, and (re)index one source. Never raises -- returns False
    on any degrade condition (embeddings unreachable, store unavailable)."""
    from api.context_chunker import chunk_markdown

    chunks = chunk_markdown(text)
    vectors: list[list[float]] = []
    model = DEFAULT_EMBEDDING_MODEL
    if chunks:
        try:
            client = OllamaEmbeddingsClient.from_config(config_data, timeout=30.0)
            vectors = client.embed([chunk.text for chunk in chunks])
            model = client.model
        except (EmbeddingClientError, ValueError) as exc:
            logger.warning("context store: embedding failed for %s: %s", source_key, exc)
            return False

    try:
        sqlite_vec = _import_sqlite_vec()
        conn = _connect(home)
    except ContextStoreUnavailable as exc:
        logger.warning("context store: unavailable during reindex of %s: %s", source_key, exc)
        return False

    try:
        with conn:
            existing_ids = [
                row[0] for row in conn.execute("SELECT id FROM chunks WHERE source_key = ?", (source_key,))
            ]
            if existing_ids:
                conn.executemany("DELETE FROM vec_chunks WHERE rowid = ?", [(i,) for i in existing_ids])
                conn.execute("DELETE FROM chunks WHERE source_key = ?", (source_key,))
            now = time.time()
            for chunk, vector in zip(chunks, vectors):
                if len(vector) != DEFAULT_EMBEDDING_DIMS:
                    logger.warning(
                        "context store: skipping chunk %s/%s -- embedding width %s != expected %s",
                        source_key, chunk.index, len(vector), DEFAULT_EMBEDDING_DIMS,
                    )
                    continue
                cursor = conn.execute(
                    "INSERT INTO chunks(source_key, source_type, path, chunk_index, heading, text, embedding_model, embedded_at)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (source_key, source_type, path, chunk.index, chunk.heading, chunk.text, model, now),
                )
                conn.execute(
                    "INSERT INTO vec_chunks(rowid, embedding) VALUES (?, ?)",
                    (cursor.lastrowid, sqlite_vec.serialize_float32(vector)),
                )
            content_hash = hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()
            conn.execute(
                "INSERT INTO sources(source_key, source_type, path, last_mtime, last_hash, last_indexed_at)"
                " VALUES (?, ?, ?, ?, ?, ?)"
                " ON CONFLICT(source_key) DO UPDATE SET"
                " source_type=excluded.source_type, path=excluded.path, last_mtime=excluded.last_mtime,"
                " last_hash=excluded.last_hash, last_indexed_at=excluded.last_indexed_at",
                (source_key, source_type, path, mtime, content_hash, now),
            )
        return True
    except sqlite3.Error as exc:
        logger.warning("context store: reindex failed for %s: %s", source_key, exc)
        return False
    finally:
        conn.close()


def retrieve(
    query: str,
    *,
    top_k: int = 5,
    home: Path | None = None,
    config_data: dict | None = None,
) -> list[RetrievedChunk]:
    if not is_enabled(config_data):
        return []
    if not query or not query.strip():
        return []
    try:
        client = OllamaEmbeddingsClient.from_config(config_data, timeout=5.0)
        vectors = client.embed([query])
    except (EmbeddingClientError, ValueError) as exc:
        logger.debug("context store: retrieval embedding failed: %s", exc)
        return []
    if not vectors or len(vectors[0]) != DEFAULT_EMBEDDING_DIMS:
        return []

    try:
        sqlite_vec = _import_sqlite_vec()
        conn = _connect(home)
    except ContextStoreUnavailable as exc:
        logger.debug("context store: unavailable during retrieval: %s", exc)
        return []
    try:
        # sqlite-vec requires the MATCH/LIMIT constraint directly on the
        # virtual table -- it isn't recognized through a JOIN ("A LIMIT or
        # 'k = ?' constraint is required on vec0 knn queries"). Query the
        # nearest rowids first, then look up their chunk rows separately.
        neighbors = conn.execute(
            "SELECT rowid, distance FROM vec_chunks WHERE embedding MATCH ? ORDER BY distance LIMIT ?",
            (sqlite_vec.serialize_float32(vectors[0]), int(top_k)),
        ).fetchall()
        if not neighbors:
            return []
        distance_by_id = {row[0]: row[1] for row in neighbors}
        placeholders = ",".join("?" for _ in neighbors)
        chunk_rows = conn.execute(
            f"SELECT id, text, source_key, source_type, path, heading FROM chunks WHERE id IN ({placeholders})",
            list(distance_by_id.keys()),
        ).fetchall()
    except sqlite3.Error as exc:
        logger.debug("context store: retrieval query failed: %s", exc)
        return []
    finally:
        conn.close()

    results = [
        RetrievedChunk(
            text=row[1], source_key=row[2], source_type=row[3], path=row[4],
            heading=row[5] or "", distance=distance_by_id[row[0]],
        )
        for row in chunk_rows
    ]
    results.sort(key=lambda chunk: chunk.distance)
    return results


def build_context_block(chunks: list[RetrievedChunk]) -> str:
    if not chunks:
        return ""
    lines = ["Relevant local context from the Local Profile and project files:"]
    for chunk in chunks:
        label = chunk.path or chunk.source_key
        lines.append(f"- [{label}] {chunk.text}")
    return "\n".join(lines)


def store_status(*, home: Path | None = None) -> dict[str, Any]:
    base = {
        "available": False,
        "reason": "",
        "chunk_count": 0,
        "source_count": 0,
        "sources": [],
        "embedding_model": DEFAULT_EMBEDDING_MODEL,
        "embedding_dims": DEFAULT_EMBEDDING_DIMS,
    }
    try:
        conn = _connect(home)
    except ContextStoreUnavailable as exc:
        return {**base, "reason": str(exc)}
    try:
        chunk_count = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
        sources = []
        for row in conn.execute("SELECT source_key, source_type, path, last_indexed_at FROM sources"):
            count_row = conn.execute(
                "SELECT COUNT(*) FROM chunks WHERE source_key = ?", (row[0],)
            ).fetchone()
            sources.append(
                {
                    "source_key": row[0],
                    "source_type": row[1],
                    "path": row[2],
                    "last_indexed_at": row[3],
                    "chunk_count": count_row[0] if count_row else 0,
                }
            )
        return {**base, "available": True, "chunk_count": chunk_count, "source_count": len(sources), "sources": sources}
    except sqlite3.Error as exc:
        return {**base, "reason": str(exc)}
    finally:
        conn.close()


# -- Ingestion triggers ------------------------------------------------------

_background_index_threads: set[threading.Thread] = set()
_background_index_threads_lock = threading.Lock()
_draining = False


def spawn_background_reindex(
    source_key: str,
    source_type: str,
    path: str,
    text: str,
    *,
    home: Path | None,
    config_data: dict | None,
    mtime: float | None = None,
) -> None:
    """Fire-and-forget reindex. Captures home/config_data as plain values from
    the caller's thread -- profile_scope is thread-local and does NOT
    propagate to a new thread, so callers must resolve these before spawning,
    not inside the worker."""

    def _run() -> None:
        try:
            reindex_source(source_key, source_type, path, text, home=home, config_data=config_data, mtime=mtime)
        except Exception:
            logger.warning("context store: background reindex crashed for %s", source_key, exc_info=True)
        finally:
            with _background_index_threads_lock:
                _background_index_threads.discard(threading.current_thread())

    with _background_index_threads_lock:
        if _draining:
            return
        worker = threading.Thread(target=_run, daemon=True, name=f"context-reindex-{source_key}")
        _background_index_threads.add(worker)
    worker.start()


def drain_background_index_threads(timeout: float = 5.0) -> None:
    global _draining
    with _background_index_threads_lock:
        _draining = True
        threads = list(_background_index_threads)
    for worker in threads:
        if worker.is_alive():
            worker.join(timeout)


def maybe_reindex_project_context(
    workspace: Path | None,
    *,
    home: Path | None = None,
    config_data: dict | None = None,
) -> None:
    """Re-embed the active project-context file only if its mtime changed
    since it was last indexed. Cheap to call from a request path -- does at
    most one small SELECT before deciding to no-op."""
    if not is_enabled(config_data) or workspace is None:
        return
    from api.memory_store import read_active_project_context

    context = read_active_project_context(workspace)
    path = context.get("path") or ""
    if not path:
        return
    mtime = context.get("mtime")
    source_key = f"project_context:{path}"
    try:
        conn = _connect(home)
    except ContextStoreUnavailable:
        return
    try:
        row = conn.execute("SELECT last_mtime FROM sources WHERE source_key = ?", (source_key,)).fetchone()
    except sqlite3.Error:
        row = None
    finally:
        conn.close()
    if row and row[0] == mtime:
        return
    spawn_background_reindex(
        source_key, "project_context", path, context.get("content") or "",
        home=home, config_data=config_data, mtime=mtime,
    )


__all__ = [
    "ContextStoreUnavailable",
    "RetrievedChunk",
    "build_context_block",
    "drain_background_index_threads",
    "is_enabled",
    "maybe_reindex_project_context",
    "reindex_source",
    "retrieve",
    "spawn_background_reindex",
    "store_status",
]
