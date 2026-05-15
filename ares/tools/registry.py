"""Tool registry for ARES.

Lives at ~/.ares/memory/tools/registry.toml — plain TOML, human-editable.

Each tool entry looks like:
[tools.n8n]
name = "n8n"
description = "Workflow automation platform"
install_method = "npm"
install_command = "npm install -g n8n"
check_command = "n8n --version"
url = "http://localhost:5678"
installed = true
version = "1.x.x"
notes = "Primary workflow engine"
"""

from __future__ import annotations

import subprocess
import tomllib
import tomli_w
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any, Awaitable, Callable, TYPE_CHECKING

from ares.runtime.config import ares_paths
from ares.runtime.audit import log_sync

if TYPE_CHECKING:
    from ares.core.reasoning import Plan, PlanStage
    from ..tasks.queue import Task


# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------

class ToolNotFoundError(Exception):
    """Stage references a tool the registry doesn't know about."""


class ToolNotInstalledError(Exception):
    """Stage references a tool that's registered but not installed."""



# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------


@dataclass
class ToolEntry:
    name: str
    description: str = ""
    install_method: str = ""  # brew | npm | pip | manual | none
    install_command: str = ""
    check_command: str = ""
    url: str = ""
    installed: bool = False
    version: str = ""
    notes: str = ""
    quirks: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Registry paths
# ---------------------------------------------------------------------------


def registry_path() -> Path:
    return ares_paths()["memory_tools"] / "registry.toml"


# ---------------------------------------------------------------------------
# Read / write
# ---------------------------------------------------------------------------


def load_registry() -> dict[str, ToolEntry]:
    path = registry_path()
    if not path.exists():
        return {}
    with open(path, "rb") as fh:
        raw = tomllib.load(fh)
    tools_raw = raw.get("tools", {})
    result: dict[str, ToolEntry] = {}
    for key, data in tools_raw.items():
        result[key] = ToolEntry(
            name=data.get("name", key),
            description=data.get("description", ""),
            install_method=data.get("install_method", ""),
            install_command=data.get("install_command", ""),
            check_command=data.get("check_command", ""),
            url=data.get("url", ""),
            installed=data.get("installed", False),
            version=data.get("version", ""),
            notes=data.get("notes", ""),
            quirks=data.get("quirks", []),
        )
    return result


def save_registry(tools: dict[str, ToolEntry]) -> Path:
    path = registry_path()
    data: dict[str, Any] = {"tools": {}}
    for key, entry in tools.items():
        d = asdict(entry)
        data["tools"][key] = d
    with open(path, "wb") as fh:
        tomli_w.dump(data, fh)
    return path


def register_tool(key: str, entry: ToolEntry) -> None:
    tools = load_registry()
    tools[key] = entry
    save_registry(tools)
    log_sync(action="tool_registered", tool=key)


def get_tool(key: str) -> ToolEntry | None:
    return load_registry().get(key)


def mark_installed(key: str, version: str = "") -> None:
    tools = load_registry()
    if key in tools:
        tools[key].installed = True
        tools[key].version = version
        save_registry(tools)


# ---------------------------------------------------------------------------
# Install / check helpers
# ---------------------------------------------------------------------------


