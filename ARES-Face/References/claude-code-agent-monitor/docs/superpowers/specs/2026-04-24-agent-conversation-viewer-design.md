# Agent Conversation Viewer Design

## Overview

Add a conversation viewer to the SessionDetail page, enabling visual inspection of Main Agent and sub-agent interactions (message content and tool call details), with data sourced from real-time JSONL transcript files.

## Problem

The current dashboard tracks agent sessions, events, and tool usage at a summary level, but does not expose the actual conversation content — user messages, assistant replies, tool call parameters, and tool results. Users cannot see what each agent actually did or said, limiting debugging and audit capabilities.

### v2 Additional Problems: Poor Pagination UX + No Real-time Updates

After v1 implementation, two core UX issues emerged:

1. **Pagination doesn't match conversation intuition** — v1 uses offset-based pagination starting from the beginning, so users see the oldest messages first and must page through to reach recent interactions, which doesn't align with chat product conventions.
2. **No real-time updates** — v1 doesn't subscribe to WebSocket events, so users must manually refresh to see new messages, making it impossible to follow active sessions in real time.
3. **Sub-agent selection uses database IDs** — v1's `agent_id` parameter relies on database agent IDs, but JSONL files are named with short IDs (e.g. `ad18a79192af10ed1`), causing a mismatch that prevents sub-agent transcripts from loading.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Data source | Real-time JSONL reads | Data is always current, no extra storage needed |
| UI location | Conversation tab within SessionDetail | User-requested; keeps agent tree in the same context |
| Claude home path | Configurable via `CLAUDE_HOME` env var | Supports non-default paths like `~/.codefuse/engine/cc/` |
| Message rendering | Collapsible tool calls and thinking blocks | Keeps the view scannable; expand for details |
| Load strategy (v2) | Chat-flow: load latest N by default, scroll up for history | Matches chat product intuition; users care most about recent interactions |
| Real-time updates (v2) | WebSocket `new_event` triggers incremental load | Active sessions don't need manual refresh |
| Agent selection (v2) | Filesystem scan + dropdown | Bypasses database ID mismatch by using file short IDs directly |

## Architecture

### Data Flow

**v1 (deprecated):**
```
User clicks "Conversation" tab
  → Frontend calls GET /api/sessions/:id/transcript[?agent_id=xxx&limit=50&offset=0]
  → Server resolves JSONL path via claude-home.js
  → Server reads and parses JSONL file
  → Server returns structured message list
  → Frontend renders MessageList (with collapsible blocks)
```

**v2 Chat-flow (current implementation):**
```
Initial load:
  User opens Conversation tab
  → GET /api/sessions/:id/transcripts  ← fetch available transcript list
  → GET /api/sessions/:id/transcript?limit=50  ← default returns latest 50 messages
  → Frontend renders message list + auto-scrolls to bottom

Real-time updates:
  CLI Hook → POST /api/hooks/event → processEvent()
    → broadcast("new_event", {session_id, ...})
      → WebSocket → ConversationView
        → GET /api/sessions/:id/transcript?after=N  ← incremental load
          → Append to bottom + auto-scroll (if user is at bottom)

History load:
  User scrolls to top
    → GET /api/sessions/:id/transcript?before=M&limit=50  ← load older messages
      → Prepend to top + preserve scroll position (no jump)
```

### Configurable Claude Home Directory

New module `server/lib/claude-home.js` centralizes all Claude directory path logic:

```
CLAUDE_HOME env var (default: ~/.claude)
  ├── projects/<encoded-cwd>/<session-id>.jsonl           ← main session transcript
  │   (encoding rule: all non-alphanumeric chars → "-", e.g. "/Users/txj/.codefuse" → "-Users-txj--codefuse")
  ├── projects/<encoded-cwd>/<session-id>/subagents/agent-<id>.jsonl  ← sub-agent transcript
  │   (sub-agent ID format: ad18a79192af10ed1, acompact-f8427be966459435)
  └── settings.json                                        ← hooks configuration
```

