# ARES Mac App — Four-Tab Model

## Tabs

| Tab | Purpose | Implementation status |
|---|---|---|
| **Companion** | ARES's desk. One chat surface, one voice, no model picker. Streams real responses from the Hermes gateway. | Chat UI + history wired; companion config loaded from `~/.hermes`; session persistence via Hermes API |
| **Hub** | User's desk for other AI tools. Auto-discovers installed tools, renders as cards with launch buttons. No re-skin, no impersonation. | Tool discovery (filesystem + Process), GitHub repo discovery, Bonjour device discovery. Cards show status. |
| **Office** | ARES's animated virtual office. Top-down 2D view of 4-5 sub-agents with three visible states (idle/working/waiting). | Agent card grid with live status. Not yet wired to real Kanban — uses `ARESAppState.officeAgents` placeholder. |
| **Settings** | Configuration that's actually needed. Integrations, Quick Launch, Runtime Status, Diagnostics. | Full four-section UI. Integrations toggle list, Quick Launch with NSWorkspace open, Runtime Status shows gateway/state, Diagnostics runs live health check. |

## What's real vs scaffolded

**Real (functional):**
- ARESCore library compiles and links as a separate Swift package target
- ToolDiscovery scans filesystem for AI tools and classifies them
- IntegrationRegistry provides hand-curated tool catalog with binary/data probes
- GitHubDiscovery scans `~/GitHub/` for local clones and enriches via `gh api`
- BonjourBrowser discovers SSH-advertising Macs on the local network (macOS only)
- Hub auto-discovery cards render with real data
- Companion chat connects to Hermes gateway HTTP endpoint
- Session readers (Claude, Gemini, Hermes, Odysseus) parse real session files
- Settings Diagnostics runs live health checks against Ollama, Hermes gateway, config files, IntegrationRegistry

**Scaffolded (UI present, data not yet real):**
- Office agent states come from `ARESAppState.officeAgents` mock data, not the live Hermes Kanban board
- Companion model routing (ARES picks the model) — currently uses configured Hermes endpoint only

## Build & run

```bash
cd ~/GitHub/ARES
swift build
swift run ARES
```

## Intentionally out of scope for 0.0 alpha

- ARES writing into another tool's data store (v1 is read-only regarding peer tools)
- ARES proxying the user into another tool's UI
- Multi-user / shared Companion sessions
- iPad/iPhone Companion apps (ARESCore compiles for iOS but the app target is macOS only)
- Voice synthesis / avatar rendering pipeline
- n8n workflow integration