"""Context Store injection into the ares-backend prefill-context hook
(api.streaming._load_webui_prefill_context), shared by both the direct/
browser ares path and the ares messaging-gateway path (api/gateway_chat.py).
"""
from __future__ import annotations

from api import context_store, streaming


def test_default_context_store_query_leaves_behavior_unchanged(monkeypatch):
    """context_store_query="" (the default) must produce byte-for-byte the
    same result as before this feature existed -- no call to retrieve()."""
    calls = []
    monkeypatch.setattr(context_store, "retrieve", lambda *a, **k: calls.append((a, k)) or [])
    base_result = {"status": "not_configured", "source": "none", "label": "", "messages": [], "message_count": 0}
    monkeypatch.setattr(streaming, "_load_webui_prefill_context_base", lambda cfg: base_result)

    result = streaming._load_webui_prefill_context({})

    assert result == base_result
    assert calls == []


def test_nonempty_query_prepends_context_block_when_chunks_found(monkeypatch):
    chunk = context_store.RetrievedChunk(
        text="Use FastAPI for the backend.", source_key="memory", source_type="memory",
        path="MEMORY.md", heading="", distance=0.1,
    )

    def fake_retrieve(query, **kwargs):
        assert query == "what framework should we use"
        return [chunk]

    monkeypatch.setattr(context_store, "retrieve", fake_retrieve)
    base_result = {
        "status": "loaded", "source": "script", "label": "notes",
        "messages": [{"role": "assistant", "content": "existing recall message"}],
        "message_count": 1,
    }
    monkeypatch.setattr(streaming, "_load_webui_prefill_context_base", lambda cfg: base_result)

    result = streaming._load_webui_prefill_context({}, context_store_query="what framework should we use")

    assert result["messages"][0]["role"] == "system"
    assert "FastAPI" in result["messages"][0]["content"]
    assert result["messages"][1] == {"role": "assistant", "content": "existing recall message"}
    assert result["message_count"] == 2


def test_nonempty_query_no_chunks_leaves_messages_unchanged(monkeypatch):
    monkeypatch.setattr(context_store, "retrieve", lambda *a, **k: [])
    base_result = {"status": "not_configured", "source": "none", "label": "", "messages": [], "message_count": 0}
    monkeypatch.setattr(streaming, "_load_webui_prefill_context_base", lambda cfg: base_result)

    result = streaming._load_webui_prefill_context({}, context_store_query="anything")

    assert result == base_result


def test_retrieval_failure_never_raises_and_leaves_messages_unchanged(monkeypatch):
    def boom(*a, **k):
        raise RuntimeError("context store exploded")

    monkeypatch.setattr(context_store, "retrieve", boom)
    base_result = {"status": "not_configured", "source": "none", "label": "", "messages": [], "message_count": 0}
    monkeypatch.setattr(streaming, "_load_webui_prefill_context_base", lambda cfg: base_result)

    result = streaming._load_webui_prefill_context({}, context_store_query="anything")

    assert result == base_result
