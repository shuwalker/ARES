"""write_memory() -> Context Store background reindex ingestion trigger.

Covers the fire-and-forget contract and the specific regression class this
codebase has hit before (api/streaming.py's _get_config_for_home comment):
a plain threading.Thread does not inherit profile_scope's thread-local state,
so home/config must be captured on the calling thread before spawning, never
re-resolved inside the worker.
"""
from __future__ import annotations

import time
from pathlib import Path

import pytest

from api import context_store


def _wait_for_chunks(home: Path, *, timeout: float = 5.0) -> dict:
    deadline = time.monotonic() + timeout
    status = context_store.store_status(home=home)
    while status["chunk_count"] == 0 and time.monotonic() < deadline:
        time.sleep(0.05)
        status = context_store.store_status(home=home)
    return status


def _install_stub_embeddings(monkeypatch):
    from api.context_embeddings import DEFAULT_EMBEDDING_DIMS

    def fake_embed(self, texts):
        return [[0.1] * DEFAULT_EMBEDDING_DIMS for _ in texts]

    monkeypatch.setattr("api.context_embeddings.OllamaEmbeddingsClient.embed", fake_embed)


def test_write_memory_spawns_background_reindex(monkeypatch, tmp_path):
    from api import memory_store, profiles

    home = tmp_path / "home"
    monkeypatch.setattr(profiles, "get_active_ares_home", lambda: home, raising=False)
    monkeypatch.setattr(memory_store, "_active_home", lambda: home)
    monkeypatch.setattr("api.config.get_config", lambda: {"context_store_enabled": True})
    _install_stub_embeddings(monkeypatch)

    result = memory_store.write_memory("memory", "# Notes\n\nUse FastAPI for the backend.")
    assert result["ok"] is True

    status = _wait_for_chunks(home)
    assert status["chunk_count"] > 0
    assert status["sources"][0]["source_key"] == "memory"


def test_write_memory_does_nothing_when_context_store_disabled(monkeypatch, tmp_path):
    from api import memory_store, profiles

    home = tmp_path / "home"
    monkeypatch.setattr(profiles, "get_active_ares_home", lambda: home, raising=False)
    monkeypatch.setattr(memory_store, "_active_home", lambda: home)
    monkeypatch.setattr("api.config.get_config", lambda: {"context_store_enabled": False})
    _install_stub_embeddings(monkeypatch)

    memory_store.write_memory("memory", "# Notes\n\nUse FastAPI for the backend.")
    time.sleep(0.2)  # give a wrongly-spawned worker a chance to run
    assert context_store.store_status(home=home)["chunk_count"] == 0


def test_write_memory_home_captured_on_calling_thread_not_reresolved_in_worker(monkeypatch, tmp_path):
    """Regression guard: switching get_active_ares_home()'s return value
    immediately after write_memory() returns must NOT redirect the background
    reindex to the new home -- it must already be committed to whichever home
    was active when write_memory() (the calling thread) ran."""
    from api import memory_store, profiles

    home_a = tmp_path / "home_a"
    home_b = tmp_path / "home_b"
    current = {"home": home_a}
    monkeypatch.setattr(profiles, "get_active_ares_home", lambda: current["home"], raising=False)
    monkeypatch.setattr(memory_store, "_active_home", lambda: current["home"])
    monkeypatch.setattr("api.config.get_config", lambda: {"context_store_enabled": True})
    _install_stub_embeddings(monkeypatch)

    memory_store.write_memory("memory", "# Notes\n\nOriginal home content.")
    # Flip the "active home" the instant control returns to the calling
    # thread -- if the worker re-resolves home instead of using what was
    # captured at spawn time, it will pick this up and write to home_b.
    current["home"] = home_b

    status_a = _wait_for_chunks(home_a)
    assert status_a["chunk_count"] > 0

    status_b = context_store.store_status(home=home_b)
    assert status_b["chunk_count"] == 0


def test_maybe_reindex_project_context_skips_when_mtime_unchanged(monkeypatch, tmp_path):
    home = tmp_path / "home"
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    (workspace / "AGENTS.md").write_text("# Agents\n\nProject rules here.", encoding="utf-8")

    monkeypatch.setattr("api.config.get_config", lambda: {"context_store_enabled": True})
    _install_stub_embeddings(monkeypatch)

    context_store.maybe_reindex_project_context(workspace, home=home, config_data={"context_store_enabled": True})
    status = _wait_for_chunks(home)
    assert status["chunk_count"] > 0

    call_count = {"n": 0}
    original_spawn = context_store.spawn_background_reindex

    def counting_spawn(*args, **kwargs):
        call_count["n"] += 1
        return original_spawn(*args, **kwargs)

    monkeypatch.setattr(context_store, "spawn_background_reindex", counting_spawn)
    # Same file, unchanged mtime -> must not spawn a second reindex.
    context_store.maybe_reindex_project_context(workspace, home=home, config_data={"context_store_enabled": True})
    time.sleep(0.2)
    assert call_count["n"] == 0


def test_maybe_reindex_project_context_disabled_is_a_noop(monkeypatch, tmp_path):
    home = tmp_path / "home"
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    (workspace / "AGENTS.md").write_text("# Agents\n\nProject rules here.", encoding="utf-8")
    _install_stub_embeddings(monkeypatch)

    context_store.maybe_reindex_project_context(workspace, home=home, config_data={"context_store_enabled": False})
    time.sleep(0.2)
    assert context_store.store_status(home=home)["chunk_count"] == 0
