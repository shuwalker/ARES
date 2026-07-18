"""Wraps ContextCompressor to run a single forced compression on a fixture.

The real agent loop checks ``should_compress()`` before calling ``compress()``.
Fixtures are intentionally sized below the 100k threshold so ``compress()``
runs in a controlled, single-shot mode — score deltas attribute to the
prompt change, not to whether the threshold happened to fire at the same
boundary twice.

Resolves the provider for the compression call via the same path the real
agent uses (``hermes_cli.runtime_provider.resolve_runtime_provider``) so
behaviour matches production aside from being a single call.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

# Locate the hermes-agent checkout so we can import ContextCompressor.
# Priority: HERMES_AGENT_ROOT env var > ~/.hermes/hermes-agent (default
# location set up by `hermes setup`) > sibling directory (handy for
# developers who clone both repos next to each other).
def _locate_hermes_agent() -> Path:
    env = os.environ.get("HERMES_AGENT_ROOT")
    if env:
        path = Path(env).expanduser().resolve()
        if (path / "agent" / "context_compressor.py").is_file():
            return path
        raise RuntimeError(
            f"HERMES_AGENT_ROOT={env} does not contain agent/context_compressor.py"
        )
    candidates = [
        Path.home() / ".hermes" / "hermes-agent",
        Path(__file__).resolve().parent.parent / "hermes-agent",
    ]
    for candidate in candidates:
        if (candidate / "agent" / "context_compressor.py").is_file():
            return candidate.resolve()
    raise RuntimeError(
        "Could not locate the hermes-agent repo. Set HERMES_AGENT_ROOT to "
        "your checkout, or clone hermes-agent into ~/.hermes/hermes-agent "
        "(the default `hermes setup` location) or as a sibling directory."
    )


_HERMES_AGENT_ROOT = _locate_hermes_agent()
if str(_HERMES_AGENT_ROOT) not in sys.path:
    sys.path.insert(0, str(_HERMES_AGENT_ROOT))

from agent.context_compressor import (  # noqa: E402
    ContextCompressor,
    estimate_messages_tokens_rough,
)


def run_compression(
    *,
    messages: List[Dict[str, Any]],
    compressor_model: str,
    compressor_provider: str,
    compressor_base_url: str,
    compressor_api_key: str,
    compressor_api_mode: str,
    context_length: int,
    focus_topic: Optional[str] = None,
    summary_model_override: Optional[str] = None,
) -> Dict[str, Any]:
    """Run a single forced compression pass over the fixture messages.

    Returns a dict with:
      - compressed_messages: the post-compression message list
      - summary_text: the summary produced (extracted from the compressed head)
      - pre_tokens, post_tokens: rough token counts before/after
      - compression_ratio: 1 - (post/pre)
      - pre_message_count, post_message_count
    """
    compressor = ContextCompressor(
        model=compressor_model,
        threshold_percent=0.50,
        protect_first_n=3,
        protect_last_n=20,
        summary_target_ratio=0.20,
        quiet_mode=True,
        summary_model_override=summary_model_override or "",
        base_url=compressor_base_url,
        api_key=compressor_api_key,
        config_context_length=context_length,
        provider=compressor_provider,
        api_mode=compressor_api_mode,
    )

    pre_tokens = estimate_messages_tokens_rough(messages)
    compressed = compressor.compress(
        messages,
        current_tokens=pre_tokens,
        focus_topic=focus_topic,
    )
    post_tokens = estimate_messages_tokens_rough(compressed)

    summary_text = _extract_summary_from_messages(compressed)

    ratio = (1.0 - (post_tokens / pre_tokens)) if pre_tokens > 0 else 0.0

    return {
        "compressed_messages": compressed,
        "summary_text": summary_text,
        "pre_tokens": pre_tokens,
        "post_tokens": post_tokens,
        "compression_ratio": ratio,
        "pre_message_count": len(messages),
        "post_message_count": len(compressed),
    }


_SUMMARY_MARKERS = (
    "## Active Task",
    "## Goal",
    "## Completed Actions",
)


def _extract_summary_from_messages(messages: List[Dict[str, Any]]) -> str:
    """Find the structured summary block inside the compressed message list.

    The compressor injects the summary as a user (or system-appended) message
    near the head. We look for the section-header markers from
    ``_template_sections`` in ``agent/context_compressor.py``.
    """
    for msg in messages:
        content = msg.get("content")
        if not isinstance(content, str):
            if isinstance(content, list):
                content = "\n".join(
                    p.get("text", "") for p in content if isinstance(p, dict)
                )
            else:
                continue
        if any(marker in content for marker in _SUMMARY_MARKERS):
            return content
    return ""
