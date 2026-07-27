# Safari MCP Browser Automation (Drained)

Source: `safari-mcp` — 97-tool MCP server for Safari browser automation (Node.js/AppleScript)

## What was drained

Core Safari automation patterns and tool definitions for driving Safari via osascript/AppleScript and a native Safari extension:

- **`safari.js`** — Main automation module: tab management, navigation, DOM inspection, form filling, screenshots, PDF export, and 97 MCP tool implementations
- **`mcp-helpers.js`** — MCP protocol helpers (tool registration, response formatting, error handling)
- **`response.js`** — Structured response builder for MCP tool results
- **`ownership-match.js`** / **`ownership-state.js`** — Tab/window ownership tracking to prevent cross-tab interference
- **`injected-escape.js`** / **`injected-validators.js`** — Injected JavaScript for sandbox escape and input validation in web pages
- **`index.js`** — MCP server entry point and tool routing
- **`safari-helper.swift`** / **`safari-helper.entitlements`** — Native Swift helper app for privileged Safari operations (URL session injection, cookie access)
- **`extension/`** — Safari Web Extension (browser extension) for in-page coordination
- **`scripts/`** — Post-install and focus/clipboard restore scripts
- **`docs/`** — Documentation
- **`mcp.json`** / **`package.json`** / **`jsconfig.json`** — Project metadata

## Stripped
- `node_modules/`, `.git/`
- Test files (`test-evaluate-*.js`, `test-tab-tracking.js`)
- `assets/`, `examples/`, Docker configs

## Integration notes
This is a Node.js MCP server. To integrate into ARES:
1. The `safari_mcp/` directory can be run as a standalone MCP server or adapted into the ARES Python FastAPI adapter layer
2. The AppleScript/osascript patterns in `safari.js` and Swift helper are macOS-specific
3. The `injected-*.js` files are browser-side scripts that must be loaded into Safari page contexts
4. Tool definitions in `mcp.json` define the 97 available tools for MCP registration