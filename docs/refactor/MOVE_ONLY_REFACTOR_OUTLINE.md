# Move-only repository reorganization

## Objective

Reorganize working ARES source into the protocol-droid tree. Preserve every
tracked file. Material leaving the active product tree goes to `TBR/`.

This is **not** a rewrite. Capabilities stay operational while paths change.

## Target root (authoritative)

```text
apps/macos/          apps/web/
services/controller/ services/observer/
core/{events,identity,memory,knowledge,orchestration,authority}/
integrations/{workers,tools,sensors,providers}/
docs/{product,architecture,decisions,guides,archive,refactor}/
TBR/
```

## Move-only rules

Allowed: `git mv`, path/import/build/docs-link repairs, temporary compatibility
bridges, TBR quarantine, tests moving with their code.

Not allowed: logic rewrites, schema/API renames for aesthetics, deleting files,
empty-folder “structure,” consolidating duplicate implementations (later pass).

## Passes

0. Baseline + remove empty husks/skeletons; process docs match this target.
1. Root renames: Mac, web UI, controller, observer (done or in progress).
2. Fill `core/` and `integrations/` by moving real modules.
3. Docs authority: one product definition, one runtime spec; rest archive/TBR.
4. Remove temporary compatibility bridges → TBR.
5. Later: consolidate duplicate memory/journal/voice (behavior change; separate).

## Verification every batch

- No tracked content deleted
- MOVE_MAP + TBR MANIFEST updated
- Pure moves retain content hash
- Relevant tests/builds pass
- Inverse rollback map = reverse of MOVE_MAP rows

## Framing

The repository is working source material. Do not describe it as undeveloped
because of stale phase/status prose. Stale prose goes to archive or TBR.
