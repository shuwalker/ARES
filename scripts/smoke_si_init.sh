#!/usr/bin/env bash
# ARES SI initiation smoke test
#
# Success criteria (golden path):
#   1. Controller health: status=ok, si_enabled=true
#   2. Direct si_turn returns text containing SI-OK (no error)
#   3. Live HTTP: session/new → chat/start → stream completes → assistant SI-OK
#   4. Second turn still works
#
# Usage:
#   ./scripts/smoke_si_init.sh
#   BASE_URL=http://127.0.0.1:8787 WORKER=hermes_local ./scripts/smoke_si_init.sh
#
# Exit 0 = initiation success. Exit 1 = failure.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEBUI="${ROOT}/webui"
BASE_URL="${BASE_URL:-http://127.0.0.1:8787}"
WORKER="${WORKER:-hermes_local}"
PROMPT="${PROMPT:-Reply with exactly: SI-OK}"
EXPECT="${EXPECT:-SI-OK}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-90}"
STREAM_WAIT_SEC="${STREAM_WAIT_SEC:-90}"
TMPDIR_SMOKE="${TMPDIR:-/tmp}/ares-si-smoke-$$"
mkdir -p "$TMPDIR_SMOKE"
trap 'rm -rf "$TMPDIR_SMOKE"' EXIT

RED=$'\033[31m';GRN=$'\033[32m';YLW=$'\033[33m';RST=$'\033[0m'
pass() { echo "${GRN}✓${RST} $*"; }
fail() { echo "${RED}✗${RST} $*" >&2; exit 1; }
info() { echo "${YLW}·${RST} $*"; }

need() { command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }
need curl
need python3

PYTHON="${WEBUI}/.venv/bin/python"
[[ -x "$PYTHON" ]] || PYTHON=python3

json_file_get() {
  # json_file_get file.pyon-expr  e.g. json_file_get /tmp/x.json "d.get('status')"
  local file="$1"
  local expr="$2"
  FILE="$file" EXPR="$expr" python3 - <<'PY'
import json, os
with open(os.environ["FILE"], encoding="utf-8") as f:
    d = json.load(f)
print(eval(os.environ["EXPR"], {"d": d}))
PY
}

