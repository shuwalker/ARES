# ARES Face — Hermes Backend Verification Plan
## Objective: Prove the app is no longer using stub/fake ("fakeray") logic and is successfully communicating with the real Hermes backend.

---

## Current State Summary

| Component | Status | Endpoint |
|---|---|---|
| Hermes Gateway | RUNNING | :8644 (webhook), Discord: ARES#5642 |
| ARES API | RUNNING | :7860 (uvicorn) |
| Dashboard | RUNNING | :9119 |
| MCP Servers | RUNNING | :9512 (perception), :9513 (voice), :9514 (avatar), :9515 (cad), :9516 (simulation), :9517 (generation), :9519 (motor) |
| `hermes_bridge.py` (stub) | EXISTS but likely UNREFERENCED | :9876 |
| ARES.app bundle | EXISTS but Swift project path is missing | — |

> The `hermes_bridge.py` at `src/ares/runtime/hermes_bridge.py` contains a `cognition_query()` stub that returns **random canned responses** (e.g., "I'm thinking about that...", "I'm listening — go ahead..."). If the app is wired to port 9876, it is using "fakeray" logic. If it is wired to :7860 or :8644, it is using the real backend.

---

## Phase 1: Code Audit — Confirm No Fakeray Remains

### 1.1 Search codebase for fakeray/stub references
```bash
grep -ri "fakeray\|fake.*ray\|cognition_query\|canned_response\|random.choice(STATES)" \
  /Users/matthewjenkins/src/ares \
  /Users/matthewjenkins/ARES_Brain \
  /Users/matthewjenkins/.hermes/skills/ares_router \
  /Users/matthewjenkins/Applications/ARES.app \
  2>/dev/null
```
**Pass criteria:** No matches outside of `hermes_bridge.py` itself.

### 1.2 Verify ARES.app binary target
Check `/Users/matthewjenkins/Applications/ARES.app/Contents/MacOS/ARES` — it references:
```bash
BINARY="$PROJECT/.build/arm64-apple-macosx/debug/ARES"
```
where `PROJECT="/Users/matthewjenkins/Documents/GitHub/ARES-App"`.
**Pass criteria:** The Swift project exists OR the app has been rebuilt to point to the real backend. If the path is broken, the app cannot start → confirm it is not running old fakeray logic.

### 1.3 Search all source for port 9876 / hermes_bridge
```bash
grep -r "9876\|hermes_bridge" \
  /Users/matthewjenkins/Documents/GitHub/ARES-App \
  /Users/matthewjenkins/src \
  /Users/matthewjenkins/ARES_Brain \
  --include="*.swift" --include="*.py" --include="*.json" --include="*.yaml" --include="*.plist" 2>/dev/null
```
**Pass criteria:** Zero references. If found, the app is still pointing at the stub.

---

## Phase 2: Runtime Verification — Network & Process

### 2.1 Confirm no process bound to port 9876
```bash
lsof -i -P | grep :9876
```
**Pass criteria:** Nothing listening. If `hermes_bridge.py` is running, kill it and investigate why.

### 2.2 Confirm ARES API and Gateway are active
```bash
curl -s http://127.0.0.1:7860/health || echo "ARES API unreachable"
curl -s http://127.0.0.1:8644/ || echo "Gateway HTTP root unreachable"
```
**Pass criteria:** Both return valid HTTP responses (even if 404, the port is alive).

### 2.3 Confirm Hermes gateway Discord connectivity
```bash
grep "Connected as ARES" /Users/matthewjenkins/.hermes/logs/gateway.log | tail -1
```
**Pass criteria:** Log line shows `Connected as ARES#5642` with recent timestamp.

---

## Phase 3: End-to-End Communication Test

### 3.1 Send a query to the real backend and verify non-canned response
```bash
curl -s -X POST http://127.0.0.1:7860/think \
  -H "Content-Type: application/json" \
  -d '{"text":"What is the capital of France?","session_id":"verify-test"}' \
  | jq .
```
**Pass criteria:** Response contains actual knowledge (e.g., "Paris") — NOT a canned string like "I'm thinking about that..." or a random state cycling.

### 3.2 Verify response latency indicates real model inference
**Pass criteria:** Response takes > 1 second (real LLM inference time). The stub on port 9876 returns instantly (< 100 ms).

### 3.3 Check gateway logs for the session
```bash
grep "verify-test" /Users/matthewjenkins/.hermes/logs/gateway.log | tail -5
```
**Pass criteria:** Logs show the session ID passing through the real gateway pipeline.

### 3.4 Verify ARES Face app network traffic (if app is running)
If the ARES Face app process is active:
```bash
lsof -p $(pgrep -f "ARES.*debug") | grep -E "(7860|8644|9512|9513|9514)"
```
**Pass criteria:** Open file descriptors connect to real backend ports, NOT port 9876.

