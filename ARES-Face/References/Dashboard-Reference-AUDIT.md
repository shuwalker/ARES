# Dashboard Reference Audit Report

A comparative audit of 4 agent dashboard UIs found in our GitHub repos, plus the built-in Hermes TUI. Focus: patterns worth adapting to ARES-Face SwiftUI.

## Repos Audited

| Repo | Lines | Stack | Key Feature |
|---|---|---|---|
| Claude-Code-Agent-Monitor | ~17.8K | React+TS, WebSocket, SQLite | Multi-agent monitoring with workflow visualization |
| Hermes Web UI | ~10K | Vue 3+TS, Naive UI, Pinia, Koa BFF | Full Hermes dashboard: chat, sessions, jobs, terminal |
| Agent-Viewer | ~1.1K | Node.js, vanilla HTML/JS | Minimal kanban for Claude Code agents in tmux |
| OS1 | ~1.9K | Next.js, Rust server | Open Interpreter's computer-use agent UI |
| Hermes TUI (built-in) | N/A | Ink (React CLI) | Terminal UI with slash commands, streaming |

---

## 1. Claude-Code-Agent-Monitor

**URL**: https://github.com/hoangson091104/claude-code-agent-monitor

### Architecture
- **Backend**: Node.js + SQLite + WebSocket for real-time event streaming
- **Frontend**: React 18 + TypeScript + Vite + TailwindCSS + Radix UI
- **Pages**: Dashboard, KanbanBoard, Sessions, SessionDetail, ActivityFeed, Analytics, Workflows, Run, Settings, CcConfig

### Key UI Patterns Worth Adapting

#### A. Agent Cards with Live Status
`AgentCard.tsx` shows real-time agent state with:
- Status badge (running/idle/completed/error)
- Token usage bar (input vs output)
- Tool call count
- Duration timer
- Expandable event list

**→ ARES-Face Port**: Our `OrchestrationView` already has this pattern. Add token usage visualization and duration timer.

#### B. Workflow Visualizations (THE BIGGEST VALUE)
The `workflows/` directory has 5 specialized views:
1. **ToolExecutionFlow.tsx** — DAG visualization of tool calls with timing
2. **AgentCollaborationNetwork.tsx** — Network graph showing subagent delegation
3. **ConcurrencyTimeline.tsx** — Gantt chart of parallel tool executions
4. **SubagentEffectiveness.tsx** — Bar charts comparing subagent performance
5. **SessionDrillIn.tsx** — Hierarchical session exploration

**→ ARES-Face Port**: This is THE pattern we need for `OrchestrationView`. A Swift `TimelineView` or custom canvas that shows concurrent tool calls as a Gantt chart. The `ConcurrencyTimeline` pattern maps directly to our `ThoughtNode` tree.

#### C. Event Filtering and Grouping
`EventGroupRow.tsx` groups related events (tool call → tool result) into collapsible rows. Filter bars let you narrow by type, agent, session.

**→ ARES-Face Port**: Group tool calls by parent task in our orchestration view. Add filter chips for "show only terminal calls", "show only file operations".

#### D. Session Detail with Full History
`SessionDetail.tsx` shows complete message history, tool calls, and metadata for a single session.

**→ ARES-Face Port**: Our `MemoryInspectorView` has session search. Add drill-in capability to see full message history for a session.

---

## 2. Hermes Web UI

**URL**: https://github.com/EKKOLearnAI/hermes-web-ui

### Architecture
- **Frontend**: Vue 3 + TypeScript + Naive UI + Pinia + vue-router + vue-i18n
- **Backend**: Koa 2 + TypeScript BFF (Business For Frontend)
- **State**: Pinia stores (app, chat, jobs, models, settings, usage, gateways, profiles)
- **i18n**: 8 languages supported

### Key UI Patterns Worth Adapting

#### A. ChatPanel with Streaming
`ChatPanel.vue` — Full chat interface with:
- SSE streaming for real-time responses
- File upload support
- Session switching drawer
- Model selector in chat input bar
- Folder picker for file context

**→ ARES-Face Port**: Our `ChatStream` + `CommandBar` already implement this. Add model selector dropdown and file attachment to CommandBar.

#### B. MessageItem with Rich Rendering
`MessageItem.vue` — Per-message rendering with:
- Markdown rendering (code blocks, tables, links)
- Tool call expandable sections
- Copy buttons on code blocks
- Timestamp display
- User/assistant visual distinction

**→ ARES-Face Port**: Our `ChatStream` message bubbles need markdown rendering. Add `MarkdownUI` or `AttributedString` rendering for code blocks.

#### C. Jobs Panel with CRUD
`JobCard.vue` + `JobFormModal.vue` — Cron job management with:
- Inline editing
- Run now button
- Status indicators (enabled/disabled, last run status)
- Schedule humanization

**→ ARES-Face Port**: Our `CronView` already exists. Add inline editing and "run now" buttons.

