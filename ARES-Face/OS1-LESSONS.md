# OS1 Architecture Lessons → ARES-Face

## What OS1 Does Well (patterns to port)

### 1. Theme System with Design Tokens
- **OS1**: `OS1Palette` struct with semantic colors (coral, bgCream, onCoralPrimary, glassFill, etc.)
- **OS1**: `OS1Typography` with named styles (titleHero, titleSection, titlePanel, body, smallCaps)
- **OS1**: `Color.os1Coral`, `Font.os1Body` static extensions for zero-boilerplate access
- **ARES gap**: We hardcode `Color.accentColor`, `.secondary`, `.ultraThinMaterial` everywhere
- **Port**: Create `ARESPalette` + `ARESTypography` with our brand tokens (black-fire red, cyan, dark bg)

### 2. BootGate Pattern
- **OS1**: `BootGate` wraps RootView, shows animated loading, sets env flag when done
- **OS1**: `@Environment(\.os1BootAnimationFinished)` lets child views defer heavy init
- **OS1**: `OS1_SKIP_BOOT=1` env var for dev fast-start
- **ARES**: We have `LaunchRipple` hardcoded in ARESRootView with a DispatchQueue delay
- **Port**: Extract to `BootGate` + `BootAnimationFinishedKey` environment value

### 3. Split View Architecture
- **OS1**: Custom `OS1HSplitView` (NSViewRepresentable wrapping NSSplitView) with warm dividers
- **OS1**: Per-section split layout state (`HermesSplitLayout`) persisted per section
- **ARES**: Basic HStack with SidebarView
- **Port**: Eventually replace with proper NSSplitView, but not urgent

### 4. Sidebar Pattern
- **OS1**: Dynamic `availableSections` computed property filters sections based on connection type
- **OS1**: `sectionRow()` renders with glass fill, icon, label, and selected state
- **OS1**: Voice button at bottom of sidebar with status indicator
- **ARES**: We have SidebarView but it's simpler
- **Port**: Follow the `availableSections` pattern for Manual vs Avatar Twin mode filtering

### 5. Voice Integration (Critical for Avatar Twin)
- **OS1**: `RealtimeVoiceRuntimeView` is a 1x1 transparent WKWebView overlay in RootView
- **OS1**: Voice server is a local NWListener that bridges WebRTC → OpenAI
- **OS1**: Voice status flows back via JS bridge → Swift → `AppState.realtimeVoiceStatus`
- **ARES**: We have `VoiceManager` but no WebRTC bridge yet
- **Port**: Eventually adopt WebRTC voice, but for now our TTS/STT pipeline works

### 6. AppSection vs DashboardPage
- **OS1**: 16 sections (connections, overview, files, sessions, cronjobs, kanban, usage, skills, knowledgeBase, terminal, desktop, mail, messaging, connectors, providers, doctor)
- **ARES**: 8 pages (chat, sessions, skills, cron, logs, config, models, analytics)
- **Key difference**: OS1 sections map 1:1 to remote Hermes services. Our pages should too.

### 7. Service Architecture
- **OS1**: Every feature has a Service object (SessionBrowserService, SkillBrowserService, etc.)
- **OS1**: Services communicate via `RemoteTransport` protocol (SSH or Orgo API)
- **OS1**: AppState owns all services, views inject via @EnvironmentObject
- **ARES**: BrainConnection does everything (WebSocket + state + chat)
- **Port**: Eventually split BrainConnection into focused services, but not now

## What We Should NOT Port

1. **Orgo/SSH transport** — We connect directly to local Hermes, not remote
2. **Desktop/VNC view** — ARES has a face, not a desktop
3. **Mail/Messaging/Connectors** — Not our domain yet
4. **Knowledge Base** — Later
5. **Provider/OAuth flows** — We use local API keys

## Immediate Actions (what we just did)

✅ Created 2-position ImmersionLevel enum (manual/avatarTwin)
✅ Built ImmersionBar with animated slider
✅ ARESRootView conditional layout per mode
✅ BrainConnection mode-aware properties
✅ DashboardPage cleaned up with operator-tool labels

## Next Steps (from OS1 lessons)

1. **ARESPalette** — Replace hardcoded colors with semantic tokens (black-fire red, cyan accent, dark bg)
2. **BootGate** — Extract boot animation from RootView into a proper gate component
3. **Voice status in sidebar** — Add mic on/off indicator like OS1's voiceModeButton
4. **Section filtering** — In Avatar Twin mode, only show chat section; in Manual mode, show all
5. **Glass surface style** — Port the `.os1GlassSurface` modifier for consistent glass panels