---

## Phase 4: Log Audit — Prove Real Hermes Backend Is Handling Traffic

### 4.1 Gateway log audit
```bash
tail -n 50 /Users/matthewjenkins/.hermes/logs/gateway.log
```
**Pass criteria:** Recent entries show:
- `inbound message:` with real user messages
- `response ready:` with non-zero `api_calls` and `response=...` char counts
- `platform=discord` or `platform=webhook` activity within last hour

### 4.2 Error log audit — ensure no stub fallback
```bash
grep -i "stub response\|fakeray\|canned" /Users/matthewjenkins/.hermes/logs/*.log
```
**Pass criteria:** No matches. (Hermes uses "stub response" language only for error-recovery edge cases — confirm these are timeout errors, not normal flow.)

### 4.3 Session dump audit
```bash
ls -lt /Users/matthewjenkins/.hermes/sessions/session_*.json | head -3
```
Read the most recent session file.
**Pass criteria:** Messages array contains real user/assistant exchanges with substantive content, not `[session:xxx] I'm thinking about that...`.

---

## Phase 5: Hermes Bridge File Status

### 5.1 Mark the stub as deprecated
If `src/ares/runtime/hermes_bridge.py` still exists unchanged:
- Either delete it, rename it, or add a clear deprecation banner to prevent accidental re-activation.

**Action:**
```bash
mv /Users/matthewjenkins/src/ares/runtime/hermes_bridge.py \
   /Users/matthewjenkins/src/ares/runtime/hermes_bridge.py.DEPRECATED
```

### 5.2 Update tests
If `/Users/matthewjenkins/tests/runtime/test_hermes_bridge.py` exists:
- Delete or archive it so CI does not continue validating the stub.

---

## Sign-off Checklist

| # | Check | How to verify | Pass |
|---|---|---|---|
| 1 | No "fakeray" / "hermes_bridge" references in app source | `grep -r` across project | [ ] |
| 2 | Port 9876 is NOT listening | `lsof -i :9876` returns empty | [ ] |
| 3 | ARES API (:7860) responds | `curl` returns valid JSON | [ ] |
| 4 | Gateway (:8644) is alive | `curl` returns HTTP | [ ] |
| 5 | Real inference latency observed | Response > 1s, contains real content | [ ] |
| 6 | Gateway logs show real traffic | `tail gateway.log` has recent `response ready` | [ ] |
| 7 | No stub/canned responses in latest session | Inspect latest `.hermes/sessions/*.json` | [ ] |
| 8 | `hermes_bridge.py` is deprecated/removed | File renamed or deleted | [ ] |
| 9 | Test file `test_hermes_bridge.py` is deprecated | File renamed or deleted | [ ] |
| 10 | ARES Face app connects to :7860 or :8644 | `lsof` on app PID shows correct ports | [ ] |

---

## Automated Smoke Test Script

Save as `/Users/matthewjenkins/verify_ares_hermes.sh` and run:

```bash
#!/bin/bash
set -euo pipefail

echo "=== ARES Hermes Backend Verification ==="

# 1. Port 9876 check
if lsof -Pi :9876 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "FAIL: Port 9876 (stub) is still listening"; exit 1
else
    echo "PASS: Port 9876 is free"
fi

# 2. ARES API health check
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7860/health 2>/dev/null | grep -q "200\|404"; then
    echo "PASS: ARES API (:7860) is reachable"
else
    echo "FAIL: ARES API (:7860) unreachable"; exit 1
fi

# 3. Real inference check
echo "Testing real inference..."
START=$(date +%s%3N)
RESP=$(curl -s -X POST http://127.0.0.1:7860/think \
  -H "Content-Type: application/json" \
  -d '{"text":"What color is the sky on a clear day?","session_id":"verify-ares-001"}' 2>/dev/null || echo "")
END=$(date +%s%3N)
LATENCY=$((END - START))

if echo "$RESP" | grep -iq "blue"; then
    echo "PASS: Real inference returned substantive answer (blue) in ${LATENCY}ms"
else
    echo "FAIL: Response was not substantive: $RESP"; exit 1
fi

# 4. Gateway log activity
if grep -q "response ready" /Users/matthewjenkins/.hermes/logs/gateway.log; then
    echo "PASS: Gateway logs show real response activity"
else
    echo "FAIL: No response activity in gateway logs"; exit 1
fi

echo "=== ALL CHECKS PASSED ==="
```

---

## Files Created
- `/Users/matthewjenkins/ares_hermes_verification_plan.md` — this plan
- `/Users/matthewjenkins/verify_ares_hermes.sh` — automated smoke test (optional)
