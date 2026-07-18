"""
plugin-llm-example — reference plugin for ``ctx.llm.complete_structured()``.

Companion to the
`Plugin LLM Access <https://hermes-agent.nousresearch.com/docs/developer-guide/plugin-llm-access>`_
docs page. Demonstrates the host-owned structured LLM lane:

* registers a single ``/receipt-extract <path>`` slash command,
* takes either a text or image file,
* returns a structured JSON record using the user's active model,
* never sees an OAuth token or API key.

Output schema::

    {
      "vendor": "...",
      "total": 0.0,
      "currency": "USD",
      "tags": ["..."]
    }

The trust gate defaults are fully restrictive: the plugin runs against
whatever provider+model the user has active. Operators who want to
pin this plugin to a specific model add::

    plugins:
      entries:
        plugin-llm-example:
          llm:
            allow_model_override: true
            allowed_models:
              - openai/gpt-4o
              - anthropic/claude-3-5-sonnet

…to ``config.yaml`` and the plugin's ``model=`` argument starts working.

This file is the smallest plugin code that exercises every part of
``ctx.llm.complete_structured()``: typed image+text input blocks,
JSON Schema validation, fallback handling for unparseable responses,
and the audit/purpose pattern. Read it alongside the docs page.
"""

from __future__ import annotations

import json
import logging
import mimetypes
import os
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger(__name__)


_RECEIPT_SCHEMA = {
    "type": "object",
    "properties": {
        "vendor": {"type": "string"},
        "total": {"type": "number"},
        "currency": {"type": "string"},
        "tags": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["vendor", "total"],
    "additionalProperties": True,
}


_INSTRUCTIONS = (
    "Extract a structured receipt record from the supplied content. "
    "Prefer the printed total over handwritten notes. "
    "Use ISO 4217 currency codes (e.g. USD, EUR). "
    "Tags should be 1-5 short categorical labels (e.g. groceries, hardware, taxi)."
)


def _looks_like_image(path: Path) -> bool:
    mime, _ = mimetypes.guess_type(str(path))
    return bool(mime and mime.startswith("image/"))


def _build_input_blocks(target: Path) -> list[dict[str, Any]]:
    """Build the structured input list for the active receipt target.

    Image files become an ``image`` block carrying raw bytes; text
    files become a ``text`` block carrying the file contents (clipped
    to 16k characters so we don't blow the model's context on a
    pathological input).
    """
    if _looks_like_image(target):
        data = target.read_bytes()
        mime, _ = mimetypes.guess_type(str(target))
        return [{
            "type": "image",
            "data": data,
            "mime_type": mime or "image/png",
            "file_name": target.name,
        }]
    text = target.read_text(encoding="utf-8", errors="replace")
    if len(text) > 16_000:
        text = text[:16_000] + "\n[... truncated ...]"
    return [{"type": "text", "text": text}]


def _make_handler(ctx: Any):
    """Build the ``/receipt-extract`` handler bound to this plugin's ctx."""

    def handler(raw_args: str) -> str:
        target_str = raw_args.strip().strip('"').strip("'")
        if not target_str:
            return (
                "Usage: /receipt-extract <path-to-receipt>\n"
                "  Accepts plain-text receipts or image files (PNG/JPEG)."
            )
        target = Path(os.path.expanduser(target_str)).resolve()
        if not target.exists():
            return f"File not found: {target}"
        if not target.is_file():
            return f"Not a file: {target}"

        try:
            inputs = _build_input_blocks(target)
        except Exception as exc:  # pragma: no cover — defensive
            return f"Failed to read {target}: {exc}"

        try:
            result = ctx.llm.complete_structured(
                instructions=_INSTRUCTIONS,
                input=inputs,
                json_schema=_RECEIPT_SCHEMA,
                schema_name="receipt.record",
                purpose="plugin-llm-example.extract_receipt",
                temperature=0.0,
                max_tokens=512,
            )
        except Exception as exc:
            logger.warning("receipt-extract failed: %s", exc)
            return f"Extraction failed: {exc}"

        if result.parsed is not None:
            pretty = json.dumps(result.parsed, indent=2, ensure_ascii=False)
            return (
                f"Extracted via {result.provider}/{result.model} "
                f"({result.usage.total_tokens} tokens):\n```json\n{pretty}\n```"
            )
        # Schema/JSON parsing failed — return raw text so the user can see why.
        return (
            f"Model did not return parseable JSON.\n"
            f"Raw response from {result.provider}/{result.model}:\n"
            f"---\n{result.text}\n---"
        )

    return handler


def register(ctx: Any) -> None:
    """Plugin entry point — wires the slash command."""
    ctx.register_command(
        name="receipt-extract",
        handler=_make_handler(ctx),
        description="Extract a structured JSON record from a receipt file (text or image).",
        args_hint="<path>",
    )
    logger.debug("plugin-llm-example: registered /receipt-extract")
