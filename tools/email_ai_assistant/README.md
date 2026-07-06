# Email AI Assistant — Tool README

Production-grade AI email management for ARES using native Mail.app as the single source of truth.

## Status

- **Branch**: `feat/odysseus-email-ai-assistant`
- **Core**: `mail_assistant.py` + `mail_assistant_production.py`
- **Tools exposed**: `list_unread_emails`, `read_email`, `draft_reply`
- **Connection**: 100% native Mail.app (AppleScript) — no custom IMAP, no app passwords
- **Philosophy**: Inbox = TO-DO list. Aggressive junk/newsletter removal. Archive receipts.

## Files

- `mail_assistant.py` — Core class with AppleScript-backed operations
- `mail_assistant_production.py` — Hardened wrapper with logging + safety
- `tool.py` — Hermes tool wrappers for agent use
- `email_thread_parser.py` (original) — Reference implementation (being integrated by swarm)

## Current Capabilities (as of Cycle 1)

- List unread messages (fast, safe batching)
- Read full message content
- Draft replies (stub → real LLM in next cycle)
- Mark read / move to junk (account-aware)

## Safety

- All destructive actions are logged
- Default limits are conservative
- Never auto-sends without explicit confirmation (enforced in production wrapper)

## Next Cycles (autonomous)

Subagents are currently working on:
1. Full thread parser integration
2. Real LLM-powered drafting
3. Hermes skill registration

Manager will review, approve, and iterate until the feature is merge-ready.

## License Note

This feature absorbs logic from Odysseus (AGPL-3.0-or-later). ARES license will be updated to AGPL-3.0-or-later upon merge.
