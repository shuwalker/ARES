# Security & Privacy Architecture

| Attribute | Details |
| :--- | :--- |
| **Status** | Canonical Security Policy |
| **Audience** | Security Engineers, System Administrators, Maintainers |
| **Owner** | ARES security and controller maintainers |
| **Last verified** | 2026-08-01 |
| **Source of truth** | Security policy, controller enforcement, and security tests |

This document defines the security boundaries, data sensitivity classifications, trust rules, credential isolation, and approval policies enforced by ARES.

---

## 1. Data Sensitivity Classifications

All records ingested into the persistent task and session database are assigned a sensitivity classification level:

| Level | Label | Example Content | Target Access | Enforcement Policy |
| :--- | :--- | :--- | :--- | :--- |
| **Level 0** | `public` | Weather, public docs, general knowledge | Any AI runtime | Included in briefings without restriction. |
| **Level 1** | `personal` | User preferences, project titles, habits | Approved runtimes | Included with provider disclosure logging. |
| **Level 2** | `private` | Personal chat logs, notes, relationships | Local models only | Redacted from all cloud API briefings. |
| **Level 3** | `sensitive` | Financial data, medical info, legal records | Explicit user approval | Redacted by default; requires per-task prompt. |
| **Level 4** | `secret` | API keys, credentials, tokens, passwords | Host device only | **Never included in any model briefing.** |

---

## 2. Security & Privacy Rules

### Rule 1: Sensitivity Gates Provider Eligibility
- Data classified as `secret` is handled strictly by the local host platform controller and is **never** transmitted in prompt text or briefings.
- Data classified as `private` is routed exclusively to approved local on-device models such as Jaeger AI or Ollama.
- Data classified as `sensitive` requires explicit user authorization prior to transmission to any runtime.

### Rule 2: Hard Local-Only Execution Mode
When **Local-Only Mode** is enabled:
- All data classified above `public` is automatically elevated to `private`.
- Communication with remote cloud API runtimes is strictly blocked.
- All context processing is handled on-device by local subprocess agents.

### Rule 3: Explicit User Approval Gates
The platform controller requires explicit interactive user confirmation before taking high-risk actions:
1. Executing shell commands or terminal operations.
2. Writing to external calendars or stateful third-party APIs.
3. Modifying or deleting system files.
4. Transmitting `sensitive` level data across a network boundary.

---

## 3. Credential & Secret Isolation

- API keys, OAuth tokens, and system secrets are managed by the platform secret vault (`services/controller/api/secrets.py`).
- Secrets are passed to subprocess agents via environment variable injection or secure headers. They are **never** rendered into conversational text context or model prompts.

---

## 4. Trust Verification of Runtime Outputs

AI runtimes are treated as **untrusted execution environments**:
- Output from an AI runtime is parsed, sanitized, and verified by the platform controller before being presented to the user or committed to persistent memory.
- Dynamic tool call execution requests must pass schema validation and authorization policy checks prior to invocation.

---

## 5. State Ownership and Read-Only Access

ARES writes only to ARES-owned state. Worker databases, transcripts, and
configuration stores belong to their respective applications. When ARES reads
external history, database connections use read-only mode and must not create
WAL, journal, lock, or migration files in the worker's home directory.

ARES continues a worker conversation through the worker adapter's resume or
append contract. It never simulates continuation by modifying a worker store.
Destructive actions against imported history are refused unless an explicit,
authorized ownership contract exists.

## 6. Local Validation Safety

Development and test runs use isolated ARES, Hermes, and provider state unless
the operator explicitly selects production state. Diagnostic output must not
print API keys, OAuth tokens, cookies, password hashes, complete environment
files, or authentication stores.
