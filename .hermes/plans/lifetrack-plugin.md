# LifeTrack Plugin — Plan

**Created:** 2026-05-18  
**Owner:** Matthew Jenkins  
**Status:** Planning → Awaiting Implementation  

---

## Problem Statement

Calendar apps plan your day but never log what actually happened. Your phone already collects:
- Location (Significant Locations, Maps Timeline)
- App usage (Screen Time)
- Movement (Health/Activity)
- Calendar events

None of this feeds back into a "planned vs. actual" view. You can't answer: *"Did I actually do what I said I'd do today?"*

---

## Product Vision

**ARES LifeTrack** = Personal productivity layer that:
1. **Auto-logs reality** from on-device sensors (no cloud, no surveillance)
2. **Reconciles against plans** from calendar + Hermes-generated goals
3. **Shows you the gap** between intent and execution
4. **Adapts future plans** based on learned patterns

**Interface:** Natural language via Hermes + visual dashboard in ARES Desktop app.

---

## Architecture

### ARES Plugin (`ares/plugins/lifetrack/`)

```
ares/plugins/lifetrack/
├── __init__.py          # Plugin registration
├── cli.py               # `ares lifetrack` commands
├── collector.py         # macOS data ingestion (Screen Time, Location, Calendar)
├── reconciler.py        # Compare planned vs. actual
├── models.py            # Pydantic schemas for events, blocks, reports
├── db.py                # SQLite/JSONL storage for activity logs
└── rules.py             # Inference rules (e.g., "Discord + late night = distraction")
```

### Data Sources (macOS)

| Source | Access Method | Granularity | Privacy |
|--------|---------------|-------------|---------|
| Screen Time | `usagestats` private API or SQLite DB | Per-app, per-minute | On-device only |
| Calendar | EventKit via `osascript` or `icalBuddy` | Event title, time, location | User already trusts calendar |
| Location | `log show --predicate 'eventMessage contains "location"'` | Significant locations, not GPS | On-device, coarse |
| Health | HealthKit export (manual) or Apple Health sync | Steps, active energy | User-controlled |
| Focus Mode | `defaults read com.apple.focus` | Active/inactive, mode name | On-device |

**Key constraint:** All ingestion is on-device. No data leaves the Mac Studio.

### Hermes Integration

Hermes calls LifeTrack plugin for:
- "How did today go?" → `ares lifetrack report --today`
- "What am I working on this week?" → `ares lifetrack goals --week`
- "Log that I finished the firmware review" → `ares lifetrack log --manual "Firmware review complete"`

Hermes also **writes goals** to LifeTrack:
- When you tell Hermes "I want to ship JP01 by June," Hermes creates a goal block.
- LifeTrack tracks progress toward that goal across days.

### ARES Desktop App (SwiftUI)

**Tabs:**

1. **Today** (default)
   - Timeline view: planned blocks (from calendar) vs. actual activity (from Screen Time)
   - Color-coded: green = on-track, yellow = drifted, red = distracted
   - Quick summary: "4h planned focus, 2h actual. Slack ate 90min."

2. **Week**
   - Bar chart: daily focus hours, goal progress
   - Goal cards: "JP01 Firmware — 3/5 milestones done"
   - Trend: "You're averaging 3.5h focus/day, down from 4.2h last week"

3. **Goals**
   - List of active goals (from Hermes)
   - Each goal shows: deadline, progress, last activity
   - "Add goal" button → opens Hermes chat: "I want to..."

4. **Reconcile** (end-of-day ritual)
   - Shows ambiguous blocks: "2-4pm: Calendar said 'Work', but you were on Discord 60% of the time. Was this work or distraction?"
   - User taps: [Work Research] [Distraction] [Meeting] [Other]
   - This labeling trains the inference rules over time

5. **Settings**
   - Data sources: toggle Screen Time, Location, Calendar
   - Privacy: "Delete last 7 days," "Export JSON"
   - Rules: customize inference (e.g., "VS Code = work" vs. "VS Code + YouTube = distraction")

---

## Bidirectional Sync with Apple Apps

### Calendar ←→ LifeTrack

**Calendar → LifeTrack (read):**
- Pull events from Apple Calendar via EventKit
- Treat events as "planned blocks"
- Event title → goal inference ("Firmware" → JP01 project)

**LifeTrack → Calendar (write):**
- When Hermes creates a goal, optionally block focus time on calendar
- Example: "Ship JP01 firmware" → Hermes schedules 2h blocks Mon/Wed/Fri
- Written as calendar events: "⚡ Focus: JP01 Firmware"

### Reminders ←→ LifeTrack

**Reminders → LifeTrack (read):**
- Pull incomplete reminders via `osascript`
- Treat as task-level goals
- Mark complete when LifeTrack detects matching activity

**LifeTrack → Reminders (write):**
- When you complete a goal, optionally create a reminder for the next step
- Example: "Firmware review done" → Hermes creates reminder "Order PCBs" due in 3 days

