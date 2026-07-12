# ARES Tools Rules

Instructions and rules for AI coding agents modifying files under this folder (`tools/`):

- **Modular & Independent**: Files in this folder are independent developer utilities, auxiliary helpers, and Model Context Protocol (MCP) server bootstrapping setups. They must remain decoupled from the main Swift application and Python server runtime.
- **Dependency Isolation**: Do not import `webui/` or `ARES-Desktop/` internal components into this folder. Keep dependencies strictly local to each tool.
- **Reference Rules**: Refer to the global assistant rules at [.claude/CLAUDE.md](file:///../.claude/CLAUDE.md).
