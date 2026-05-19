# ARES Desktop

Native macOS SwiftUI client for the NousResearch Hermes Agent AI platform.

ARES gives the real Hermes workflow a calm, fast, native Mac surface. It
connects directly over SSH, keeps the Hermes host as the only source of truth,
and does not add a gateway, daemon, or sync layer on the host side.

## What ARES is

ARES (Autonomous Reasoning & Execution System) is a native macOS desktop app
that lets you manage, monitor, and interact with Hermes AI agents running on
local or remote hosts over SSH. It surfaces sessions, Kanban, files, skills,
analytics, multi-agent swarm control, and a real embedded terminal in one
focused window.

No browser wrapper. No gateway API. No local mirror slowly drifting from the
machine that actually matters.

## Feature Tabs

| Tab | Description |
|-----|-------------|
| Connections | Add and manage SSH connection profiles; test reachability and authentication |
| Overview | Active host summary, discovered Hermes profiles, important paths, and gateway controls |
| Sessions | Search and browse the remote session store, pin sessions, continue chat, or resume in terminal |
| Chat | Streaming SSE chat with the active Hermes agent; supports configurable thinking levels |
| Memory | View and manage the agent's memory entries via the Dashboard API |
| Soul | Read and edit the agent's soul/persona file anchored to the remote host |
| Tools | List available tools registered with the agent and review pending tool-approval requests |
| Office | Embedded office/workspace panel for document and project context |
| Kanban | Full Hermes Kanban workspace: boards, tasks, comments, dependencies, run history, and orchestration |
| Terminal | Real SSH shell embedded in the app with tabs, theme presets, and multi-profile support |
| Jobs | Dashboard-side cron jobs managed via the Dashboard API (port 9119) |
| MCP | Model Context Protocol server management: install, enable/disable, marketplace discovery |
| Analytics | Daily token charts, per-model breakdown, and skill usage statistics over configurable periods |
| Swarm | Multi-agent swarm management: workers, missions, health, Kanban cards, and runtime output |
| Conductor | High-level mission director: set a goal, dispatch workers, monitor conductor progress |
| Operations | Operations agents view for managing multi-step autonomous operation runs |
| Crew Status | Live status board for all active crew members and their current states |
| Files | Browse and edit remote text files and canonical Hermes files with conflict checks before save |
| Skills | Discover, read, create, and edit remote `SKILL.md` files in the Hermes skills store |
| Config | Hermes configuration editor served by the Dashboard API |
| Keys | API key management via the Dashboard API |
| Models | Model configuration and selection via the Dashboard API |
| Profiles | Hermes profile management via the Dashboard API |
| Logs | Live log viewer streamed from the Dashboard API |
| Plugins | Install, enable/disable, update, and remove agent plugins; manage memory providers |
| Global Search | Full-text search across sessions, skills, files, and other content on the active host |
| Workflows | Locally saved prompt presets scoped to the active host/profile; launches a fresh terminal tab |
| Cron Jobs | Browse and manage the Hermes scheduler state: create, edit, pause, resume, run-now, delete |
| Usage | Token totals, top sessions, top models, and profile breakdowns |
| Second Brain | LanceDB embedding search across documents, sessions, and skills on the host |
| Avatar | Embedded VTuber/avatar panel for local connections |
| YouTube | Review, edit metadata, and approve/reject staged videos for publishing |
| Documentation | In-app documentation viewer loading the Hermes docs site |

## Architecture

### Transport Layers

ARES uses two complementary transports to communicate with the Hermes host.

#### 1. SSH Bridge (primary)

A Python RPC bridge executed over SSH handles all operations that need direct
filesystem access on the remote host:

- **Sessions** — reads the remote session store and message transcripts
- **Kanban** — opens the upstream Hermes Kanban workspace from the host filesystem
- **Files** — browses remote directories and edits remote text files with conflict detection
- **Skills** — discovers and edits remote `SKILL.md` files
- **Soul** — reads and writes the agent soul/persona file

