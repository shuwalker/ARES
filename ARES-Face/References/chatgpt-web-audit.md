# Audit Report: `chatgpt-web` (Chanzhaoyu/chatgpt-web)

## Repo Info
- **Language/Framework**: Vue 3 (Options API + Composition API), TypeScript, Naive UI, Tailwind CSS
- **Architecture**: Clean minimal chat UI, focused on OpenAI API conversation with prompt templates and message management.
- **Local Path**: `/Users/matthewjenkins/Documents/GitHub/chatgpt-web`

---

## Key UI Patterns (SwiftUI Adaptable)

### 1. Conversation Page (`views/chat/index.vue`, ~554 lines)
**Patterns:**
- **Simple message list + input footer**: No sidebar in desktop; sidebar is separate route layout.
- **Regenerate / copy / delete per message**: Dropdown menu on each message with `copyText`, `toggleRenderType` (raw vs markdown), `delete`.
- **Stop generation button**: Floating sticky button at bottom when `loading` is true.
- **Export to PNG**: Uses `html-to-image` to snapshot the chat container, then downloads.
- **Context toggle**: "Use context" switch that controls whether previous messages are included in API request.

**SwiftUI mapping:**
- `List` of message views with `.swipeActions` or `Menu` for actions
- `Button("Regenerate")` as swipe or context action
- `Button("Stop")` inline with loading indicator
- `ShareLink` or `UIImage` snapshot via `ImageRenderer` for export
- `Toggle("Use context")` in settings sheet

---

### 2. Message Component (`views/chat/components/Message/index.vue`, ~145 lines)
**Patterns:**
- **Avatar inversion**: User on right, assistant on left. Avatar image toggles via `inversion` prop.
- **Dropdown actions**: `NDropdown` with trigger `hover` on desktop, `click` on mobile. Placement mirrors based on `inversion`.
- **Text rendering delegation**: `TextComponent` handles markdown vs raw.

**SwiftUI mapping:**
- `HStack` with conditional `.frame(alignment:)` based on `isUser`
- `Menu` with primary/trailing placement
- `AsyncImage` for avatars

---

### 3. Markdown Text Rendering (`views/chat/components/Message/Text.vue`, ~152 lines)
**Patterns:**
- **MarkdownIt pipeline**: `markdown-it` + `highlight.js` for code blocks, `markdown-it-katex` for math, `markdown-it-link-attributes` for external links.
- **Code block wrapper**: Header with language label + copy button, then `<code>` body with `hljs` classes.
- **Bracket escaping**: `escapeBrackets()` and `escapeDollarNumber()` preprocessors for math rendering.
- **Raw text toggle**: `asRawText` prop renders plain `whitespace-pre-wrap` instead of parsed markdown.

**SwiftUI mapping:**
- Use `AttributedString` with Markdown support (iOS 15+) or `Markdown` view (iOS 16+)
- `SyntaxHighlighter` via AttributedStringBuilder or native `CodeBlock` in Markdown
- `Copy` button in context menu for code blocks
- `SegmentedPicker` for raw vs rendered toggle

---

### 4. Streaming Updates (`views/chat/hooks/useScroll.ts` implied)
**Patterns:**
- **`onDownloadProgress`**: XMLHttpRequest progress callback parses partial `responseText`, extracts last JSON line, incrementally updates message.
- **Auto-scroll**: `scrollToBottomIfAtBottom()` checks if user is already at bottom before scrolling (so reading history isn't interrupted).
- **AbortController**: `handleStop()` aborts the in-flight request.

**SwiftUI mapping:**
- `URLSession` streaming with `bytes` async sequence
- `ScrollViewReader` for intelligent scrolling
- `Task { await stream }` with `Task.cancel()` for stop

---

## Files Worth Bookmarking
| File | Purpose |
|------|---------|
| `views/chat/index.vue` | Main chat page, streaming, export |
| `views/chat/components/Message/index.vue` | Message row with avatar + actions |
| `views/chat/components/Message/Text.vue` | Markdown rendering, code blocks |
| `store/modules/chat/helper.ts` | Session persistence helpers |
| `api/index.ts` | API client with streaming |

---

## Unique Adaptations for SwiftUI
- **Prompt templates**: `chatgpt-web` has a prompt store with slash-triggered templates. ARES-Face can use `.searchable` on `List` or a `/`-triggered inline picker.
- **Math rendering**: If ARES handles math, `MarkdownContent` in iOS 16+ renders LaTeX natively via MathJax WebView or native `AttributedString`.
- **Export**: `ImageRenderer` (iOS 16+) creates shareable snapshots of any SwiftUI view hierarchy.
