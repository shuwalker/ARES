# ARES LifeTrack Plugin

**Automatic time tracking and productivity analysis for ARES.**

LifeTrack automatically logs your actual day (apps, calendar, location) and compares it against your planned schedule. Built as an ARES plugin following the same architecture as the Mail plugin.

---

## Features

- **Auto-ingestion**: Pulls Screen Time data, Calendar events, and location context
- **Classification**: Maps apps → categories (work, comms, distraction, research, health)
- **Reconciliation**: Compares planned vs. actual time with focus score
- **CLI commands**: `ares lifetrack process`, `ares lifetrack report`, `ares lifetrack stats`
- **REST API**: `/api/lifetrack/today`, `/api/lifetrack/week`, `/api/lifetrack/override`
- **SQLite persistence**: All data stored in `~/.ares/lifetrack.db`

---

## Installation

LifeTrack is included in the ARES repo. No separate installation needed.

```bash
# Verify plugin is loaded
ares lifetrack --help
```

---

## Quick Start

```bash
# Initialize database (auto-runs on first command)
ares lifetrack stats

# Process yesterday's data
ares lifetrack process

# Process today (for testing)
ares lifetrack process --today

# View today's summary
ares lifetrack today

# View weekly report
ares lifetrack week

# View detailed daily report
ares lifetrack report --date=2026-05-19
```

---

## Commands

| Command | Description |
|---------|-------------|
| `ares lifetrack process` | Process a day's tracking data (default: yesterday) |
| `ares lifetrack today` | Show today's summary |
| `ares lifetrack week` | Show weekly summary |
| `ares lifetrack stats` | Show lifetime statistics |
| `ares lifetrack report --date=YYYY-MM-DD` | Detailed daily report |
| `ares lifetrack override <bundle_id> <category>` | Set custom app category |
| `ares lifetrack overrides` | List all custom overrides |

---

## App Categories

| Category | Description | Example Apps |
|----------|-------------|--------------|
| `work` | Deep work, coding, writing | Xcode, VS Code, Terminal |
| `comms` | Communication | Discord, Slack, Messages |
| `research` | Learning, browsing | Safari, Chrome, iBooks |
| `distraction` | Entertainment | YouTube, Netflix, Twitter |
| `health` | Fitness, medical | Health, Strava, Nike Run |
| `meeting` | Scheduled meetings | Calendar events with "meeting" |
| `unknown` | Unclassified | New/unrecognized apps |

---

## Custom App Overrides

Override default classifications for your workflow:

```bash
# Mark Chrome as work (for research-heavy workflow)
ares lifetrack override com.google.Chrome work

# Mark Discord as distraction (during focus hours)
ares lifetrack override com.hnc.Discord distraction

# List all overrides
ares lifetrack overrides
```

---

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/lifetrack/today` | GET | Today's reconciliation |
| `/api/lifetrack/date/{date}` | GET | Specific date reconciliation |
| `/api/lifetrack/week` | GET | Weekly report |
| `/api/lifetrack/stats` | GET | Lifetime statistics |
| `/api/lifetrack/override` | POST | Set app category override |
| `/api/lifetrack/overrides` | GET | List all overrides |
| `/api/lifetrack/override/{bundle_id}` | DELETE | Remove override |

---

## Data Storage

- **Database**: `~/.ares/lifetrack.db` (SQLite)
- **Tables**: `activity_blocks`, `daily_reconciliations`, `user_corrections`, `app_overrides`
- **Retention**: Indefinite (user can manually prune)

---

## Privacy

- **100% local**: No data leaves your Mac
- **No cloud sync**: All data stays in `~/.ares/lifetrack.db`
- **No telemetry**: Plugin doesn't phone home
- **User-controlled**: You decide what to track and when

---

## Limitations

### macOS Permissions

LifeTrack requires the following macOS permissions for full functionality:

| Permission | Required For | Status |
|------------|--------------|--------|
| Screen Time | App usage data | ⚠️ Manual setup needed |
| Calendar | Event ingestion | ✅ Works via AppleScript |
| Location | Context inference | ⚠️ Restricted in macOS 13+ |
| Accessibility | Active app detection | Optional |

### Screen Time Setup (macOS 13+)

macOS restricts Screen Time data access. To enable:

1. **System Settings** → **Privacy & Security** → **Analytics & Improvements**
2. Enable **Share Mac Analytics**
3. Restart ARES: `ares stop && ares start`

If Screen Time data is unavailable, LifeTrack falls back to:
- Calendar events only (intent tracking)
- Manual activity logging (future feature)

---

## Architecture

```
ares/plugins/lifetrack/
├── __init__.py      # Orchestrator: process_day(), run_pipeline()
├── models.py        # Pydantic schemas: ActivityBlock, DailyReconciliation
├── driver.py        # Data ingestion: Screen Time, Calendar, Location
├── classify.py      # Classification engine: app→category mapping
├── db.py            # SQLite persistence layer
├── cli.py           # Click CLI commands
└── api.py           # FastAPI REST endpoints
```

---

## Development

### Testing Ingestion

```bash
# Test Screen Time data fetch
.venv/bin/python -c "
from ares.plugins.lifetrack.driver import get_screen_time_data
from datetime import datetime, timedelta

start = datetime.now() - timedelta(days=1)
end = datetime.now()

events = get_screen_time_data(start, end)
print(f'Found {len(events)} app usage events')
"

# Test Calendar data fetch
.venv/bin/python -c "
from ares.plugins.lifetrack.driver import get_calendar_events
from datetime import datetime, timedelta

start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
end = start + timedelta(days=1)

events = get_calendar_events(start, end)
print(f'Found {len(events)} calendar events')
"
```

### Adding New Data Sources

1. Add fetch function in `driver.py`
2. Add model in `models.py`
3. Integrate in `__init__.py` → `process_day()`
4. Update this README

---

## Future Enhancements

- [ ] **Manual activity logging**: CLI command to log activities Screen Time misses
- [ ] **Focus mode detection**: Auto-pause tracking during deep work sessions
- [ ] **Weekly email digest**: Send Sunday night summary via email
- [ ] **Goal tracking**: Compare actual hours vs. weekly goals (e.g., "40h work/week")
- [ ] **Pattern detection**: "You're most productive on Tuesdays 9-11am"
- [ ] **Integration with ARES tasks**: Auto-link tracked time to active goals

---

## Troubleshooting

### "No data available"

- Run `ares lifetrack process --today` to ingest current day
- Check Screen Time permissions (see above)
- Verify Calendar has events for the date

### "Database locked"

- Only one process should access the DB at a time
- Restart ARES: `ares stop && ares start`

### Calendar events not showing

- Ensure Calendar.app has events for the target date
- Check macOS permissions: System Settings → Privacy → Calendars
- Test manually: `osascript -e 'tell application "Calendar" to get events of calendar "Calendar"'`

---

## License

Same as ARES core (MIT).
