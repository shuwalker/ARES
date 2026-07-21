# JaegerAI Integration — ARES

## Current Status

**SI Pipeline:** Disabled (code kept, not routed)  
**Backend:** Direct JROS → JaegerAI  
**Default:** `jros_local` adapter

## Architecture

```
User (WebUI)
    ↓
FastAPI `/api/chat/stream`
    ↓
JROSBackend (`webui/api/backends/jros.py`)
    ↓
jros_gateway_chat (`webui/api/jros_gateway_chat.py`)
    ↓
JaegerAI (~/jaeger/jaeger)
    ↓
Ollama (gemma4:31b-mlx)
```

## Configuration

### Environment Variables

```bash
# JaegerAI location (auto-detected, optional)
export JAEGER_HOME=~/jaeger

# Gateway URL (if running JaegerAI gateway)
export ARES_JROS_GATEWAY_URL=http://127.0.0.1:8643

# SI Pipeline (disabled by default)
export ARES_SI_ENABLED=false
```

### Settings (`~/.ares/settings.json`)

```json
{
  "si_enabled": false,
  "default_backend": "jros_local"
}
```

## JaegerAI Setup

1. **Install JaegerAI** (if not already):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh | bash
   ```

2. **Verify JaegerAI is running**:
   ```bash
   ~/jaeger/jaeger --self-test
   ```

3. **Check model**:
   ```bash
   ollama list
   # Should show: gemma4:31b-mlx
   ```

## ARES Setup

1. **Install ARES**:
   ```bash
   bash ~/GitHub/ARES/install.sh
   ```

2. **Start ARES**:
   ```bash
   cd ~/GitHub/ARES/ARES-Mac_os
   ./ARES
   ```

3. **Complete onboarding**:
   - Native window detects JaegerAI at `~/jaeger`
   - Shows: JaegerAI = Ready, others = Pending
   - Completes → writes `~/.ares/backend.yaml`

## Testing

### Check JROS Backend Health

```bash
cd ~/GitHub/ARES/webui
.venv/bin/python -c "
from api.backends.jros import JROSBackend
backend = JROSBackend()
print('Available:', backend.is_available())
print('Health:', backend.health())
"
```

### Test Chat Turn

```bash
curl -X POST http://127.0.0.1:8787/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello", "session_id": "test"}'
```

## Re-enable SI Later

To re-enable the SI pipeline:

```bash
export ARES_SI_ENABLED=true
# Or in settings.json:
# { "si_enabled": true }
```

Then restart ARES.

## Files

- **Backend adapter:** `webui/api/backends/jros.py`
- **Gateway bridge:** `webui/api/jros_gateway_chat.py`
- **SI code (disabled):** `webui/api/si/`
- **Onboarding:** `ARES-Mac_os/Sources/ARES/ARESOnboardingView.swift`

