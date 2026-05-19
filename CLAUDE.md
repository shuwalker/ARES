# ARES — Developer Notes for AI Assistants

This file describes the ARES codebase for AI assistants working on it. Read
this before making changes.

## Repository Layout

```
ARES-Autonomous-Reasoning-Execution-System/
├── ARES-Desktop/               Native macOS SwiftUI app (primary focus)
│   ├── Package.swift           Swift package manifest (swift-tools-version 6.1)
│   ├── Sources/
│   │   └── HermesDesktop/     Executable target named "ARES"
│   │       ├── App/           App entry point, AppState, lifecycle
│   │       ├── Models/        Data models, AppSection enum
│   │       ├── Services/      All network, SSH, and feature services
│   │       │   ├── SSH/       SSHTunnelService, SSHTransport
│   │       │   ├── Transport/ TransportProtocol, HTTP/SSH/WebSocket
│   │       │   └── Storage/   Local persistence helpers
│   │       ├── Views/         SwiftUI views
│   │       ├── Utilities/     Extensions, helpers, L10n
│   │       └── Resources/     Bundled assets, Python bridge scripts
│   ├── Tests/
│   │   └── HermesDesktopTests/  Unit tests
│   └── Vendor/SwiftTerm/      Vendored terminal emulator
├── ares/                      Python daemon (separate system, not the macOS app)
├── docs/                      Project documentation
└── .github/workflows/         CI/CD pipelines
```

## How to Build

```bash
cd ARES-Desktop
swift build                     # debug build
swift build -c release          # release build
swift test                      # run tests
```

Or use the helper scripts:

```bash
cd ARES-Desktop
./scripts/build-macos-app.sh          # produces dist/ARES.app
./scripts/run-tests.sh                # runs the test suite
./scripts/package-github-release.sh  # produces dist/ARES.app.zip + checksums
./scripts/verify-release.sh          # verifies the packaged archive
```

The Swift package executable is named `ARES`. The bundle naming convention used
by SwiftPM produces `ARES_ARES.bundle` — use that exact name when referencing
the app bundle from code or scripts.

## Key Architecture

### Two Transport Layers

ARES communicates with the Hermes host via two complementary paths:

**1. SSH Bridge (Python RPC)**

Used by: Sessions, Kanban (filesystem side), Files, Skills, Soul, Cron Jobs.

A short Python script is piped over stdin/stdout through a normal SSH
connection. It handles all operations that need direct filesystem access on the
remote host. No daemon is installed on the host side.

Key services: `SessionBrowserService`, `KanbanBrowserService`,
`SkillBrowserService`, `FileEditorService`, `SoulService`,
`CronBrowserService`.

**2. Dashboard API (HTTP via SSH tunnel)**

Used by: Chat (SSE streaming), Memory, Tools, Config, Models, Logs, Keys,
Profiles, Plugins, Jobs, MCP, Analytics, Swarm, Conductor, Operations,
Crew Status, Kanban orchestration API.

`SSHTunnelService` auto-starts on SSH connect and port-forwards
`localhost:9119` on the remote host to a dynamically chosen local port (starting
at 19119). All HTTP calls go through this tunnel. `DashboardAPIService` is the
single service that owns all HTTP calls to the Dashboard API.

### AppState

- `AppState` is `@MainActor final class ObservableObject`
- All published UI state lives in `AppState` — loading flags, selection IDs,
  error strings, data arrays
- It is the single source of truth for the UI; views read from it and dispatch
  actions through it
- File: `Sources/HermesDesktop/App/AppState.swift`

### Sidebar Navigation

`AppSection` (`Sources/HermesDesktop/Models/AppSection.swift`) is a
`CaseIterable` enum where each case is one sidebar tab. To add a new tab:

1. Add a `case` to `AppSection` with a `rawValue` string identifier
2. Add `title`, `systemImage`, and optionally `navigationShortcutKey` to the
   switch statements in `AppSection`
3. Add the corresponding route and view in `RootView`

Do not add cases without views — the compiler will warn but the app will crash
or show a blank panel at runtime.

### DashboardAPIService

`Sources/HermesDesktop/Services/DashboardAPIService.swift`

Handles all HTTP requests to the Hermes dashboard (port 9119 via tunnel).
Obtain the tunnel's local port from `SSHTunnelService.localPort` before
constructing URLs. All methods are `async throws`.

### SessionBrowserService

`Sources/HermesDesktop/Services/SessionBrowserService.swift`

Python RPC bridge over SSH. Handles session listing, session messages, and
chat turns that go through the SSH path rather than the Dashboard API.

### SSHTunnelService

`Sources/HermesDesktop/Services/SSH/SSHTunnelService.swift`

Manages the SSH local port-forward process lifecycle. Call `start(connection:)`
after the user connects; call `stop()` on disconnect or app termination. The
service is `@unchecked Sendable` and uses `NSLock` internally.

## Swift 6 Concurrency

The package uses `swift-tools-version: 6.1` with strict concurrency checking.
Follow these rules when adding code:

- Mark all UI-touching types and methods `@MainActor`
- Use `@unchecked Sendable` only for types that manage their own thread safety
  with a lock (document why)
- Use structured concurrency (`async let`, `TaskGroup`) over raw `Task {}`
  where possible
- Do not use `DispatchQueue.main.async` in new code — use `await MainActor.run`
  or `@MainActor` annotations instead

## Bundle Name

SwiftPM names the resource bundle `ARES_ARES.bundle`. Use this exact name when
loading bundled resources (Python scripts, assets) from code:

```swift
Bundle.module  // preferred — SwiftPM resolves this automatically
```

## What NOT to Add

**Do not add Gateway management features.** Gateway management is explicitly
excluded by the project owner. The app talks directly to the Hermes host over
SSH and through the dashboard tunnel. It does not manage, configure, or expose
any gateway service.

## CI/CD

- `macos-ci.yml` — runs on every push and PR; builds, tests, packages, and
  verifies on `macos-15` with Xcode 16
- `release.yml` — triggered by `v*` tags; same pipeline plus publishes a draft
  GitHub Release with `ARES.app.zip`, `ARES.app.zip.sha256`, and
  `ARES.app.zip.manifest.json`

## Localization

All user-visible strings go through `L10n.string(…)`. Localization resources
for English, Simplified Chinese, and Russian are in `Sources/HermesDesktop/Resources/`.
Do not hardcode strings in views.

## Tests

Tests live in `Tests/HermesDesktopTests/` (target `ARESTests`). Run with
`swift test` from the `ARES-Desktop/` directory or with `./scripts/run-tests.sh`.
