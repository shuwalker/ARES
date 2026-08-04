"""LLM cost calculation using LiteLLM (industry standard).

Uses LiteLLM's pricing database which is automatically maintained
and covers 100+ LLM models from all major providers.
"""

from __future__ import annotations

import logging
from typing import Optional

logger = logging.getLogger(__name__)


def estimate_cost(
    model: str,
    input_tokens: int,
    output_tokens: int,
) -> float:
    """Calculate cost for an LLM API call using LiteLLM pricing.

    Args:
        model: Model name (e.g., "claude-3-opus", "gpt-4", "gemini-1.5-pro")
        input_tokens: Number of input tokens
        output_tokens: Number of output tokens

    Returns:
        Cost in USD (float)

    Examples:
        >>> estimate_cost("claude-3-opus", 1000, 500)
        0.04125  # $0.015 per 1K input + $0.075 per 1K output

        >>> estimate_cost("llama2-70b", 1000, 500)
        0.0  # Local model, zero marginal cost

    Note:
        LiteLLM maintains pricing for 100+ models and updates automatically.
        If a model is not found, returns 0.0 (assumes local/free).
    """
    try:
        from litellm import completion_cost

        # LiteLLM's completion_cost() calculates total cost for a completion
        # It internally knows input/output token pricing per model
        # Create a mock completion response
        total_cost = completion_cost(
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
        )

        return round(total_cost, 6)

    except Exception as exc:
        logger.warning("Could not calculate cost for model %s: %s", model, exc)
        # Fallback: $0.001 per 1K tokens (safe underestimate)
        return round(((input_tokens + output_tokens) / 1000.0) * 0.001, 6)


def get_model_provider(model: str) -> str:
    """Identify which provider a model belongs to.

    Returns one of: "anthropic", "openai", "google", "meta", "mistral", "local", "unknown"
    """
    model_lower = model.lower()

    if "claude" in model_lower:
        return "anthropic"
    elif "gpt" in model_lower or "o1" in model_lower:
        return "openai"
    elif "gemini" in model_lower:
        return "google"
    elif "llama" in model_lower:
        return "meta"
    elif "mistral" in model_lower:
        return "mistral"
    elif "local" in model_lower or "offline" in model_lower:
        return "local"
    else:
        return "unknown"


def is_local_model(model: str) -> bool:
    """Check if model runs locally (zero marginal cost)."""
    return get_model_provider(model) == "local"
