# Hermes Workspace UI Components (Drained)

Source: `hermes-workspace` — Full web workspace for Hermes Agent (TypeScript/React)

## What was drained

UI components, hooks, stores, and library utilities that ARES WebUI did not already have. These are organized into subdirectories mirroring the original project structure:

### Components (this directory)
- **Agent chat/swarm/view** — `agent-chat/`, `agent-swarm/`, `agent-view/`, `agent-avatar.tsx`, `agent-card.tsx`, `orchestrator-avatar.tsx`
- **Chat panel** — `chat-panel.tsx`, `chat-panel-toggle.tsx`, `prompt-kit/`
- **Mobile** — `mobile-hamburger-menu.tsx`, `mobile-page-header.tsx`, `mobile-prompt/`, `mobile-sessions-panel.tsx`, `mobile-tab-bar.tsx`
- **Settings & modes** — `settings/`, `settings-dialog/`, `mode-selector.tsx`, `manage-modes-modal.tsx`, `rename-mode-dialog.tsx`, `save-mode-dialog.tsx`
- **Terminal** — `terminal/`, `terminal-panel.tsx`, `terminal-shortcut-listener.tsx`
- **Auth** — `auth/`
- **Connection/status** — `connection-overlay.tsx`, `connection-startup-screen.tsx`, `backend-unavailable-state.tsx`, `claude-health-banner.tsx`, `claude-reconnect-banner.tsx`, `status-indicator.tsx`, `system-metrics-footer.tsx`
- **Search** — `search/`
- **Cron** — `cron-manager/`
- **Memory** — `memory-viewer/`
- **Inspector** — `inspector/`
- **File explorer** — `file-explorer/`
- **Onboarding** — `onboarding/`
- **Misc** — `command-palette.tsx`, `context-meter.tsx`, `error-boundary.tsx`, `error-toast.tsx`, `export-menu.tsx`, `workflow-help-modal.tsx`, `workspace-shell.tsx`, and others

### Hooks (`../../hooks/drained/hermes-workspace/`)
31 React hooks for agent behaviors, chat streaming, gateway capabilities, voice input, mobile UX, etc.

### Stores (`../../stores/drained/hermes-workspace/`)
8 state stores: agent-swarm, chat-activity, chat, mission, session-model, task, terminal-panel, workspace.

### Lib (`../../lib/drained/hermes-workspace/`)
29 utility modules: gateway API, model info, provider catalog, feature gates, i18n, theme, workspace agents, etc.

## Stripped
- Test files (`*.test.tsx`, `*.test.ts`)
- `node_modules/`, build artifacts, Docker configs, CI configs
- Desktop Electron wrappers, Dockerfiles, lock files

## Integration notes
These components use Hermes-specific imports and APIs. Adapt import paths and API clients to ARES conventions when integrating.