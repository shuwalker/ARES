# ARES Windows App Rules

Instructions and rules for AI coding agents modifying files under this folder (`ARES-Windows/`):

- **Platform-Specific Boundary**: This folder is strictly for the Windows Tauri/Rust desktop wrapper. Never add Swift code or macOS native app settings here.
- **Product Intent**: Treat this as the active Windows companion app for ARES. It should wrap the shared Web UI and grow Windows-native integrations such as tray controls, lifecycle management, status, and starting/stopping the Web UI server.
- **Paths & Config**: All relative directories in `src-tauri/tauri.conf.json` must be relative to the tauri workspace (e.g. `"frontendDist": "../../webui"`).
- **Reference Rules**: Refer to the global assistant rules at [../.claude/CLAUDE.md](../.claude/CLAUDE.md).