def check_tool_installed(entry: ToolEntry) -> tuple[bool, str]:
    """Run check_command and return (installed, version_string)."""
    if not entry.check_command:
        return False, ""
    try:
        result = subprocess.run(
            entry.check_command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            version = result.stdout.strip().splitlines()[0] if result.stdout else ""
            return True, version
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return False, ""


def probe_all_tools() -> dict[str, bool]:
    """Check installation status for all registered tools."""
    tools = load_registry()
    status: dict[str, bool] = {}
    for key, entry in tools.items():
        installed, version = check_tool_installed(entry)
        if installed and not entry.installed:
            tools[key].installed = True
            tools[key].version = version
        status[key] = installed
    save_registry(tools)
    return status


# ---------------------------------------------------------------------------
# Built-in tool definitions (pre-populated registry)
# ---------------------------------------------------------------------------

BUILT_IN_TOOLS: dict[str, ToolEntry] = {
    "n8n": ToolEntry(
        name="n8n",
        description="Workflow automation platform — visible, editable workflows",
        install_method="npm",
        install_command="npm install -g n8n",
        check_command="n8n --version",
        url="http://localhost:5678",
        notes="Primary workflow engine for ARES automations",
    ),
    "elevenlabs": ToolEntry(
        name="ElevenLabs",
        description="AI voice synthesis — cloned voice TTS",
        install_method="none",
        url="https://elevenlabs.io",
        notes="Web API, no local install needed. Requires API key.",
    ),
    "davinci_resolve": ToolEntry(
        name="DaVinci Resolve",
        description="Professional video editor — .drp project format",
        install_method="manual",
        url="https://www.blackmagicdesign.com/products/davinciresolve",
        notes="GUI app. ARES opens .drp files and can script via Lua API.",
    ),
    "lm_studio": ToolEntry(
        name="LM Studio",
        description="Local LLM inference server — OpenAI-compatible API",
        install_method="manual",
        url="http://localhost:1234",
        check_command="curl -s http://localhost:1234/v1/models",
        notes="Runs local models. ARES uses this for sensitive/high-volume tasks.",
    ),
    "homebrew": ToolEntry(
        name="Homebrew",
        description="macOS package manager",
        install_method="manual",
        check_command="brew --version",
        notes="Primary CLI package manager for macOS",
    ),
    "llm": ToolEntry(
        name="llm",
        description="Cloud or local LLM via ares.llm router",
        install_method="none",
        installed=True,
        notes="Pseudo-tool — routed through ares.llm.cloud / .local",
    ),
    "shell": ToolEntry(
        name="shell",
        description="Local shell command execution",
        install_method="none",
        installed=True,
        notes="Pseudo-tool — runs stage.action via /bin/sh",
    ),
    "human": ToolEntry(
        name="human",
        description="Manual stage — awaits human action",
        install_method="none",
        installed=True,
        notes="Pseudo-tool — execution returns immediately with a manual marker",
    ),
}


def ensure_builtin_tools() -> None:
    """Ensure built-in tool definitions are in the registry."""
    tools = load_registry()
    changed = False
    for key, entry in BUILT_IN_TOOLS.items():
        if key not in tools:
            tools[key] = entry
            changed = True
    if changed:
        save_registry(tools)


# ---------------------------------------------------------------------------
# Invocation layer — stage dispatch via the registry
# ---------------------------------------------------------------------------

ToolInvoker = Callable[["PlanStage", "Task"], Awaitable[str]]

_INVOKERS: dict[str, ToolInvoker] = {}

# Strings the LLM planner commonly emits, mapped to canonical registry keys.
_ALIASES: dict[str, str] = {
    "claude": "llm",
    "gpt": "llm",
    "gpt-4": "llm",
    "gpt-5": "llm",
    "llm": "llm",
    "ai": "llm",
    "openai": "llm",
    "anthropic": "llm",
    "human": "human",
    "manual": "human",
    "user": "human",
    "human review": "human",
    "shell": "shell",
    "bash": "shell",
    "sh": "shell",
    "terminal": "shell",
}

# Install methods that always pass the installed check (no local install needed).
_NO_INSTALL_METHODS = frozenset({"none", ""})


def register_invoker(key: str, fn: ToolInvoker) -> None:
    """Register an async handler for a registry key."""
    _INVOKERS[key] = fn


def resolve_tool_key(tool_string: str) -> str | None:
    """Map a stage.tool string to a canonical registry key, or None.

    Lookup order: alias map → exact lowercase registry key.
    """
    if not tool_string:
        return None
    key = tool_string.strip().lower()
    if key in _ALIASES:
        return _ALIASES[key]
    if key in load_registry():
        return key
    return None


def _check_stage(stage: "PlanStage") -> str:
    """Validate a single stage's tool. Returns canonical key or raises."""
    if not stage.tool:
        raise ToolNotFoundError(
            f"stage {stage.id} ({stage.name!r}) has no tool declared"
        )
    key = resolve_tool_key(stage.tool)
    if key is None:
        raise ToolNotFoundError(
            f"stage {stage.id}: unknown tool {stage.tool!r} — not in registry"
        )
    entry = get_tool(key)
    if entry is not None and entry.install_method not in _NO_INSTALL_METHODS:
        if not entry.installed:
            install_hint = entry.install_command or "(no install command on file)"
            raise ToolNotInstalledError(
                f"stage {stage.id}: tool {key!r} is registered but not installed. "
                f"Install with: {install_hint}"
            )
    if key not in _INVOKERS:
        raise ToolNotFoundError(
            f"stage {stage.id}: no invoker registered for tool {key!r}"
        )
    return key


def validate_plan(plan: "Plan") -> None:
    """Pre-flight check — raises if any stage's tool is unresolved/uninstalled.

    Collects every failure across the plan into a single error message so
    the user can fix all gaps in one pass instead of one stage at a time.
    """
    not_found: list[str] = []
    not_installed: list[str] = []
    for stage in plan.stages:
        try:
            _check_stage(stage)
        except ToolNotFoundError as exc:
            not_found.append(str(exc))
        except ToolNotInstalledError as exc:
            not_installed.append(str(exc))
    if not_installed:
        raise ToolNotInstalledError("; ".join(not_installed + not_found))
    if not_found:
        raise ToolNotFoundError("; ".join(not_found))


async def invoke(stage: "PlanStage", task: "Task") -> str:
    """Resolve `stage.tool` against the registry and dispatch to its invoker."""
    key = _check_stage(stage)
    return await _INVOKERS[key](stage, task)