Existing hardcoded paths in `import-history.js`, `install-hooks.js`, and `settings.js` are migrated to use this module.

---

## API

### GET /api/sessions/:id/transcripts (v2 new)

List available transcript files for a session (main + sub-agents), scanned directly from the filesystem.

**Response (200):**

```json
{
  "transcripts": [
    { "id": "main", "name": "Main Agent", "type": "main", "has_transcript": true },
    { "id": "ad18a79192af10ed1", "name": "code-reviewer", "type": "subagent", "subagent_type": "code-reviewer", "has_transcript": true },
    { "id": "acompact-f8427be966459435", "name": "Context Compaction", "type": "compaction", "has_transcript": true }
  ]
}
```

**Design notes:**

- Bypasses database agent IDs; scans the filesystem directly for JSONL file short IDs
- `id` field maps directly to the filename: `agent-<id>.jsonl`, used as the `agent_id` parameter for the `transcript` API
- Compaction file name format: `agent-acompact-<hex>.jsonl`, id is `acompact-<hex>`
- Attempts to read `.meta.json` in the same directory for agent type description
- Falls back to scanning all `projects/` subdirectories when the exact encoded path doesn't exist

### GET /api/sessions/:id/transcript

Read a session's JSONL transcript file and return a structured message list.

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `agent_id` | string | null | Transcript short ID (from `transcripts` endpoint); omit for main session |
| `limit` | number | 50 | Max messages to return (max 200) |
| `after` | number | null | Incremental mode: only return messages with JSONL line > after (v2 new) |
| `before` | number | null | History mode: only return the latest N messages with JSONL line < before (v2 new) |
| `offset` | number | 0 | Legacy pagination offset (compatible, mutually exclusive with after/before) |

**Response (200):**

```json
{
  "messages": [
    {
      "type": "user",
      "timestamp": "2026-04-24T10:23:45Z",
      "content": [
        { "type": "text", "text": "Please implement the login feature" }
      ]
    },
    {
      "type": "assistant",
      "timestamp": "2026-04-24T10:23:52Z",
      "model": "claude-sonnet-4-6",
      "usage": { "input_tokens": 1500, "output_tokens": 800 },
      "content": [
        { "type": "text", "text": "I'll help you implement the login feature." },
        { "type": "thinking", "text": "Let me analyze the codebase..." },
        {
          "type": "tool_use",
          "name": "Read",
          "id": "toolu_abc123",
          "input": { "file_path": "/src/auth.ts" }
        }
      ]
    }
  ],
  "total": 120,
  "has_more": true,
  "last_line": 523,
  "first_line": 474
}
```

**v2 New Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `last_line` | number | JSONL line number of the last message in the current response; used as the `after` parameter for incremental requests |
| `first_line` | number | JSONL line number of the first message in the current response; used as the `before` parameter for history loading |

**Loading Modes:**

| Mode | Parameters | Behavior | Use Case |
|------|-----------|----------|----------|
| Default | No after/before/offset | Return the latest N messages | Initial load |
| Incremental | `after=N` | Return messages with line > N (up to limit) | WebSocket-triggered new message loading |
| History | `before=M` | Return the latest N messages with line < M | Scroll-up to load older messages |
| Compatible | `offset=K` | Skip first K, return next N | Legacy pagination (kept for compatibility) |

**Error Responses:**

| Status | Condition |
|--------|-----------|
| 200 | When JSONL file doesn't exist, returns empty `{ messages: [], total: 0, has_more: false, last_line: 0, first_line: 0 }` |
| 404 | Session ID not found in database |

**Implementation Rules:**

- Only extract entries with `type: "user"` or `type: "assistant"`; skip system/progress entries
- Match `tool_use` and `tool_result` via `id` field; unpaired tool_use shows no result section
- Truncate individual content exceeding 10KB, appending `[truncated]`
- Re-read the file on every request (no server-side caching) to ensure real-time freshness
- When `cwd` is null, scan all `projects/` subdirectories to find the JSONL for the sessionId
- Internally use JSONL line numbers as cursors; remove the `line` field from responses, expose `first_line` / `last_line` to the client