The bridge is a short Python script shipped inside the app bundle
(`ARES_ARES.bundle`) and piped over stdin/stdout through a normal SSH
connection. No daemon is installed on the host.

#### 2. Dashboard API (HTTP via SSH tunnel)

Many features talk to the Hermes dashboard HTTP API, which listens on
`localhost:9119` on the remote host. ARES port-forwards that port to a
dynamically chosen local port via `SSHTunnelService` and sends requests
through the tunnel.

Features powered by the Dashboard API:

- **Config, Models, Logs, Keys, Profiles, Plugins** — full Hermes administration
- **Chat** — SSE streaming chat turns
- **Memory, Tools** — agent memory and tool registry
- **Kanban plugin API** — board orchestration endpoints
- **Jobs** — dashboard-side cron job management
- **MCP** — Model Context Protocol server registry
- **Analytics** — usage analytics endpoints
- **Swarm, Conductor** — multi-agent coordination APIs

All Dashboard API calls are handled by `DashboardAPIService`.

#### 3. SSH Tunnel Service

`SSHTunnelService` auto-starts when ARES connects to a remote host. It spawns:

```
ssh -N -L <localPort>:127.0.0.1:9119 [user@]host [-p sshPort]
```

and polls the forwarded port until it becomes reachable (up to 10 seconds),
then keeps the tunnel alive with `ServerAliveInterval=30`. The tunnel tears
down automatically on disconnect. This makes the Dashboard API available
transparently without any manual setup on the host.

### Key Services

| Service | Transport | Responsibilities |
|---------|-----------|-----------------|
| `SessionBrowserService` | SSH bridge (Python RPC) | Sessions, cron jobs |
| `KanbanBrowserService` | SSH bridge + Dashboard API | Kanban boards and tasks |
| `SkillBrowserService` | SSH bridge (Python RPC) | Skills discovery and editing |
| `FileEditorService` | SSH bridge (Python RPC) | Remote file browse and edit |
| `SoulService` | SSH bridge (Python RPC) | Soul file read/write |
| `DashboardAPIService` | HTTP via SSH tunnel | All Dashboard API calls |
| `HermesChatService` | SSE via SSH tunnel | Streaming chat |
| `UsageBrowserService` | HTTP via SSH tunnel | Usage and analytics |
| `SSHTunnelService` | SSH process | Port-forward lifecycle |

### AppState

`AppState` is a `@MainActor` `ObservableObject` that owns all published UI
state. Every view model property, loading flag, error string, and selection ID
lives here. Navigation between sidebar sections is controlled by
`selectedSection: AppSection`.

`AppSection` is a `CaseIterable` enum that drives the sidebar. Adding a new tab
requires adding a case to `AppSection` and a corresponding route in `RootView`.

## Requirements

- macOS 14.0 or later
- A running Hermes Agent instance (local or SSH-accessible remote)
- SSH access from this Mac to the Hermes host, working without interactive
  prompts (key-based or SSH agent auth)
- `python3` available in the remote SSH environment

For local builds:

- Xcode 16+ (Xcode 16.2 or 16.3 recommended)
- Swift 5.10+ / Swift 6.1

## Installation

### Option 1: GitHub Releases (recommended)

