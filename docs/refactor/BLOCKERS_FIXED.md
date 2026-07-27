# Migration blockers — fixed

## 1. Credential ignore rules

`.gitignore` now ignores controller runtime secrets under the **new** paths:

- `services/controller/.pbkdf2_key`
- `services/controller/.signing_key`
- `services/controller/.login_attempts.json`
- plus `**/.pbkdf2_key`, `**/.signing_key`, `**/.login_attempts.json`
- venv/node_modules/state under `services/controller/` and `apps/web/`

Legacy `webui/` ignore rules retained for old checkouts.

Verified: `git check-ignore` hits those files; they are not staged.

## 2. Compatibility shims tracked

Untracked shims under `services/controller/api/` (and `core/` / `integrations/` package markers) are **`git add`ed** so a commit of the renames cannot omit them.

## 3. Operational path repairs

| Location | Fix |
|----------|-----|
| `services/controller/scripts/install.sh` | Validates `services/controller` + `apps/web`; rsync excludes updated |
| `services/observer/com.ares.observer.plist` | Paths → `services/observer/` |
| `.github/workflows/tests.yml` | `python scripts/si_doctor.py` (controller cwd) |
| `services/controller/scripts/si_doctor.py` | Restored from TBR; monorepo `sys.path` |
| `INSTALL.md` / `README.md` / `CONTRIBUTING.md` | No longer instruct `cd webui` as source of truth |

## 4. TBR policy

`FOLDER_STRUCTURE.md` and `ROOT_FIRST_PRINCIPLES.md` no longer say agents may delete TBR after verification. Deletion requires **explicit human approval** (`TBR/README.md` rule 8).

## 5. Onboarding contract test

`onboarding-profile.test.ts` matches the eight-step flow including Jaeger Character/Model.

## Verification run

- ownership check: pass
- shim imports: pass
- onboarding + navigation vitest: pass
- focused SI/context/journal tests: 57 passed
