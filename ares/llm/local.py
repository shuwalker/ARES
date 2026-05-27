"""Local LLM client — LM Studio at localhost:1234.

Uses OpenAI-compatible API.
"""

from __future__ import annotations

import httpx
from typing import Any

from ares.runtime.config import get_config
from ares.runtime.audit import log

# Shared async client — avoids per-request TCP overhead
_client: httpx.AsyncClient | None = None


def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient()
    return _client


async def complete(
    *,
    system: str,
    messages: list[dict[str, Any]],
    task_id: str | None = None,
    max_tokens: int = 4096,
    model: str | None = None,
) -> str:
    """Call the local LM Studio model and return the text response."""
    cfg = get_config()
    base_url = cfg.agent.local_ollama_url
    model = model or cfg.agent.local_model

    await log(
        task_id=task_id,
        action="llm_call",
        backend="local",
        model=model,
        url=base_url,
    )

    payload = {
        "model": model,
        "messages": [{"role": "system", "content": system}] + messages,
        "max_tokens": max_tokens,
        "stream": False,
        "options": {"num_ctx": 65536},
    }

    # Fast-path gate (Lilith pattern) — placeholder.
    # If cfg.agent.fast_path_enabled, a lightweight model (llama3.2:3b)
    # would intercept short/simple turns here and short-circuit the call,
    # returning early before engaging the full agent. Not yet implemented.
    try:
        client = _get_client()
        response = await client.post(
            f"{base_url}/chat/completions",
            json=payload,
            timeout=120.0,
        )
        response.raise_for_status()
        data = response.json()
        text = data["choices"][0]["message"]["content"]

        await log(
            task_id=task_id,
            action="llm_response",
            backend="local",
            tokens=data.get("usage", {}).get("completion_tokens", 0),
        )
        return text

    except (httpx.ConnectError, httpx.TimeoutException) as e:
        await log(
            task_id=task_id,
            action="llm_error",
            backend="local",
            error=str(e),
        )
        raise RuntimeError(f"LM Studio not reachable at {base_url}. Is LM Studio running with a model loaded?") from e


async def is_available() -> bool:
    """Check if LM Studio is running."""
    cfg = get_config()
    base_url = cfg.agent.local_ollama_url
    try:
        client = _get_client()
        response = await client.get(f"{base_url}/models", timeout=5.0)
        return response.status_code == 200
    except Exception:
        return False
