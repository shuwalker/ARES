# ARES Repository Agent Prompt

You are working inside the ARES repository: https://github.com/shuwalker/ARES.

## Current priority

Make the onboarding branch safe and usable for a public clone-first experience:

1. A fresh clone should include every required source directory, including `ARES-Modules/`.
2. WebUI first-run onboarding should guide users through backend setup, private-network/mobile access, MCP placement, workspace selection, and password/auth setup.
3. Public repo files must not hardcode Matthew-specific paths, hardware, IPs, tailnet names, private config, or credentials.
4. If the selected backend is missing, onboarding must give the install/docs link or let the user connect an existing backend URL.

## Licensing

- ARES is licensed under AGPL-3.0 with a commercial dual-license option. See `LICENSE` and `COMMERCIAL-LICENSE.md`.
- Upstream Hermes WebUI code inside `webui/` preserves its MIT notice in `webui/LICENSE`.
- Do not remove upstream copyright or license notices.
- Do not add code with license terms incompatible with AGPL distribution.
- Do not change the license model without explicit maintainer approval.

## Public repo privacy boundary

Never put private runtime values into public source, docs, prompts, tests, or defaults. Blockers include real personal paths, Tailscale IPs, hostnames, tailnet names, personal hardware requirements, `.hermes`, `.ares/config`, SOUL.md, auth files, API keys, tokens, and cookies.

Use placeholders, detected values, or user-selected paths instead.

## Required checks before saying ready

```bash
git diff --check
swift build
cd webui && ./scripts/test.sh tests/test_onboarding_static.py tests/test_ares_onboarding_public_portability.py tests/test_ares_provider_sync.py tests/test_jros_backend_streaming.py
```

Also run a changed-file privacy scan. Matches are acceptable only inside explicit regression-test forbidden-string lists.

## Development rules

- Keep the existing repo layout: `Sources/`, `ARES-Modules/`, `webui/`, `tools/`, `docs/`.
- Do not create new top-level folders without explicit approval.
- Do not modify Hermes Agent source inside `~/.hermes/hermes-agent/`; treat it as an external dependency.
- Preserve hot-reload behavior (`ARES_WEBUI_RELOAD=1`).
- Follow existing WebUI route/static/CSS patterns and existing Swift patterns.
- Write working, tested code; no stubs or placeholder behavior.
