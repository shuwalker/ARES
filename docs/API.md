# Core REST & Realtime API Contracts

| Attribute | Details |
| :--- | :--- |
| **Status** | Canonical core API contract; not an exhaustive route inventory |
| **Transport** | HTTP/1.1 REST, Server-Sent Events (SSE) |
| **Base URL** | `http://127.0.0.1:8788` |
| **Content-Type** | `application/json`, `text/event-stream` |
| **Audience** | Frontend Developers, SDK Authors, Integration Engineers |
| **Owner** | Controller and client-contract maintainers |
| **Last verified** | 2026-08-01 |
| **Source of truth** | `services/controller/fastapi_app/routers/`, schemas, and tests |

This document describes stable, product-relevant contracts implemented by the
ARES controller. The router source and generated OpenAPI schema remain the
complete route inventory.

---

## 1. Authentication & Global Conventions

### Authentication Headers
All authenticated API requests require an owner identity header or session cookie:
```http
Authorization: Bearer <session_token>
Content-Type: application/json
```

### Standard Error Response Format
All error responses return standard HTTP status codes accompanied by a structured JSON error object:

```json
{
  "error": {
    "code": 404,
    "message": "Task with ID 'task_88a91' was not found",
    "type": "NotFoundError"
  }
}
```

### Standard HTTP Status Codes

| Code | Status | Meaning |
| :--- | :--- | :--- |
| `200` | **OK** | Request completed successfully. |
| `201` | **Created** | Resource created successfully. |
| `400` | **Bad Request** | Malformed request body or invalid parameters. |
| `401` | **Unauthorized** | Missing or invalid authentication credentials. |
| `404` | **Not Found** | Target resource or route does not exist. |
| `500` | **Internal Error** | Controller execution or database error. |

---

## 2. Task & Personal Organizer API (`/api/organizer/*`)

Handles task capture, triage statuses, daily schedule generation, and priority management.

### `POST /api/organizer/tasks`
Creates a new task record in the task database.

**Request Payload (`application/json`)**:
```json
{
  "title": "Renew vehicle registration",
  "priority": "high",
  "due_date": "2026-08-01",
  "estimated_minutes": 45,
  "project": "Personal",
  "context": "online",
  "notes": "Remember to retrieve current insurance policy number"
}
```

**Response (`201 Created`)**:
```json
{
  "id": "7b82e912-3a5c-4f11-92e1-a9821049b1a0",
  "title": "Renew vehicle registration",
  "status": "todo",
  "priority": "high",
  "due_date": "2026-08-01",
  "estimated_minutes": 45,
  "project": "Personal",
  "context": "online",
  "notes": "Remember to retrieve current insurance policy number",
  "created_at": "2026-07-27T15:30:00Z",
  "updated_at": "2026-07-27T15:30:00Z"
}
```

---

### `GET /api/organizer/tasks`
Retrieves a list of tasks, optionally filtered by status.

**Query Parameters**:
- `status` (*optional string*): `inbox` | `todo` | `blocked` | `done` | `cancelled` | `deferred`

**Response (`200 OK`)**:
```json
{
  "tasks": [
    {
      "id": "7b82e912-3a5c-4f11-92e1-a9821049b1a0",
      "title": "Renew vehicle registration",
      "status": "todo",
      "priority": "high",
      "due_date": "2026-08-01",
      "estimated_minutes": 45
    }
  ]
}
```

---

### `POST /api/organizer/capture`
Quickly captures an ambiguous obligation from raw text input into the Inbox.

**Request Payload (`application/json`)**:
```json
{
  "text": "Research Roman road construction techniques for history essay"
}
```

**Response (`200 OK`)**:
```json
{
  "id": "c9102ab3",
  "title": "Research Roman road construction techniques for history essay",
  "status": "inbox",
  "priority": "medium",
  "created_at": "2026-07-27T15:32:00Z"
}
```

---

### `GET /api/organizer/today`
Retrieves task items categorized into today's triage view groups.

