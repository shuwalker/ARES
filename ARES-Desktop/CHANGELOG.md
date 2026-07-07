# ARES CHANGELOG

## 2025-06-06 — ARESCore library split + four-tab navigation

### Changed
- **ARESCore library target split** (build-system only, no product behavior change)
  - 28 files moved from `Sources/ARES/` → `Sources/ARESCore/`: all Models, Discovery services, Hub Readers, UpdateCheckService, Utilities
  - New `ARESEnvironment.swift` added to ARESCore with public `.hermes` path helpers
  - All ARESCore types converted from `internal` to `public` access (1021 declarations)
  - All 58 files in `Sources/ARES/` now `import ARESCore`
  - `Package.swift` updated: `ARESCore` library target with `dependencies: []`, ARES executable depends on it, platforms include `.iOS(.v17)` alongside `.macOS(.v14)`, tests depend on both targets
  - `#if os(macOS)` guards added to BonjourBrowser (NetService), GitHubDiscovery (Process/gh CLI), and ToolDiscovery (NSWorkspace/resolveOnPATH)
  - BonjourBrowser non-macOS stub provided (empty, no-op)
  - GitHubDiscovery non-macOS stubs provided (Process-based methods return defaults)
- **Four-tab navigation**: added `settings` case to `ARESTab` enum
- **SettingsView created**: four sections per product spec — Integrations (tool read toggles), Quick Launch (system commands), Runtime Status (gateway/sessions/skills/memory, read-only), Diagnostics (Run Check button with inline report)
- ARESRootView switch updated with `.settings` → `SettingsView()` case

### Verification
- `swift build` green from clean state (0 errors, warnings only)
- ARESCore compiles as standalone library target
- ARES executable target links ARESCore

### Rollback
- Revert this commit to restore 3-tab structure; ARESCore files move back to ARES target