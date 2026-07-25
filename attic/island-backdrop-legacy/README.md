# Island backdrop — legacy source (recovered)

Recovered on 2026-07-25 from `stash@{0}` (`8334be36`, *"untracked files on main:
a71910da"*, labeled `review-backup-before-ares-cleanup-2026-07-25`). These files
were **never committed on any branch** — `git log --all --diff-filter=A` for
`custom_backgrounds.css` and `background_manager.js` returns nothing. They are
preserved here so the design no longer depends on a single local stash entry.

## What this was

The "ARES Clean Glassmorphism Island Backdrop Engine": a full-viewport wallpaper
using `ares-island-wide.png`, with every shell surface rendered as translucent
glass over it. `island_backdrop_proof.png` is the author's screenshot of it
running.

| File | Role |
|---|---|
| `custom_backgrounds.css` | The backdrop engine — wallpaper layer, glass surfaces, position modes |
| `background_manager.js` | localStorage preference manager (`ares-island-backdrop`) |
| `test_island_backdrop_static.py` | Static assertions against the legacy markup |
| `island_backdrop_proof.png` | Reference screenshot of the intended result |

## Why it is attic and not live code

It targets `webui/static/` — the legacy vanilla-JS UI deleted from `main` in
`bf319ddd` (2026-07-17) when the React frontend became the only web app. Every
selector (`.sidebar`, `.rail`, `#mainChat`, `.composer-box`, `.layout`) refers to
markup that no longer exists, and the settings controls assume server-rendered
`index.html` checkboxes.

The live port is `webui/frontend/src/styles/island-backdrop.css`, which reaches
the same result through the React frontend's design tokens rather than through
per-selector `!important` overrides. Keep these files as the **visual reference**
for opacity values, blur radius, and layering intent — not as code to restore.
