# Architecture (current)

Canonical runtime and Companion/worker models for the running system.

| Document | Role |
|----------|------|
| [RUNTIME.md](RUNTIME.md) | **How the machine works** — processes, stores, chat path |
| [PRODUCT_SURFACES.md](PRODUCT_SURFACES.md) | UI domains (Companion, Self, Library, …) |
| [SYSTEM_BOUNDARIES.md](SYSTEM_BOUNDARIES.md) | What Companion owns vs workers |
| [WORKER_ADAPTER_CONTRACT.md](WORKER_ADAPTER_CONTRACT.md) | Worker adapter expectations |
| [MEMORY_AND_CONTEXT_MODEL.md](MEMORY_AND_CONTEXT_MODEL.md) | Memory / context packaging |
| [ORCHESTRATION_MODEL.md](ORCHESTRATION_MODEL.md) | Planning / multi-step work |
| [TRUST_AND_PRIVACY_MODEL.md](TRUST_AND_PRIVACY_MODEL.md) | Classification, eligibility, approvals |

Decisions (ADRs) live in [`../decisions/`](../decisions/).

Product naming and purpose: [`.claude/FOUNDATION.md`](../../.claude/FOUNDATION.md).

Historical audits: [`../archive/`](../archive/). Quarantine: [`../../TBR/`](../../TBR/).
