# ARES Personal Organizer Plan

## Outcome

Build the first immediately useful protocol-droid capability: a local-first
system that captures obligations, turns them into realistic plans, helps manage
the current day, replans when circumstances change, and preserves continuity
across restarts.

ARES is the repository and platform name. The user interacts with their
user-named protocol droid. LLMs may interpret or explain, but deterministic
software owns tasks, schedules, permissions, persistence, and completion state.

## Definition of usable

The organizer is functionally usable when a person can:

1. Capture a task through text or voice in under ten seconds.
2. Put unclear items into an Inbox without being forced to organize immediately.
3. Clarify a task into an outcome, next action, project, deadline, estimate,
   energy requirement, and context.
4. Generate a realistic daily plan from tasks, calendar commitments, available
   time, priorities, routines, energy, and user preferences.
5. Accept, edit, reorder, defer, complete, or cancel any recommendation.
6. Replan the remaining day after interruption, delay, or changing priorities.
7. Carry unfinished work forward without silently losing or duplicating it.
8. Review completed, deferred, missed, and newly created work at day’s end.
9. Restart the application without losing the plan or active task state.
10. Inspect why an item was scheduled and what data was used.

## Core daily loop

```text
Capture
→ Clarify
→ Prioritize
→ Plan
→ Focus
→ Check in
→ Replan
→ Review
→ Carry forward
```

The organizer should reduce cognitive load. It should not create extra
administrative work merely to maintain the system.

## Product scope

### Organizer MVP

- Universal task Inbox.
- Quick capture from the protocol-droid conversation.
- Manual task entry and editing.
- Projects and unassigned standalone tasks.
- Priority, due date, duration, energy, context, status, and notes.
- Today view with ordered tasks and time blocks.
- Deterministic daily-plan generator.
- Manual plan editing through drag, reorder, resize, defer, and complete.
- Calendar read integration.
- Approval before creating or changing calendar events.
- Routines and recurring tasks.
- Morning planning session.
- Midday replan.
- Evening review and carry-forward.
- Local persistence and restart recovery.
- Activity receipt explaining planning decisions.

### Reliable personal-manager release

- Native notifications and reminders.
- Voice capture, spoken plan summary, interruption, and follow-up.
- Natural-language task clarification.
- Workload and overcommitment warnings.
- Weekly review.
- Preference memory: working hours, focus-block length, break policy, energy
  patterns, protected time, and planning style.
- Multiple calendars with inclusion and privacy controls.
- Task dependencies and blocked-state handling.
- Search, export, backup, correction, and deletion.
- Offline operation for all core planning behavior.

### Later

- Email and message extraction.
- Location-aware reminders.
- Multi-device encrypted synchronization.
- Shared household or team plans.
- Proactive screen/context awareness.
- Home automation and robotics.
- Automatic external actions beyond explicitly granted policies.

## Non-goals

- Do not require an LLM to create, complete, or persist a task.
- Do not let a model directly mutate the task database.
- Do not silently change a calendar.
- Do not create an autonomous productivity manager that pressures the user.
- Do not permanently retain raw microphone or camera data.
- Do not block the organizer on the wider repository reorganization.
- Do not replace working task, schedule, Today, routine, or calendar code merely
  to produce a theoretically cleaner implementation.

## Primary user flows

### 1. Capture

Examples:

- “Remind me to renew the registration next Thursday.”
- “I need to research Roman road construction.”
- “Add groceries.”
- “This bug needs another two hours.”

The capture service stores the original statement as an event, extracts a
proposed task, and presents any material ambiguity. Low-risk fields can be
edited later; capture must remain fast.

### 2. Morning plan

The protocol droid asks only what is necessary:

- What absolutely must happen today?
- How much usable time is available?
- What energy or constraints are present?
- Are calendar commitments accurate?

It then proposes:

- Fixed calendar commitments.
- Protected focus blocks.
- Small tasks placed into suitable gaps.
- Breaks and transition time.
- Explicitly unscheduled work when the day cannot contain everything.

### 3. Live day management

The Today view shows:

- Now.
- Next.
- Later today.
- Waiting or blocked.
- Unscheduled but relevant.

Starting a task creates an active focus session. Completion, pause, delay, and
interruption are events rather than destructive overwrites.

### 4. Replanning

Replanning is triggered manually or by an observed mismatch:

- A task took longer.
- A meeting moved.
- A new urgent item arrived.
- The user’s available energy changed.
- A dependency remained blocked.

ARES preserves completed work and fixed commitments, then proposes the smallest
necessary change to the remaining plan. It explains what moved and why.

### 5. Evening review

The review asks:

- What completed?
- What remains important?
- What should be deferred, delegated, broken down, or dropped?
- What was learned about estimates and energy?

Carry-forward requires an explicit destination: tomorrow, a date, backlog,
waiting, or cancelled. Nothing vanishes silently.

## Data model

### Task

