# ARES Full Integration Plan

> **For Hermes:** Execute this plan task-by-task. Each task is bite-sized (2-5 min). Power through sequentially.

**Goal:** Port all portable code from reference repos into ARES, building a complete Synthetic Person interface with VS Code-like workspace, app integration, and all Paperclip/Hermes WebUI features.

**Architecture:** ARES is a flat registry of agnostic backends (Paperclip pattern) with a React frontend. Each feature is a page + API endpoint. No company/org scoping — one user, one SI.

**Tech Stack:** React + Vite + TypeScript (frontend), FastAPI + Python (backend), shadcn/ui + lucide-react (UI), Monaco + xterm.js (workspace)

---

## Repo Inventory & What to Port

### Paperclip (reference_sources/paperclip/) — 1701 ts files
**Already ported:** adapter registry, 14 adapters, Inbox, Issues, Routines, Skills, Secrets
**Still to port:**
- AgentDetail (agent config form)
- BoardChat (multi-agent chat)
- Activity feed
- Search
- Cost tracking

### Hermes WebUI (reference_sources/hermes-web/) — 1104 ts files
**Already ported:** nothing
**To port:**
- Model picker (model/provider switching UI)
- Cron page (scheduling)
- Skills editor (skill management)
- Credentials/env page
- Channels page (messaging integrations)
- Plugin system (30-slot plugin registry)
- System health page
- i18n system

### Hermes Desktop (reference_sources/hermes-desktop/) — Swift
**To port (patterns only):**
- Subagent tree viewer
- Right-rail file access
- Session management patterns

### colibri (reference_sources/colibri/) — C MoE inference engine
**To reference:**
- GLM-5.2 744B model inference on consumer hardware
- Expert disk streaming pattern
- OpenAI-compatible server interface

### gbrain (GitHub/gbrain/) — 1969 ts files
**To reference (Phase 3):**
- Temporal knowledge graph for Context Store
- Entity extraction from conversations
- Synthesis and gap analysis patterns

### SAM (GitHub/SAM/) — 201 ts + 440 Swift
**To reference (Phase 4):**
- Voice pipeline architecture
- Multi-provider API framework
- AgentOrchestrator for multi-step workflows
- MCP framework with 8 tools/60+ operations

### Agent Governance Toolkit (GitHub/agent-governance-toolkit/) — 2319 files
**To reference:**
- Approval/policy engine patterns
- Human-in-the-loop patterns

### Open-LLM-VTuber (GitHub/Open-LLM-VTuber/) — 125 py
**To reference (Phase 4):**
- Voice + avatar config pipeline
- Live2D character system
- Real-time audio streaming

### Open WebUI (GitHub/open-webui/) — 668 files
**To reference:**
- Model management UI patterns
- Document/RAG upload
- Multi-model conversation handling

### Hermes Workspace (GitHub/hermes-workspace/) — 815 ts files
**To reference:**
- Swarm.yaml worker pattern
- Gateway + dashboard architecture
- Electron desktop wrapper

---

## Phase 1: Workspace (VS Code-like) — Tonight

### Task 1: Add Monaco editor to WorkspacePage
**Objective:** Replace 41-line stub with a split-pane file tree + code editor

**Files:**
- Modify: `webui/frontend/src/pages/WorkspacePage.tsx`
- Create: `webui/frontend/src/components/FileTree.tsx`
- Create: `webui/frontend/src/components/CodeEditor.tsx`

**Step 1:** Install Monaco editor
```bash
cd webui/frontend && npm install @monaco-editor/react
```

**Step 2:** Create FileTree component
- Left sidebar showing project files
- Fetches from `/api/list?session_id=...&path=.`
- Click to open file in editor
- Folders expand/collapse

**Step 3:** Create CodeEditor component
- Monaco editor with syntax highlighting
- Reads/writes files via `/api/file/read` and `/api/file/write`
- Dark theme matching ARES

**Step 4:** Wire WorkspacePage
- Split pane: left = FileTree, right = CodeEditor
- Resizable divider
- Current file state

### Task 2: Add xterm.js to TerminalPage
**Objective:** Replace 67-line stub with a real terminal

**Files:**
- Modify: `webui/frontend/src/pages/TerminalPage.tsx`

**Step 1:** Install xterm.js
```bash
cd webui/frontend && npm install xterm @xterm/xterm
```

**Step 2:** Wire WebSocket terminal
- Connect to `/api/terminal/start` then WebSocket
- xterm.js renders output
- Input goes back through WebSocket
- Dark theme

### Task 3: Build CanvasPage
**Objective:** Replace 97-line stub with a visual canvas

**Files:**
- Modify: `webui/frontend/src/pages/CanvasPage.tsx`

**Step 1:** Add a simple canvas
- HTML5 Canvas or react-konva
- Draw shapes, text, connections
- Save/load canvas state via API

---

## Phase 2: Paperclip Pages — Tonight

### Task 4: Port AgentDetail (agent config form)
**Objective:** Create agent configuration page

**Files:**
- Create: `webui/frontend/src/pages/AgentDetailPage.tsx`
- Add route in `App.tsx`

**Step 1:** Read Paperclip's AgentDetail.tsx for reference
**Step 2:** Build form with: name, adapter type, model, provider, toolsets
**Step 3:** Wire to backend adapter registry