---

## Frontend

### SessionDetail Page Changes

Replace the current flat layout with a **tabbed interface**:

```
[Agents]  [Conversation]  [Timeline]
```

- **Agents tab** — existing agent hierarchy tree (active by default)
- **Conversation tab** — new conversation viewer
- **Timeline tab** — existing event timeline

### Conversation Tab Components

**v2 Chat-flow architecture:**

```
ConversationView.tsx
├── TranscriptSelector   — dropdown selector (v2 replaces AgentFilter)
├── ScrollContainer      — scrollable message container
│   ├── HistoryLoader    — scroll-up history loading indicator
│   └── MessageList.tsx
│       ├── UserMessage      — user message
│       └── AssistantMessage
│           ├── TextBlock    — plain text content
│           ├── ThinkingBlock — collapsible thinking content
│           └── ToolCallBlock — collapsible tool call + result
│               ├── ToolUse      — tool name + parameters
│               └── ToolResult   — execution result / error
└── NewMsgButton         — "New messages" floating button (v2 new)
```

### TranscriptSelector (v2 replaces AgentFilter)

- Top dropdown selector: `[Main Agent ▾]` or `[Context Compaction ▾]`
- Data source: `GET /api/sessions/:id/transcripts` (filesystem scan, not database)
- Reloads the corresponding transcript on switch
- Only shown when transcripts > 1
- Message count displayed alongside: `518 messages`

### Chat-flow Behavior (v2 new)

**Initial load:**
- Call `transcript?limit=50` to get the latest 50 messages
- Auto-scroll to bottom after rendering
- Track `last_line` and `first_line` for subsequent requests

**Real-time updates (WebSocket-driven):**
- Subscribe to `eventBus` `new_event` events
- Only process events where `session_id` matches the current session
- On event, call `transcript?after=last_line&limit=50` for incremental loading
- If user is at bottom (< 100px from bottom), auto-scroll to latest message
- If user has scrolled up, show "New messages" floating button; click to scroll to bottom

**Scroll-up history loading:**
- Listen for scroll events; trigger when `scrollTop < 50` and `has_more` is true
- Call `transcript?before=first_line&limit=50` to fetch older messages
- Prepend to top of list; preserve scroll position via `scrollHeight` delta
- Show spinner while loading; show "↑ Scroll up for older messages" hint at top

**Key Refs:**
- `lastLineRef` — tracks the JSONL line number of the newest message, used for incremental requests
- `firstLineRef` — tracks the JSONL line number of the oldest loaded message, used for history loading
- `scrollContainerRef` — scroll container DOM reference
- `isAtBottomRef` — boolean flag tracking whether user is at the bottom

### Message Rendering

- **User messages**: right-aligned, blue background, display text content
- **Assistant messages**: left-aligned, default background, including:
  - Model name and token usage as faded metadata
  - Text blocks rendered inline
  - Thinking blocks: collapsed by default, click to expand (dimmed style)
  - Tool calls: collapsed by default showing only tool name, click to expand:
    - Tool name as header with icon
    - Input parameters formatted as JSON (collapsible)
    - Tool result with success/error indicator

### Interaction Details

- **Long text truncation**: content over 500 characters is truncated by default, with an "expand" link
- **Lazy loading (v2)**: initial load of latest 50 messages; scroll-up auto-loads older 50; WebSocket-driven incremental append
- **Real-time updates (v2)**: on WebSocket `new_event` with matching `session_id`, incrementally load new messages
- **Auto-scroll (v2)**: auto-scroll to latest when user is at bottom; show floating "New messages" button when user has scrolled up
- **Empty state**: when JSONL is missing or empty, show "No conversation records found."

---

## Server Module: claude-home.js

