#!/usr/bin/env python3
"""
ARES Journal — Universal conversation importer.

Indexes all AI conversations on this machine into a unified, searchable database
at ~/.ares/journal/journal.db.

Usage:
    python -m api.journal.import_all              # Import everything
    python -m api.journal.import_all --source hermes  # Import only Hermes
    python -m api.journal.import_all --source grok    # Import only Grok
    python -m api.journal.import_all --stats          # Show current stats
    python -m api.journal.import_all --search "boot bug"  # Search all conversations
"""

import argparse
import json
import sys
import time
import uuid
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from api.journal.schema import init_db, stats, search, list_conversations, get_db


def import_all(sources: list[str] | None = None) -> dict:
    """Import conversations from all available sources."""
    batch_id = str(uuid.uuid4())
    results = {}

    all_sources = {
        "hermes": ("api.journal.import_hermes", "import_hermes"),
        "claude_code": ("api.journal.import_claude_code", "import_claude_code"),
        "grok": ("api.journal.import_grok", "import_grok"),
        "codex": ("api.journal.import_codex", "import_codex"),
        "gemini": ("api.journal.import_gemini", "import_gemini"),
        "sam": ("api.journal.import_sam", "import_sam"),
    }

    target_sources = sources or list(all_sources.keys())

    for source_name in target_sources:
        if source_name not in all_sources:
            print(f"  ⚠ Unknown source: {source_name}")
            continue

        module_name, func_name = all_sources[source_name]
        try:
            module = __import__(module_name, fromlist=[func_name])
            func = getattr(module, func_name)
            result = func(batch_id=batch_id)
            results[source_name] = result

            if result.get("skipped"):
                print(f"  ⏭ {source_name}: {result.get('reason', 'skipped')}")
            else:
                conv = result.get("imported_conversations", 0)
                msg = result.get("imported_messages", 0)
                print(f"  ✅ {source_name}: {conv} conversations, {msg} messages")
        except Exception as e:
            results[source_name] = {"error": str(e), "skipped": True}
            print(f"  ❌ {source_name}: {e}")

    return results


def show_stats():
    """Show current journal statistics."""
    s = stats()
    print(f"\n📊 ARES Journal — {s['total_conversations']} conversations, {s['total_messages']} messages")
    print()
    for source, count in s.get("by_source", {}).items():
        print(f"  {source:15s}: {count} conversations")
    if not s.get("by_source"):
        print("  (empty — run import_all to populate)")
    print()


def show_search(query: str, source: str | None = None):
    """Search the journal for a query."""
    results = search(query, source=source)
    print(f"\n🔍 Search results for '{query}':")
    print()
    for r in results:
        print(f"  [{r['source']}] {r['title']}")
        print(f"    {r['snippet'][:200]}")
        print(f"    Updated: {time.strftime('%Y-%m-%d %H:%M', time.gmtime(r['updated_at'])) if r['updated_at'] else 'unknown'}")
        print()


def show_conversations(source: str | None = None, limit: int = 20):
    """List recent conversations."""
    convs = list_conversations(source=source, limit=limit)
    print(f"\n📚 Recent conversations ({'all' if not source else source}):")
    print()
    for c in convs:
        ts = time.strftime('%Y-%m-%d %H:%M', time.gmtime(c['updated_at'])) if c.get('updated_at') else 'unknown'
        print(f"  [{c['source']:12s}] {c['title'][:60]}")
        print(f"    {c['message_count']} messages, updated {ts}")
        print()


def main():
    parser = argparse.ArgumentParser(description="ARES Journal — Universal conversation importer")
    parser.add_argument("--source", "-s", action="append", help="Import only this source (repeatable)")
    parser.add_argument("--stats", action="store_true", help="Show current statistics")
    parser.add_argument("--search", "-q", help="Search all conversations")
    parser.add_argument("--list", "-l", action="store_true", help="List recent conversations")
    parser.add_argument("--limit", type=int, default=20, help="Limit for list results")

    args = parser.parse_args()

    # Initialize DB
    init_db()

    if args.stats:
        show_stats()
        return

    if args.search:
        show_search(args.search, source=args.source[0] if args.source else None)
        return

    if args.list:
        show_conversations(source=args.source[0] if args.source else None, limit=args.limit)
        return

    # Import
    print("🚀 ARES Journal — Importing all conversation sources...")
    print()
    results = import_all(sources=args.source)
    print()
    show_stats()


if __name__ == "__main__":
    main()