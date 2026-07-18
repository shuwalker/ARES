# ARES Integration Log

What was ported from each reference repo and where it lives in ARES.

## Paperclip (reference_sources/paperclip/)

| Feature | ARES Location | Status |
|---------|--------------|--------|
| Adapter registry (flat map, agnostic naming) | `api/backends/router.py` | ✅ Done |
| 14 adapters (hermes_local, jros_local, claude_local, codex_local, gemini_local, grok_local, opencode_local, cursor_local, pi_local, openai_cloud, xai_cloud, ollama_local, ares_local, hybrid) | `api/backends/cli_backends.py`, `api/backends/hermes.py`, `api/backends/jros.py` | ✅ Done |
| Approval queue / Inbox | `frontend/src/pages/InboxPage.tsx` | ✅ Done |
| Issues / kanban | `frontend/src/pages/IssuesPage.tsx` | ✅ Done |
| Routines | `frontend/src/pages/RoutinesPage.tsx` | ✅ Done |
| SkillStudio | `frontend/src/pages/SkillStudioPage.tsx` | ✅ Done |
| Secrets | `frontend/src/pages/SecretsPage.tsx` | ✅ Done |
| Agent config form | Not yet ported | ⏳ |
| BoardChat (multi-agent chat) | Not yet ported | ⏳ |
| Activity feed | `frontend/src/pages/ActivityPage.tsx` (stub) | ⏳ |

## Hermes WebUI (reference_sources/hermes-web/)

| Feature | ARES Location | Status |
|---------|--------------|--------|
| Model picker | Not yet ported | ⏳ |
| Cron | Not yet ported | ⏳ |
| Skills editor | Not yet ported | ⏳ |
| Credentials / env | Not yet ported | ⏳ |
| Channels | Not yet ported | ⏳ |
| Plugin system | Not yet ported | ⏳ |
| i18n | Not yet ported | ⏳ |

## Hermes Desktop (reference_sources/hermes-desktop/)

| Feature | ARES Location | Status |
|---------|--------------|--------|
| Native macOS app | `ARES-Desktop/Sources/` (pre-existing) | ✅ Pre-existing |
| Subagent tree | Not yet ported | ⏳ |

## gbrain

| Feature | ARES Location | Status |
|---------|--------------|--------|
| Temporal knowledge graph pattern | Reference only | 📋 Planned |

## SAM

| Feature | ARES Location | Status |
|---------|--------------|--------|
| Voice pipeline architecture | Reference only | 📋 Planned |
| Multi-provider API framework | Reference only | 📋 Planned |

## Agent Governance Toolkit

| Feature | ARES Location | Status |
|---------|--------------|--------|
| Approval/policy engine patterns | Reference only | 📋 Planned |

## Open-LLM-VTuber

| Feature | ARES Location | Status |
|---------|--------------|--------|
| Voice + avatar config pipeline | Reference only | 📋 Planned |

## Open WebUI

| Feature | ARES Location | Status |
|---------|--------------|--------|
| Model management UI patterns | Reference only | 📋 Planned |

## Hermes Workspace

| Feature | ARES Location | Status |
|---------|--------------|--------|
| Swarm.yaml worker pattern | Reference only | 📋 Planned |
