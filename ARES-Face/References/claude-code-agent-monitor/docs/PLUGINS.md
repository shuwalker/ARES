# Claude Code Agent Monitor — Plugin Marketplace

Official Claude Code plugins for the Agent Monitor dashboard. These plugins extend Claude Code with skills, agents, hooks, and CLI tools for deep analytics, productivity automation, developer tools, AI-powered insights, and dashboard connectivity.

## Quick Start

### Add the marketplace

```bash
claude plugin marketplace add hoangsonww/Claude-Code-Agent-Monitor
```

### Install a plugin

```bash
# Install individual plugins
claude plugin install ccam-analytics@hoangsonww-claude-code-agent-monitor
claude plugin install ccam-productivity@hoangsonww-claude-code-agent-monitor
claude plugin install ccam-devtools@hoangsonww-claude-code-agent-monitor
claude plugin install ccam-insights@hoangsonww-claude-code-agent-monitor
claude plugin install ccam-dashboard@hoangsonww-claude-code-agent-monitor
```

### Or install locally during development

```bash
# From the repo root, test a plugin locally
claude --plugin-dir plugins/ccam-analytics
```

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- Agent Monitor dashboard running at `http://localhost:4820` (see [SETUP.md](../SETUP.md))
- Hooks installed: `npm run setup` from the Agent Monitor project

## Available Plugins

### 1. `ccam-analytics` — Analytics & Monitoring

Deep analytics on Claude Code sessions, token usage, costs, and productivity metrics.

**Skills:**

| Skill | Command | Purpose |
|-------|---------|---------|
| Session Report | `/ccam-analytics:session-report` | Comprehensive session report with per-model tokens (input/output/cache_read/cache_write + compaction baselines), cost breakdown, agent hierarchy, tool activity, and timeline |
| Cost Breakdown | `/ccam-analytics:cost-breakdown` | Per-model cost analysis using the pricing engine (pattern-matched rules at $/Mtok), daily trends, cache efficiency, and optimization opportunities |
| Usage Trends | `/ccam-analytics:usage-trends` | Daily session/event trends (365-day retention), token volume trends, tool rankings, model distribution, session health, and event type ratios |
| Productivity Score | `/ccam-analytics:productivity-score` | Weighted scorecard: completion rate, token efficiency (cache hits + compaction pressure), tool effectiveness (PreToolUse/PostToolUse ratio), velocity (turn_count + turn_duration_ms), and cost efficiency |

**Agent:** `analytics-advisor` — Full analytics advisor with access to all API endpoints including the workflow intelligence API (11 datasets per session).

**Hooks:** Logs `Stop` and `SubagentStop` events for session metric tracking.

**CLI:** `ccam-stats` — Terminal dashboard showing session counts, cost summary with per-model breakdown, and token usage with compaction baselines.

```bash
ccam-stats                # Show all stats
ccam-stats --cost         # Cost summary with per-model breakdown
ccam-stats --tokens       # Token usage with baselines
ccam-stats --json         # Raw JSON output
```

---

### 2. `ccam-productivity` — Productivity & Workflows

Workflow automation, standup reports, sprint tracking, and workflow optimization.

**Skills:**

| Skill | Command | Purpose |
|-------|---------|---------|
| Daily Standup | `/ccam-productivity:daily-standup` | Standup summary from recent sessions — work grouped by project (cwd), costs, tool invocations, errors, compactions, and turn velocity |
| Weekly Report | `/ccam-productivity:weekly-report` | Weekly report with daily_sessions/events trends, per-session costs, token volumes with baselines, tool top 20, and completion rates |
| Sprint Summary | `/ccam-productivity:sprint-summary` | Sprint summary grouped by project, per-model costs, token efficiency, subagent effectiveness, velocity metrics, and retrospective data |
| Workflow Optimizer | `/ccam-productivity:workflow-optimizer` | Workflow optimization using the **workflow intelligence API** — tool flow transitions, subagent effectiveness, model delegation, error propagation, concurrency lanes, and compaction impact |

**Agent:** `productivity-coach` — Reviews work patterns using session metadata (thinking_blocks, turn_count, turn_duration_ms, usage_extras) and workflow intelligence data.

**Hooks:** Session start/end timing for duration tracking.

---

### 3. `ccam-devtools` — Developer Tools

Debugging, diagnostics, data export, and health monitoring for the Agent Monitor.

**Skills:**

| Skill | Command | Purpose |
|-------|---------|---------|
| Session Debug | `/ccam-devtools:session-debug` | Debug a session's full event chain (all 10+ event types), agent hierarchy, token usage with baselines, and workflow intelligence |
| Hook Diagnostics | `/ccam-devtools:hook-diagnostics` | Diagnose hook installation (7 types), dashboard connectivity, handler validation, event delivery, and data freshness |
| Data Export | `/ccam-devtools:data-export` | Export sessions/events/analytics/costs in JSON, CSV, or Markdown via `/api/settings/export` |
| Health Check | `/ccam-devtools:health-check` | System health: API, database (SQLite WAL), WebSocket, endpoints (6 routes), hooks, disk usage, and data freshness |

