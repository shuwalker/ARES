# Extensions

ARES loads extensions from a trusted local extension directory. Extension code runs in the WebUI browser origin, so only install extensions you trust.

Extension settings use browser-local controls through `window.HermesExtensionSettings`. Settings persist only non-default overrides. The server does not store extension settings or expose a generic settings write route.

## Diagnostics

Open **Settings → Extensions** to inspect the configured directory, loaded manifest, assets, warnings, and sanitized loopback sidecars returned by `GET /api/extensions/status`.

The panel can use `POST /api/extensions/toggle` to save a WebUI-managed override. This does not edit extension manifests, fetch new extension assets, uninstall files, or proxy sidecars. Sidecar checks run in the browser with `credentials: 'omit'`; ARES does **not** proxy sidecar requests.

A manifest can declare an optional top-level `runtime` object. Only allowlisted scalar fields are returned. These are browser-local controls and do **not** return `HERMES_WEBUI_EXTENSION_DIR` or the override state-file path.
