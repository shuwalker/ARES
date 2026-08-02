# Contributing to ARES

Thank you for helping build ARES.

## Start with repository context

1. Read [`AGENTS.md`](AGENTS.md).
2. Read [`docs/CURRENT_STATE.md`](docs/CURRENT_STATE.md).
3. Use [`docs/README.md`](docs/README.md) to find the contract that owns your
   task.
4. Read the scoped `AGENTS.md` nearest to the code you will change.

`CLAUDE.md` and other tool-specific entrypoints intentionally route to the same
cross-agent context. Do not maintain separate product explanations for each
tool.

## Contribution principles

- Build for a public clone, not one developer's machine.
- Keep onboarding understandable to non-experts.
- Prefer working, verified behavior over stubs or implied functionality.
- Preserve the boundary between ARES-owned state and external workers.
- Never make one framework the product identity.
- Keep private runtime values, secrets, personal paths, and credentials out of
  source, documentation, logs, and fixtures.

## Process

1. Inspect `git status -sb` and preserve existing work.
2. Create a focused branch.
3. Identify the state owner, API/event/settings contract, and acceptance tests.
4. Make one coherent change and add proportionate tests.
5. Update the owning documentation in the same commit when behavior or a
   contract changes.
6. Run the relevant checks and report exact results.
7. Open a pull request describing scope, impact, verification, known gaps, and
   documentation impact.

## Documentation impact

A pull request must say whether it changes any of the following:

- Product behavior, language, tabs, or ownership
- Architecture, persistence, adapters, or events
- Routes, settings keys, schemas, or wire formats
- Permissions, secrets, privacy, or external actions
- Setup, CI, Docker, packaging, or runtime operation
- An accepted decision or feature acceptance criterion

If yes, update the document that owns the contract. Do not create a new document
when a canonical or feature document already owns the information.

For a durable boundary change, include **Contract Routing** and **Contract
Change** in the PR body and update the relevant decision record, docs, and tests
together.

## Code standards

- Follow established patterns in the scoped application or service.
- Authenticate and owner-scope new API endpoints.
- Normalize external runtime data before it enters product clients.
- Make user-facing setup and settings behavior real and verifiable.
- Do not modify another repository or a real worker home as part of an ARES
  change without explicit authorization and a separate branch.
- New Jaeger state uses `jaeger_local` and canonical `ARES_JAEGER_*` variables.

## Verification

Choose checks based on the affected surface:

```bash
git diff --check

cd apps/web
npm run typecheck
npm test -- --run
npm run build

cd ../..
swift test

cd services/controller
.venv/bin/python -m pytest -q tests/<relevant_test>.py
./scripts/test.sh
```

The full controller suite is large and has inherited reorganization debt. Read
`docs/CURRENT_STATE.md`, run focused tests while iterating, and never hide a
known broad-suite failure.

## Licensing

ARES is AGPL-3.0 with a commercial dual-license option. See `LICENSE` and
`COMMERCIAL-LICENSE.md`. Preserve applicable upstream notices.
