#!/usr/bin/env python3
"""
Headless browser smoke test — the console-error page-load gate.

WHY THIS EXISTS
  `node --check`, ESLint, and the (mocked) pytest suite cannot see the class of
  bug that has actually bricked releases: JavaScript that parses fine but throws
  at *runtime* when a real browser executes the page. Examples that shipped:
    - a `const` reassigned at runtime (v0.51.168 "Failed to load conversation
      messages" — #3162)
    - a `function X(){}` colliding with a `window.X = {}` in classic scripts
      (#2715 / #2771)
  Every one of those throws on load or first interaction and produces a blank or
  broken page for *every* user. This smoke boots the production ASGI app and loads
  the key pages in headless Chromium, failing if ANY uncaught exception or
  console error fires.

SCOPE
  Deliberately AGENT-FREE so it runs in CI (which does not install ares-agent):
  it verifies the page loads and its JS initializes cleanly — it does NOT drive a
  full chat (that needs the agent + mock provider and runs in the private QA
  harness's golden-path E2E). This is the "does the app even come up without
  throwing" gate, which is the highest-frequency brick class.

USAGE
  python tests/browser_smoke.py
  (Requires: playwright + chromium. Boots Uvicorn on an ephemeral port with an
  isolated temp state dir and no agent.)

EXIT CODES
  0 — all pages loaded with zero console errors / uncaught exceptions
  1 — a console error or uncaught exception was detected (regression)
  2 — environment/setup failure (server didn't boot, playwright missing, etc.)
"""
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error

PORT = int(os.getenv("SMOKE_PORT", "8796"))
BASE = f"http://127.0.0.1:{PORT}"

# Every registered workspace route must execute cleanly in the production build.
PAGES = [
    "/today", "/conversation", "/search", "/workspace", "/board",
    "/canvas", "/terminal", "/hatchery", "/inbox", "/issues",
    "/projects", "/cases", "/goals", "/timeline", "/schedules",
    "/skills", "/secrets", "/activity", "/agents", "/usage",
    "/connections", "/webhooks", "/pairing", "/mcp", "/config",
]

# Known-benign console noise (extend deliberately, each with a reason). Every
# entry here is a blind spot, so keep the list short.
BENIGN = [
    "favicon",          # favicon 404 in bare env — not app code
    "manifest.json",    # PWA manifest probe under headless http
    "serviceworker",    # SW registration noise under headless http
    "sw.js",            # service worker fetch noise
    "the server responded with a status of 404",  # static asset 404 in bare env
]


def _is_benign(text):
    t = text.lower()
    return any(p.lower() in t for p in BENIGN)


