# Audit Report: `agent-viewer` (hallucinogen/agent-viewer)

## Repo Info
- **Language/Framework**: Vanilla JavaScript (ES6), Express, no build step
- **Architecture**: Two-file app: `server.js` + `public/index.html`. Manages Claude Code agents in tmux sessions with SSE event streaming.
- **Local Path**: `/Users/matthewjenkins/Documents/GitHub/agent-viewer`

---

## Key UI Patterns (SwiftUI Adaptable)

### 1. Kanban Board for Agents
**Patterns:**
- **Three-column layout**: `Queue` (idle agents), `In Progress` (active), `Done` (completed).
- **Drag-and-drop**: Cards can be dragged between columns; triggers API calls to update server state.
- **Card metadata**: Agent name, current task, status badge, last activity time.
- **Auto-refresh**: Polling every 3 seconds via `GET /api/events`.

### 2. SSE Event Streaming
**Patterns:**
- **Server-Sent Events**: `EventSource` / `GET /api/events` streams real-time agent state changes.
- **Reconnection**: Automatic reconnect with backoff on connection loss.
- **Client-side buffering**: Events queue if UI is mid-render, then batch-apply.

**SwiftUI mapping:**
- `URLSession` with `dataTask` using `text/event-stream`
- `Timer` fallback for polling if SSE unavailable
- `@Published var agents` batch-updated on receive

### 3. tmux Pane Capture
**Patterns:**
- **Real-time read-only terminal**: `tmux capture-pane -e -p` output displayed in a scrollable window.
- **ANSI color rendering**: Preserves terminal colors in HTML output.

**SwiftUI mapping:**
- `NSTextView` or `Text` with `AttributedString` for ANSI colors (or SwiftTerm library)

---

## Files Worth Bookmarking
| File | Purpose |
|------|---------|
| `server.js` | Express API, tmux integration, SSE endpoint |
| `public/index.html` | Vanilla JS kanban board, event source client |
| `CLAUDE.md` | Architecture documentation |

---

## Unique Adaptations for SwiftUI
- The two-file simplicity makes this a good reference for **minimal viable dashboards**.
- For ARES-Face: a single-page SwiftUI `List` with drag-and-drop + `async/await` polling can replicate this behavior.
