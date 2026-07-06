#!/usr/bin/env python3
"""
ARES Usage Tracker — cron check script.

Runs periodically to:
  1. Evaluate provider usage and burn rates
  2. Update provider_state.json with current routing info
  3. Report if a provider is projected to exhaust before reset

Called by Hermes cron job every 15-30 minutes.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tracker import evaluate_routing, get_burn_rate


def main():
    result = evaluate_routing()
    active = result["active_provider"]
    depleted = result["depleted"]

    # Build a report
    lines = []
    lines.append(f"Active: {active or 'NONE'}")
    lines.append("")

    for provider, info in result["providers"].items():
        status = "DEPLETED" if info["depleted"] else "OK"
        lines.append(f"{provider}: {status} | {info['pct_used']}% used | {info['remaining']} remaining | {info['burn_rate']}/hr")
        if info["will_exhaust"]:
            lines.append(f"  ⚠️  Will exhaust {info['days_early']}d before weekly reset")

    # If ollama-cloud is projected to exhaust early, that's the headline
    oc = result["providers"].get("ollama-cloud", {})
    if oc.get("will_exhaust"):
        lines.append("")
        lines.append(f"⚠️  OLLAMA-CLOUD: will exhaust {oc['days_early']}d early at current burn rate")
        lines.append(f"   Switch to: {active or 'NONE'}")

    print("\n".join(lines))


if __name__ == "__main__":
    main()
