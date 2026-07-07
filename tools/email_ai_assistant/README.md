# Email AI Assistant

AI email management for ARES using the native macOS Mail.app as the single
source of truth — no IMAP credentials, no app passwords, everything runs
through AppleScript against your already-authenticated mail accounts.

Wired into the WebUI's Email panel via `webui/api/email_routes.py`
(`/api/email/*`).

## Capabilities

- List unread / all inbox messages
- Read full message content
- Classify messages (fast heuristic domain/subject matching, LLM fallback for
  anything uncertain)
- Draft replies via the configured LLM
- Auto-clean: move junk/newsletters to Junk, archive receipts/statements
- Optional export of archived messages to a configured local/NAS path

## Configuration

Nothing here is hardcoded to a specific person or machine. Configure via
environment variables, or `~/.ares/mail_config.json`:

| Setting | Env var | Purpose |
|---|---|---|
| Assistant name | `ARES_MAIL_ASSISTANT_NAME` | Used in LLM prompts ("email assistant for \<name\>") |
| Archive export path | `ARES_MAIL_NAS_PATH` | Where `auto_clean`/`save_to_nas` write archived `.eml` files. Unset = disabled. |
| Extra keep addresses | `ARES_MAIL_KEEP_ADDRESSES` | Comma-separated senders/domains that should never be classified as junk |
| Work domains | `ARES_MAIL_WORK_DOMAINS` | Comma-separated employer domain(s) filed under the "Work" archive category |

The LLM classifier/drafter uses whatever OpenAI-compatible endpoint is
configured via `OLLAMA_API_KEY` / `OLLAMA_CLOUD_URL` / `ARES_MAIL_MODEL`
(falls back to `~/.hermes/.env` for the API key).

See `ares_mail_config.py` for the full config resolution logic.

## Files

- `mail_assistant.py` — the `MailAssistant` class: AppleScript operations, classification, LLM drafting
- `ares_mail_config.py` — operator-specific configuration (name, paths, domain lists)
- `__init__.py` — package init