```js
// Centralized Claude home directory path management
function getClaudeHome() {
  return process.env.CLAUDE_HOME || path.join(os.homedir(), ".claude");
}

function getProjectsDir() {
  return path.join(getClaudeHome(), "projects");
}

function getSettingsPath() {
  return path.join(getClaudeHome(), "settings.json");
}

// Encoding rule: all non-alphanumeric characters replaced with "-"
// Example: "/Users/txj/.codefuse" → "-Users-txj--codefuse"
function encodeCwd(cwd) {
  return cwd.replace(/[^a-zA-Z0-9]/g, "-");
}

function getTranscriptPath(sessionId, cwd) {
  if (!cwd) return null;
  const encoded = encodeCwd(cwd);
  const candidate = path.join(getProjectsDir(), encoded, `${sessionId}.jsonl`);
  if (fs.existsSync(candidate)) return candidate;
  // Fallback: scan projects/ subdirectories
  return findTranscriptPath(sessionId);
}

function getSubagentTranscriptPath(sessionId, cwd, agentId) {
  if (!cwd) return null;
  const encoded = encodeCwd(cwd);
  const candidate = path.join(getProjectsDir(), encoded, sessionId, "subagents", `agent-${agentId}.jsonl`);
  if (fs.existsSync(candidate)) return candidate;
  // Fallback: scan all project directories
  return findSubagentTranscriptPath(sessionId, agentId);
}

function findTranscriptPath(sessionId) {
  // Fallback: when cwd is unknown, scan projects/ subdirectories
  const projectsDir = getProjectsDir();
  if (!fs.existsSync(projectsDir)) return null;
  const dirs = fs.readdirSync(projectsDir, { withFileTypes: true });
  for (const d of dirs) {
    if (!d.isDirectory()) continue;
    const candidate = path.join(projectsDir, d.name, `${sessionId}.jsonl`);
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
}

// v2 new: support prefix fuzzy matching for compaction type
function findSubagentTranscriptPath(sessionId, agentId) {
  const projectsDir = getProjectsDir();
  if (!fs.existsSync(projectsDir)) return null;
  const dirs = fs.readdirSync(projectsDir, { withFileTypes: true });
  for (const d of dirs) {
    if (!d.isDirectory()) continue;
    const subagentsDir = path.join(projectsDir, d.name, sessionId, "subagents");
    if (!fs.existsSync(subagentsDir)) continue;
    // Exact match
    const exact = path.join(subagentsDir, `agent-${agentId}.jsonl`);
    if (fs.existsSync(exact)) return exact;
    // Prefix fuzzy match (compaction type: agentId starts with "acompact-")
    if (agentId.startsWith("acompact-")) {
      const files = fs.readdirSync(subagentsDir);
      const match = files.find(f => f.startsWith("agent-acompact-") && f.endsWith(".jsonl"));
      if (match) return path.join(subagentsDir, match);
    }
  }
  return null;
}
```

---

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `server/lib/claude-home.js` | **New** | Claude home directory path management; v2 adds `findSubagentTranscriptPath` prefix fuzzy matching |
| `server/routes/sessions.js` | Modified | v1: add `GET /sessions/:id/transcript`; v2: add `GET /sessions/:id/transcripts`, transcript endpoint gains `after`/`before` params and `first_line`/`last_line` response |
| `scripts/import-history.js` | Modified | Use `getClaudeHome()` instead of hardcoded path |
| `scripts/install-hooks.js` | Modified | Use `getSettingsPath()` instead of hardcoded path |
| `server/routes/settings.js` | Modified | Use `getClaudeHome()` for hooks detection |
| `client/src/lib/types.ts` | Modified | v1: add `TranscriptMessage`, `TranscriptContent`; v2: add `TranscriptInfo`, `TranscriptListResult`, `TranscriptResult` gains `last_line`/`first_line` |
| `client/src/lib/api.ts` | Modified | v1: add `sessions.transcript()`; v2: add `sessions.transcripts()`, `transcript()` gains `after`/`before` params |
| `client/src/pages/SessionDetail.tsx` | Modified | Add tab switching and Conversation tab; v2: remove `agents` prop from ConversationView |
| `client/src/components/conversation/ConversationView.tsx` | **New** → v2 rewrite | v1: basic pagination; v2: chat-flow mode (WebSocket incremental + scroll-up history + auto-scroll) |
| `client/src/components/conversation/MessageList.tsx` | **New** | Message list (with collapsible blocks, command formatting, skill content folding, task notification folding) |
| `client/src/components/conversation/ToolCallBlock.tsx` | **New** | Collapsible tool call display |

