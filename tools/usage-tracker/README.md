# ARES Usage Tracker

Tracks LLM provider usage across sessions to prevent burning through weekly quotas.

## The Problem

Ollama Cloud has no API to check remaining quota — no headers, no endpoint. The only way to see usage is the web dashboard. This means you can burn through your weekly allowance 2-3 days early without warning.

## The Solution

A local usage tracker that:

1. **Records every request** — timestamp, model, estimated GPU-time weight
2. **Tracks both windows** — 5-hour session and 7-day weekly, knows when each resets
3. **Calculates burn rate** — "at this rate, you'll hit the weekly cap on Thursday instead of Sunday"
4. **Proactively switches** — when projected burn hits 80% of weekly, marks provider as depleted so Ares routes to the next provider

## Files

| File | Purpose |
|------|---------|
| `tracker.py` | Core engine — recording, burn rate, threshold detection, routing evaluation |
| `tool.py` | Ares tool entry point — CLI interface for recording and checking |
| `cron_check.py` | Cron check script — runs every 15-30 min, reports projected depletion |
| `__init__.py` | Package marker |

## Data Files (in `~/.ares/`)

| File | Purpose |
|------|---------|
| `usage_tracker.json` | Raw request log with timestamps, models, weights |
| `provider_state.json` | Current routing state — which providers are depleted, active provider |

## Model Weight Tiers

Models are assigned a weight (1-4) based on relative GPU-time cost:

| Level | Examples | Relative Cost |
|-------|----------|---------------|
| 1 (Light) | gpt-oss:20b, devstral-small-2 | 1x |
| 2 (Medium) | deepseek-v4-flash, gemma4:31b, nemotron-3-super | 2x |
| 3 (Heavy) | qwen3.5:397b-cloud | 3x |
| 4 (Extra Heavy) | glm-5.1, kimi-k2.6, minimax-m3, deepseek-v4-pro | 4x |

## Usage

```bash
# Record a request
python3 tool.py record ollama-cloud deepseek-v4-flash

# Check current status
python3 tool.py status

# Evaluate routing (which provider should be active)
python3 tool.py evaluate

# Set a weekly budget (in weight-units)
python3 tool.py budget ollama-cloud 5000

# Reset a provider's usage data
python3 tool.py reset ollama-cloud
```

## Budget Tuning

Default budgets are estimates. Tune them by observing when you actually hit limits:

1. Note the date you hit a 429 on a provider
2. Check `usage_tracker.json` for total weight in the last 7 days
3. Set budget slightly below that: `python3 tool.py budget ollama-cloud <value>`

## Provider Chain

The tracker evaluates providers in priority order:

1. **xai-oauth** (Grok 4.3) — burn xAI usage first
2. **openai-codex** (GPT-5.5) — burn OpenAI usage next
3. **ollama-cloud** (deepseek-v4-flash) — last cloud resort
4. **ollama-local** (gemma4:e4b-mlx) — recovery (always available)
