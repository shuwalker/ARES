# Task: Depth-Port Hermes WebUI Pages to ARES for Feature Parity

## Context
ARES WebUI (`~/GitHub/ARES/webui/`) has stub implementations of many pages. Hermes WebUI (`~/GitHub/hermes-webui/`) has production-ready, fully-featured versions of these same pages.

**Goal:** Port Hermes WebUI pages to ARES, adapting them to ARES contracts, API, and design system — not copy-pasting.

## Reference Documents (READ FIRST)

1. **`~/GitHub/ARES/.claude/FOUNDATION.md`** — ARES product definition, vocabulary, architecture
2. **`~/GitHub/ARES/.claude/webui/CLAUDE.md`** — WebUI-specific rules
3. **`~/GitHub/ARES/webui/CLAUDE.md`** — Additional WebUI constraints
4. **`~/GitHub/ARES/.hermes/skills/autonomous-ai-agents/ares-symbiotic-controller/SKILL.md`** — Existing porting patterns, pitfall documentation
5. **`~/GitHub/ARES/docs/`** — ARES architecture and API contracts

## Porting Pattern (CRITICAL)

**DO NOT copy-paste.** Follow this pattern for each page:

1. **Read the Hermes page** for layout, structure, UX flow, features
2. **Identify ARES equivalents:**
   - API endpoints (`aresApi.*` in `webui/frontend/src/shared/ares-api.ts`)
   - Contract types (`webui/frontend/src/shared/contracts.ts`)
   - UI components (`webui/frontend/src/components/ui/*`)
   - Design tokens (Graphite dark theme in `webui/frontend/src/index.css`)
3. **Rewrite using ARES patterns:**
   - Use `aresApi.method()` — not raw `fetch()`
   - Use ARES contract types — not Hermes types
   - Use ARES components (shadcn/ui, Radix) — not Hermes's `@nous-research/ui`
   - Use ARES CSS vars (`--foreground`, `--card`, `--border`) — not Hermes theme
4. **Strip org-scoping** — Hermes has company/team/RBAC; ARES is personal
5. **Test** — TypeScript compiles, page loads, API calls work

## Pages to Port (Priority Order)

### Tier 1 (High Priority — Core Workflow)
| Hermes Page | ARES Stub | Hermes Lines | Features to Port |
|-------------|-----------|--------------|------------------|
| `src/pages/SessionsPage.tsx` | `webui/frontend/src/pages/SessionsPage.tsx` | ~1700 | Session list, search, filter, pin/archive, bulk ops |
| `src/pages/ChatPage.tsx` | `webui/frontend/src/pages/ConversationPage.tsx` | ~1100 | Chat surface, model picker, streaming, tool blocks |
| `src/pages/FilesPage.tsx` | `webui/frontend/src/pages/FilesPage.tsx` | ~525 | File browser, upload, workspace integration |
| `src/pages/AnalyticsPage.tsx` | `webui/frontend/src/pages/AnalyticsPage.tsx` | ~600 | Usage stats, cost tracking, charts |

### Tier 2 (Management Pages)
| Hermes Page | ARES Stub | Hermes Lines | Features to Port |
|-------------|-----------|--------------|------------------|
| `src/pages/ModelsPage.tsx` | `webui/frontend/src/pages/ModelsPage.tsx` | ~1300 | Model catalog, provider groups, capabilities |
| `src/pages/PluginsPage.tsx` | `webui/frontend/src/pages/PluginsPage.tsx` | ~580 | Plugin list, enable/disable, config |
| `src/pages/LogsPage.tsx` | `webui/frontend/src/pages/LogsPage.tsx` | ~246 | Log viewer, filter, search, export |

### Tier 3 (Life Management — Rebrand from Hermes)
| Hermes Page | ARES Rebrand | Hermes Lines | Features to Port |
|-------------|--------------|--------------|------------------|
| `src/pages/CompaniesPage.tsx` | `DomainsPage.tsx` (Life Areas) | ~??? | Work/Health/Finances/Projects/Relationships |
| `src/pages/CostsPage.tsx` | `FinancesPage.tsx` | ~??? | AI subscriptions, budgets, spending |
| `src/pages/CasesPage.tsx` | `LifeAdminPage.tsx` | ~??? | Insurance, medical, home repairs, travel |
| `src/pages/GoalsPage.tsx` | `GoalsPage.tsx` (keep name) | ~??? | Life/career/health/learning goals with progress |
| `src/pages/TimelinePage.tsx` | `JournalPage.tsx` | ~??? | Gantt of activity, habits, history |
| `src/pages/PipelinesPage.tsx` | `WorkflowsPage.tsx` | ~5274 | Multi-step automated workflows (heavy port) |

