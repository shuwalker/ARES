# Audit Report: `Claude-Code-Agent-Monitor` (hoangsonww)

## Repo Info
- **Language/Framework**: React 18, TypeScript, Tailwind CSS, shadcn/ui-inspired custom components, Vite
- **Architecture**: Dashboard for monitoring Claude Code agent sessions with SQLite + WebSocket backend
- **Local Path**: `/Users/matthewjenkins/Documents/GitHub/Claude-Code-Agent-Monitor`

---

## Key UI Patterns (SwiftUI Adaptable)

### 1. Dashboard Health Overview (`Dashboard.tsx`, ~1359 lines)
**Patterns:**
- **Composite Health Score**: Weighted index (`0.4×success + 0.25×cache + 0.25×errorAvoid + 0.1×heap`) rendered as a ring gauge (SVG circle with `strokeDasharray`). Color shifts: green ≥ 90, amber ≥ 70, red < 70.
- **Donut / Pie charts**: Inline SVG segments for database record distribution (sessions/agents/events). No chart library — pure SVG with `strokeDasharray`/`strokeDashoffset` math.
- **Live connection badge**: Pulsing dot + "Live" / "Offline" pill with real-time WebSocket state.
- **StatCard grid**: `grid-cols-1 md:grid-cols-2 lg:grid-cols-3` responsive layout.
- **Memory / heap progress bars**: Thin rounded bars with threshold-based colors (red > 90%, amber > 70%).

**SwiftUI mapping:**
- `Canvas` for ring gauge and donut charts (using `Path` arcs)
- `@ObservedObject var healthModel` exposing `score: Double`
- `Capsule().fill(colorForScore(score))` for status indicator
- `LazyVGrid(columns: ...)` for stat cards
- `Gauge` (iOS 16+) or custom linear progress bar for memory

---

### 2. Session Detail + Conversation Tabs (`SessionDetail.tsx`, ~989 lines)
**Patterns:**
- **Tab bar with mount-once optimization**: `visitedTabs` Set prevents remount on tab switch, eliminating flash.
- **Three-pane detail view**: Agents list (hierarchical with expand/collapse), Conversation transcript, Timeline of events.
- **Agent hierarchy auto-expand**: Parents with `working` children expand automatically via depth traversal.
- **Agent → Conversation navigation**: Clicking a leaf agent switches to Conversation tab and auto-selects matching transcript via `subagent_type`/`name` fallback logic.
- **Event grouping by type**: `groupEvents()` merges related events into visual groups with count badges.
- **Transcript ID mapping**: Three-tier fallback (exact `db_agent_id` → `type === "main"` → `subagent_type` match).
- **Load-more pagination**: "Show more" per-column with `COLUMN_PAGE_SIZE` client-side limit.

**SwiftUI mapping:**
- `TabView(selection: $activeTab)` with lazy tab content
- `List` with `children:` or custom DisclosureGroup for agent hierarchy
- `NavigationSplitView` for master-detail agent→conversation flow
- `ForEach(eventGroups)` with section headers
- `Button("Show more")` that increments `displayLimit`

---

### 3. Tool Call Rendering (`ToolCallBlock.tsx`, ~280 lines)
**Patterns:**
- **Per-tool type layout**: Bash gets command block; Write gets path + code; Edit gets side-by-side removed/added; Grep gets pattern/path/glob tags; Read gets path + offset/limit badge.
- **Collapsible header**: Chevron rotation 0° → 90°, status chip (`error` red, `ok` green, `pending` gray).
- **Language detection from file extension**: Extension → syntax language map (`.ts` → `ts`, `.py` → `python`, etc.).
- **Payload heuristics**: JSON bracket detection, diff prefix (`+++`/`---`/`@@`), bash output default.
- **Truncation indicator**: `_truncated` field in payload shows truncated label.

