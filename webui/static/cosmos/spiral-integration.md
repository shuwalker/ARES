# Spiral Fork — Future Integration Notes

> This note is a **future plan artifact**, not current scope.
> It documents how Obsidian Cosmos will eventually live inside the
> Spiral fork of Ares once the standalone product is selling.

## Why this exists

Obsidian Cosmos ships as a standalone `cosmos.html` first.
The reason is time-to-revenue:
a single file opens without install, screenshots cleanly,
and converts on Gumroad without asking buyers to trust a new binary.

Once Base/Pro tiers have real demand, the Spiral fork becomes the
premium container. The HTML renderer is browser-native; it fits
inside an Electron/Chromium `BrowserView` or a local WebView with
zero rewrites.

## Planned architecture

| Layer | Responsibility |
|---|---|
| `cosmos.html` | Renderer, parser, themes, theme switcher. Still usable standalone. |
| `ares-bridge.json` | Config schema that maps Ares settings to `obsidian-dashboard.json`. |
| `spiral-launcher.js` | Spawns a local app window that loads `cosmos.html` with injected Ares paths. |
| `spiral-dashboard.html` | Shell frame with sidebar, vault selector, update checker, branding. |

## Data flow

```
Ares fork launcher
  ↓ reads
ares-bridge.json
  ↓ injects
obsidian-dashboard.json overrides
  ↓ opens
BrowserWindow / WebView → file:///.../cosmos.html
```

## Config mapping

```json
{
  "vaultPath": "${SPIRAL_VAULTS}/SprialSecondBrain",
  "theme": "solar-system",
  "launcher": {
    "windowMode": "chromium-browser-view",
    "brandColor": "#4d96ff",
    "showHeader": true
  }
}
```

## Provenance / brand guardrails

- The renderer stays MIT-0 or commercial license; the fork wrapper stays Spiral-proprietary.
- Cosmos keep its own release cadence. The fork only tracks stable tags.
- White-label tier = Spiral fork with buyer branding injected via `ares-bridge.json`.

## Migration checklist (future)

- [ ] Buyer has Base tier unlocked.
- [ ] Buyer opts into Spiral fork beta.
- [ ] `spiral-launcher.js` loads `cosmos.html` from bundled assets.
- [ ] Ares sidebar exposes “Open Cosmos” action.
- [ ] Vault paths come from Ares config, not manual selection.
- [ ] Theme switcher syncs with Ares theme manager.

## Decision record

- **Date:** 2026-07-05
- **Decision:** Standalone HTML first. Ares fork integration after proven demand.
- **Rationale:** Faster ship, lower ops burden, clearer attribution.
