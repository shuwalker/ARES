# Web UI Agent Guide

Read the repository [`AGENTS.md`](../../AGENTS.md) first.

## Scope

`apps/web/` is the only production Web UI. It is React + TypeScript + Vite and
is served from `apps/web/dist` by the controller. Do not create a second static
or framework-branded shell.

## Rules

- Route product ownership through `app-navigation.ts` and feature modules.
- Components consume ARES-owned contracts from `src/shared/`; translate raw
  backend payloads at the boundary.
- Preserve the six environments and standalone Settings utility described in
  `docs/PRODUCT_SPEC.md`.
- Settings must not duplicate Control Center controls.
- UI copy is user language. Put architecture explanations in documentation or
  progressive disclosure, not large instructional cards.
- A saved setting must either affect behavior or be labeled honestly as pending.
- Keep empty, loading, error, disconnected, and narrow-window states usable.

## Verification

```bash
npm run typecheck
npm test -- --run
npm run build
```

For SI Settings work, read
[`docs/features/si-personalization.md`](../../docs/features/si-personalization.md).