- Stable ID.
- Original capture text.
- Title and desired outcome.
- Next action.
- Status: inbox, ready, scheduled, active, paused, waiting, completed, cancelled.
- Project ID.
- Priority and user override.
- Due date and “do not start before” date.
- Estimated and actual duration.
- Energy requirement.
- Context: computer, phone, home, errands, person, location.
- Dependencies and blocked reason.
- Recurrence rule.
- Sensitivity and disclosure policy.
- Created, updated, completed, and superseded timestamps.

### Project

- Outcome.
- Status.
- Area of life.
- Next-action requirement.
- Target date.
- Task membership.
- Notes and relevant artifacts.

### Daily plan

- Date and timezone.
- Available-time windows.
- Fixed calendar blocks.
- Proposed task blocks.
- User-edited ordering.
- Planning assumptions.
- Version and revision history.
- Accepted and rejected suggestions.

### Routine

- Trigger or recurrence.
- Preferred time window.
- Duration.
- Skip policy.
- Completion history.

### Focus session

- Task.
- Planned and actual start/end.
- Interruptions.
- Completion or pause result.

### Event

Every capture, clarification, schedule proposal, approval, edit, completion,
deferral, and replan creates a durable event with origin and timestamp.

## Planning engine

The core planner is deterministic. It should work offline without a model.

### Inputs

- Ready tasks.
- User priorities.
- Deadlines.
- Calendar commitments.
- Working hours.
- Available time windows.
- Duration estimates.
- Energy preferences.
- Routines.
- Dependencies.
- Current time and timezone.

### Candidate score

Use an inspectable weighted score based on:

- User-stated priority.
- Deadline urgency.
- Consequence of delay.
- Project importance.
- Dependency unblocking.
- Energy fit.
- Available-duration fit.
- Context-switch cost.
- Age and repeated deferral.

The score recommends; it never overrides a direct user decision.

### Scheduling rules

1. Preserve fixed calendar events.
2. Preserve protected personal time.
3. Schedule deadlines and high-consequence work first.
4. Match demanding work to preferred energy windows.
5. Include transition and break buffers.
6. Use small gaps for short compatible tasks.
7. Never overfill the day to make the plan look complete.
8. Leave lower-value tasks visibly unscheduled.
9. Replan only the uncompleted future portion of the day.
10. Explain each inclusion, exclusion, and movement.

## Architecture

### Controller

Add one organizer application service behind the existing FastAPI controller:

```text
capture
→ task repository
→ planning engine
→ calendar availability
→ plan proposal
→ approval
→ persisted plan
→ Today presentation
```

Suggested destination ownership:

```text
webui/api/organizer/
  models
  repository
  capture
  recurrence
  planning
  replanning
  review
  service

webui/fastapi_app/routers/domains/organizer/
  tasks
  projects
  plans
  routines
  focus

webui/frontend/src/features/organizer/
  inbox
  today
  task editor
  plan editor
  review
  hooks and contracts
```

Reuse existing Today, Goals, routines, schedules, calendar, project, persistence,
conversation, streaming, and native-tool capabilities through adapters. Do not
duplicate their stores.

### Persistence

Use ARES-owned SQLite with WAL mode and explicit migrations. The organizer
tables and events belong to the same user/profile scope as the existing product
state. Derived views may be rebuilt from authoritative records.

### Model use

An LLM worker may:

- Parse informal capture text.
- Suggest clarification questions.
- Break projects into candidate next actions.
- Explain a plan conversationally.
- Summarize a daily or weekly review.

Traditional code validates the structured result. The model cannot directly
commit tasks, calendar events, reminders, or completion state.

### Native macOS integration

Use native calendar, notification, microphone, speech-recognition, and
text-to-speech capabilities. Calendar reads follow user-selected calendar
scope. Calendar writes require a preview and approval unless the user later
grants a narrowly defined automation policy.

## API contracts

Initial API families:

```text
POST   /api/organizer/capture
GET    /api/organizer/tasks
POST   /api/organizer/tasks
PATCH  /api/organizer/tasks/{id}
POST   /api/organizer/tasks/{id}/complete
POST   /api/organizer/tasks/{id}/defer

GET    /api/organizer/projects
POST   /api/organizer/projects

GET    /api/organizer/plans/{date}
POST   /api/organizer/plans/{date}/generate
PATCH  /api/organizer/plans/{date}
POST   /api/organizer/plans/{date}/replan

GET    /api/organizer/routines
POST   /api/organizer/routines

POST   /api/organizer/focus/start
POST   /api/organizer/focus/{id}/pause
POST   /api/organizer/focus/{id}/complete

POST   /api/organizer/reviews/evening
POST   /api/organizer/reviews/weekly
```

All mutations require authenticated owner scope, CSRF protection where
applicable, validation, durable event recording, and idempotency.

## Delivery plan

### Phase 0 — Stabilize the refactor branch

Estimated effort: one focused day.

- Finish the approved move-only batch.
- Keep existing entry points operational.
- Restore all required tests and builds to green.
- Add no organizer behavior during an unverified structural move.

Exit gate: clean ownership map, no missing paths, green focused baseline.

### Phase 1 — Task foundation

Estimated effort: one to two focused days.

