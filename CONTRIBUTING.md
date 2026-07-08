# Contributing to ARES

Thank you for your interest in contributing to ARES.

## Code of conduct

Be respectful, direct, and focused on building a high-quality open-source UI/control layer for Hermes Agent, JROS, and the larger ARES companion roadmap.

## Licensing

ARES is licensed under AGPL-3.0 with a commercial dual-license option. See `LICENSE` and `COMMERCIAL-LICENSE.md`.

ARES also contains upstream Hermes WebUI code under `webui/`; that component preserves its original MIT notice in `webui/LICENSE`. Do not remove upstream copyright or license notices.

By contributing to ARES, you agree that your contribution is compatible with the repository's AGPL distribution model.

## Development philosophy

- Build for public clone-first installability, not one person's local machine.
- Make onboarding clear for non-expert users.
- Keep private runtime details out of public code and docs.
- Prefer working, verified implementation over plans or stubs.

## Before you start

1. Read `CLAUDE.md`.
2. Read `AGENTS.md`.
3. Read `README.md`.
4. If working in WebUI, read the relevant files under `webui/` and run focused tests through `webui/scripts/test.sh`.

## Contribution process

1. Fork the repository and create a focused branch.
2. Make focused, well-tested changes.
3. Update docs when behavior changes.
4. Open a pull request with a clear summary and test plan.

## Code standards

- Follow existing patterns in the codebase.
- New user-facing setup behavior must be real and verified.
- New API endpoints must include authentication and owner-scope checks.
- Preserve hot-reload behavior (`ARES_WEBUI_RELOAD=1`).
- Do not modify Hermes Agent source code under `~/.hermes/hermes-agent/`.

## Public privacy boundary

Never commit Matthew-specific private runtime values: real paths, IPs, hostnames, tailnet names, hardware assumptions, tokens, API keys, cookies, `.hermes`, `.ares/config`, or SOUL.md.

Use placeholders, detected values, or user-selected paths.

## Verification

Before proposing a commit, run the relevant checks and report exact output:

```bash
git diff --check
swift build
cd webui && ./scripts/test.sh tests/test_onboarding_static.py tests/test_ares_onboarding_public_portability.py tests/test_ares_provider_sync.py tests/test_jros_backend_streaming.py
```

## Upstream / Contract Routing

For contract-affecting PR or Contract Change proposals that impact the core API surface, we follow the Contract Routing protocol. These changes are reviewed and bundled together in a release batch.