**Response (`200 OK`)**:
```json
{
  "now": [],
  "next": [
    { "id": "7b82e912", "title": "Renew vehicle registration", "priority": "high" }
  ],
  "later": [],
  "blocked": [],
  "unscheduled": [
    { "id": "c9102ab3", "title": "Research Roman road construction", "priority": "medium" }
  ]
}
```

---

### `GET /api/organizer/plan`
Runs the deterministic planner to generate a time-blocked schedule for the active day.

**Response (`200 OK`)**:
```json
{
  "plan": [
    {
      "task_id": "7b82e912",
      "task_title": "Renew vehicle registration",
      "start_time": "09:00",
      "duration_minutes": 45
    }
  ],
  "summary": "Today: 1 task scheduled, 1 unscheduled",
  "generated_at": "2026-07-27T15:35:00Z"
}
```

---

## 3. Conversational Turn Execution & Streaming API (`/api/chat/*`)

Handles conversation initialization and real-time streaming of assistant responses.

### `POST /api/chat/start`
Initiates a turn request and allocates an active event stream.

**Request Payload (`application/json`)**:
```json
{
  "session_id": "sess_88a910bf",
  "message": "What tasks are scheduled for me today?",
  "model": "claude-3-5-sonnet",
  "provider": "anthropic"
}
```

**Response (`200 OK`)**:
```json
{
  "status": "ok",
  "stream_id": "str_44190ab2",
  "session_id": "sess_88a910bf"
}
```

---

### `GET /api/chat/stream`
Opens a Server-Sent Events (SSE) connection to receive real-time token deltas and tool execution updates.

**Query Parameters**:
- `stream_id` (*required string*): The stream identifier returned by `/api/chat/start`.

**Stream Events (`text/event-stream`)**:

```http
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive

event: token
data: {"delta": "You "}

event: token
data: {"delta": "have "}

event: token
data: {"delta": "one high-priority task scheduled today."}

event: tool_call
data: {"name": "get_today_tasks", "args": {}}

event: done
data: {"session_id": "sess_88a910bf", "completed_at": "2026-07-27T15:36:00Z"}
```

---

## 4. Provider & Model Registry API (`/api/ares/*`)

Manages available AI execution runtimes and character presentation cards.

### `GET /api/ares/providers`
Lists all registered AI model runtime providers.

**Response (`200 OK`)**:
```json
{
  "providers": [
    {
      "id": "jaeger_local",
      "kind": "runtime",
      "enabled": true,
      "endpoint": "http://127.0.0.1:8000",
      "capabilities": ["chat", "embodiment"]
    }
  ]
}
```

---

### `GET /api/ares/characters`
Retrieves character visual avatar persona metadata cards.

**Response (`200 OK`)**:
```json
{
  "characters": [
    {
      "id": "jarvis",
      "name": "JARVIS",
      "role": "Tactical Assistant",
      "traits": ["precise", "polite", "efficient"],
      "avatar_url": "/assets/characters/jarvis.png"
    }
  ]
}
```

---

## 5. Settings API (`/api/settings`)

### `GET /api/settings`

Returns the authenticated profile's effective settings. Secret values are not
part of this contract.

### `POST /api/settings`

Applies a partial authenticated settings update. Unknown, invalid, or
out-of-range values are rejected or ignored according to controller validation;
clients must read the response as the saved result rather than assuming every
submitted value was accepted.

SI personalization keys:

| Key | Accepted value |
| --- | --- |
| `local_profile_character` | `grounded`, `warm`, `direct`, `curious` |
| `si_cal_verbosity` | `concise`, `balanced`, `explanatory` |
| `si_cal_tone` | `direct`, `balanced`, `conversational` |
| `si_cal_support` | `supportive`, `balanced`, `challenging` |
| `si_cal_initiative` | `reactive`, `balanced`, `proactive` |
| `si_cal_notes` | String, trimmed, maximum 2,000 characters, no null byte |

These are preference keys, not permission or autonomy controls. Their behavior
contract and current implementation status are defined in
[`features/si-personalization.md`](features/si-personalization.md).
