# ARES documentation

This folder is organized by **authority**. Agents and humans should read current
documents first. Historical material is preserved, not mixed into the product definition.

## Current (read these)

| Role | Document |
|------|----------|
| **Product definition** | [`.claude/FOUNDATION.md`](../.claude/FOUNDATION.md) and [`product/product-vision.md`](product/product-vision.md) |
| **Runtime how-it-works** | [`architecture/RUNTIME.md`](architecture/RUNTIME.md) |
| **UI surfaces / IA** | [`architecture/PRODUCT_SURFACES.md`](architecture/PRODUCT_SURFACES.md) |
| **System boundaries** | [`architecture/SYSTEM_BOUNDARIES.md`](architecture/SYSTEM_BOUNDARIES.md) |
| **Worker contract** | [`architecture/WORKER_ADAPTER_CONTRACT.md`](architecture/WORKER_ADAPTER_CONTRACT.md) |
| **Memory & context** | [`architecture/MEMORY_AND_CONTEXT_MODEL.md`](architecture/MEMORY_AND_CONTEXT_MODEL.md) |
| **Orchestration** | [`architecture/ORCHESTRATION_MODEL.md`](architecture/ORCHESTRATION_MODEL.md) |
| **Trust & privacy** | [`architecture/TRUST_AND_PRIVACY_MODEL.md`](architecture/TRUST_AND_PRIVACY_MODEL.md) |
| **ADRs (why)** | [`decisions/`](decisions/) |
| **Source ownership** | [`product/source-ownership.md`](product/source-ownership.md) |
| **Operator guides** | [`guides/`](guides/) |

## Layout of this tree

```text
docs/
  product/         # what ARES is (product)
  architecture/    # how the machine works (current models)
  decisions/       # accepted ADRs
  guides/          # operator / how-to
  ui/              # live UI design notes referenced by code
  archive/         # historical audits, memos, sync logs
  refactor/        # move-only reorganization process only
```

## Not current product truth

| Location | Meaning |
|----------|---------|
| [`archive/`](archive/) | Point-in-time audits, design memos, sync history |
| [`../TBR/`](../TBR/) | Quarantine (stale status, conflicting proposals, retired source) |
| [`refactor/`](refactor/) | Reorganization process, not the product definition |

Do **not** treat phase checklists, “SI disabled” notes, or competing multi-agent
proposals as the current architecture. Those live under `TBR/` or `archive/`.

## Repository layout (code)

See [`refactor/FOLDER_STRUCTURE.md`](refactor/FOLDER_STRUCTURE.md):

```text
apps/macos   apps/web
services/controller   services/observer
core/   integrations/
```

## Naming (locked)

| Word | Meaning |
|------|---------|
| **ARES** | Application / repository package only |
| **Companion** | Everything that is not a worker — continuous SI relationship |
| **Workers** | Replaceable models, agents, tools, devices |
