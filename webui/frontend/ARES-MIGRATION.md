# ARES React Frontend Migration

This directory was staged from the Paperclip React/Vite UI as the starting
point for the ARES frontend migration.

- Source repository: `/Users/matthewjenkins/GitHub/paperclip`
- Source directory: `ui/`
- Source commit: `2617bee422b4fc3c0be5b44636ad5071e30f5546`
- Source license: MIT; retained in `PAPERCLIP-LICENSE`

The initial copy intentionally excludes dependency and generated directories:
`node_modules/`, `dist/`, `storybook-static/`, `.vite/`, TypeScript build-info
files, and `.DS_Store`.

## Migration result

All five migration steps are complete. The imported feature graph was reduced to reusable
React/Vite and design-system primitives. The compiled application now uses
ARES-owned pages and contracts, contains no workspace package dependencies, and
boots without a model runtime. Corporate product concepts and backend adapters
are not part of the compiled source.

The Python server serves only the compiled React application and implements SPA
routing without swallowing API misses. A missing production build returns a
clear 404 instead of loading a second frontend. `ARES_VITE_DEV=1` explicitly enables the local Vite
development proxy. The React application now reads controller health, settings,
sessions, workspaces, runtime health, and MCP inventory through a typed adapter.
Conversation creation and responses use the existing session and chat endpoints,
including SSE streaming; Workspace and Terminal use the existing controller
contracts. Backend-specific response shapes remain confined to translators, and
missing runtimes are represented as unavailable capabilities instead of page
failures. The retired `webui/static/` application and its routing fallbacks have
been removed. Login support, public shares, public assets, the web manifest, and
the one-release service-worker cache retirement path are owned by the React
frontend.
