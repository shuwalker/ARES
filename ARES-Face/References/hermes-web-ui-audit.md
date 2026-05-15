# Audit Report: `hermes-web-ui` (EKKOLearnAI/hermes-web-ui)

## Repo Info
- **Language/Framework**: Vue 3 (Composition API), TypeScript, SCSS, Naive UI component library
- **Architecture**: Full-featured web client for a multi-modal AI agent named Hermes
- **Local Path**: `/Users/matthewjenkins/Documents/GitHub/hermes-web-ui`

---

## Key UI Patterns (SwiftUI Adaptable)

### 1. Chat Input (`ChatInput.vue`, ~894 lines)
**Patterns worth stealing for ARES-Face:**
- **Auto-expanding textarea with resize handle**: `max-height: 400px`, `min-height: 20px`, `resize: none` + mouse-driven row-resize handler (`cursor: row-resize`).
- **Slash command dropdown**: Detects `/` prefix, filters bridge commands, shows name/args/description grid. SwiftUI `TextField` + `.searchable` or custom overlay.
- **Drag-and-drop file attachments**: `dragenter`/`dragleave`/`drop` events, thumbnail previews (64×64 for images, file cards for docs), remove button on hover.
- **Context token meter**: Linear gradient bar (`context-bar`) showing token usage %, color shifts to amber/red at thresholds.
- **Auto-play speech toggle**: Switch per message with global setting persistence.

**SwiftUI mapping:**
- `TextEditor` with dynamic height via `GeometryReader`
- `@State` for slash command filter + overlay `List`
- `NSItemProvider` / `DropDelegate` for drag-and-drop
- `ProgressView(value:)` or custom `Rectangle` fill for token meter
- `Toggle` for speech setting

---

### 2. Message Rendering (`MessageItem.vue`, ~1413 lines)
**Patterns:**
- **`ContentBlock[]` parser**: Separates text, image attachments, and file downloads inline. Each block type gets its own renderer.
- **Thinking / reasoning blocks**: Collapsible header with chevron, streaming-time indicator, character count. Body uses `MarkdownRenderer`.
- **Tool call display**: Inline expandable row per tool (name, status badge `running`/`error`, preview). Click to expand into arguments/result code blocks.
- **TTS integration**: Inline play/pause button per message bubble, state syncs with global speech service. Visual feedback via animated `rainbow-glow` box-shadow when playing.
- **Attachment download URLs**: URL construction via `getApiKey()` injected helper.

**SwiftUI mapping:**
- `ForEach(blocks)` with `switch block.type` rendering
- `DisclosureGroup` for thinking blocks
- `Button` with `Image(systemName: "chevron.right")` rotation for tool expand
- `AVSpeechSynthesizer` for TTS, `@Published` state in view model
- `AsyncImage` / `ShareLink` for attachments

---

### 3. Message List (`MessageList.vue`, ~718 lines)
**Patterns:**
- **Auto-scroll to bottom**: `scrollToBottom()` on initial load; "New messages" floating pill appears when user is scrolled up.
- **Message queue overlay**: Floating panel with orbiting spinner + queued message previews. `max-height` constrained, dismissible.
- **Tool call status side-panel**: Inline list of active tools with spinners, durations, and error icons.
- **Empty state**: Centered logo + text with fade transition.
- **Scroll-to-message**: `scrollIntoView({ behavior: 'smooth' })` for highlight.

**SwiftUI mapping:**
- `ScrollViewReader` + `scrollTo(id)` for bottom anchoring
- `overlay(alignment: .bottom)` for new-message pill
- `ZStack` overlay for queue panel
- `withAnimation(.spring)` for entry/exit

---

### 4. Sidebar Session Management (`ChatPanel.vue`, ~1471 lines)
**Patterns:**
- **Collapsible sidebar**: Width animation via CSS transition; on mobile becomes a slide-over sheet with backdrop.
- **Session grouping by time**: `today`, `yesterday`, `last7`, `last30`, `older` — dynamically computed groups.
- **Pinned sessions**: Fixed section above grouped items.
- **Batch selection mode**: Multi-select checkboxes + bulk delete confirmation.
- **Context menu**: Right-click for rename, workspace set, delete.
- **Workspace badge**: Folder name clipped from full path in header.
- **Live streaming indicator**: Dot pulse on session items when actively streaming.

**SwiftUI mapping:**
- `NavigationSplitView` or custom `Sidebar` with collapse toggle
- `Section` + `List` with date-based grouping
- `@State` for `isBatchMode` + `Set<UUID>` selection
- `Menu` for context actions
- `Path` trimming + `Text` for workspace label

---

### 5. Approval Bar Pattern
A toolbar appears above input when a tool approval is pending. Shows tool description, command preview, and choice buttons (`once`, `session`, `always`, `deny`).

**SwiftUI mapping:**
- `VStack` with `HStack` buttons as an inline banner, `.background(.secondary.opacity(0.1))`

---

## State Management Approach
- **Pinia stores** for global chat/session state (not directly usable in SwiftUI)
- **Reactive refs** (`ref`, `computed`) per component — maps naturally to `@State`/`@Binding`/`@ObservedObject`
- **SSE streaming** for assistant responses — event stream parsed incrementally into message store

---

## Styling Approach
- **SCSS variables** in `styles/variables.scss`: `$bg-primary`, `$border-color`, `$accent-primary`, `$msg-user-bg`, `$msg-assistant-bg`
- **Role-based coloring**: User messages get green tint, assistant gets gray, system gets yellow left border
- **Dark mode**: `.dark &` nested overrides everywhere

**SwiftUI mapping:**
- Central `Theme` struct with `Color` extensions
- `Environment(\.colorScheme)` for dark mode
- `ViewModifier` for common bubble styling

---

## Files Worth Bookmarking
| File | Purpose |
|------|---------|
| `ChatInput.vue` | Input, slash commands, attachments, context meter |
| `MessageItem.vue` | ContentBlock rendering, thinking blocks, tool expansion, TTS |
| `MessageList.vue` | Scroll management, queue panel, tool status overlay |
| `ChatPanel.vue` | Sidebar, session grouping, batch mode, context menu |
| `MarkdownRenderer.vue` | Custom markdown with code copy buttons |
