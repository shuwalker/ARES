"""Regression tests for the WebUI /pet handoff."""

import json
from pathlib import Path
import subprocess
import tempfile
import textwrap


REPO_ROOT = Path(__file__).resolve().parents[1]
COMMANDS_JS = (REPO_ROOT / "static" / "commands.js").read_text(encoding="utf-8")
MESSAGES_JS = (REPO_ROOT / "static" / "messages.js").read_text(encoding="utf-8")


def _run_pet_js(*, status, adapter_status=None, hook_result=None, hook_throws=False, command="/pet feed tuna"):
    hook_setup = ""
    if hook_throws:
        hook_setup += textwrap.dedent(
            """
            ctx.window.__hermesHandlePetSlashCommand = async payload => {
              hookCalls.push(payload);
              throw new Error('hook failed');
            };
            """
        )
    elif hook_result is not None:
        hook_setup += textwrap.dedent(
            f"""
            ctx.window.__hermesHandlePetSlashCommand = async payload => {{
              hookCalls.push(payload);
              return {json.dumps(hook_result)};
            }};
            """
        )

    script = textwrap.dedent(
        f"""
        const vm = require('vm');
        const hookCalls = [];
        const window = {{
          __HERMES_WEBUI_DESKTOP_COMPANION_STATUS__: {json.dumps(adapter_status)},
        }};
        window.window = window;
        const ctx = {{
          console,
          window,
          localStorage: {{ getItem(){{return null;}}, setItem(){{}}, removeItem(){{}} }},
          t: key => key,
          api: async path => {{
            if (path === '/api/extensions/status') return {json.dumps(status)};
            throw new Error('unexpected api path: ' + path);
          }},
        }};
        {hook_setup}
        vm.createContext(ctx);
        vm.runInContext({json.dumps(COMMANDS_JS)}, ctx);
        (async () => {{
          const result = await vm.runInContext(`(async () => {{ return await handlePetSlashCommand({json.dumps(command)}, {{name:'pet'}}); }})()`, ctx);
          process.stdout.write(JSON.stringify({{result, hookCalls}}));
        }})().catch(err => {{
          console.error(err && err.stack || err);
          process.exit(1);
        }});
        """
    )
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as handle:
        handle.write(script)
        script_path = Path(handle.name)
    try:
        proc = subprocess.run(["node", str(script_path)], check=True, capture_output=True, text=True)
    finally:
        script_path.unlink(missing_ok=True)
    return json.loads(proc.stdout)


def test_pet_help_routes_to_install_guidance_when_companion_is_missing():
    result = _run_pet_js(
        status={"enabled": False, "extensions": [], "gallery_installed": {}},
        adapter_status=None,
    )

    assert result["result"]["handled"] is False
    message = result["result"]["message"]
    assert "Desktop Companion is not installed yet." in message
    assert "Settings -> Extensions -> Gallery -> Desktop Companion" in message
    assert "https://github.com/franksong2702/hermes-webui-desktop-companion#after-gallery-install" in message
    assert "Desktop Companion app" in message


def test_pet_help_routes_to_enable_guidance_when_companion_is_disabled():
    result = _run_pet_js(
        status={
            "enabled": True,
            "extensions": [
                {
                    "id": "desktop-companion",
                    "name": "Desktop Companion",
                    "effective_enabled": False,
                    "user_disabled": True,
                    "status": "user_disabled",
                }
            ],
        },
        adapter_status=None,
    )

    assert result["result"]["handled"] is False
    message = result["result"]["message"]
    assert "Desktop Companion is installed but disabled." in message
    assert "Enable it in Settings -> Extensions" in message
    assert "Desktop Companion app" in message
    assert "https://github.com/franksong2702/hermes-webui-desktop-companion#after-gallery-install" in message


def test_pet_help_routes_to_reload_and_start_guidance_when_adapter_status_is_missing():
    result = _run_pet_js(
        status={
            "enabled": True,
            "extensions": [
                {
                    "id": "desktop-companion",
                    "name": "Desktop Companion",
                    "effective_enabled": True,
                    "user_disabled": False,
                    "status": "enabled",
                }
            ],
        },
        adapter_status=None,
    )

    assert result["result"]["handled"] is False
    message = result["result"]["message"]
    assert "adapter status is not loaded yet" in message
    assert "Reload WebUI if you just enabled it" in message
    assert "Desktop Companion app" in message


def test_pet_help_routes_to_connect_guidance_when_adapter_is_not_connected():
    result = _run_pet_js(
        status={
            "enabled": True,
            "extensions": [
                {
                    "id": "desktop-companion",
                    "name": "Desktop Companion",
                    "effective_enabled": True,
                    "user_disabled": False,
                    "status": "enabled",
                }
            ],
        },
        adapter_status={"connected": False},
    )

    assert result["result"]["handled"] is False
    message = result["result"]["message"]
    assert "local app is not connected yet" in message
    assert "Start or connect the Desktop Companion app" in message
    assert "Setup guide:" in message


def test_pet_help_hands_off_to_desktop_companion_hook_when_connected():
    result = _run_pet_js(
        status={
            "enabled": True,
            "extensions": [
                {
                    "id": "desktop-companion",
                    "name": "Desktop Companion",
                    "effective_enabled": True,
                    "user_disabled": False,
                    "status": "enabled",
                }
            ],
        },
        adapter_status={"connected": True},
        hook_result={"handled": True, "message": "mascot handled"},
        command="/pet   feed  tuna  ",
    )

    assert result["result"] == {"handled": True, "message": ""}
    assert result["hookCalls"] == [
        {
            "command": "/pet   feed  tuna  ",
            "args": "feed tuna",
            "source": "webui-slash-command",
            "metadata": {"name": "pet"},
        }
    ]


def test_pet_help_falls_back_when_hook_is_missing_or_fails():
    absent = _run_pet_js(
        status={
            "enabled": True,
            "extensions": [
                {
                    "id": "desktop-companion",
                    "name": "Desktop Companion",
                    "effective_enabled": True,
                    "user_disabled": False,
                    "status": "enabled",
                }
            ],
        },
        adapter_status={"connected": True},
    )
    failed = _run_pet_js(
        status={
            "enabled": True,
            "extensions": [
                {
                    "id": "desktop-companion",
                    "name": "Desktop Companion",
                    "effective_enabled": True,
                    "user_disabled": False,
                    "status": "enabled",
                }
            ],
        },
        adapter_status={"connected": True},
        hook_throws=True,
    )

    for result in (absent, failed):
        message = result["result"]["message"]
        assert result["result"]["handled"] is False
        assert "Desktop Companion is installed and connected" in message
        assert "/pet is not available yet in this Desktop Companion version" in message
        assert "Update the Desktop Companion app" in message
        assert "https://github.com/franksong2702/hermes-webui-desktop-companion#after-gallery-install" in message


def test_pet_slash_intercept_bypasses_generic_agent_execution():
    intercept_idx = MESSAGES_JS.find("Slash command intercept")
    normal_send_idx = MESSAGES_JS.find("const activeSid=S.session.session_id", intercept_idx)
    assert intercept_idx != -1
    assert normal_send_idx != -1
    intercept = MESSAGES_JS[intercept_idx:normal_send_idx]

    assert "if(_parsedCmd.name==='pet')" in intercept
    assert "handlePetSlashCommand(text,{name:'pet'})" in intercept
    assert "executeAgentCommand(text,_agentCmd||{name:_agentCmdName})" in intercept
