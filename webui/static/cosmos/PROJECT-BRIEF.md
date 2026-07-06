# Obsidian Cosmos — Project Brief

> **Status:** `In Build`  
> **Author:** Sean Jenkins  
> **Created:** 2026-07-05  
> **Last updated:** 2026-07-05  
> **Vault version:** SpiralSecondBrain  
> **Estimated build time:** 8–12 hrs / 2 calendar days  
> **Target price:** $29–$59  
> **Linked source:** `RESTORE.md`, `RESTORE-oauth.md`, `daily/`, `systems/repo-catalog.md`, `archive/youtube-notes/`

---

## What It Is

Obsidian Cosmos is a local-only HTML dashboard that reads a user’s Obsidian vault and renders it as a visual system — solar system, skill tree, constellation map, etc. Files become nodes; wikilinks become orbits/edges; tags become color-coded clusters. The deliverable is a single HTML file the buyer opens locally; no server, no account, no AI API required.

## Why It Sells

- Obsidian’s built-in graph view is functional but plain. This is the shareable, screenshot-worthy version.
- A visual dashboard is experiential, not just structural — harder to copy from a template pack.
- Themes create an upsell market: Base → Pro → White-label.
- Proof is immediate: screenshots of YOUR vault rendered as a skill tree or solar system.

## Pricing

| Tier | Price | Includes |
|---|---|---|
| Base | $29 | Solar System + Skill Tree themes |
| Pro | $59 | Base + Constellation + RPG Map + custom CSS editor |
| White-label | $199 | Multi-vault + brand colors + support |

Channel: Gumroad first.

## Buyer Pitch

One sentence: “Your Obsidian graph, but it looks like a video game.”

Demo before buy: yes — screenshots/GIF of actual vault rendered in both themes.

## Source Provenance

All structure/ideas derived from Spiral vault assets:
- `RESTORE.md` — folder schema
- `RESTORE-oauth.md` — vault restore flow
- `daily/` — real note-link graph structure
- `systems/repo-catalog.md` — vault inventory for demo screenshots
- `archive/youtube-notes/` — visual theme research

No generic dashboard templates were used.

## Delivery Format Decision

**Standalone single-file HTML first.**
Ship `cosmos.html` as the Base tier product. Integration into the Spiral fork
of Ares happens later as a Pro/White-label upgrade. See `spiral-integration.md` for the planned bridge architecture.

This keeps the initial offering:
- zero-install,
- screenshot-ready,
- easy to support,
- safe to iterate without polluting the fork before there are buyers.

## Provenance / Ownership Proof Strategy

- Mirror the release on GitHub under `SeanJ07/obsidian-cosmos`.
- Tag every release with a signed Git tag (`gh release create --verify-tag`).
- Include a `PROVENANCE.md` artifact block in each release:
  - project SHA fingerprints,
  - source vault notes references,
  - release timestamp + tag.
- Gumroad receipts act as buyer proof of first sale.

## Changelog

- 2026-07-05 — Created by Sean Jenkins.
- 2026-07-05 — Added docs site, screenshots, gumroad draft, one-pager PDF.
- 2026-07-05 — Added `spiral-integration.md` future bridge plan.

---

*Product doc: `projects/ai-monetization/obsidian-cosmos.md`*  
*Project brief: `projects/obsidian-cosmos/PROJECT-BRIEF.md`*
