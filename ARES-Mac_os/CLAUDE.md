# ARES macOS App Rules

Instructions and rules for AI coding agents modifying files under this folder (`ARES-Desktop/`):

- **Platform-Specific Boundary**: This folder is strictly for the native macOS SwiftUI/AppKit desktop application and the shared Swift package target `ARESCore`. Never add Python files, node modules, or other web assets here.
- **Background Agent Design**: ARES runs as a tray-based background agent (`LSUIElement = true`). If you modify the windowing structure, ensure that:
  - The app launches silently in the status bar with no Dock icon (`.accessory` activation policy).
  - Open windows temporarily toggle the policy to `.regular` (showing the Dock icon) and closing all windows reverts it to `.accessory`.
- **Integration Layer Only**: Do not hardcode runtime logic. All data, tool, and session modifications must go through `ARESCore` protocol boundaries (e.g. `AgenticFrameworkBackend`, `Identity`, etc.).
- **Reference Rules**: Refer to the global assistant rules at [.claude/CLAUDE.md](file:///../.claude/CLAUDE.md).
