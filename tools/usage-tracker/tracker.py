#!/usr/bin/env python3
"""
ARES Usage Tracker — tracks LLM provider usage to prevent burning through weekly quotas.

Tracks requests per provider, calculates burn rate against configurable weekly budgets,
and writes routing state so Hermes can skip depleted providers before they 429.

Reset windows:
  - Ollama Cloud: 5-hour session + 7-day weekly
  - xAI Grok: rolling windows (2h/5h/24h)
  - OpenAI Codex: 5-hour rolling + weekly cap

Usage data stored in ~/.ares/usage_tracker.json
"""

import json
import os
import time
from datetime import datetime, timezone
from typing import Optional

# ── Paths ──────────────────────────────────────────────────────────────────

DATA_DIR = os.path.expanduser("~/.ares")
DATA_FILE = os.path.join(DATA_DIR, "usage_tracker.json")
STATE_FILE = os.path.join(DATA_DIR, "provider_state.json")

# ── Model weight tiers (relative GPU-time cost) ────────────────────────────
# Level 1 = baseline. Each level up burns ~2x more quota per request.
# These are estimates — tune based on real-world experience.

MODEL_WEIGHTS = {
    # Ollama Cloud
    "gpt-oss:20b": 1,
    "gpt-oss:20b-cloud": 1,
    "devstral-small-2": 1,
    "devstral-small-2:cloud": 1,
    "deepseek-v4-flash": 2,
    "deepseek-v4-flash:cloud": 2,
    "qwen3.5:397b-cloud": 3,
    "gemma4:31b-cloud": 2,
    "nemotron-3-super:cloud": 2,
    "gpt-oss:120b-cloud": 2,
    "glm-5.1": 4,
    "glm-5.1:cloud": 4,
    "glm-5": 4,
    "glm-5.2": 4,
    "kimi-k2.6": 4,
    "kimi-k2.6:cloud": 4,
    "minimax-m3": 4,
    "minimax-m3:cloud": 4,
    "deepseek-v4-pro": 4,
    # xAI Grok
    "grok-4.3": 2,
    "grok-4": 2,
    "grok-build-0.1": 2,
    # OpenAI Codex
    "gpt-5.5": 2,
    "gpt-5.5-codex": 2,
    "gpt-5.3-codex": 2,
}

DEFAULT_WEIGHT = 2  # fallback for unknown models

# ── Default weekly budgets (in weight-units) ───────────────────────────────
# These are starting estimates. Tune by observing when you actually hit limits.
# Ollama Cloud Pro: ~50x Free tier. If Free ~100 units/week, Pro ~5000.
# Set conservatively — you can raise them.

DEFAULT_BUDGETS = {
    "ollama-cloud": 5000,   # weight-units per week — tune this
    "xai-oauth": 3000,      # Grok SuperGrok estimate
    "openai-codex": 4000,   # Codex Pro estimate
}

# ── Reset windows in seconds ──────────────────────────────────────────────

SESSION_WINDOW = 5 * 3600       # 5 hours
WEEKLY_WINDOW = 7 * 24 * 3600   # 7 days

# ── Thresholds ────────────────────────────────────────────────────────────

PROACTIVE_SWITCH_THRESHOLD = 0.80  # switch when 80% of weekly budget projected


def _load() -> dict:
    """Load usage tracker data."""
    if os.path.exists(DATA_FILE):
        try:
            with open(DATA_FILE) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {"requests": [], "budgets": dict(DEFAULT_BUDGETS)}


def _save(data: dict):
    """Save usage tracker data."""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(DATA_FILE, "w") as f:
        json.dump(data, f, indent=2, default=str)


def _load_state() -> dict:
    """Load provider routing state."""
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {"depleted": {}, "active_provider": None}


def _save_state(state: dict):
    """Save provider routing state."""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


def get_weight(model: str) -> int:
    """Get the weight tier for a model."""
    return MODEL_WEIGHTS.get(model, MODEL_WEIGHTS.get(model.replace(":cloud", ""), DEFAULT_WEIGHT))


