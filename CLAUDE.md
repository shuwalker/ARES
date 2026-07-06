# CLAUDE.md — ARES Repository Rules for AI Agents

This file defines mandatory rules for AI agents working in the ARES repository.

## Licensing

- ARES is licensed under AGPL-3.0 with a commercial dual-license option. See `LICENSE` and `COMMERCIAL-LICENSE.md`.
- Upstream Hermes WebUI code in `webui/` preserves its MIT notice in `webui/LICENSE`.
- Do not remove upstream copyright or license notices.
- Do not introduce code with terms incompatible with AGPL distribution.
- Do not change the license model without explicit maintainer approval.

## Project focus

ARES is being made installable and functional for people who clone the public repo. The current priority is production-grade onboarding, backend setup guidance, and clean public documentation.

## Public repo privacy boundary

Public repo code/docs must not contain Matthew-specific runtime values: personal paths, real Tailscale IPs/hostnames/tailnet names, personal hardware requirements, `.hermes`, `.ares/config`, SOUL.md, auth files, tokens, API keys, cookies, or live profile assumptions.

Use placeholders, detected values, or user-selected paths.

## Repository structure rules

Keep the existing layout:

- `Sources/` — Swift native app
- `ARES-Modules/` — local Swift package required by `Package.swift`
- `webui/` — Python web server and frontend
- `tools/` — standalone utilities
- `docs/` — documentation and assets

Do not create new top-level directories without explicit approval. Do not modify Hermes Agent source code under `~/.hermes/hermes-agent/`.

## Code quality standards

- Write production-quality, tested code.
- No stubs or placeholder implementations for user-facing setup paths.
- Follow existing patterns in `webui/api/`, `webui/static/`, and `Sources/ARES/`.
- New API endpoints must include proper authentication/owner-scope checks.
- Preserve hot-reload behavior (`ARES_WEBUI_RELOAD=1`).

## Before proposing any commit

```bash
git diff --check
swift build
cd webui && ./scripts/test.sh tests/test_onboarding_static.py tests/test_ares_onboarding_public_portability.py tests/test_ares_provider_sync.py tests/test_jros_backend_streaming.py
```

Also run a privacy leak scan on changed public files. Any Matthew-specific match outside an explicit regression-test forbidden-string list is a blocker.