### Implementation Notes

- Use `osascript` for Calendar/Reminders — no external APIs needed
- Sync is **pull-based** (LifeTrack reads) + **push-on-change** (Hermes writes)
- Conflict resolution: user always wins. If calendar says "Meeting" but Screen Time says "Netflix," LifeTrack flags it for reconciliation, not auto-correction.

---

## Implementation Phases

### Phase 1: Data Ingestion (Week 1-2)
- [ ] `collector.py`: Screen Time SQLite reader (macOS: `/Library/Application Support/com.apple.ScreenTime/`)
- [ ] `collector.py`: Calendar reader via `osascript`
- [ ] `db.py`: JSONL schema for activity events
- [ ] CLI: `ares lifetrack ingest --today` (manual trigger)
- [ ] CLI: `ares lifetrack raw --today` (dump raw data for debugging)

### Phase 2: Reconciliation (Week 3)
- [ ] `reconciler.py`: Match calendar events to Screen Time blocks
- [ ] `rules.py`: Basic inference (app + time → category)
- [ ] CLI: `ares lifetrack report --today` (planned vs. actual)
- [ ] Memory: Write daily summary to ARES episodic memory

### Phase 3: Hermes Integration (Week 4)
- [ ] Hermes skill: `lifetrack-report` (calls ARES plugin via MCP)
- [ ] Hermes skill: `lifetrack-log` (manual activity logging)
- [ ] Hermes skill: `lifetrack-goals` (goal tracking)
- [ ] Natural language: "How did today go?" → triggers report

### Phase 4: ARES Desktop App (Week 5-6)
- [ ] SwiftUI: Today tab (timeline view)
- [ ] SwiftUI: Week tab (charts)
- [ ] SwiftUI: Goals tab (list + progress)
- [ ] SwiftUI: Reconcile tab (user labeling)
- [ ] API: `/api/lifetrack/today`, `/api/lifetrack/week`, `/api/lifetrack/goals`

### Phase 5: Bidirectional Sync (Week 7-8)
- [ ] Calendar write: `ares lifetrack calendar block --goal "JP01"` 
- [ ] Reminders write: `ares lifetrack reminder create --text "Order PCBs" --due 2026-05-25`
- [ ] Conflict UI: flag mismatches for user review

### Phase 6: Adaptive Planning (Week 9+)
- [ ] Learn from reconciliation: if user labels "Discord 2-4pm" as "Work Research," adjust rules
- [ ] Hermes uses historical data: "You typically get 3h focus on Tuesdays. Schedule accordingly."
- [ ] Weekly review: "Last week you missed 2 firmware blocks. Want to reschedule?"

---

## Privacy Boundaries

**Hard rules:**
1. No data leaves the Mac Studio. No cloud sync, no analytics.
2. User can delete any day's data via CLI: `ares lifetrack delete --date 2026-05-18`
3. Location is coarse (significant locations only, not GPS trail).
4. Screen Time is aggregated (app + duration, not keystrokes or content).

**User controls:**
- Toggle each data source independently
- Set "private hours" (e.g., 9pm-7am = no logging)
- Export all data as JSON for personal backup

---

## Open Questions

1. **Screen Time access:** macOS 13+ stores this in a SQLite DB with restricted permissions. May need Full Disk Access. Alternative: use `usagestats` private API (undocumented, may break).

2. **Calendar write permissions:** User must grant ARES access to Calendar. Should this be a separate approval gate, or part of initial setup?

3. **Inference accuracy:** How wrong can the auto-categorization be before it frustrates the user? Start conservative (flag more for manual review) and learn.

4. **Hermes goal → calendar block:** Should this be automatic or require approval? Default: approval for first 5 blocks, then auto.

---

## Success Metrics

- **Week 1:** Can ingest Screen Time + Calendar, show raw data
- **Week 3:** Can show "planned vs. actual" report via CLI
- **Week 4:** Hermes can answer "How did today go?"
- **Week 6:** ARES Desktop app shows Today + Week tabs
- **Week 8:** Bidirectional sync with Calendar/Reminders works
- **Week 12:** User reports "I actually use this daily" (not just built it)

---

## Risks

| Risk | Mitigation |
|------|------------|
| Screen Time DB schema changes between macOS versions | Abstract behind `collector.py` interface, test on macOS 13/14/15 |
| Calendar sync conflicts (duplicate events) | Use unique event ID prefix: `ARES-<goal-id>` |
| User feels surveilled by their own tool | Default to "private hours," make deletion easy, show data usage transparently |
| Inference rules get it wrong often | Start with conservative rules, require user labeling for ambiguous blocks |
| ARES Desktop app timeline is too complex | Start with simple bar chart, iterate based on user feedback |

---

## Next Step

**Awaiting Hermes implementation.** Once Hermes can reliably call ARES plugins via MCP, start Phase 1.

**Estimated effort:** 8-12 weeks for full vision. MVP (CLI report + Hermes integration) = 4 weeks.
