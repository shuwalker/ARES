# Upstream sync — 2026-07-12

First full synchronization of `webui/` with upstream
[hermes-webui](https://github.com/nesquena/hermes-webui) since the `webui/`
baseline was cut on 2026-07-01. Brings in ~338 upstream commits
(through the `exp-v0.52.47` era).

## Why this was harder than it should have been

`webui/` was created as a snapshot of the app on **Jul 1**, but the repo's
git merge-base with upstream was **Jul 7** (the root tree kept receiving
upstream merges for a week after the snapshot). A subtree 3-way merge
against that base silently **drops** anything upstream added Jul 1–7 that
upstream hasn't touched since — it looks like an intentional deletion on
our side. That dropped ~250 files (tests, helpers, `api/` modules) and
in-file regions (`apply_cors_preflight_headers` in `api/routes.py`) on the
first pass.

**Repair strategy** (what actually shipped):

1. Subtree merge `upstream/master` (`-X subtree=webui`) — 143 files
   auto-merged, 39 conflicted, resolved by policy below.
2. **Bulk truth-sync**: every file ARES never touched was overwritten with
   upstream's current version outright (197 updated, 250 restored).
3. **Delta re-application**: for the ~40 files ARES *did* modify, ARES's
   true delta (Jul-1 snapshot → pre-merge) was re-applied via `git apply
   --3way` onto upstream's latest; the 13 that conflicted were resolved by
   hand.

## Conflict-resolution policy

Upstream's fix + ARES's feature, concretely:

- `api/routes.py` — upstream's profile-config cache, request diagnostics,
  custom-provider repair, MoA fast-path; ARES's
  `_filter_model_catalog_for_active_ares_backend` re-wrapped around the
  models endpoints; Monarch/characters/JROS routes intact.
- `api/updates.py` — upstream's update channels + git-lock recovery; ARES's
  owning-repo discovery (`_find_owning_git_repo`), JROS update target, and
  version-file fallback kept on top.
- `static/index.html` — ARES rail (Finance tab), backend/persona dropdowns,
  "Message ARES…" composer kept; upstream's update-lock button,
  stale-client banner, i18n/a11y attributes taken.
- `static/i18n.js` — merged key-wise: ARES-reworded strings win on key
  collisions, all new upstream keys added (all locales).
- `static/panels.js` — ARES backend-selector section + JROS update surfaces
  kept; upstream profile-switch session browser + manual-update note taken.
  Provider panel filter is the union: `…||p.is_self_hosted||p.has_key`.
- **Storage keys standardized back on upstream's `hermes-webui-*` names.**
  The partial `ares-webui-*` rename lived only in `boot.js` while
  `sessions.js`/`messages.js`/`ui.js` still used the hermes names — session
  and model restore were genuinely broken. `ares-identity.js` now migrates
  any values saved under the short-lived `ares-*` names back.
- `webui/docs/` restored (the "strip upstream docs" pass had deleted files
  the test suite asserts on).

## ARES-Desktop vs hermes-desktop

`ARESCore` was copied from hermes-desktop on 2026-06-05. hermes-desktop's
default branch has had **no commits since 2026-05-23 (v0.9.1)** — the copy
already contains every released upstream fix. Nothing to port. (Post-copy
work upstream exists only on unreleased feature branches, e.g. mobile.)

## Making the next sync cheap (recommendation)

ARES's delta over upstream today is ~161 files, but the hot, conflict-prone
set is small and stable:

| File | Why it conflicts |
|---|---|
| `api/routes.py` | ARES wraps/adds endpoints inline |
| `static/index.html` | ARES adds rail buttons + dropdowns inline |
| `static/panels.js` | ARES backend selector lives inline |
| `static/i18n.js` | ARES rewords upstream string values |
| `api/updates.py` | ARES adds a JROS update target inline |
| `static/boot.js` | (was) storage-key rename — now resolved |

Everything else ARES owns is **new, isolated files** (`api/ares_*.py`,
`api/jros_*.py`, `api/monarch*.py`, `api/characters.py`,
`static/finance.*`, `static/characters.*`, `static/ares-identity.js`) —
those never conflict. The way to shrink the table above to near-zero:

1. **routes.py**: add one ARES hook module (`api/ares_routes.py`) that
   routes.py calls at a single registration point; move the catalog filter
   and route wiring there. One-line diff against upstream forever.
2. **index.html**: inject ARES rail buttons/dropdowns from JS
   (`ares-identity.js` already loads on every page) instead of editing the
   HTML inline.
3. **i18n.js**: keep an `ares-i18n-overrides.js` applied after load rather
   than editing upstream's string table.
4. **Never rename upstream's persisted keys or public function names** —
   rebrand at the display layer only.

Do this refactor *after* the current release ships; it's mechanical and
low-risk but touches the hot files one more time.

## Verification

- `python -m compileall` over `api/ server.py bootstrap.py mcp_server.py
  scripts tests` — clean.
- `node --check` over every `static/*.js` — clean.
- Full suite: see FORK_CHANGES.md entry for final counts (baseline before
  sync: 11,439 passed / 36 failed — the 36 were pre-existing failures on
  main, most caused by the split storage keys and stripped docs this sync
  fixes).
