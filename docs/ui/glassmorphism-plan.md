# Glassmorphism shell — restoration plan

Branch: `feat/glassmorphism-gui`

Restores the "island backdrop" design — a full-viewport island wallpaper with the
shell rendered as translucent glass over it — to the React frontend.

## Where the original went

The design was built against `webui/static/`, the vanilla-JS UI deleted from
`main` in `bf319ddd` (2026-07-17) when the React frontend became the only web app.
Its source was never committed on any branch; it survived only in `stash@{0}`
(`8334be36`). It is now preserved at [attic/island-backdrop-legacy/](../../attic/island-backdrop-legacy/),
including the author's reference screenshot.

The wallpaper itself was never lost: `webui/frontend/public/assets/ares-island-wide.png`
is tracked on `main` and is byte-identical to the source Gemini render.

## Why this is a port, not a restore

The legacy engine drives ~40 hand-listed selectors (`.sidebar`, `.rail`,
`#mainChat`, `.composer-box`) with `!important`. None of that markup exists now.

The React frontend is token-driven — Tailwind v4 with oklch design tokens — so the
port reopens the **tokens** instead. Redefining `--card` under
`:root.island-backdrop` turns all 20 `bg-card` consumers to glass at once, with no
per-component edits and no specificity war. Token specificity `(0,2,0)` beats both
`:root` and `.dark` at `(0,1,0)`, so import order does not matter.

Keep the attic files as the reference for opacity, blur radius, and layering
intent. Do not restore them as code.

## Phases

### Phase 1 — token foundation ✅ done

Ships the effect behind an opt-in switch, with zero change to the default UI.

- `src/styles/island-backdrop.css` — wallpaper layer, translucent token
  overrides, one blur pass, position modes, reduced-transparency fallback.
- `src/island-backdrop.ts` — preference module. Reuses the legacy
  `ares-island-backdrop` localStorage key and settings shape so an existing
  preference still loads.
- Settings → Appearance → **Island backdrop**: enable, surface opacity, anchor.
- Applied in `main.tsx` before first paint so an enabled backdrop never flashes
  the opaque shell.

**Default is off.** Every rule is gated on `html.island-backdrop`; with the class
absent the file contributes no matching rules. `island-backdrop.test.ts` asserts
that default and fails if phase 2 flips it prematurely.

### Phase 2 — convert hardcoded surfaces (next)

The blocker for making this default-on. 62 surfaces use arbitrary Tailwind values
(`bg-[#151614]`, `bg-[#1b1c1a]`, `bg-[#111210]`, `border-[#343631]`) instead of
tokens, so they stay opaque while everything around them turns to glass. Worst
concentrations:

| File | Hardcoded backgrounds |
|---|---|
| `components/command-center/ControlDeck.tsx` | ~24 |
| `components/command-center/CommandCenterShell.tsx` | ~14 |

Work: map each hex to its nearest existing token, replace, confirm no visual
change with the backdrop **off** (this is a pure refactor in the default theme),
then confirm glass appears with it on. Do the shell before the deck — the shell
is the large-area surface that sells the effect.

### Phase 3 — depth pass

Once surfaces are translucent, tune what the legacy engine spent most of its
lines on: the floating composer pill (`border-radius: 16px`, lifted shadow),
removal of hard horizontal dividers under the titlebar and panel heads, and card
hover/focus states that brighten fill rather than adding a second blur.

### Phase 4 — parity and defaults

- Light theme: `:root` and `.dark` are currently identical, so the shell is
  effectively dark-only. Light-mode glass needs its own fill values — the legacy
  engine used `rgba(255,255,255,0.45)` on cards, worth reusing.
- Native macOS shell (`ARES-Mac_os`): the WKWebView host should agree with the
  web shell so the wallpaper is not clipped by native chrome.
- Flip the default to on, update `island-backdrop.test.ts`, and capture a
  proof screenshot to sit alongside the legacy one.

## Constraints

- **One blur pass only.** The legacy header calls out "nested `backdrop-filter`
  blur glitches" and "double-blur box outlines" as the bugs it existed to fix.
  Blur is applied once, at `#root`. Do not add `backdrop-filter` to panes.
- **`--popover` stays opaque.** Dropdowns and command menus float over arbitrary
  content; translucent ones are unreadable.
- **Honour `prefers-reduced-transparency`.** The wallpaper stays, translucency
  and blur drop out.
