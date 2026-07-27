"""Ollama readiness and model discovery.

The simplest transport shape in the provider layout — a plain local HTTP server,
no gateway/bridge choice, no CLI probe — which is the point: the status contract
holds without forcing JaegerAI's or Hermes's structure onto it.

Honours ``OLLAMA_HOST`` so a remote or non-default daemon is reachable.
"""
from __future__ import annotations

import logging

from api.providers.status_contract import ProviderStatus, connected, offline

logger = logging.getLogger(__name__)

_TIMEOUT = 2.0


def base_url() -> str:
    """Ollama's HTTP endpoint, honouring ``OLLAMA_HOST``."""
    from api.backends.cli_backends import _ollama_base_url

    return _ollama_base_url()


def _tags() -> list[dict] | None:
    """Ollama's installed-model list, or None when the daemon is unreachable."""
    import requests

    try:
        response = requests.get(f"{base_url()}/api/tags", timeout=_TIMEOUT)
    except Exception:
        logger.debug("Ollama tags probe failed", exc_info=True)
        return None
    if response.status_code != 200:
        return None
    try:
        payload = response.json()
    except Exception:
        logger.debug("Ollama returned a non-JSON tag listing", exc_info=True)
        return None
    models = payload.get("models") if isinstance(payload, dict) else None
    return models if isinstance(models, list) else []


def check_status() -> ProviderStatus:
    """Whether the Ollama daemon is answering, and how many models it holds."""
    models = _tags()
    if models is None:
        return offline(
            f"Ollama is not reachable at {base_url()}. Start it with `ollama serve`.",
            endpoint=base_url(),
        )
    return connected(
        f"Ollama is running with {len(models)} model(s).",
        endpoint=base_url(),
        model_count=len(models),
    )


def installed_models() -> list[dict]:
    """Models Ollama actually has, newest-looking name first.

    Returns an empty list when the daemon is unreachable — callers render "no
    models" rather than a hardcoded guess.
    """
    return _tags() or []
