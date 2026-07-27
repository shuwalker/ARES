# Glassmorphism shell — design notes

**Status:** Live UI design notes for the island backdrop / glass shell in
`apps/web`. Not a product roadmap and not a claim that the product is unfinished.
Referenced by `apps/web` source comments and token tests.

Branch (historical): `feat/glassmorphism-gui`

Describes the "island backdrop" design — a full-viewport island wallpaper with the
shell rendered as translucent glass over it — for the React frontend.

## Where the original went

The design was built against `webui/static/`, the vanilla-JS UI deleted from
`main` in `bf319ddd` (2026-07-17) when the React frontend became the only web app.
Its source was never committed on any branch; it survived only in `stash@{0}`
(`8334be36`). It is now preserved at
[TBR/20260726-existing-attic/attic/island-backdrop-legacy/](../../TBR/20260726-existing-attic/attic/island-backdrop-legacy/),
including the author's reference screenshot.

The wallpaper itself was never lost: `apps/web/public/assets/ares-island-wide.png`
is tracked and is byte-identical to the source Gemini render.

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

### Phase 2 — convert hardcoded surfaces ✅ done

Every surface the shell paints now reads from a token. Converted
`CommandCenterShell.tsx`, `ControlDeck.tsx`, `Markdown.tsx`, and
`ResizeHandle.tsx`; accent, status, and text colours stay literal, since only
surfaces need translucency and converting text would have touched 300+ usages
for no benefit.

Values are byte-identical to what was inline. Mapping them onto the existing
`--card` / `--background` scale was rejected: that scale is cool (oklch hue 255,
`--card` = `#13181e`) while the shell is warm-neutral (`#151614`), so unifying
them recolours the entire workbench. `shell-tokens.test.ts` pins the values.

Two structural fixes were needed beyond the mechanical swap:

- **Inline styles.** `ConversationPage.tsx` and `WorkbenchPane.tsx` held their
  palettes in JS objects applied via `style={{...}}`, which no stylesheet can
  override. Their `bg`/`surface` entries now read `var(--chat-bg)` and friends.
- **Compound opacity.** Nested translucent wrappers multiply — 42% over 42%
  reads as 66%, a third layer as 80%, which buried the wallpaper. Each region
  now tints exactly once: `--shell-root` and `--chat-bg` drop to `transparent`
  under the backdrop because a tinted pane already covers them. Verified by
  walking the ancestor chain at three points; all three report a single layer.

### Phase 3 — depth pass ✅ mostly done

- Blur moved off `backdrop-filter` entirely. It was silently dead: esbuild
  lowered it to the `-webkit-` alias, which computed to nothing, so the
  wallpaper rendered razor sharp. It is now a plain `filter` on the wallpaper
  layer — visually identical (that layer is the only thing behind the shell),
  cheaper to composite, and immune to stacking-context surprises.
- A scrim over the wallpaper keeps text legible regardless of which image is
  set. Without it the bright sunset sky washed out body copy completely.
- Still open from the legacy engine: the floating composer pill (`border-radius:
  16px`, lifted shadow) and removal of hard dividers under panel heads.

### Phase 4 — parity and remaining work

- **Light theme.** `:root` and `.dark` are identical today, so the shell is
  effectively dark-only. Light-mode glass needs its own fill values — the legacy
  engine used `rgba(255,255,255,0.45)` on cards, worth reusing.
- **Native macOS shell.** The WKWebView host should agree with the web shell so
  the wallpaper is not clipped by native chrome.
- **The Hermes palettes.** `ConversationPage.tsx` and `WorkbenchPane.tsx` are
  commented "Hermes-matching dark blue palette" and are genuinely cooler than
  the rest of the shell. Now that they are tokens, reconciling them with the
  ARES scale is a contained change — but it is a design decision, not a
  refactor.

## Constraints

- **One blur pass only.** The legacy header calls out "nested `backdrop-filter`
  blur glitches" and "double-blur box outlines" as the bugs it existed to fix.
  Blur is applied once, at `#root`. Do not add `backdrop-filter` to panes.
- **`--popover` stays opaque.** Dropdowns and command menus float over arbitrary
  content; translucent ones are unreadable.
- **Honour `prefers-reduced-transparency`.** The wallpaper stays, translucency
  and blur drop out.