wait_stream_done() {
  local stream_id="$1"
  local deadline=$((SECONDS + STREAM_WAIT_SEC))
  local active="true"
  while (( SECONDS < deadline )); do
    curl -s -m 5 "$BASE_URL/api/chat/stream/status?stream_id=$stream_id" \
      -o "$TMPDIR_SMOKE/status.json" || echo '{}' >"$TMPDIR_SMOKE/status.json"
    active=$(json_file_get "$TMPDIR_SMOKE/status.json" "d.get('active')" 2>/dev/null || echo true)
    if [[ "$active" == "False" || "$active" == "false" || "$active" == "None" ]]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

echo "=== ARES SI initiation smoke ==="
echo "BASE_URL=$BASE_URL  WORKER=$WORKER"
echo

# --- 1. Health ---
info "health"
HEALTH_CODE=$(curl -s -m 5 -o "$TMPDIR_SMOKE/health.json" -w '%{http_code}' "$BASE_URL/api/health" || true)
[[ "$HEALTH_CODE" == "200" ]] || fail "health HTTP $HEALTH_CODE (is LaunchAgent/webui running?)"
STATUS=$(json_file_get "$TMPDIR_SMOKE/health.json" "d.get('status')")
SI=$(json_file_get "$TMPDIR_SMOKE/health.json" "d.get('si_enabled')")
[[ "$STATUS" == "ok" ]] || fail "health status=$STATUS"
[[ "$SI" == "True" || "$SI" == "true" ]] || fail "si_enabled=$SI (want true). Check ARES_SI_ENABLED / settings."
pass "health ok, si_enabled=true"

# --- 2. Direct si_turn (in-process) ---
info "direct si_turn via $WORKER"
export ARES_SI_ENABLED=1
export PYTHONPATH="${WEBUI}${PYTHONPATH:+:$PYTHONPATH}"
PROMPT="$PROMPT" WORKER="$WORKER" EXPECT="$EXPECT" WEBUI="$WEBUI" \
  "$PYTHON" - <<'PY' >"$TMPDIR_SMOKE/direct.json"
import json, os, sys, time
sys.path.insert(0, os.environ["WEBUI"])
from api.si.bridge import si_enabled, si_turn

assert si_enabled(), "si_enabled() false in-process"
prompt = os.environ["PROMPT"]
worker = os.environ["WORKER"]
expect = os.environ["EXPECT"]
t0 = time.time()
r = si_turn(prompt, session_id="smoke-direct", target_worker=worker)
out = {
    "elapsed": round(time.time() - t0, 1),
    "error": r.get("error"),
    "worker": r.get("worker"),
    "text": (r.get("text") or "")[:500],
    "intent": r.get("intent"),
}
print(json.dumps(out))
err = out.get("error")
if err is not None and str(err).strip() and str(err).strip().lower() not in ("none", "null"):
    sys.stderr.write(f"direct error: {err}\n")
    sys.exit(1)
if expect not in (out.get("text") or ""):
    sys.stderr.write(f"missing {expect!r} in {out.get('text')!r}\n")
    sys.exit(1)
PY
DIRECT_ELAPSED=$(json_file_get "$TMPDIR_SMOKE/direct.json" "d.get('elapsed')")
DIRECT_WORKER=$(json_file_get "$TMPDIR_SMOKE/direct.json" "d.get('worker')")
pass "direct si_turn ok (${DIRECT_ELAPSED}s, worker=$DIRECT_WORKER)"

# --- 3. Live HTTP chat path ---
info "HTTP session/new"
mkdir -p "${HOME}/workspace"
curl -s -m 15 -X POST "$BASE_URL/api/session/new" \
  -H 'Content-Type: application/json' \
  -d '{}' -o "$TMPDIR_SMOKE/new.json" \
  || fail "session/new request failed"
SID=$(json_file_get "$TMPDIR_SMOKE/new.json" "(d.get('session') or d).get('session_id') or ''")
[[ -n "$SID" ]] || fail "no session_id from session/new"
pass "session created: $SID"

info "HTTP chat/start"
# Build JSON body safely
PROMPT="$PROMPT" SID="$SID" WORKER="$WORKER" python3 - <<'PY' >"$TMPDIR_SMOKE/start_body.json"
import json, os
print(json.dumps({
    "session_id": os.environ["SID"],
    "message": os.environ["PROMPT"],
    "connection_id": os.environ["WORKER"],
}))
PY
curl -s -m "$HTTP_TIMEOUT" -X POST "$BASE_URL/api/chat/start" \
  -H 'Content-Type: application/json' \
  -d @"$TMPDIR_SMOKE/start_body.json" \
  -o "$TMPDIR_SMOKE/start.json" \
  || fail "chat/start request failed"
STREAM=$(json_file_get "$TMPDIR_SMOKE/start.json" "d.get('stream_id') or ''")
[[ -n "$STREAM" ]] || fail "chat/start did not return stream_id: $(cat "$TMPDIR_SMOKE/start.json")"
pass "stream started: $STREAM"

info "wait for stream inactive (max ${STREAM_WAIT_SEC}s)"
wait_stream_done "$STREAM" || fail "stream still active after ${STREAM_WAIT_SEC}s"
pass "stream completed"

info "session messages"
curl -s -m 15 "$BASE_URL/api/session?session_id=$SID" -o "$TMPDIR_SMOKE/session.json"
EXPECT="$EXPECT" SESSION_JSON="$TMPDIR_SMOKE/session.json" python3 - <<'PY'
import json, os, sys
with open(os.environ["SESSION_JSON"], encoding="utf-8") as f:
    d = json.load(f)
s = d.get("session") or d
msgs = s.get("messages") or []
expect = os.environ["EXPECT"]
print(f"  backend={s.get('ares_backend')} message_count={s.get('message_count')} msgs={len(msgs)}")
ok = False
for m in msgs:
    role = m.get("role")
    content = m.get("content") or ""
    print(f"  {role}: {content[:200]!r}")
    if role == "assistant" and expect in content:
        ok = True
if not ok:
    sys.exit(2)
PY
case $? in
  0) pass "HTTP path assistant returned ${EXPECT}" ;;
  2) fail "HTTP session missing assistant ${EXPECT}" ;;
  *) fail "failed to parse session response" ;;
esac

# --- 4. Second turn ---
info "second turn"
PROMPT2="Reply with exactly: SI-2"
SID="$SID" WORKER="$WORKER" PROMPT2="$PROMPT2" python3 - <<'PY' >"$TMPDIR_SMOKE/start2_body.json"
import json, os
print(json.dumps({
    "session_id": os.environ["SID"],
    "message": os.environ["PROMPT2"],
    "connection_id": os.environ["WORKER"],
}))
PY
curl -s -m "$HTTP_TIMEOUT" -X POST "$BASE_URL/api/chat/start" \
  -H 'Content-Type: application/json' \
  -d @"$TMPDIR_SMOKE/start2_body.json" \
  -o "$TMPDIR_SMOKE/start2.json" \
  || fail "second chat/start failed"
STREAM2=$(json_file_get "$TMPDIR_SMOKE/start2.json" "d.get('stream_id') or ''")
[[ -n "$STREAM2" ]] || fail "second turn no stream_id: $(cat "$TMPDIR_SMOKE/start2.json")"
wait_stream_done "$STREAM2" || fail "second stream still active"
curl -s -m 15 "$BASE_URL/api/session?session_id=$SID" -o "$TMPDIR_SMOKE/session2.json"
SESSION_JSON="$TMPDIR_SMOKE/session2.json" python3 - <<'PY'
import json, os, sys
with open(os.environ["SESSION_JSON"], encoding="utf-8") as f:
    d = json.load(f)
s = d.get("session") or d
texts = " ".join(
    (m.get("content") or "")
    for m in (s.get("messages") or [])
    if m.get("role") == "assistant"
)
if "SI-2" not in texts and "SI-OK" not in texts:
    print("assistant texts:", texts[:400])
    sys.exit(2)
print(f"  second-turn messages ok, count={s.get('message_count')}")
PY
case $? in
  0) pass "second turn ok" ;;
  *) fail "second turn did not complete with expected text" ;;
esac

echo
pass "SI INITIATION SUCCESS"
echo "session_id=$SID worker=$WORKER"
exit 0