def record(provider: str, model: str, response_length: int = 0):
    """
    Record a request to a provider.

    Args:
        provider: Provider name (ollama-cloud, xai-oauth, openai-codex)
        model: Model name
        response_length: Approximate response token count (for future refinement)
    """
    data = _load()
    now = time.time()
    weight = get_weight(model)

    data["requests"].append({
        "provider": provider,
        "model": model,
        "weight": weight,
        "timestamp": now,
        "response_length": response_length,
    })

    # Prune entries older than 8 days (keep one extra day beyond weekly window)
    cutoff = now - (WEEKLY_WINDOW + 86400)
    data["requests"] = [r for r in data["requests"] if r["timestamp"] >= cutoff]

    _save(data)


def get_usage(provider: Optional[str] = None, window: str = "weekly") -> dict:
    """
    Get usage stats for a provider.

    Args:
        provider: Provider name, or None for all
        window: "session" (5h) or "weekly" (7d)

    Returns:
        dict with total_weight, request_count, window_start, window_end, remaining_estimate
    """
    data = _load()
    now = time.time()

    if window == "session":
        window_seconds = SESSION_WINDOW
    else:
        window_seconds = WEEKLY_WINDOW

    cutoff = now - window_seconds

    requests = data["requests"]
    if provider:
        requests = [r for r in requests if r["provider"] == provider]

    in_window = [r for r in requests if r["timestamp"] >= cutoff]
    total_weight = sum(r["weight"] for r in in_window)
    request_count = len(in_window)

    # Find the earliest request in this window to calculate start
    if in_window:
        window_start = min(r["timestamp"] for r in in_window)
    else:
        window_start = now

    window_end = window_start + window_seconds

    # Budget
    budget = data.get("budgets", {}).get(provider or "unknown", DEFAULT_BUDGETS.get(provider, 5000)) if provider else 5000

    return {
        "provider": provider or "all",
        "window": window,
        "window_seconds": window_seconds,
        "window_start": window_start,
        "window_end": window_end,
        "request_count": request_count,
        "total_weight": total_weight,
        "budget": budget,
        "remaining": max(0, budget - total_weight),
        "pct_used": round((total_weight / budget) * 100, 1) if budget > 0 else 0,
    }


def get_burn_rate(provider: str) -> dict:
    """
    Calculate burn rate and projected depletion for a provider.

    Returns:
        dict with rate_per_hour, projected_depletion_ts, projected_depletion_in,
        will_exhaust_before_reset, days_early
    """
    usage = get_usage(provider, window="weekly")
    now = time.time()

    total_weight = usage["total_weight"]
    budget = usage["budget"]
    window_start = usage["window_start"]
    window_end = usage["window_end"]

    # Hours elapsed since window start
    hours_elapsed = max(0.1, (now - window_start) / 3600)

    # Burn rate per hour
    rate_per_hour = total_weight / hours_elapsed

    # Projected depletion
    remaining = budget - total_weight
    if rate_per_hour > 0 and remaining > 0:
        hours_until_depleted = remaining / rate_per_hour
        projected_depletion_ts = now + (hours_until_depleted * 3600)
    else:
        hours_until_depleted = 0
        projected_depletion_ts = now

    # Will we exhaust before the weekly reset?
    hours_until_reset = max(0, (window_end - now) / 3600)
    will_exhaust = hours_until_depleted < hours_until_reset and rate_per_hour > 0

    days_early = 0
    if will_exhaust:
        days_early = round((hours_until_reset - hours_until_depleted) / 24, 1)

    return {
        "provider": provider,
        "rate_per_hour": round(rate_per_hour, 1),
        "total_weight": total_weight,
        "budget": budget,
        "remaining": remaining,
        "pct_used": usage["pct_used"],
        "hours_elapsed": round(hours_elapsed, 1),
        "hours_until_reset": round(hours_until_reset, 1),
        "projected_depletion_ts": projected_depletion_ts,
        "projected_depletion_in_hours": round(hours_until_depleted, 1),
        "will_exhaust_before_reset": will_exhaust,
        "days_early": days_early,
        "window_end": window_end,
    }


