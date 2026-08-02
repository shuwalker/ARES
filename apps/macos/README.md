# ARES Desktop

ARES Desktop is the native macOS owner of the local ARES application lifecycle.
It presents native product surfaces, starts the local controller, manages the
menu bar and global shortcut, and exposes effective device state to the shared
Web UI.

Read [`AGENTS.md`](AGENTS.md) and
[`../../docs/features/system-settings.md`](../../docs/features/system-settings.md)
before changing this boundary.

## Current contract

- ARES.app creates and supervises the controller on the configured ARES port.
- It refuses to adopt an unrelated or orphaned server already using that port.
- Each launch gives the app and controller a matching runtime instance ID.
- The native app writes a short-lived heartbeat and effective device settings.
- The controller stores desired settings and authenticated native commands.
- Safari/Web clients disable native controls when the app is unavailable.
- Closing the last window stops the controller when background operation is
  disabled; reopening ARES starts it again.

Jaeger AI, Hermes, Codex, Claude, and other workers remain external tools behind
ARES adapters. They do not own the ARES app, settings, identity, or controller
lifecycle. New code and UI use **Jaeger AI** and canonical `jaeger_local` names;
retired JROS names are accepted only at explicit migration boundaries.

## Build, test, and run

```bash
cd /path/to/ARES
swift test
./apps/macos/build-app.sh
open ./apps/macos/ARES.app
```

The development bundle discovers `services/controller/` from the monorepo and
uses its canonical `.venv`. The production packaging story must eventually
bundle or install that runtime explicitly; it must not silently attach to a
separately launched controller.
