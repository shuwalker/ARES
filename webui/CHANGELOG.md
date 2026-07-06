# ARES Web UI changelog

## Unreleased

- Added provider fallback chain sync — when you set up providers in Hermes config, ARES now automatically copies the `fallback_providers` chain to JROS config so both backends use the same fallback sequence. No more manual sync needed.
- Provider sync endpoint (`/api/ares/provider/sync`) now syncs both active provider AND fallback chain in one call.
- Settings → Providers tab now also shows providers that have a configured API key (even if not configurable via env var), fixing `ollama-local` being hidden despite having a key.
- Auto-sync: provider changes in Settings now automatically propagate to Hermes and JROS configs via `_sync_providers_on_settings_save()`.
- Fixed `_has_explicit_pool_credentials()` returning `True` for providers with stale credential pool entries (metadata-only placeholders with no actual key). Anthropic and similar providers with empty env-var refs now correctly report `has_key: false`.
- Cleaned up stale Anthropic credential pool entries (OAuth token + API key with no actual secrets).
- Fixed JROS path resolution: now finds the actual JROS install at `~/jaeger/jaeger_os/instance/default/config.yaml` (plus env var and `~/.jaeger/` fallbacks).
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
