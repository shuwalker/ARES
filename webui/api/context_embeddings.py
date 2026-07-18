"""Embedding client for the Context Store.

Calls the OpenAI-compatible /v1/embeddings surface, matching every other
local-model integration in this codebase (jros_gateway_chat.py's
/v1/chat/completions, config.py's /v1/models listing) — deliberately not
Ollama's native /api/embed route.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_EMBEDDING_MODEL = "nomic-embed-text"
DEFAULT_EMBEDDING_DIMS = 768
DEFAULT_BASE_URL = "http://localhost:11434"


class EmbeddingClientError(RuntimeError):
    """Raised when the embeddings endpoint can't be reached or fails."""


class OllamaEmbeddingsClient:
    """Small JSON HTTP client for a local Ollama embeddings endpoint."""

    def __init__(self, *, base_url: str, model: str, timeout: float = 5.0):
        self.base_url = str(base_url or "").strip().rstrip("/")
        if not self.base_url:
            raise ValueError("embeddings base_url is required")
        scheme = urllib.parse.urlsplit(self.base_url).scheme.lower()
        if scheme not in ("http", "https"):
            raise ValueError(f"embeddings base_url must be http(s); got scheme '{scheme or '(none)'}'")
        self.model = str(model or DEFAULT_EMBEDDING_MODEL).strip() or DEFAULT_EMBEDDING_MODEL
        self.timeout = float(timeout)

    @classmethod
    def from_config(
        cls,
        config_data: dict | None = None,
        *,
        model: str | None = None,
        timeout: float = 5.0,
    ) -> "OllamaEmbeddingsClient":
        # Embeddings always go through the "ollama" provider slot, independent
        # of whichever provider the active chat model uses — embeddings are a
        # separate concern from chat model selection.
        from api.config import _get_provider_base_url

        base_url = _get_provider_base_url("ollama") or DEFAULT_BASE_URL
        resolved_model = model
        if resolved_model is None and isinstance(config_data, dict):
            resolved_model = str(config_data.get("context_store_embedding_model") or "").strip() or None
        return cls(base_url=base_url, model=resolved_model or DEFAULT_EMBEDDING_MODEL, timeout=timeout)

    def embed(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        payload = json.dumps({"model": self.model, "input": list(texts)}).encode("utf-8")
        req = urllib.request.Request(
            f"{self.base_url}/v1/embeddings",
            data=payload,
            headers={"Content-Type": "application/json", "Accept": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as exc:
            try:
                detail = exc.read(2048).decode("utf-8", errors="replace")
            except Exception:
                detail = ""
            raise EmbeddingClientError(f"Embeddings endpoint returned HTTP {exc.code}: {detail[:500]}") from exc
        except Exception as exc:
            raise EmbeddingClientError(f"Embeddings request failed: {exc}") from exc
        try:
            body = json.loads(raw or "{}")
        except json.JSONDecodeError as exc:
            raise EmbeddingClientError("Embeddings endpoint returned invalid JSON") from exc
        data = body.get("data") if isinstance(body, dict) else None
        if not isinstance(data, list):
            raise EmbeddingClientError("Embeddings endpoint returned an unexpected payload shape")
        vectors: list[list[float]] = []
        for item in data:
            embedding = (item or {}).get("embedding") if isinstance(item, dict) else None
            if not isinstance(embedding, list):
                raise EmbeddingClientError("Embeddings endpoint returned a malformed embedding entry")
            vectors.append([float(value) for value in embedding])
        if len(vectors) != len(texts):
            raise EmbeddingClientError("Embeddings endpoint returned a mismatched result count")
        return vectors


__all__ = ["DEFAULT_EMBEDDING_MODEL", "EmbeddingClientError", "OllamaEmbeddingsClient"]
