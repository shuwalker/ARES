"""Research utilities shared across deep research and handler.

Ported from Odysseus src/research_utils.py. Centralizes text cleaning,
quality filtering, and other logic used across the research system.
"""

from __future__ import annotations

import re
from typing import Optional


def strip_thinking(text: Optional[str]) -> Optional[str]:
    """Strip thinking/reasoning blocks from LLM output.

    Removes <think>...</think>, <thinking>...</thinking>, and
    similar reasoning tags that some models emit.
    """
    if text is None:
        return None
    # Remove <think>...</think> blocks (possibly multiline)
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL)
    text = re.sub(r"<thinking>.*?</thinking>", "", text, flags=re.DOTALL)
    # Remove <reflection>...</reflection> blocks
    text = re.sub(r"<reflection>.*?</reflection>", "", text, flags=re.DOTALL)
    return text.strip()


# Markers indicating extracted content is boilerplate, error text, or empty.
LOW_QUALITY_MARKERS = [
    "insufficient to",
    "content is insufficient",
    "no substantive data",
    "does not contain",
    "not relevant to",
    "no relevant information",
    "unable to extract",
    "completely unrelated",
    "boilerplate",
    "footer text",
    "cookie consent",
    "cookie banner",
    "cookie notice",
    "copyright notice",
    "copyright footer",
    "all rights reserved",
]


def is_low_quality(summary: str) -> bool:
    """Check if a finding summary indicates useless or irrelevant content."""
    try:
        if not isinstance(summary, str) or not summary:
            return True
        low = summary.lower()
        return any(marker in low for marker in LOW_QUALITY_MARKERS)
    except Exception:
        return False  # fail open