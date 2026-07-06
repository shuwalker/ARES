# Email AI Assistant — Merge Checklist

## Branch: `feat/odysseus-email-ai-assistant` → `main`

### Files Changed (2 commits)

| Commit | Description |
|--------|-------------|
| `98d4544c` | `feat(email): initial AI assistant foundation on native Mail.app` |
| `4328b155` | `chore(email): manager cycle 1 - production hardening + docs` |

### Files to Merge

| File | Lines | Status | Notes |
|------|-------|--------|-------|
| `mail_assistant.py` | 377 | ✅ Tested | Core module — AppleScript + LLM draft_reply |
| `mail_assistant_production.py` | 64 | ⚠️ Reference | Production wrapper, not used yet |
| `email_server.py` | 2535 | ⚠️ Reference | Odysseus MCP server (absorbed, not production) |
| `email_thread_parser.py` | 614 | ⚠️ Reference | Thread parser (absorbed, not production) |
| `email_thread_parser_original.py` | 614 | ⚠️ Cleanup | Original Odysseus version, delete before merge |
| `tool.py` | 62 | ⚠️ Reference | MCP tool wrapper, not production |
| `__init__.py` | 14 | ✅ | Package init |
| `README.md` | 44 | ✅ | Documentation |

### Verification Tests (all passed)

- [x] **email-8**: `list_unread(limit=10)` — returned 10 real messages from unified inbox
- [x] **email-8**: `read_message('118313')` — fetched full xAI welcome email (subject, sender, body, HTML)
- [x] **email-8**: `mark_read('100872')` — marked PayPal promo as read
- [x] **email-8**: `move_to_junk('100872')` — moved PayPal promo to Junk (account-aware routing)
- [x] **email-9**: `draft_reply('118313')` — LLM generated real reply via glm-5.1 (Ollama Cloud)
- [x] **email-9**: `draft_reply('102571')` — LLM generated concise reply for financial statement
- [x] **email-9**: API key resolution from `~/.hermes/.env` fallback works

### Pre-Merge Actions

- [ ] **Delete `email_thread_parser_original.py`** — dead code, absorbed into main parser
- [ ] **Strip `.pytest_cache/` and `__pycache__/`** — build artifacts, not source
- [ ] **Review `email_server.py` (2535 lines)** — decide: keep as reference, or remove before merge
- [ ] **Review `tool.py` and `mail_assistant_production.py`** — decide: keep or remove
- [ ] **Update `__init__.py` exports** — expose `MailAssistant`, `get_mail_assistant`
- [ ] **Add `.gitignore` for `__pycache__/` and `.pytest_cache/`**

### Merge Decision Points

| Item | Recommendation | Reason |
|------|---------------|--------|
| `mail_assistant.py` | **Merge** | Production-ready, tested on real inbox |
| `email_server.py` | **Don't merge** | 102KB Odysseus reference, absorbed patterns into mail_assistant |
| `email_thread_parser.py` | **Don't merge** | Absorbed into `parse_thread()` method |
| `email_thread_parser_original.py` | **Delete** | Dead copy |
| `mail_assistant_production.py` | **Don't merge** | Thin wrapper, not yet used |
| `tool.py` | **Don't merge** | MCP tool surface, not used in current ARES app |
| `README.md` | **Merge** | Updated docs |

### What Gets Merged

```
tools/email_ai_assistant/
├── __init__.py          # Package exports
├── mail_assistant.py    # Production module (377 lines)
└── README.md            # Documentation
```

### What Gets Removed Before Merge

- `email_server.py` (absorbed)
- `email_thread_parser.py` (absorbed)
- `email_thread_parser_original.py` (dead copy)
- `mail_assistant_production.py` (not yet used)
- `tool.py` (not yet used)
- `.pytest_cache/` (build artifact)
- `__pycache__/` (build artifact)