# ARES Trust and Privacy Model

## Data Classifications

Every piece of data in the Journal must have a sensitivity classification:

| Class | Label | Examples | Who Can See | Default Rule |
|-------|-------|----------|-------------|--------------|
| **Public** | `public` | Weather, general knowledge, public docs | Any worker | Include in briefings freely |
| **Personal** | `personal` | User preferences, project names, habits | Approved providers | Include with disclosure tracking |
| **Private** | `private` | Personal conversations, health, relationships | Local workers only | Redact from cloud briefings |
| **Sensitive** | `sensitive` | Financial data, medical info, legal matters | Explicit user approval per task | Redact by default, require approval |
| **Secret** | `secret` | API keys, passwords, auth tokens | Never leave the device | Never include in any briefing |

## Trust Rules

### Rule 1: Data Classification Gates Provider Eligibility

```
IF data_class == "secret":
    NEVER include in any briefing, never send to any worker
    
IF data_class == "sensitive":
    NEVER include without explicit user approval for THIS task
    Log disclosure in audit ledger
    
IF data_class == "private":
    ONLY include in briefings to local workers (Ollama, local Hermes)
    Redact from cloud provider briefings
    
IF data_class == "personal":
    Include in briefings to approved providers
    Log which provider received what data
    
IF data_class == "public":
    Include freely, no special handling
```

### Rule 2: Local-Only Mode

When the user enables local-only mode:
- ALL data classes above `public` are treated as `private`
- Only local workers (Ollama, local Hermes) receive briefings
- Cloud workers receive only `public` data
- This is a hard override regardless of individual data classifications

### Rule 3: Approval Gates

These actions ALWAYS require explicit user approval:
- Sending `sensitive` data to any worker
- Executing shell commands
- Deleting files
- Making external API calls that modify state
- Spending above a configurable cost threshold

### Rule 4: Irreversible Actions

Irreversible actions MUST:
1. Present the action to the user before executing
2. Show exactly what data will be shared with which worker
3. Wait for approval
4. Log the approval in the activity ledger

### Rule 5: Worker Data Boundaries

- Workers receive ONLY the `ContextBriefing` assembled by the Context Compiler
- Workers CANNOT access the Journal directly
- Workers CANNOT access other workers' outputs unless the SI includes them
- Workers CANNOT initiate actions; the SI dispatches all tasks
- Worker outputs are UNTRUSTED INPUT and MUST be verified

## Implementation

### Phase 1: Sensitivity Column (Required for Context Compiler)

Add to Journal schema:

```sql
ALTER TABLE conversations ADD COLUMN sensitivity TEXT DEFAULT 'personal';
ALTER TABLE messages ADD COLUMN sensitivity TEXT DEFAULT 'personal';
ALTER TABLE documents ADD COLUMN sensitivity TEXT DEFAULT 'personal';
```

Default classification rules:
- Imported conversations → `personal`
- Imported documents → `personal`
- System preferences → `personal`
- API keys in config → `secret`
- Health, financial, legal keywords → `sensitive`
- Public research → `public`

### Phase 2: Trust Engine Module

```python
# api/trust_engine.py

def classify_data(content: str, metadata: dict) -> str:
    """Classify data sensitivity using deterministic rules."""
    # 1. Check explicit tags (user-marked)
    # 2. Check source (secret vault = "secret")
    # 3. Check keywords (financial, medical, legal → "sensitive")
    # 4. Default to "personal"

def filter_briefing(briefing: ContextBriefing, worker: ReasoningProvider) -> ContextBriefing:
    """Remove items from briefing that the worker is not eligible to see."""
    # 1. Get worker's privacy_class
    # 2. For each item in briefing:
    #    a. If sensitivity == "secret": remove
    #    b. If sensitivity == "sensitive" and not user_approved: remove
    #    c. If sensitivity == "private" and worker is cloud: remove
    #    d. Otherwise: include
    # 3. Add removed items to context_manifest as "redacted"
    # 4. Return filtered briefing

def check_approval_required(action: str, data_sensitivity: str) -> bool:
    """Check if an action requires user approval."""
    # Shell commands: always
    # Sensitive data to any worker: always
    # Cost above threshold: always
```

### Phase 3: Disclosure Ledger

```sql
CREATE TABLE disclosure_ledger (
    id INTEGER PRIMARY KEY,
    timestamp REAL,
    session_id TEXT,
    worker_id TEXT,
    data_class TEXT,
    data_source TEXT,  -- conversation, document, preference
    reason TEXT,        -- why this data was shared
    user_approved INTEGER DEFAULT 0
);
```

Every time data leaves the device to a cloud worker, it gets logged here. Users can inspect this ledger to see exactly what data went where and why.