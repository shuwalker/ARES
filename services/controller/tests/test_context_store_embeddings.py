"""Tests for api.context_embeddings.OllamaEmbeddingsClient.

Uses a real ThreadingHTTPServer fake, the same technique as
_FakeJrosGateway in test_jros_backend_streaming.py.
"""
from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from api.context_embeddings import (
    DEFAULT_EMBEDDING_DIMS,
    DEFAULT_EMBEDDING_MODEL,
    EmbeddingClientError,
    OllamaEmbeddingsClient,
)


class _FakeEmbeddingsServer(BaseHTTPRequestHandler):
    seen: list[dict] = []
    mode = "ok"  # "ok" | "http_error" | "bad_json" | "bad_shape" | "mismatched_count"

    def log_message(self, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        payload = json.loads(self.rfile.read(length).decode("utf-8"))
        type(self).seen.append(payload)

        if self.mode == "http_error":
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            body = b'{"error": "boom"}'
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if self.mode == "bad_json":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            body = b"not json"
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if self.mode == "bad_shape":
            body = json.dumps({"data": "not-a-list"}).encode()
        elif self.mode == "mismatched_count":
            body = json.dumps({"data": [{"embedding": [0.1] * DEFAULT_EMBEDDING_DIMS}]}).encode()
        else:
            texts = payload.get("input") or []
            body = json.dumps({"data": [{"embedding": [0.1] * DEFAULT_EMBEDDING_DIMS} for _ in texts]}).encode()

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _start_fake_server(mode: str):
    _FakeEmbeddingsServer.mode = mode
    _FakeEmbeddingsServer.seen = []
    server = ThreadingHTTPServer(("127.0.0.1", 0), _FakeEmbeddingsServer)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, f"http://127.0.0.1:{server.server_address[1]}"


def test_embed_happy_path_returns_vectors_for_each_text():
    server, base = _start_fake_server("ok")
    try:
        client = OllamaEmbeddingsClient(base_url=base, model="nomic-embed-text")
        vectors = client.embed(["hello", "world"])
        assert len(vectors) == 2
        assert all(len(v) == DEFAULT_EMBEDDING_DIMS for v in vectors)
        assert _FakeEmbeddingsServer.seen[0]["model"] == "nomic-embed-text"
        assert _FakeEmbeddingsServer.seen[0]["input"] == ["hello", "world"]
    finally:
        server.shutdown()
        server.server_close()


def test_embed_empty_texts_returns_empty_without_a_request():
    client = OllamaEmbeddingsClient(base_url="http://127.0.0.1:1", model="x")
    assert client.embed([]) == []


def test_embed_http_error_raises_embedding_client_error():
    server, base = _start_fake_server("http_error")
    try:
        client = OllamaEmbeddingsClient(base_url=base, model="x", timeout=2.0)
        with pytest.raises(EmbeddingClientError):
            client.embed(["hello"])
    finally:
        server.shutdown()
        server.server_close()


def test_embed_connection_refused_raises_embedding_client_error():
    client = OllamaEmbeddingsClient(base_url="http://127.0.0.1:1", model="x", timeout=1.0)
    with pytest.raises(EmbeddingClientError):
        client.embed(["hello"])


def test_embed_malformed_json_raises_embedding_client_error():
    server, base = _start_fake_server("bad_json")
    try:
        client = OllamaEmbeddingsClient(base_url=base, model="x", timeout=2.0)
        with pytest.raises(EmbeddingClientError):
            client.embed(["hello"])
    finally:
        server.shutdown()
        server.server_close()


def test_embed_unexpected_shape_raises_embedding_client_error():
    server, base = _start_fake_server("bad_shape")
    try:
        client = OllamaEmbeddingsClient(base_url=base, model="x", timeout=2.0)
        with pytest.raises(EmbeddingClientError):
            client.embed(["hello"])
    finally:
        server.shutdown()
        server.server_close()


def test_embed_mismatched_result_count_raises_embedding_client_error():
    server, base = _start_fake_server("mismatched_count")
    try:
        client = OllamaEmbeddingsClient(base_url=base, model="x", timeout=2.0)
        with pytest.raises(EmbeddingClientError):
            client.embed(["hello", "world"])
    finally:
        server.shutdown()
        server.server_close()


def test_non_http_scheme_rejected():
    with pytest.raises(ValueError):
        OllamaEmbeddingsClient(base_url="file:///etc/passwd", model="x")


def test_from_config_resolves_base_url_via_provider_config(monkeypatch):
    from api import config

    monkeypatch.setattr(config, "_get_provider_base_url", lambda provider_id: "http://example-ollama:1234" if provider_id == "ollama" else None)
    client = OllamaEmbeddingsClient.from_config({})
    assert client.base_url == "http://example-ollama:1234"
    assert client.model == DEFAULT_EMBEDDING_MODEL


def test_from_config_falls_back_to_default_base_url(monkeypatch):
    from api import config

    monkeypatch.setattr(config, "_get_provider_base_url", lambda provider_id: None)
    client = OllamaEmbeddingsClient.from_config({})
    assert client.base_url == "http://localhost:11434"


def test_from_config_reads_embedding_model_override(monkeypatch):
    from api import config

    monkeypatch.setattr(config, "_get_provider_base_url", lambda provider_id: None)
    client = OllamaEmbeddingsClient.from_config({"context_store_embedding_model": "mxbai-embed-large"})
    assert client.model == "mxbai-embed-large"
