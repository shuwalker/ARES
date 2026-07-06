# Obsidian Cosmos — Build Session Brief

> **Session type:** Build + Marketing  
> **Project:** Obsidian Cosmos  
> **Goal:** Ship a working single-file HTML dashboard and create marketing assets for launch  
> **Date:** YYYY-MM-DD  
> **Author:** Sean Jenkins  
> **Session ID:** obsidian-cosmos-build-01

---

## Session Rules

1. Do not plan without building.
2. Every hour must produce either a code artifact or a marketing artifact.
3. Stop when the single-file dashboard renders the Spiral vault in both Solar System and Skill Tree themes.
4. Do not add a third theme until the first two are packaged.
5. Marketing assets are first-class deliverables, not afterthoughts.

---

## Development Track

### Working Directory
`projects/obsidian-cosmos/`

### Deliverables
- [ ] `cosmos.html` — single-file dashboard, no build step required for end user
- [ ] `vault-parser.js` — reads `*.md`, extracts frontmatter, wikilinks, tags
- [ ] `themes/solar-system.js` — folders as orbital rings, files as planets
- [ ] `themes/skill-tree.js` — folders as branches, files as skill nodes
- [ ] `theme-switcher.js` — UI for switching themes
- [ ] `obsidian-dashboard.json` — config schema
- [ ] `README.md` — 12-step “drop in and open” instructions

### Acceptance Tests
- [ ] Opens `daily/` from Spiral vault without errors
- [ ] Shows at least 50 nodes
- [ ] Wikilinks render as edges
- [ ] Theme switcher works without page reload
- [ ] File size under 500KB gzipped

---

## Marketing Track

### Working Directory
`projects/obsidian-cosmos/marketing/`

### Deliverables
- [ ] 5 screenshots:
  - Solar System theme on Spiral vault
  - Skill Tree theme on Spiral vault
  - Theme switcher UI
  - Config JSON example
  - Graph close-up with tags
- [ ] 1-page PDF: “Your Obsidian graph, but it looks like a video game”
- [ ] Gumroad listing draft with hook, screenshots, bundle contents
- [ ] Beta offer: 3 slots at $15 for 2-sentence testimonial

### Acceptance Tests
- [ ] Screenshots show both themes clearly
- [ ] PDF has one hook, one screenshot, one price
- [ ] Gumroad draft is complete enough to publish in 30 minutes

---

## Post-Docs Pipeline

1. **Provenance artifacts:** After docs finish, emit `PROVENANCE.json` with SHA256 fingerprints and file inventory for the entire project folder.
2. **Branding/ownership proof:** Maintain `spiral-integration.md` as the source-of-truth decision record and provenance note. It records:
   - standalone-first strategy,
   - planned Spiral/Ares fork integration,
   - GitHub release strategy,
   - signed-tag policy.
3. **GitHub release:** When code/documentation work is complete and verified, publish:
   - `gh repo create SeanJ07/obsidian-cosmos --public --source=. --remote=origin --push`
   - `gh release create v0.1.0-beta --verify-tag cosmos.html themes/ theme-switcher.js obsidian-dashboard.json README.md docs/ marketing/ PROVENANCE.json`
   - Attach screenshots to the release body in Markdown.
4. **Ownership signal:** Each public artifact should have ownership metadata available for dispute resolution:
   - GitHub timestamps + repo ownership
   - Gumroad receipt metadata
   - Local vault provenance notes in `PROJECT-BRIEF.md`

---

## Session Flow

1. **Hour 1-2:** scaffold `cosmos.html` + basic vault parser. Goal: HTML file that reads vault and shows a basic force-directed graph.
2. **Hour 3-4:** implement Solar System theme. Goal: orbital-ring layout with planet nodes.
3. **Hour 5-6:** implement Skill Tree theme. Goal: branch layout with skill-node styling.
4. **Hour 7:** theme switcher UI + `obsidian-dashboard.json` config.
5. **Hour 8:** package as single-file dashboard. Test on fresh clone.
6. **Hour 9:** record screenshots + write README.
7. **Hour 10:** 1-page PDF + Gumroad listing draft.
8. **Hour 11-12:** polish, fix bugs, finalize beta offer.

---

## Out of Scope

- Constellation theme
- RPG Map theme
- Custom CSS editor
- Obsidian plugin bridge
- Server-side rendering
- Auto-update from Obsidian live

These are Pro tier features. Ship Base tier first.

---

## Source Provenance

All code patterns and design decisions are derived from Spiral vault assets:
- `daily/` — graph structure and link density
- `RESTORE.md` — folder schema for orbital mapping
- `systems/repo-catalog.md` — vault inventory for demo dataset
- `archive/youtube-notes/` — visual design research

---

## Changelog

- 2026-07-05 — Session brief created by Sean Jenkins.
