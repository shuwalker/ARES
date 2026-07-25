# ARES Verification Guide

## Frontend gate

```bash
cd webui/frontend
npm ci
npm run typecheck
npm test
npm run build
```

Vitest covers normalized response translation, standalone defaults, and SSE
event translation. Add component or browser coverage for new interaction flows.

## Python gate

Use the supported repository virtual environment:

```bash
cd webui
.venv/bin/python -m pytest tests/
```

Python tests cover API, authentication, persistence, streaming, workspace,
terminal, provider, and serving contracts. The retired Vanilla frontend's
source-scanning tests are not architectural requirements.

## Production smoke test

Build React, start the repository server on an isolated port, and verify:

- `/today` returns the React shell;
- hashed JS and CSS assets return 200 with immutable caching;
- `/health`, `/api/settings`, `/api/sessions`, and `/api/workspaces` return JSON;
- unknown `/api/` paths remain JSON 404s;
- `/static/ui.js` is not served;
- a missing `frontend/dist/index.html` yields a frontend 404;
- a headless browser renders Today and reports controller availability.

Do not replace the user's installed `~/.ares` WebUI during repository smoke
tests.
