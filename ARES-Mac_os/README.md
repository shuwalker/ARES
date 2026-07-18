# ARES Desktop

ARES Desktop is the native macOS control shell for the ARES Web UI and adapter
layer. It launches or attaches to the local Web UI, presents it in a `WKWebView`,
and provides native settings, menu bar status, server control, remote access,
runtime status, and approval surfaces.

## Current Surface

- SwiftUI macOS app launched with `swift run ARES`.
- Main window wraps the Web UI at the configured host and port.
- Menu bar item opens ARES, starts/stops/restarts the Web UI server, opens
  settings, and quits the app.
- Settings expose:
  - Web UI host, port, auto-launch, and reload/dev mode.
  - Server health and recent logs.
  - Active backend selector for Hermes, JROS, and hybrid mode.
  - Hermes and JROS gateway URL/key fields.
  - LAN and Tailscale URLs with QR code for phone/tablet access.
  - Browser microphone constraints for remote HTTP access.
  - Pending approvals and recent audit log entries.

## Responsibility Boundary

ARES Desktop does not replace Hermes, JROS, or the Web UI. It is a native
presentation and control layer over those systems:

- Hermes owns Hermes runtime state.
- JROS owns JROS runtime, embodiment, and canonical character/persona state.
- ARES projects active runtime identity and owns user-facing presentation,
  permissions, settings, server control, and continuity surfaces.

## Build And Run

```bash
cd ~/GitHub/ARES
swift build
swift run ARES
```

The app starts the Web UI automatically when `Start WebUI Server on App Launch`
is enabled. Server launch exports the native Hermes/JROS gateway settings into
the Web UI process environment.

## Archived Notes

Older experimental desktop plans that do not describe the current app have been
moved out of the repo to:

```text
/Users/matthewjenkins/Desktop/ARES-misaligned-archive/
```
