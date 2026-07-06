# ARES MCP Bootstrap

ARES should help users wire useful MCP servers into their selected agent backend without making them understand every transport detail first. Hermes Agent is the default backend today, but onboarding must describe the backend generically and install it when missing.

This bootstrap separates MCP servers into two deployment classes:

1. **Local-only MCPs** — must run on the device that owns the app, browser, camera, serial device, or OS automation surface.
2. **Remote/server MCPs** — stateless/API/database/file-service tools that can run on a home server, NAS, rack PC, VPS, or other external machine and be reached over a private network/HTTP with auth.

## Why this exists

Every user's setup is different. ARES should inspect the current computer and guide the user to the right placement: keep app/device-bound automation on the owning machine, and move stateless or always-on services to a trusted server only when the user has one.

## Quick start

Show the catalog and deployment plan:

```bash
python3 tools/mcp-bootstrap/mcp_bootstrap.py --catalog --plan
```

Configure and verify the local Safari MCP server:

```bash
python3 tools/mcp-bootstrap/mcp_bootstrap.py --all
```

Configure a remote HTTP MCP server:

```bash
python3 tools/mcp-bootstrap/mcp_bootstrap.py \
  --configure-remote my-server \
  --url http://100.x.y.z:9000/mcp \
  --headers-json '{"Authorization":"Bearer CHANGE_ME"}'
```

## Current known servers

### `safari-mcp`

- Mode: **local-only**
- Runs on: Mac with Safari
- Why: requires real Safari, AppleScript, and a bundled Swift helper
- Hermes config: stdio via `npx safari-mcp`
- Detailed guide: `../safari-mcp-bootstrap/README.md`

### `filesystem`

- Mode: **local or remote**
- Runs on: any machine with Node
- Why: can expose a chosen directory over stdio or via a remote MCP gateway
- Warning: expose only the exact directory needed

### `time`

- Mode: **remote-preferred**
- Runs on: any server with `uvx`
- Why: stateless utility server; no reason to require GUI Mac resources

## Deployment rule

| Server type | Where to run | Example |
|---|---|---|
| App/browser/OS/device-bound | Local device that owns the app/device | Safari MCP on the user's Mac |
| API/database/stateless utility | Server/homelab/VPS/NAS | Time, databases, search, internal APIs |
| File service | Wherever the files live | NAS/rack for shared files, local for local-only files |

## Hermes config model

Local stdio MCP:

```yaml
mcp:
  servers:
    safari-mcp:
      command: npx
      args:
        - safari-mcp
      env:
        SAFARI_MCP_BACKGROUND: true
```

Remote HTTP MCP:

```yaml
mcp:
  servers:
    my-server:
      url: http://100.x.y.z:9000/mcp
      headers:
        Authorization: Bearer CHANGE_ME
```

After changing MCP config, restart Hermes or use `/reload-mcp` when available.

## Security defaults

- Prefer Tailscale/private network URLs over public Internet exposure.
- Use auth headers for remote HTTP MCP servers.
- Never expose broad filesystem roots like `/`, `$HOME`, or an entire NAS unless the user explicitly understands the risk.
- Keep browser/app automation local when it depends on user sessions, cookies, app permissions, or physical hardware.

## Viewer-facing setup flow

For ARES installers:

1. Install Hermes/ARES.
2. Run this bootstrap with `--catalog --plan`.
3. Install local-only MCPs on the correct local machine.
4. Install remote-capable MCPs on the user's server/homelab/VPS/NAS.
5. Add remote URLs to the selected backend config.
6. Restart Hermes and verify tools appear.

This gives ARES a repeatable onboarding path for MCPs without requiring every user to already understand MCP internals.
