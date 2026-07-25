# ARES WebUI Frontend

This is the framework-independent React/Vite frontend for ARES. It owns the
navigation, presentation, Local Profile, and normalized frontend contracts. It
does not import model-runtime packages or assume an assistant is connected.

## Development

```sh
npm install
npm run dev
```

The Vite development server listens on `127.0.0.1:5173` and proxies `/api` and
WebSocket requests to the ARES Python server at `127.0.0.1:8787`.

To keep the normal ARES URL while developing, start Vite and run the Python
server with `ARES_VITE_DEV=1`. The Python server proxies frontend GET requests
to Vite while retaining all API, authentication, share, and extension routes
itself. If Vite is unavailable, it falls back to the production React build.

## Verification

```sh
npm run typecheck
npm test
npm run build
```

`npm run build` writes the production application to `dist/`. The Python server
serves that build and routes client-side navigation through its `index.html`.
If the build is absent, frontend navigation returns a clear 404 while API routes
remain available.

## Architecture

- `src/shared/contracts.ts` defines UI-owned normalized data shapes.
- `src/shared/ares-api.ts` maps those contracts to the existing Python API.
- `src/shared/translators.ts` isolates legacy response shapes from React components.
- `src/shared/chat-stream.ts` normalizes ARES Server-Sent Events.
- `src/shared/ares-context.tsx` owns shared controller, session, and connection state.
- `src/shared/local-profile.tsx` keeps the Local Profile usable without a runtime.
- `src/components/ui/` contains reusable design-system primitives.
- `src/pages/` contains ARES product routes using one work-unit term: Task.

Provider and framework integrations must adapt to these contracts through the
ARES API; they must not become imports of the UI package.