**Agent:** `issue-triager` — Triages issues across Express API, SQLite database, WebSocket, hook handler, transcript cache, and MCP server.

**CLI:**

```bash
ccam-doctor               # Diagnostic report
ccam-doctor --quick       # Basic connectivity check
ccam-doctor --deep        # Extended checks with DB integrity

ccam-export sessions                      # Export sessions as JSON
ccam-export events --format csv --limit 500  # Export events as CSV
ccam-export all --output backup.json      # Full backup
ccam-export costs --pretty                # Pretty-printed cost data
```

---

### 4. `ccam-insights` — AI-Powered Insights

Pattern detection, anomaly alerting, optimization recommendations, and session comparison.

**Skills:**

| Skill | Command | Purpose |
|-------|---------|---------|
| Pattern Detect | `/ccam-insights:pattern-detect` | Detect patterns via workflow intelligence — tool flow transitions, recurring sequences, agent co-occurrence, model delegation habits, error propagation paths |
| Anomaly Alert | `/ccam-insights:anomaly-alert` | Statistical anomaly detection — cost outliers, token anomalies (cache miss spikes, baseline surges), unusual event type ratios, complexity score outliers |
| Optimization Suggest | `/ccam-insights:optimization-suggest` | Data-driven optimization — model downgrade opportunities, cache optimization, compaction reduction, tool reliability improvements |
| Session Compare | `/ccam-insights:session-compare` | Side-by-side comparison — per-model tokens with baselines, cost breakdowns, workflow complexity, tool flow differences, and metadata deltas |

**Agent:** `insights-advisor` — Strategic analysis using the full data model including workflow intelligence (11 datasets), token baselines, and session metadata.

---

### 5. `ccam-dashboard` — Dashboard Connector

Direct MCP integration and quick status checks.

**Skills:**

| Skill | Command | Purpose |
|-------|---------|---------|
| Dashboard Status | `/ccam-dashboard:dashboard-status` | Quick health check — API connectivity, session/event counts, hook status, and data freshness |
| Quick Stats | `/ccam-dashboard:quick-stats` | One-line metrics summary — active sessions, total cost, event count, top tool, cache efficiency |

**MCP Server:** Provides Claude Code with direct tool access to the Agent Monitor API for reading sessions, events, analytics, and workflow data.

**Settings:** Default agent model configuration for the plugin's agent tools.

---

## Data Model Reference

These plugins query the Agent Monitor API at `http://localhost:4820`. Key data shapes:

### Token Tracking
- **4 token types**: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`
- **4 baselines**: `baseline_input`, `baseline_output`, `baseline_cache_read`, `baseline_cache_write` (preserve pre-compaction tokens)
- **Effective total** = current + baseline

### Cost Calculation
- Formula: `(tokens / 1,000,000) × rate_per_mtok` for each token type
- Model matching: longest `model_pattern` wins (e.g., `claude-sonnet-4-5%` beats `claude-sonnet-4%`)
- Pre-seeded rates for Opus, Sonnet, Haiku families

### Session Metadata (JSON)
- `thinking_blocks`: count of extended thinking blocks
- `turn_count`: number of conversation turns
- `total_turn_duration_ms`: cumulative turn processing time
- `usage_extras`: `{ service_tiers[], speeds[], inference_geos[] }`

### Event Types
`PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `SessionStart`, `SessionEnd`, `Notification`, `Compaction`, `APIError`, `TurnDuration`

### Workflow Intelligence API (`/api/workflows/{sessionId}`)
11 datasets: `stats`, `orchestration` (DAG), `toolFlow` (transitions), `effectiveness` (subagent success), `patterns` (recurring sequences), `modelDelegation`, `errorPropagation` (by depth), `concurrency` (lanes), `complexity` (score), `compaction` (impact), `cooccurrence` (agent pairs)

## Plugin Development

To create your own plugins for the Agent Monitor, see the [Claude Code plugin documentation](https://docs.anthropic.com/en/docs/claude-code/plugins).

### Plugin structure

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json          # Required: name, description, version
├── skills/
│   └── my-skill/
│       └── SKILL.md         # Skill definition with $ARGUMENTS
├── agents/
│   └── my-agent.md          # Agent with model, tools, instructions
├── hooks/
│   └── hooks.json           # Event hooks (fail-safe, non-blocking)
├── bin/
│   └── my-cli-tool          # CLI scripts (added to PATH)
├── .mcp.json                # MCP server configuration
└── settings.json            # Plugin settings
```

### Testing locally

```bash
# Test with --plugin-dir flag
claude --plugin-dir /path/to/my-plugin

# Use the plugin's skills
/my-plugin:my-skill some arguments
```

## Troubleshooting

### Dashboard not reachable
```bash
# Start the dashboard
cd /path/to/Claude-Code-Agent-Monitor
npm start

# Or in development mode
npm run dev
```

### Hooks not installed
```bash
cd /path/to/Claude-Code-Agent-Monitor
npm run setup
```

### Plugin not found
```bash
# Verify marketplace is added
claude plugin marketplace list

# Re-add if needed
claude plugin marketplace add hoangsonww/Claude-Code-Agent-Monitor
```

## License

Same as the parent project. See [LICENSE](../LICENSE).