**SwiftUI mapping:**
- `DisclosureGroup(isExpanded:)` with custom header (icon + name + summary + status badge)
- `switch toolName` for specific layouts
- `Text(filePath).onTapGesture` for path display
- `CodeBlockView(code:lang:)` wrapping a Swift-syntax highlighter or `AttributedString`

---

### 4. Kanban Board (`KanbanBoard.tsx`, ~460 lines)
**Patterns:**
- **Dual view toggle**: Agents vs Sessions persisted in `localStorage`.
- **Status columns**: Fixed columns (`working`, `waiting`, `completed`, `error`) with colored dot pulse on active states.
- **Client-side pagination per column**: `COLUMN_PAGE_SIZE = 10`, "show more" expands by increments.
- **Column help tooltips**: Keyboard-focusable help icons with multi-line descriptions anchored left to avoid clipping.
- **Responsive horizontal scroll**: `overflow-x-auto` with `-mx-8 px-8` negative margins for full-bleed columns.
- **Live badge**: Same pulsing dot pattern as Dashboard.

**SwiftUI mapping:**
- `Picker` with segmented style for view toggle
- `ScrollView(.horizontal)` containing `VStack` columns
- `LazyVStack` with `items.prefix(limit)` for pagination
- `Popover` or `Tooltip` for column help text
- `Button` with `Label` for show-more

---

### 5. Conversation Streaming (`ConversationView.tsx`, ~432 lines)
**Patterns:**
- **Incremental tail-fetch**: `after: lastLineRef.current` to append only new messages.
- **Bootstrap mode**: If transcript empty, fetch latest 50 instead of incremental.
- **Fetch coalescing**: If fetch is in-flight and a new trigger arrives, queue exactly one retry post-completion.
- **Visibility-gated polling**: `document.visibilityState === "visible"` check at 3s intervals; catches hooks that don't fire for user-typed messages.
- **WebSocket + polling hybrid**: WS for real-time, polling for gap closure and WS reconnection catch-up.
- **Scroll preservation**: `prevScrollHeight/newScrollHeight` delta when loading history at top.
- **New messages pill**: Floating "New messages" button at bottom when not at bottom.

**SwiftUI mapping:**
- `Timer.publish(every: 3, on: .common)` gated by `UIApplication.shared.applicationState`
- `URLSession` with `Range` headers for incremental JSONL tailing
- `ScrollViewReader` with `proxy.scrollTo(bottomID)`
- `Button("New messages")` floating via `.overlay(alignment: .bottom)`

---

## State Management
- **`eventBus`**: Custom pub/sub with WebSocket subscription — maps to `ObservableObject` + `WebSocketTask`
- **`api` layer**: REST API client with typed endpoints (`api.sessions.list`, `api.events.list`, etc.) — maps to `APIService` actor
- **`useSyncExternalStore`**: React hook polling connection state — maps to `@Published var isConnected`

---

## Styling Approach
- **Tailwind CSS utility classes**: `bg-surface-1`, `border-border`, `text-gray-100`, `rounded-xl`
- **CSS custom properties** (design tokens): surface colors, border colors, accent colors
- **Framing**: `card` class = `rounded-xl border border-border bg-surface-1 p-4`
- **Tool style map** (`toolStyle.ts`): Per-tool icon, chip color, border color, text color.

**SwiftUI mapping:**
- Central `Theme` enum with `Color` values
- `ViewModifier` for `card` style
- `Label` with SF Symbols matching tool icons

---

## Files Worth Bookmarking
| File | Purpose |
|------|---------|
| `Dashboard.tsx` | Health ring, pie chart, stat cards, live badge |
| `SessionDetail.tsx` | Agent hierarchy, tab switching, event timeline |
| `ToolCallBlock.tsx` | Tool-specific rendering, collapsible blocks |
| `KanbanBoard.tsx` | Status columns, pagination, view toggle |
| `ConversationView.tsx` | Incremental fetch, WS+polling, scroll management |
| `CodeBlock.tsx` | Syntax highlighting with copy button |
| `toolStyle.ts` | Per-tool icon/color mapping table |
