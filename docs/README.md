# ARES Repository Documentation

| Attribute | Details |
| :--- | :--- |
| **Status** | Active / Canonical |
| **Audience** | Developers, System Architects, Maintainers, Operators |
| **Target Platform** | macOS, Linux/WSL, Web (React SPA) |

Welcome to the **ARES** engineering documentation repository. This directory contains the complete technical specifications, architectural designs, API reference guides, security policies, and developer manuals for the ARES platform.

---

## Standard Documentation Index

| File | Primary Focus |
| :--- | :--- |
| **[`ARCHITECTURE.md`](ARCHITECTURE.md)** | System architecture, process topology, component boundaries, decoupled state storage, and turn orchestration. |
| **[`DEVELOPMENT.md`](DEVELOPMENT.md)** | Developer & operator guide: local environment setup, native macOS shell, Web UI, Windows/Tauri app, Docker, WSL, and troubleshooting. |
| **[`SECURITY.md`](SECURITY.md)** | Data classification rules (`public` to `secret`), privacy boundaries, trust engine gates, credential handling, and local-only execution modes. |
| **[`API.md`](API.md)** | Complete API reference: REST routers (`/api/organizer/*`, `/api/chat/*`, `/api/ares/*`), SSE streaming protocol, and schemas. |
| **[`PRODUCT_SPEC.md`](PRODUCT_SPEC.md)** | Unified product vision, protocol-droid organizer capabilities, data models, and delivery roadmap. |

---

## Architectural Principles & Core Concepts

- **Platform Core (Assistant Controller)**: The primary Python FastAPI backend (`services/controller/`) that manages persistent user state, context assembly, task planning, and runtime routing.
- **AI Runtimes (Execution Engines)**: Pluggable AI model processes and external agents (Jaeger AI, Ollama, Claude Code, Hermes, and cloud LLMs) invoked as isolated subprocesses or API client bridges.
- **Persistent Event Log & Task Store**: SQLite database (`webui_state/`) storing user sessions, message history, and task records with Full-Text Search (FTS5).
- **Decoupled Read-Only State Pattern**: ARES writes exclusively to its own state storage. External AI runtime databases are accessed strictly in read-only mode (`?mode=ro`).

---

## Auxiliary Files

- **`.nojekyll`**: Standard static site deployment file used by GitHub Pages to disable automatic Jekyll build processing for markdown repositories.
