# TBR — To Be Reviewed

`TBR/` is a tracked quarantine area for files that should leave the active
source or current documentation tree but must not be deleted.

TBR means **To Be Reviewed**, not “safe to delete.”

## Required layout

```text
TBR/<YYYYMMDD>-<batch-name>/<original/path>
```

Keeping the original relative path makes provenance and restoration obvious.

## Rules

1. Use `git mv`; never copy-and-delete.
2. Add one row to `TBR/MANIFEST.tsv` for every moved path.
3. Preserve file contents, copyright, license, and upstream provenance.
4. Verify that active builds, imports, routes, plugins, tools, tests, packaging,
   installers, and current docs do not depend on the path.
5. Do not place secrets, user data, runtime state, databases, generated
   dependencies, caches, build output, or application bundles here.
6. Do not edit quarantined content to make it look historically consistent.
   Add classification notes to the manifest instead.
7. Restoration must be possible with an inverse `git mv`.
8. Actual deletion requires a separate, explicit human-approved task after
   review. No reorganization task may delete TBR content.

## Status values

- `quarantined`
- `restored`
- `reviewed_keep`
- `approved_for_future_removal`

The last status is still not permission for an agent to delete the file.
