# ARES Web UI changelog

## Unreleased

- Added the ARES first-run onboarding flow, private-network guidance, and local-versus-remote MCP placement.
- Added an Artifacts tab for files created or edited during a session.
- Session event reconnects now use bounded jitter/backoff.
- Expanded cron run rows now show full output and no longer drops content when Markdown rendering is unavailable.
- New conversations now resync the configured default model provider.
- Fixed #2211 so the workspace panel can reopen reliably.
- Fixed #3340 status messages for saved memory and created/updated a skill actions.
- Large plain-text pastes in the composer now become `.md` attachments.
- Large MCP tool inventories use 5-item default pages with a per-page selector up to 40 tools.
- PWA notifications now use the service worker (#3196).
- Notification permission controls now reflect the real browser state (#4118).
- The session action menu can regenerate conversation titles (#3106).

## [v0.51.103]

ARES is derived from Hermes Web UI. Earlier upstream history is available in the upstream project changelog.