def evaluate_routing() -> dict:
    """
    Evaluate all providers and determine optimal routing.

    Returns:
        dict with active_provider, depleted list, and per-provider status
    """
    state = _load_state()
    now = time.time()

    providers = ["xai-oauth", "openai-codex", "ollama-cloud"]
    results = {}

    for provider in providers:
        burn = get_burn_rate(provider)
        usage = get_usage(provider, window="weekly")

        # Check if provider is depleted or should be skipped
        is_depleted = False
        reason = None

        if usage["remaining"] <= 0:
            is_depleted = True
            reason = "budget_exhausted"
        elif burn["will_exhaust_before_reset"] and usage["pct_used"] >= PROACTIVE_SWITCH_THRESHOLD * 100:
            is_depleted = True
            reason = f"projected_depletion_{burn['days_early']}d_early"

        results[provider] = {
            "depleted": is_depleted,
            "reason": reason,
            "pct_used": usage["pct_used"],
            "remaining": usage["remaining"],
            "burn_rate": burn["rate_per_hour"],
            "will_exhaust": burn["will_exhaust_before_reset"],
            "days_early": burn["days_early"],
        }

    # Determine active provider (first non-depleted in priority order)
    active = None
    for provider in providers:
        if not results[provider]["depleted"]:
            active = provider
            break

    # Update state
    state["depleted"] = {p: results[p]["reason"] for p in providers if results[p]["depleted"]}
    state["active_provider"] = active
    state["last_evaluated"] = now
    state["providers"] = results
    _save_state(state)

    return {
        "active_provider": active,
        "depleted": state["depleted"],
        "providers": results,
        "timestamp": now,
    }


def set_budget(provider: str, budget: int):
    """Set the weekly budget (in weight-units) for a provider."""
    data = _load()
    data.setdefault("budgets", {}).update(DEFAULT_BUDGETS)
    data["budgets"][provider] = budget
    _save(data)


def get_budgets() -> dict:
    """Get current budgets for all providers."""
    data = _load()
    return data.get("budgets", dict(DEFAULT_BUDGETS))


def reset_provider(provider: str):
    """Reset usage data for a provider (for testing or manual reset)."""
    data = _load()
    data["requests"] = [r for r in data["requests"] if r["provider"] != provider]
    _save(data)

    state = _load_state()
    state["depleted"].pop(provider, None)
    _save_state(state)


def summary() -> str:
    """Get a human-readable summary of current usage."""
    result = evaluate_routing()
    lines = []
    lines.append(f"Active provider: {result['active_provider'] or 'NONE'}")
    lines.append("")

    for provider, info in result["providers"].items():
        status = "⚠️ DEPLETED" if info["depleted"] else "✅ OK"
        if info["reason"]:
            status += f" ({info['reason']})"
        lines.append(f"  {provider}:")
        lines.append(f"    Status:     {status}")
        lines.append(f"    Used:       {info['pct_used']}%")
        lines.append(f"    Remaining:  {info['remaining']} units")
        lines.append(f"    Burn rate:  {info['burn_rate']} units/hr")
        if info["will_exhaust"]:
            lines.append(f"    ⚠️ Will exhaust {info['days_early']} days before reset")
        lines.append("")

    return "\n".join(lines)


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print(summary())
        sys.exit(0)

    cmd = sys.argv[1]

    if cmd == "record":
        provider = sys.argv[2] if len(sys.argv) > 2 else "ollama-cloud"
        model = sys.argv[3] if len(sys.argv) > 3 else "deepseek-v4-flash"
        record(provider, model)
        print(f"Recorded request to {provider}/{model}")

    elif cmd == "status":
        print(summary())

    elif cmd == "evaluate":
        result = evaluate_routing()
        print(json.dumps(result, indent=2, default=str))

    elif cmd == "budget":
        if len(sys.argv) == 4:
            set_budget(sys.argv[2], int(sys.argv[3]))
            print(f"Set {sys.argv[2]} budget to {sys.argv[3]}")
        else:
            budgets = get_budgets()
            for p, b in budgets.items():
                print(f"  {p}: {b} units/week")

    elif cmd == "reset":
        provider = sys.argv[2] if len(sys.argv) > 2 else "ollama-cloud"
        reset_provider(provider)
        print(f"Reset usage data for {provider}")

    else:
        print(f"Unknown command: {cmd}")
        print("Usage: tracker.py [record|status|evaluate|budget|reset]")