1. Download `ARES.app.zip` from the
   [latest GitHub Release](https://github.com/shuwalker/ares-autonomous-reasoning-execution-system/releases/latest).
2. Double-click the zip to extract `ARES.app`.
3. Quit any older running copy of ARES.
4. Drag `ARES.app` into `Applications`.
5. First launch: right-click `ARES.app`, choose `Open`, then confirm `Open`.

ARES is currently ad-hoc signed and not notarized by Apple. macOS may show a
first-launch warning. If macOS blocks the launch:

1. Click `Done` (not `Move to Bin`).
2. Right-click `ARES.app` and choose `Open`.
3. If needed: `System Settings` > `Privacy & Security` > `Open Anyway`.

Do not disable Gatekeeper or use `sudo` to install ARES. See
[docs/distribution.md](docs/distribution.md) for the full signing and checksum
model.

### Option 2: Build from source

```bash
cd ARES-Desktop
swift build -c release
```

Or open in Xcode:

```bash
open Package.swift
```

To produce the full app bundle and release archive:

```bash
./scripts/build-macos-app.sh
./scripts/package-github-release.sh
```

Artifacts land in `dist/`:

- `dist/ARES.app.zip`
- `dist/ARES.app.zip.sha256`
- `dist/ARES.app.zip.manifest.json`

To verify a release zip against the published manifest:

```bash
./scripts/verify-release.sh /path/to/ARES.app.zip /path/to/ARES.app.zip.manifest.json
```

## Connecting to Hermes

1. Open ARES and go to the **Connections** tab.
2. Click the `+` button to create a new connection profile.
3. Choose **SSH** (for a remote host) or **Local** (for Hermes on this Mac via
   `localhost`).
4. Enter the connection details:
   - **SSH alias** (recommended): the short name from `~/.ssh/config`, e.g.
     `hermes-home`
   - Or **Host / User / Port** explicitly, e.g. `vps.example.com` / `alex` / `22`
5. Optionally set a **Hermes profile** (e.g. `researcher`) to target
   `~/.hermes/profiles/researcher` instead of the default `~/.hermes`.
6. Click **Test** to verify SSH reachability, authentication, and `python3`
   availability.
7. Click **Use Host** to activate the connection.

When you connect to an SSH host, ARES automatically starts the SSH tunnel
(`SSHTunnelService`) in the background, port-forwarding the Hermes dashboard
(`localhost:9119` on the host) to a local port. Chat, Memory, Tools, Config,
and all other Dashboard API features become available as soon as the tunnel is
established — no manual setup required.

### Connect to the same Mac

Hermes running on the same Mac is supported. Use `localhost`, your local
hostname, or a local SSH alias. ARES still connects over SSH and does not read
files directly from disk.

## CI/CD

GitHub Actions runs on **macOS-15** with Xcode 16 on every push and pull
request. The CI job:

1. Runs the test suite (`./scripts/run-tests.sh`)
2. Builds the app bundle (`./scripts/build-macos-app.sh`)
3. Packages the release archive (`./scripts/package-github-release.sh`)
4. Verifies the archive checksum (`./scripts/verify-release.sh`)
5. Uploads `ARES.app.zip`, `ARES.app.zip.sha256`, and
   `ARES.app.zip.manifest.json` as build artifacts

Tagged releases (`v*`) trigger an additional job that runs the same pipeline
and then publishes a **draft GitHub Release** with the three release artifacts
attached and auto-generated release notes.

## Package Structure

```
ARES-Desktop/
├── Package.swift                    Swift package manifest (swift-tools-version 6.1)
├── Sources/
│   └── HermesDesktop/              Main executable target (named "ARES")
│       ├── App/                    App entry point, AppState, lifecycle
│       ├── Models/                 Data models and AppSection enum
│       ├── Services/               Transport, SSH, API, and feature services
│       │   ├── SSH/                SSHTunnelService, SSHTransport
│       │   ├── Transport/          TransportProtocol, HTTP/SSH/WebSocket transports
│       │   ├── Storage/            Local persistence
│       │   └── *.swift             Feature services (Dashboard, Session, Kanban, …)
│       ├── Views/                  SwiftUI views
│       ├── Utilities/              Helpers, extensions, localization
│       └── Resources/              Bundled assets and Python bridge scripts
├── Tests/
│   └── HermesDesktopTests/         Unit tests
├── Vendor/
│   └── SwiftTerm/                  Vendored terminal emulator library
├── scripts/                        Build, package, verify, and test scripts
├── dist/                           Release artifacts (gitignored)
└── .github/workflows/              CI/CD (macos-ci.yml, deploy-pages.yml)
```

## Localization

ARES ships localization resources for English, Simplified Chinese, and Russian.
All user-visible strings are routed through `L10n.string(…)`.
