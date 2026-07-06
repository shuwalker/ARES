#!/usr/bin/env python3
"""
ARES Usage Tracker — Hermes tool entry point.

Called by Hermes to:
  - Record a request to a provider
  - Check current usage status
  - Evaluate which provider to route to
  - Set budgets
  - Reset provider data

Usage:
  python3 tool.py record <provider> <model> [response_length]
  python3 tool.py status
  python3 tool.py evaluate
  python3 tool.py budget [provider] [amount]
  python3 tool.py reset <provider>
"""

import sys
import os

# Add parent to path so we can import tracker
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tracker import record, summary, evaluate_routing, set_budget, get_budgets, reset_provider


def main():
    if len(sys.argv) < 2:
        print(summary())
        return

    cmd = sys.argv[1]

    if cmd == "record":
        provider = sys.argv[2] if len(sys.argv) > 2 else "ollama-cloud"
        model = sys.argv[3] if len(sys.argv) > 3 else "deepseek-v4-flash"
        response_length = int(sys.argv[4]) if len(sys.argv) > 4 else 0
        record(provider, model, response_length)
        print(f"recorded:{provider}:{model}")

    elif cmd == "status":
        print(summary())

    elif cmd == "evaluate":
        result = evaluate_routing()
        active = result["active_provider"] or "none"
        depleted = ",".join(result["depleted"].keys()) or "none"
        print(f"active:{active}")
        print(f"depleted:{depleted}")
        for p, info in result["providers"].items():
            print(f"{p}:{info['pct_used']}%:{info['remaining']}:{info['depleted']}")

    elif cmd == "budget":
        if len(sys.argv) >= 4:
            set_budget(sys.argv[2], int(sys.argv[3]))
            print(f"budget:{sys.argv[2]}:{sys.argv[3]}")
        else:
            budgets = get_budgets()
            for p, b in budgets.items():
                print(f"{p}:{b}")

    elif cmd == "reset":
        provider = sys.argv[2] if len(sys.argv) > 2 else "ollama-cloud"
        reset_provider(provider)
        print(f"reset:{provider}")

    else:
        print(f"Unknown command: {cmd}")
        print("Usage: tool.py [record|status|evaluate|budget|reset]")


if __name__ == "__main__":
    main()
