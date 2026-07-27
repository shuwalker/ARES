# Pass 4 — Frontend feature grouping

## Layout

```text
apps/web/src/features/
  advanced-chat/   Conversation, Share
  companion/       Companion, Today, Inbox, Routines, Activation
  self/            Self, Goals, Timeline, Cases
  workshop/        Workshop, Workspace, Terminal, Canvas, Projects, Board, Issues
  library/         Library, Collections, Search
  system/          System, Agents, Connections, Skills, Settings, …
```

`pages/` removed after moves. Imports updated in `App.tsx` and `app-navigation.ts`.

## Verification

- `npm run typecheck` — pass
- `npm test` — (see command output)

## Shared shell

Unchanged under `components/`, `shared/`, `app-navigation.ts`.
