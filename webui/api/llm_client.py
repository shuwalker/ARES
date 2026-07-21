"""Optional direct Anthropic/OpenAI SDK calls for the Missions orchestrator.

Sub-agent dispatch (webui/api/missions.py) routes coding/tool-using sub-tasks
through the existing Hermes/JROS backends (webui/api/backends/), which carry
tool use, memory, and persona. This module is only for the CEO decomposition
step and pure-reasoning sub-tasks that call a cloud model directly with no
agent loop involved.

anthropic/openai are optional installs — see requirements.txt — matching the
edge-tts/psutil/python-docx pattern already used elsewhere in this webui:
missing package or missing key raises LLMProviderUnavailable, which callers
turn into a graceful per-subtask failure rather than a server error.
"""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


class LLMProviderUnavailable(RuntimeError):
    """Raised when a direct provider call can't be made (no SDK or no key)."""


def _resolve_key(env_names: tuple[str, ...]) -> str | None:
    from api.config import _thread_local_env_value

    for name in env_names:
        value = _thread_local_env_value(name).strip()
        if value:
            return value
    return None


def _anthropic_key() -> str | None:
    from api.config import _get_anthropic_fallback_env_vars

    return _resolve_key(_get_anthropic_fallback_env_vars())


def _openai_key() -> str | None:
    return _resolve_key(("OPENAI_API_KEY",))


def _missions_config() -> dict:
    from api import config as _config

    cfg = getattr(_config, "cfg", {}) or {}
    missions_cfg = cfg.get("missions", {}) if isinstance(cfg, dict) else {}
    return missions_cfg if isinstance(missions_cfg, dict) else {}


def default_anthropic_model() -> str:
    return str(_missions_config().get("anthropic_model") or "claude-sonnet-4-5")


def default_openai_model() -> str:
    return str(_missions_config().get("openai_model") or "gpt-4o")


def call_anthropic(prompt: str, *, system: str | None = None, model: str | None = None, max_tokens: int = 4096) -> str:
    """One-shot Anthropic Messages API call. Raises LLMProviderUnavailable if unusable."""
    try:
        import anthropic
    except ImportError as exc:
        raise LLMProviderUnavailable(
            "The 'anthropic' package is not installed. Install it in the webui venv: pip install anthropic"
        ) from exc
    key = _anthropic_key()
    if not key:
        raise LLMProviderUnavailable(
            "No Anthropic API key configured. Set ANTHROPIC_API_KEY in ~/.hermes/.env or the environment."
        )
    client = anthropic.Anthropic(api_key=key)
    resp = client.messages.create(
        model=model or default_anthropic_model(),
        max_tokens=max_tokens,
        system=system or "",
        messages=[{"role": "user", "content": prompt}],
    )
    return "".join(block.text for block in resp.content if getattr(block, "type", None) == "text")


def call_openai(prompt: str, *, system: str | None = None, model: str | None = None, max_tokens: int = 4096) -> str:
    """One-shot OpenAI Chat Completions call. Raises LLMProviderUnavailable if unusable."""
    try:
        import openai
    except ImportError as exc:
        raise LLMProviderUnavailable(
            "The 'openai' package is not installed. Install it in the webui venv: pip install openai"
        ) from exc
    key = _openai_key()
    if not key:
        raise LLMProviderUnavailable(
            "No OpenAI API key configured. Set OPENAI_API_KEY in ~/.hermes/.env or the environment."
        )
    client = openai.OpenAI(api_key=key)
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    resp = client.chat.completions.create(model=model or default_openai_model(), max_tokens=max_tokens, messages=messages)
    return resp.choices[0].message.content or ""


def provider_available(provider: str) -> bool:
    """Cheap availability check (SDK importable + key resolvable) for status reporting."""
    if provider == "anthropic":
        try:
            import anthropic  # noqa: F401
        except ImportError:
            return False
        return _anthropic_key() is not None
    if provider == "openai":
        try:
            import openai  # noqa: F401
        except ImportError:
            return False
        return _openai_key() is not None
    return False