---

## Error Handling

| Scenario | Handling |
|----------|----------|
| JSONL file doesn't exist | Return `{ messages: [], total: 0, has_more: false, last_line: 0, first_line: 0 }`; UI shows "No conversation records found." |
| JSONL line parse failure | Skip the line, continue processing remaining lines |
| Single content exceeds 10KB | Truncate and append `[truncated]` marker |
| Sub-agent JSONL doesn't exist | Same as main file — return empty list |
| Session cwd is null | Use `findTranscriptPath()` to scan project directories |
| CLAUDE_HOME path invalid | Log warning, return empty list |
| Incremental load returns no new messages (v2) | `after` request returns empty array, frontend silently ignores |
| History load failure (v2) | Silent failure, doesn't interrupt user experience |
| WebSocket disconnection (v2) | Doesn't affect loaded messages; next event after reconnect triggers incremental load |

## Edge Cases

- **Compaction**: After `/compact`, older messages are lost from the JSONL. The viewer only shows what's currently in the file — this is expected behavior. Compact transcripts appear as separate entries in the transcript selector.
- **Active sessions**: JSONL may be actively written to. Every request re-reads the file for real-time freshness. WebSocket events trigger incremental loading — no polling needed.
- **Unpaired tool_use/tool_result**: Display the tool call without the result section; no error.
- **Message order**: JSONL is ordered chronologically; responses preserve the same order (oldest first).
- **Database ID vs file ID mismatch (v2)**: Database agent IDs use format `<sessionId>-jsonl-<shortId>`, but JSONL filenames use `agent-<shortId>.jsonl`. v2 bypasses database IDs entirely via the `transcripts` endpoint, which scans the filesystem and uses file short IDs.
- **Compaction filename format (v2)**: In the database, compaction agent IDs use format `<sessionId>-compact-<uuid>`, but filenames use `agent-acompact-<hex>.jsonl`. `findSubagentTranscriptPath` supports prefix fuzzy matching for `agent-acompact-*.jsonl`.
- **Scroll position preservation (v2)**: When loading history, the scroll position is preserved by computing the `scrollHeight` delta, ensuring the viewport content doesn't jump.
- **Duplicate events (v2)**: WebSocket may send multiple `new_event` messages; incremental loading uses `after` line number for deduplication, preventing duplicate appends.

## Testing Strategy

| Layer | Test Content |
|-------|-------------|
| API unit tests | `GET /sessions/:id/transcript` — normal response, file not found, invalid session, pagination params, agent_id filtering |
| API unit tests | `GET /sessions/:id/transcript` — v2: `after` incremental loading, `before` history loading, `first_line`/`last_line` response |
| API unit tests | `GET /sessions/:id/transcripts` — v2: file scanning, compaction type, meta.json reading |
| API unit tests | `claude-home.js` — path inference logic, env var override, fallback scanning, compaction prefix fuzzy matching |
| Frontend component tests | `MessageList` rendering, `ToolCallBlock` collapse/expand, command formatting, skill content folding |
| Frontend component tests | `ConversationView` — v2: initial load, incremental append, history load, scroll detection, new messages indicator |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_HOME` | `~/.claude` | Claude Code home directory (e.g. `~/.codefuse/engine/cc/`) |