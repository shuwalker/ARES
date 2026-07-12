# ARES Windows App Rules

Instructions and rules for AI coding agents modifying files under this folder (`ARES-Windows/`):

- **Platform-Specific Boundary**: This folder is strictly for the Windows Tauri/Rust desktop wrapper. Never add Swift code or macOS native app settings here.
- **Paths & Config**: All relative directories in `src-tauri/tauri.conf.json` must be relative to the tauri workspace (e.g. `"frontendDist": "../../webui"`).
- **Reference Rules**: Refer to the global assistant rules at [.claude/CLAUDE.md](file:///../.claude/CLAUDE.md).