#### D. Terminal Panel
`TerminalPanel.vue` — In-browser terminal via xterm.js + WebSocket PTY.

**→ ARES-Face Port**: The `TaskRunnerView` terminal input is a good start. For full terminal, we'd need a PTY WebSocket bridge — low priority.

#### E. Drawer System
`DrawerPanel.vue` — Collapsible drawer for secondary content (files, search, settings).

**→ ARES-Face Port**: Add drawer panels to `OrchestrationView` for showing file context, tool output details, etc.

---

## 3. Agent-Viewer

**URL**: https://github.com/EKKOLearnAI/agent-viewer

### Architecture
- Single server.js + single index.html (no build step)
- Express backend, vanilla JS frontend
- SSE for real-time updates
- tmux integration for agent lifecycle

### Key Patterns Worth Adapting

#### A. Three-Column Kanban
Running / Idle / Completed — drag-and-drop cards representing agent instances.

**→ ARES-Face Port**: Our `OrchestrationView` should show tool calls in a similar kanban layout (Running / Done / Failed).

#### B. Auto-Discovery
Scans tmux sessions to find running Claude Code agents and adds them to the registry.

**→ ARES-Face Port**: Scan running Hermes processes and MCP servers to populate the orchestration view.

#### C. State Detection via Output Parsing
Classifies agent state by pattern-matching terminal output ("esc to interrupt" = running).

**→ ARES-Face Port**: Our cognitive state is already streamed via WebSocket. No need for output parsing.

---

## 4. OS1 (Open Interpreter)

**URL**: https://github.com/OpenInterpreter/OS1

### Architecture
- Next.js frontend + Rust server backend
- Computer-use agent: sees screen, clicks, types
- Real-time screen streaming via WebRTC
- Canvas overlay for click/type annotations

### Key Patterns Worth Adapting

#### A. Screen Streaming with Annotation Overlay
OS1 streams the agent's screen view and overlays click targets, type annotations, and selection highlights.

**→ ARES-Face Port**: For ARES-Face in Avatar Twin mode, we already stream the cognitive state. Consider adding a "screen awareness" mode where ARES can see and annotate the Mac desktop — this would require macOS accessibility/CGWindow API.

#### B. Real-Time Activity Indicator
OS1 shows a "thinking" / "clicking" / "typing" status bar with progress.

**→ ARES-Face Port**: Our `StreamOverlay` already does this. Add specific "clicking" and "typing" states for when ARES uses computer_use tool.

---

## 5. Hermes TUI (Built-in)

Located at `~/.hermes/hermes-agent/ui-tui/`. The Ink-based terminal UI with slash commands.

### Key Patterns Worth Adapting

#### A. Slash Command System
The TUI has `/model`, `/session`, `/clear`, `/compact`, etc. This maps to our `TaskRunnerView` quick actions.

**→ ARES-Face Port**: Add slash command parsing to `CommandBar`. When user types `/`, show autocomplete for common actions.

---

## Priority Adaptation Map

| Pattern | Source | ARES-Face Component | Priority |
|---|---|---|---|
| Tool execution DAG/timeline | CC-Agent-Monitor | OrchestrationView | 🔴 HIGH |
| Token usage bar | CC-Agent-Monitor | OrchestrationView | 🟡 MEDIUM |
| Model selector in chat input | Hermes Web UI | CommandBar | 🟡 MEDIUM |
| Markdown rendering in messages | Hermes Web UI | ChatStream | 🔴 HIGH |
| Drawer panels for context | Hermes Web UI | OrchestrationView | 🟡 MEDIUM |
| Kanban tool call layout | Agent-Viewer | OrchestrationView | 🟢 LOW |
| Slash command parsing | Hermes TUI | CommandBar | 🟡 MEDIUM |
| File upload/attachment | Hermes Web UI | CommandBar | 🟢 LOW |
| Session detail drill-in | CC-Agent-Monitor | MemoryInspectorView | 🟡 MEDIUM |
| Screen awareness overlay | OS1 | New: ScreenVisionView | 🟢 FUTURE |

---

## Recommended Next Steps for ARES-Face

### Immediate (these sessions)
1. **Markdown rendering in ChatStream** — Messages should render code blocks, tables, links, bold/italic
2. **Token usage counter** in OrchestrationView — show input/output tokens consumed per turn
3. **Tool call Gantt chart** in OrchestrationView — show concurrent tool calls on a timeline

### Near-term
4. **Model selector dropdown** in CommandBar — switch between configured models
5. **Slash commands** in CommandBar — `/model`, `/compact`, `/clear`, `/run`
6. **Drawer panels** — collapsible context panels in OrchestrationView

### Future
7. **Computer use awareness** — when ARES uses computer_use, show screen annotations
8. **Agent network graph** — visualization of subagent delegation chains
9. **Proactive notifications** — badge count and system notifications for completed tasks
