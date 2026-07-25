# Safari MCP Bootstrap for ARES

This tool configures and verifies the optional Safari MCP path used by ARES when the selected backend is Ares Agent.

It exists because Safari automation on macOS is not a computer-vision problem. The durable solution is a native MCP server that drives the real logged-in Safari through AppleScript/WebKit tooling.

## What this gives ARES

- Registers `safari-mcp` in the local Ares Agent config when Ares is the selected backend.
- Verifies the MCP server starts and exposes its tools.
- Runs `safari_doctor` to detect missing macOS approvals.
- Prints the exact one-time remediation steps for Safari / Automation / Accessibility / Screen Recording.
- Avoids relying on screenshots or desktop vision.

## Canonical repos

- Upstream reference: `https://github.com/achiya-automation/safari-mcp`
- Local clone: any user-selected path; `~/GitHub/safari-mcp` is only a convenient example.

`safari-mcp` must run on the Mac that has Safari. It cannot run on Linux rack PCs because it depends on macOS, Safari, AppleScript, and the bundled Swift helper.

## Quick start

```bash
python3 tools/safari-mcp-bootstrap/safari_mcp_bootstrap.py --configure-ares
```

Expected result:

- Node/npm present
- `safari-mcp` package/repo available on this Mac
- Ares config contains `mcp.servers.safari-mcp`
- `safari_doctor` runs

## One-time macOS approvals

If the doctor reports failures, perform the exact matching approval:

1. Safari → Settings → Advanced → enable **Show features for web developers**.
2. Safari → Develop → enable **Allow JavaScript from Apple Events**.
3. System Settings → Privacy & Security → Automation → allow the Ares/Terminal host app to control Safari.
4. Native click/keyboard only: System Settings → Privacy & Security → Accessibility → add `safari-helper`.
5. Screenshot/PDF visual capture only: System Settings → Privacy & Security → Screen Recording → add the host app if prompted.

These approvals are one-time macOS security gates. ARES can detect and guide them, but should not attempt to click the permission dialogs.

## Verification command

```bash
python3 tools/safari-mcp-bootstrap/safari_mcp_bootstrap.py
```

If `safari_doctor` passes Apple Events / Automation, ARES can use the MCP tools to list tabs, read pages, and process Safari state without computer vision.

## Current Safari workflow

1. Use `safari-mcp` for live Safari state: tabs, pages, navigation, reading, forms.
2. Use direct Safari file parsing only when Full Disk Access is granted and needed for bookmark/Reading List database extraction.
3. Route extracted URLs into:
   - Ares Kanban for actionable tasks.
   - the user's selected knowledge base or notes directory for durable knowledge.
   - the cloned ARES repo only for shareable tooling/docs/examples.

## Why not rack PC?

Servers are correct for containerized/general MCP servers. Safari MCP is different: it controls the real Safari app and therefore must run locally on the Mac that owns Safari. It is lightweight and should not materially affect RAM/CPU.
