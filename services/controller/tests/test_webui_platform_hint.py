"""Regression: WebUI AIAgent call sites must use platform='webui', not 'cli'.

These are static source-level checks that will catch any future regression where
a developer accidentally reverts the platform kwarg back to 'cli'.
"""
import pathlib
import re

REPO_ROOT = pathlib.Path(__file__).parent.parent
PLATFORM_KWARG_RE = r'platform\s*=\s*["\']{platform}["\']'


def _load_source(relative_path: str) -> str:
    """Load a repository source file with a focused assertion on missing files."""
    path = REPO_ROOT / relative_path
    assert path.exists(), f"{relative_path} does not exist"
    return path.read_text(encoding="utf-8")


def _count_platform_kwargs(source: str, platform: str) -> int:
    return len(re.findall(PLATFORM_KWARG_RE.format(platform=re.escape(platform)), source))


def test_streaming_uses_webui_platform():
    """api/streaming.py must pass platform='webui' when constructing AIAgent."""
    streaming_py = _load_source("api/streaming.py")
    webui_count = _count_platform_kwargs(streaming_py, "webui")
    cli_count = _count_platform_kwargs(streaming_py, "cli")
    assert cli_count == 0, (
        f"streaming.py still has {cli_count} platform='cli' AIAgent call(s); convert to 'webui'"
    )
    assert webui_count >= 1, (
        f"streaming.py expected ≥1 platform='webui' call, found {webui_count}"
    )


def test_fastapi_transport_does_not_construct_agents_directly():
    """Framework adapters delegate generation to the canonical chat runtime."""
    adapters = _load_source("fastapi_app/adapters/frameworks.py")
    realtime = _load_source("fastapi_app/realtime.py")
    assert "AIAgent(" not in adapters + realtime
    assert "from api.chat_runtime import start_session_turn" in adapters