## Acceptance Criteria

For each ported page:

```bash
# 1. TypeScript compiles
cd ~/GitHub/ARES/webui/frontend
npm run typecheck  # No errors in ported page

# 2. Build succeeds
npm run build  # Output in frontend/dist/

# 3. Page loads without console errors
# Open http://localhost:8787/<page-route>
# Check DevTools console for errors

# 4. API calls work
# Interact with page features, verify network tab shows successful API calls

# 5. Design matches ARES Graphite theme
# Dark mode colors, spacing, typography match existing ARES pages
```

## Existing Ported Pages (Reference Examples)

These pages were already depth-ported correctly — use them as patterns:

- **SessionsPage.tsx** (486 lines) — Search/filter, pin/archive, bulk delete
- **SkillsPage.tsx** (500 lines) — Category pills, toggle, Sheet detail drawer
- **SystemPage.tsx** (568 lines) — Health cards, diagnostics, confirm dialogs
- **ProfilesPage.tsx** (719 lines) — Active indicator, dropdown actions, clone dialog
- **CronPage.tsx** (611 lines) — Cron builder, status badges, run-now, history dialog
- **EnvPage.tsx** (766 lines) — Scoped vars, reveal, bulk edit, reorder
- **SecretsPage.tsx** (691 lines) — CRUD, scope filter, reveal/mask
- **ChannelsPage.tsx** (335 lines) — Channel list, status, test, connect/disconnect
- **McpPage.tsx** (480 lines) — Server list, status, toggle, restart, add/edit/delete
- **AgentsPage.tsx** (260 lines) — Backend registry, status badges
- **AgentDetailPage.tsx** (480 lines) — Adapter detail, tools with toggles
- **ConfigPage.tsx** (656 lines) — Structured form, JSON/YAML editor, validation
- **WebhooksPage.tsx** (275 lines) — List, toggle, create, delete
- **PairingPage.tsx** (230 lines) — Device list, approve, revoke, clear
- **HatcheryPage.tsx** (460 lines) — Hardware scan, mold form, hatched SI list
- **AnalyticsPage.tsx** (538 lines) — Usage insights, charts, breakdown
- **ProfileBuilderPage.tsx** (749 lines) — Multi-step wizard, model selection

**Study these files** to understand the porting pattern before starting new pages.

## Pitfalls to Avoid

1. **Don't import Hermes types** — Use ARES contracts from `@/shared/contracts`
2. **Don't use raw fetch()** — Use `aresApi.*` methods from `@/shared/ares-api`
3. **Don't copy Hermes CSS** — Use ARES Graphite theme vars from `index.css`
4. **Don't port org-scoping** — Strip company/team/RBAC logic
5. **Don't assume API parity** — Check ARES backend has the endpoint first
6. **Don't write custom components** — Use shadcn/ui from `@/components/ui/*`
7. **Don't ignore TypeScript errors** — Fix type mismatches properly
8. **Don't skip testing** — Verify page loads and works before declaring done

## Files to Study First

1. **`webui/frontend/src/shared/contracts.ts`** — ARES type definitions
2. **`webui/frontend/src/shared/ares-api.ts`** — API client methods
3. **`webui/frontend/src/shared/translators.ts`** — API response translators
4. **`webui/frontend/src/components/ui/`** — shadcn component library
5. **`webui/frontend/src/index.css`** — Graphite theme CSS variables
6. **`references/hermes-webui-porting-guide.md`** — Detailed porting patterns (if exists)
7. **`references/repo-evaluation.md`** — Repo evaluation and priority

## After Porting

For each completed page:
1. Add to `webui/frontend/src/App.tsx` routes
2. Add to `webui/frontend/src/AppShell.tsx` navigation
3. Update `CHANGELOG.md` with feature addition
4. Test on desktop and narrow viewport widths

## Start With

**Pick ONE Tier 1 page** (recommend `FilesPage.tsx` or `AnalyticsPage.tsx` — simpler than Sessions/Chat).

Port it fully following the pattern above. Once that's verified as a good port, continue with the rest of Tier 1, then Tier 2, then Tier 3.

**Do not port all pages at once** — do one at a time, verify, then move to the next.