### Task 5: Port BoardChat (multi-agent chat)
**Objective:** Multi-agent conversation view

**Files:**
- Create: `webui/frontend/src/pages/BoardChatPage.tsx`
- Add route in `App.tsx`

**Step 1:** Read Paperclip's BoardChat.tsx for reference
**Step 2:** Build chat view showing messages from multiple agents
**Step 3:** Wire to backend streaming

### Task 6: Port Activity feed
**Objective:** Replace 12-line stub with activity timeline

**Files:**
- Modify: `webui/frontend/src/pages/ActivityPage.tsx`

**Step 1:** Read Paperclip's ActivityFeed.tsx for reference
**Step 2:** Build timeline of events (chat, tasks, routines, approvals)
**Step 3:** Wire to backend activity API

---

## Phase 3: Hermes WebUI Pages — Tonight

### Task 7: Port Model picker
**Objective:** Model/provider switching UI

**Files:**
- Create: `webui/frontend/src/components/ModelPicker.tsx`
- Integrate into ConversationPage

**Step 1:** Read Hermes WebUI's model picker for reference
**Step 2:** Build dropdown showing available models from each adapter
**Step 3:** Wire to backend model catalog API

### Task 8: Port Cron page
**Objective:** Scheduled task management

**Files:**
- Create: `webui/frontend/src/pages/CronPage.tsx`
- Add route in `App.tsx`

**Step 1:** Read Hermes WebUI's CronPage for reference
**Step 2:** Build cron job list with create/edit/delete
**Step 3:** Wire to backend cron API

### Task 9: Port Credentials/Env page
**Objective:** API key and environment variable management

**Files:**
- Create: `webui/frontend/src/pages/CredentialsPage.tsx`
- Add route in `App.tsx`

**Step 1:** Read Hermes WebUI's EnvPage for reference
**Step 2:** Build credential list with add/edit/delete
**Step 3:** Wire to backend secrets API

### Task 10: Port Channels page
**Objective:** Messaging integration management

**Files:**
- Create: `webui/frontend/src/pages/ChannelsPage.tsx`
- Add route in `App.tsx`

**Step 1:** Read Hermes WebUI's ChannelsPage for reference
**Step 2:** Build channel list with connect/disconnect
**Step 3:** Wire to backend channels API

### Task 11: Port System health page
**Objective:** System status dashboard

**Files:**
- Create: `webui/frontend/src/pages/SystemHealthPage.tsx`
- Add route in `App.tsx`

**Step 1:** Read Hermes WebUI's SystemHealth for reference
**Step 2:** Build health dashboard with adapter status, model status, resource usage
**Step 3:** Wire to backend health API

---

## Phase 4: MCP & App Integration — Weekend

### Task 12: Port MCP config UI
**Objective:** MCP server configuration

**Files:**
- Create: `webui/frontend/src/pages/McpConfigPage.tsx`
- Add route in `App.tsx`

**Step 1:** Read Hermes WebUI's MCP page for reference
**Step 2:** Build MCP server list with add/remove
**Step 3:** Wire to backend MCP config API

### Task 13: Wire computer_use into chat
**Objective:** ARES can drive apps on your Mac

**Files:**
- Modify: `webui/api/backends/hermes.py`
- Modify: `webui/frontend/src/pages/ConversationPage.tsx`

**Step 1:** Ensure Hermes adapter passes computer_use capability
**Step 2:** Show computer_use status in chat UI
**Step 3:** Test: "ARES, open Safari and search for X"

---

## Phase 5: Polish & Ship — Weekend

### Task 14: Fill remaining stubs
**Files:**
- `TodayPage.tsx` (32 lines) → dashboard with recent activity
- `SharePage.tsx` (76 lines) → share session view
- `UsageCostPage.tsx` (273 lines) → already decent, verify

### Task 15: Mobile/iPad responsive
**Objective:** All pages work on iPad

**Files:**
- All page components

**Step 1:** Test each page at iPad width
**Step 2:** Fix sidebar collapse, font sizes, touch targets

### Task 16: Final verification
**Objective:** Full end-to-end test

**Step 1:** Test chat end-to-end
**Step 2:** Test all pages load
**Step 3:** Test adapter connections
**Step 4:** Test file tree + editor
**Step 5:** Test terminal
**Step 6:** Test MCP config

---

## Execution Order

```
Phase 1 (Workspace) → Phase 2 (Paperclip) → Phase 3 (Hermes WebUI) → Phase 4 (MCP) → Phase 5 (Polish)
```

Each phase is independent. If one breaks, skip it and move to the next.

## Verification

After each task:
```bash
# Restart server
launchctl kickstart -k gui/$(id -u)/com.ares.webui
sleep 6

# Quick health check
curl -s http://127.0.0.1:8787/health | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])"

# Test the changed page loads
curl -s http://127.0.0.1:8787/ | head -5
```

## Risks & Tradeoffs

- **Monaco editor** is a large dependency (~5MB). Alternative: CodeMirror (lighter, ~500KB)
- **xterm.js** is standard, no alternative needed
- **Paperclip pages** have heavy company scoping — stripping it is manual but mechanical
- **Hermes WebUI pages** are per-instance, need re-architecting per-agent
- **Computer use** requires cua-driver on the Mac — already installed via Hermes