- Inventory existing task, goal, schedule, routine, calendar, and Today code.
- Define canonical organizer contracts.
- Add migrations for tasks, projects, events, and recurrence.
- Implement repository and CRUD service.
- Add compatibility adapters for existing task-like records.
- Build Inbox and task editor.

Exit gate: tasks persist, edit, complete, defer, recur, and survive restart.

### Phase 2 — Daily planning engine

Estimated effort: two focused days.

- Availability calculation.
- Priority scoring.
- Dependency and due-date handling.
- Duration and energy matching.
- Time-block generation.
- Overcommitment detection.
- Explanation manifest.
- Deterministic unit-test scenarios.

Exit gate: the same inputs produce the same valid plan, fixed commitments are
never overwritten, and overfull days are reported honestly.

### Phase 3 — Today and replanning experience

Estimated effort: two focused days.

- Inbox/Triage view.
- Now, Next, Later, Waiting, and Unscheduled groups.
- Plan editing and manual ordering.
- Focus-session controls.
- Midday replan.
- Evening review and carry-forward.
- Activity receipt.

Exit gate: a complete day can be managed without editing databases or opening
an individual worker interface.

### Phase 4 — Calendar, reminders, and notifications

Estimated effort: two to three focused days.

- Calendar read adapter.
- Calendar selection and privacy scope.
- Write preview and approval.
- Reminder and notification scheduling.
- Timezone and daylight-saving tests.
- Graceful operation without calendar access.

Exit gate: calendar-aware plans work read-only; approved writes are exact and
verified.

### Phase 5 — Protocol-droid conversation and voice

Estimated effort: two to three focused days.

- Natural-language capture.
- Clarification flow.
- Spoken morning plan.
- Voice completion and deferral.
- Barge-in and cancellation.
- Minimal bounded organizer context for workers.
- No raw audio retention by default.

Exit gate: the organizer remains fully usable without a model, while voice and
conversation make it faster.

### Phase 6 — Reliability and personal beta

Estimated effort: two to four focused days.

- Restart and crash recovery.
- Backup, export, and restore.
- Search and history.
- Correction and deletion.
- Weekly review.
- Estimate-learning suggestions.
- Accessibility and narrow-screen testing.
- Packaging and upgrade migration.

Exit gate: use it daily for seven consecutive days without lost tasks,
duplicated calendar events, or unexplained schedule changes.

## Seven-day MVP sequence

### Day 1

- Freeze organizer contracts.
- Map existing capabilities.
- Create database migrations and repositories.

### Day 2

- Task CRUD, Inbox, status transitions, projects, and recurrence.

### Day 3

- Availability, priority scoring, and deterministic plan generation.

### Day 4

- Today plan editor, completion, deferral, focus state, and carry-forward.

### Day 5

- Calendar read integration, overcommitment detection, and plan explanations.

### Day 6

- Conversation capture, clarification, and morning/evening workflows.

### Day 7

- Restart recovery, focused regression suite, packaging, and first real daily
  trial.

## Testing

### Unit

- Task validation and transitions.
- Recurrence expansion.
- Priority scores.
- Availability and time-block placement.
- Dependency handling.
- Carry-forward.
- Timezone and daylight-saving behavior.

### Integration

- Capture to persisted task.
- Task to generated plan.
- Calendar event to protected time.
- Replan after interruption.
- Completion and evening review.
- Restart recovery.
- Approval-gated calendar write.

### Failure and privacy

- Calendar unavailable or permission denied.
- Worker unavailable.
- Malformed model extraction.
- Duplicate request replay.
- Database interruption.
- Secret or private task blocked from an ineligible worker.
- No raw voice retention.

### End-to-end acceptance

```text
Capture five obligations
→ clarify two ambiguous items
→ import today’s calendar availability
→ generate and edit a realistic plan
→ start and complete work
→ interrupt and replan
→ defer one item
→ review the day
→ restart ARES
→ recover the exact state
```

## Success measures

- Capture takes less than ten seconds.
- A daily plan is generated in under three seconds without a model.
- No task disappears without a recorded status transition.
- No calendar write occurs without matching authority.
- Restart recovery restores every active plan and focus state.
- Overcommitment is shown rather than hidden.
- Planning explanations identify the relevant constraints.
- The user can override every recommendation.
- Core functionality works offline.
- Seven consecutive real-use days complete without lost or duplicated work.

## Immediate next actions

1. Finish and verify the folder-only reorganization.
2. Inventory existing Today, goal, schedule, routine, project, and calendar
   ownership.
3. Write an organizer contract and migration RFC.
4. Implement Task, Project, DailyPlan, Routine, FocusSession, and OrganizerEvent.
5. Ship text capture, Inbox, and manual Today planning first.
6. Add deterministic plan generation.
7. Add calendar reads and approval-gated writes.
8. Add protocol-droid conversation and native voice after the offline organizer
   works.

## Realistic schedule

- Functional personal MVP: approximately seven focused development days.
- Reliable daily organizer: one to two focused weeks.
- Voice-enabled personal manager: three to five focused weeks.
- Proactive, multi-device protocol droid: two to three months after the core
  organizer is trustworthy.