def _wait_for_health(timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(BASE + "/health", timeout=2) as r:
                if r.status == 200:
                    return True
        except (urllib.error.URLError, OSError):
            pass
        time.sleep(0.5)
    return False


def main():
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("SKIP: playwright not installed", file=sys.stderr)
        return 2

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    app_py = os.path.join(repo_root, "fastapi_app", "main.py")
    if not os.path.exists(app_py):
        print(f"SETUP FAIL: FastAPI app not found at {app_py}", file=sys.stderr)
        return 2

    state_dir = tempfile.mkdtemp(prefix="ares-browser-smoke-")
    env = os.environ.copy()
    # Strip real provider keys so nothing leaks into the smoke server.
    for k in list(env):
        if k.endswith("_API_KEY"):
            env.pop(k, None)
    env.update({
        "ARES_WEBUI_PORT": str(PORT),
        "ARES_WEBUI_HOST": "127.0.0.1",
        "ARES_WEBUI_STATE_DIR": state_dir,
        "ARES_HOME": state_dir,
        "ARES_BASE_HOME": state_dir,
        # Point agent discovery at a path that doesn't exist — the server is
        # designed to boot and serve the UI even when the agent is absent.
        "ARES_WEBUI_AGENT_DIR": os.path.join(state_dir, "no-agent"),
    })

    log = open(os.path.join(state_dir, "server.log"), "w")
    proc = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "uvicorn",
            "fastapi_app.main:app",
            "--host",
            "127.0.0.1",
            "--port",
            str(PORT),
            "--no-server-header",
        ],
        cwd=repo_root, env=env,
        stdout=log, stderr=subprocess.STDOUT,
        **({"creationflags": subprocess.CREATE_NO_WINDOW} if sys.platform == "win32" else {}),
    )
    try:
        if not _wait_for_health(timeout=30):
            print("SETUP FAIL: server did not become healthy in 30s", file=sys.stderr)
            log.flush()
            with open(os.path.join(state_dir, "server.log")) as f:
                print(f.read()[-2000:], file=sys.stderr)
            return 2

        failures = []
        with sync_playwright() as pw:
            browser = pw.chromium.launch(
                headless=True, args=["--no-sandbox", "--disable-dev-shm-usage"]
            )
            # Exercise the real first-run contract before opening workspace
            # routes. No provider, model, agent framework, or credential is
            # installed in this environment; setup must still finish.
            ctx = browser.new_context(base_url=BASE)
            page = ctx.new_page()
            onboarding_errors = []
            page.on("console", lambda m: onboarding_errors.append(("console", m.text))
                    if m.type == "error" else None)
            page.on("pageerror", lambda e: onboarding_errors.append(("pageerror", str(e))))
            page.goto("/", wait_until="domcontentloaded")
            page.get_by_role("heading", name="A personal intelligence, built around you.").wait_for(timeout=30000)
            page.get_by_role("button", name="Shape the experience").click()
            page.get_by_label("What should ARES call you?").fill("Browser Smoke")
            page.get_by_label("What should your SI be called?").fill("Beacon")
            page.get_by_role("button", name="Continue").click()
            page.get_by_role("heading", name="Shape Beacon.").wait_for(timeout=15000)
            page.get_by_role("button", name="curious").click()
            page.get_by_role("button", name="Health").click()
            page.get_by_role("button", name="Tell me things").click()
            page.get_by_role("button", name="Continue").click()
            page.get_by_role("button", name="Your tailnet").click()
            page.get_by_role("button", name="Save Local Profile").click()
            page.get_by_role("heading", name="Choose how ARES thinks.").wait_for(timeout=30000)
            page.get_by_role("button", name="Review setup").click()
            page.get_by_text("Saved locally", exact=True).wait_for(timeout=30000)

            settings_response = page.request.get(BASE + "/api/settings")
            if not settings_response.ok:
                failures.append(f"  [onboarding] settings read returned {settings_response.status}")
            else:
                saved = settings_response.json()
                expected = {
                    "owner_name": "Browser Smoke",
                    "bot_name": "Beacon",
                    "local_profile_setup_mode": "advanced",
                    "local_profile_character": "curious",
                    "local_profile_autonomy": "observe",
                    "local_profile_reachability": "private-network",
                    "local_profile_life_areas": ["health"],
                }
                for key, value in expected.items():
                    if saved.get(key) != value:
                        failures.append(
                            f"  [onboarding] {key}={saved.get(key)!r}, expected {value!r}"
                        )

            page.get_by_role("button", name="Open ARES").click()
            page.wait_for_url("**/today", timeout=15000)

            # Exercise the command-center wiring itself, not just its route
            # modules. The persistent workbench must switch real implementations
            # in place and the mode rail must navigate without a page reload.
            files_tab = page.get_by_role("tab", name="files", exact=True)
            terminal_tab = page.get_by_role("tab", name="terminal", exact=True)
            files_tab.wait_for(timeout=15000)
            if files_tab.get_attribute("aria-selected") != "true":
                failures.append("  [command-center] Files workbench was not selected by default")
            terminal_tab.click()
            if terminal_tab.get_attribute("aria-selected") != "true":
                failures.append("  [command-center] Terminal workbench did not activate")
            page.get_by_label("Terminal", exact=True).wait_for(timeout=15000)
            files_tab.click()
            if files_tab.get_attribute("aria-selected") != "true":
                failures.append("  [command-center] Files workbench did not reactivate")

            page.get_by_role("link", name="Chat", exact=True).click()
            page.wait_for_url("**/conversation", timeout=15000)
            page.get_by_role("link", name="Core", exact=True).click()
            page.wait_for_url("**/today", timeout=15000)

            meaningful = [
                (kind, txt) for (kind, txt) in onboarding_errors
                if not _is_benign(txt)
            ]
            if meaningful:
                failures.extend(
                    f"  [onboarding] {kind}: {txt}" for kind, txt in meaningful
                )
            else:
                print("OK  / — Advanced Local Profile setup without a runtime")
            ctx.close()

            for path in PAGES:
                ctx = browser.new_context(base_url=BASE)
                page = ctx.new_page()
                errors = []
                page.on("console", lambda m: errors.append(("console", m.text))
                        if m.type == "error" else None)
                page.on("pageerror", lambda e: errors.append(("pageerror", str(e))))

                page.goto(path, wait_until="domcontentloaded")
                # Give boot.js / view init time to run and throw if it's going to.
                try:
                    page.wait_for_selector("#msg, .app, body", timeout=10000)
                except Exception:
                    pass
                time.sleep(1.5)

                meaningful = [(kind, txt) for (kind, txt) in errors if not _is_benign(txt)]
                if meaningful:
                    for kind, txt in meaningful:
                        failures.append(f"  [{path}] {kind}: {txt}")
                else:
                    print(f"OK  {path} — no console errors")
                ctx.close()
            browser.close()

        if failures:
            print("\nBROWSER SMOKE FAILED — runtime JS errors detected:", file=sys.stderr)
            print("\n".join(failures), file=sys.stderr)
            return 1
        print("\nBROWSER SMOKE PASSED — all pages loaded with zero console errors")
        return 0
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


if __name__ == "__main__":
    sys.exit(main())
