"""ARES Mail Triage — Orchestrator.

Runs the full triage pipeline: fetch, classify, move, rescue, learn.
Returns a TriageResult.
"""

from __future__ import annotations

from .models import TriageResult, ClassificationLabel, EmailMessage, ClassifiedMessage
from . import rules, db, driver


def triage(dry_run: bool = False) -> TriageResult:
    """
    Run full mail triage pipeline.

    1. Fetch unread inbox messages
    2. Initialize / load learning DB
    3. Classify each message
    4. Move junk to junk folders (unless dry_run)
    5. Scan junk folders for rescues
    6. Move rescued messages to inbox (unless dry_run)
    7. Update DB
    8. Return TriageResult
    """
    # Init DB
    db.init_db()

    # Load learned patterns
    learned_keep = db.load_keep_addresses()
    learned_junk = db.load_junk_addresses()
    learned_domains = db.load_junk_domains(threshold=3)

    # Fetch
    inbox = driver.fetch_unread()

    # Discover junk folders
    junk_map = driver.discover_junk_mailboxes()

    # Classify
    priority, junk, keep = [], [], []
    for msg in inbox:
        label, rule = rules.classify(
            msg,
            learned_keep=learned_keep,
            learned_junk=learned_junk,
            learned_domains=learned_domains,
        )
        classified = ClassifiedMessage(message=msg, label=label, matched_rule=rule)
        if label == "PRIORITY":
            priority.append(classified)
        elif label == "JUNK":
            junk.append(classified)
        else:
            keep.append(classified)

    # Move junk
    moved_junk = []
    if junk and not dry_run:
        junk_msgs = [c.message for c in junk]
        moved = driver.move_to_junk(junk_msgs, junk_map)
        db.record_junked(moved)
        moved_junk = moved
    elif junk and dry_run:
        moved_junk = [c.message for c in junk]

    # Scan junk folders for rescues
    junk_folder_msgs = driver.scan_junk_folders(junk_map, limit=rules.JUNK_SCAN_LIMIT)
    rescue_candidates = [m for m in junk_folder_msgs if rules.should_rescue(m)]

    rescued = []
    if rescue_candidates and not dry_run:
        rescued = driver.move_to_inbox(rescue_candidates)
        db.record_rescued(rescued)
    elif dry_run:
        rescued = rescue_candidates

    # Build summary
    lines = []
    if priority:
        lines.append(f"📬  PRIORITY ({len(priority)}) — needs reply")
        for c in priority:
            lines.append(f"   {c.message.sender[:48]}")
            lines.append(f"   {c.message.subject[:58]}")
    if moved_junk:
        lines.append(f"🗑   JUNKED ({len(moved_junk)})")
        for m in moved_junk[:15]:
            lines.append(f"   {m.sender[:36]:<36}  {m.subject[:36]}")
        if len(moved_junk) > 15:
            lines.append(f"   ... and {len(moved_junk) - 15} more")
    if rescued:
        lines.append(f"✅  RESCUED FROM JUNK ({len(rescued)})")
        for m in rescued[:15]:
            lines.append(f"   {m.sender[:36]:<36}  {m.subject[:36]}")
    if keep:
        lines.append(f"📎  KEEP ({len(keep)}) — transactional")

    summary = "\n".join(lines) if lines else "Inbox is clean."

    return TriageResult(
        dry_run=dry_run,
        priority=priority,
        junk=junk,
        keep=keep,
        moved_junk=moved_junk,
        rescued=rescued,
        summary=summary,
    )
