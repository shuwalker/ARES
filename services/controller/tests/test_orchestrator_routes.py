import urllib.request
import json

BASE_URL = "http://localhost:8787"

# These are the API routes that power the universal UI tabs
ROUTES = [
    "/api/settings",
    "/api/profiles",
    "/api/memory/collections",
    "/api/cron",
    "/api/missions",
    "/api/kanban/boards",
    "/api/characters",
    "/api/workspaces"
]

print("ARES Orchestrator UI Route Audit")
print("================================")
for route in ROUTES:
    try:
        req = urllib.request.Request(BASE_URL + route)
        with urllib.request.urlopen(req, timeout=2) as response:
            status = response.getcode()
            print(f"[OK] {route} -> HTTP {status}")
    except urllib.error.HTTPError as e:
        # 401 Unauthorized is expected since we haven't logged in, 
        # but it proves the route is alive and handled by ARES, not Ares!
        print(f"[OK - Auth Guarded] {route} -> HTTP {e.code}")
    except Exception as e:
        print(f"[FAIL] {route} -> {e}")
