"""One-shot fixture scrubber for scripts/compression_eval/fixtures/.

Source: ~/.hermes/sessions/<file>.jsonl
Output: .worktrees/.../scripts/compression_eval/fixtures/<name>.json

Scrubbing passes:
  1. agent.redact.redact_sensitive_text — API keys, tokens, connection strings
  2. Username paths — /home/teknium/ → /home/user/, ~/.hermes/ preserved as-is
     (that path is universal)
  3. Personal handles — "Teknium"/"teknium"/"teknium1" → "user"
  4. Reasoning scratchpads — strip <REASONING_SCRATCHPAD>...</REASONING_SCRATCHPAD>
     blocks and <think>...</think> tags (personality leakage risk)
  5. session_meta line — drop entirely, we only need the messages
  6. User message personality — lightly paraphrase the first user message to keep
     task intent while removing "vibe"; subsequent user turns kept verbatim
     since they're short instructions

The fixture format matches DESIGN.md:
  {
    "name": "...",
    "description": "...",
    "model": "...",           # best guess from original session
    "context_length": 200000,
    "messages": [...],        # OpenAI-format, only role/content/tool_calls/tool_call_id/tool_name
    "notes": "Scrubbed from ~/.hermes/sessions/... on 2026-04-24"
  }
"""
from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List


def _locate_hermes_agent() -> Path:
    """Locate the hermes-agent checkout for `agent.redact` imports.

    Priority: HERMES_AGENT_ROOT env var > ~/.hermes/hermes-agent > sibling dir.
    """
    env = os.environ.get("HERMES_AGENT_ROOT")
    if env:
        path = Path(env).expanduser().resolve()
        if (path / "agent" / "redact.py").is_file():
            return path
        raise RuntimeError(
            f"HERMES_AGENT_ROOT={env} does not contain agent/redact.py"
        )
    candidates = [
        Path.home() / ".hermes" / "hermes-agent",
        Path(__file__).resolve().parent.parent / "hermes-agent",
    ]
    for candidate in candidates:
        if (candidate / "agent" / "redact.py").is_file():
            return candidate.resolve()
    raise RuntimeError(
        "Could not locate the hermes-agent repo. Set HERMES_AGENT_ROOT to "
        "your checkout, or clone hermes-agent into ~/.hermes/hermes-agent "
        "or as a sibling directory."
    )


_HERMES_AGENT_ROOT = _locate_hermes_agent()
sys.path.insert(0, str(_HERMES_AGENT_ROOT))
from agent.redact import redact_sensitive_text  # noqa: E402


SESSION_DIR = Path.home() / ".hermes" / "sessions"
# Resolve FIXTURES_DIR relative to this script so the scrubber runs the
# same way inside a worktree, a main checkout, or from a contributor's
# clone at a different path.
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"

# (source_file, output_name, description, user_first_paraphrase, model_guess, context_length, truncate_at)
# truncate_at: keep messages[:truncate_at] (None = keep all). Applied BEFORE
# orphan-empty-assistant cleanup.
SPECS = [
    (
        "20260321_060441_fef7be92.jsonl",
        "feature-impl-context-priority",
        "~75-turn feature-impl: user asks how multiple project-context files "
        "(.hermes.md / AGENTS.md / CLAUDE.md / .cursorrules) are handled when "
        "all are present; agent investigates the codebase, designs a priority "
        "order, patches the loader + tests, live-tests with a scenario "
        "directory, commits to a feature branch, opens a PR, and merges after "
        "approval. Exercises investigate → decide → implement → verify → "
        "ship flow with clear artifact trail (2 files modified, 1 PR).",
        (
            "If .hermes.md, AGENTS.md, CLAUDE.md, and .cursorrules all exist in "
            "the same directory, does the agent load all of them or pick one? "
            "Use the hermes-agent-dev skill to check."
        ),
        "anthropic/claude-sonnet-4.6",
        200000,
        74,  # cut at "Merged and pulled. Main is current." — drops trailing unrelated cron-delivery messages
    ),
    (
        "20260412_233741_3f2119a8.jsonl",
        "debug-session-feishu-id-model",
        "~60-turn debug/triage PR-review session: a third-party bug report "
        "says the gateway's Feishu adapter misuses the open_id / union_id / "
        "user_id identity model (open_id is app-scoped, not the bot's "
        "canonical ID). An open community PR (#8388) tries to fix it. Agent "
        "reviews the PR against current main, fetches upstream Feishu/Lark "
        "identity docs, and produces a decision. Exercises long tool-heavy "
        "context with PR diffs, upstream docs, and a clear decision at the "
        "end — the classic 'can the summary still name the PR number, the "
        "root cause, and the decision?' scenario.",
        (
            "A community user reports the Feishu/Lark adapter gets the identity "
            "model wrong — open_id is app-scoped, not the bot's canonical ID. "
            "There's an open PR #8388 trying to fix it. Use the hermes-agent-dev "
            "skill and the pr-triage-salvage skill to review it."
        ),
        "anthropic/claude-sonnet-4.6",
        200000,
        58,  # end at "Here's my review: ..." — clean decision point before the "close it, implement cleaner" pivot
    ),
    (
        "20260328_160817_77bd258b.jsonl",
        "config-build-competitive-scouts",
        "~60-turn iterative config/build session: user wants a set of weekly "
        "cron jobs that scan competing AI coding agents (openclaw, nanoclaw, "
        "ironclaw, codex, opencode, claude-code, kilo-code, gemini-cli, "
        "cline, aider, roo) for merged PRs or web updates worth porting to "
        "hermes-agent. User adds one target per turn; agent creates each cron "
        "job and re-states the accumulated schedule. Exercises artifact trail "
        "(which jobs are configured, which days) and iterative state "
        "accumulation — the canonical case for iterative-merge summarization.",
        (
            "Set up a cron job for the agent every Sunday to scan all PRs "
            "merged into openclaw that week, decide which are worth adding to "
            "hermes-agent, and open PRs porting those features."
        ),
        "anthropic/claude-sonnet-4.6",
        200000,
        None,
    ),
]


# Tool output truncation is DELIBERATELY DISABLED.
#
# An earlier iteration truncated tool outputs > 2KB to keep fixture JSON
# files small, but that defeats the whole purpose of the eval. Real
# sessions have 30KB skill_view dumps, 10KB read_file outputs, 5KB
# web_extract bodies — compression has to either head-protect them,
# summarize them, or drop them. A fixture without that load doesn't
# exercise the compressor. The size win wasn't worth the signal loss.
#
# The function remains so the scrubbing_passes record in the fixture
# JSON continues to truthfully describe what was applied (no-op in this
# configuration).
_TOOL_OUTPUT_MAX = None  # None disables truncation entirely


def _maybe_truncate_tool_output(text: str, tool_name: str) -> str:
    if _TOOL_OUTPUT_MAX is None or not text or len(text) <= _TOOL_OUTPUT_MAX:
        return text
    keep = _TOOL_OUTPUT_MAX - 200
    head = text[:keep]
    return (
        head
        + f"\n\n[... tool output truncated for fixture — original was {len(text)} chars"
        + (f" from {tool_name}" if tool_name else "")
        + "]"
    )


_PATH_RE = re.compile(r"/home/teknium\b")
# No \b boundaries — some tool content stores newlines as the literal
# two-char sequence "\\n" (escaped JSON), so a "\\nTeknium..." run has a
# word char ('n') immediately before 'T' and \b fails. Substring match is
# safer here; "Teknium" as a substring of an unrelated word is
# implausible in this corpus.
_USER_RE = re.compile(r"teknium1|Teknium|teknium", re.IGNORECASE)
# Only strip scratchpads in ASSISTANT content, not tool results (might be legit)
_SCRATCH_RE = re.compile(
    r"<REASONING_SCRATCHPAD>.*?</REASONING_SCRATCHPAD>\s*", re.DOTALL
)
_THINK_RE = re.compile(r"<think>.*?</think>\s*", re.DOTALL)
# Discord/Telegram user mention leakage in messaging-platform sessions
_USER_MENTION_RE = re.compile(r"<@\*{3}>|<@\d+>")
# Contributor emails (from git show output etc) — anything@domain.tld
# Keep noreply@github-style placeholders obvious; real personal emails get
# replaced with a contributor placeholder.
_EMAIL_RE = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
# "Author: Name <email>" git-show headers — rewrite the whole line
_GIT_AUTHOR_RE = re.compile(r"Author:\s*[^<\n]+<[^>]+>")


def _scrub_text(text: str, *, drop_scratchpads: bool = False) -> str:
    """Apply the pipeline to a raw text string.

    drop_scratchpads only affects assistant messages — tool outputs that
    happen to contain similar markers are left alone.
    """
    if not text:
        return text
    if drop_scratchpads:
        text = _SCRATCH_RE.sub("", text)
        text = _THINK_RE.sub("", text)
    text = _PATH_RE.sub("/home/user", text)
    text = _USER_RE.sub("user", text)
    text = _USER_MENTION_RE.sub("<@user>", text)
    # Rewrite git "Author: Name <email>" lines before generic email replace
    text = _GIT_AUTHOR_RE.sub("Author: contributor <contributor@example.com>", text)
    text = _EMAIL_RE.sub("contributor@example.com", text)
    text = redact_sensitive_text(text)
    return text


def _content_to_str(content: Any) -> str:
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for p in content:
            if isinstance(p, dict) and "text" in p:
                parts.append(p["text"])
            elif isinstance(p, str):
                parts.append(p)
        return "\n".join(parts)
    return str(content)


def _scrub_tool_calls(tool_calls: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for tc in tool_calls or []:
        if not isinstance(tc, dict):
            continue
        fn = tc.get("function", {}) or {}
        args = fn.get("arguments", "")
        if isinstance(args, str):
            args = _scrub_text(args)
        new_tc = {
            "id": tc.get("id", ""),
            "type": tc.get("type", "function"),
            "function": {
                "name": fn.get("name", ""),
                "arguments": args,
            },
        }
        out.append(new_tc)
    return out


def _scrub_message(m: Dict[str, Any], *, first_user_paraphrase: str | None, user_turn_idx: List[int]) -> Dict[str, Any] | None:
    role = m.get("role")
    if role in (None, "session_meta"):
        return None

    content = _content_to_str(m.get("content"))

    if role == "assistant":
        content = _scrub_text(content, drop_scratchpads=True)
    elif role == "user":
        # Use paraphrase for the very first user turn only
        user_turn_idx[0] += 1
        if user_turn_idx[0] == 1 and first_user_paraphrase is not None:
            content = first_user_paraphrase
        else:
            content = _scrub_text(content)
    else:
        content = _scrub_text(content)
        # Truncate large tool outputs
        if role == "tool":
            tn = m.get("tool_name") or m.get("name") or ""
            content = _maybe_truncate_tool_output(content, tn)

    new_msg: Dict[str, Any] = {"role": role, "content": content}

    if role == "assistant":
        tcs = m.get("tool_calls") or []
        if tcs:
            new_msg["tool_calls"] = _scrub_tool_calls(tcs)
    if role == "tool":
        if m.get("tool_call_id"):
            new_msg["tool_call_id"] = m["tool_call_id"]
        if m.get("tool_name") or m.get("name"):
            new_msg["tool_name"] = m.get("tool_name") or m.get("name")

    return new_msg


def build_fixture(
    source_file: str,
    output_name: str,
    description: str,
    first_user_paraphrase: str,
    model_guess: str,
    context_length: int,
    truncate_at: int | None = None,
) -> Dict[str, Any]:
    src = SESSION_DIR / source_file
    raw_msgs: List[Dict[str, Any]] = []
    with src.open() as fh:
        for line in fh:
            try:
                raw_msgs.append(json.loads(line))
            except Exception:
                pass

    # Skip session_meta lines up front so truncate_at counts real messages
    raw_msgs = [m for m in raw_msgs if m.get("role") != "session_meta"]
    if truncate_at is not None:
        raw_msgs = raw_msgs[:truncate_at]

    user_turn_counter = [0]
    scrubbed: List[Dict[str, Any]] = []
    for m in raw_msgs:
        new = _scrub_message(
            m,
            first_user_paraphrase=first_user_paraphrase,
            user_turn_idx=user_turn_counter,
        )
        if new is not None:
            scrubbed.append(new)

    # Drop empty-content assistant messages that have no tool_calls
    # (artifact of scratchpad-only turns post-scrub)
    pruned: List[Dict[str, Any]] = []
    for m in scrubbed:
        if (
            m["role"] == "assistant"
            and not (m.get("content") or "").strip()
            and not m.get("tool_calls")
        ):
            continue
        pruned.append(m)
    # Trim trailing orphan tool messages (no matching assistant)
    while pruned and pruned[-1]["role"] == "tool":
        pruned.pop()
    scrubbed = pruned

    # Inject a synthetic public-safe system message so the compressor has
    # a head to anchor on. The real system prompts embed personality and
    # platform-specific content we don't want checked in.
    system_msg = {
        "role": "system",
        "content": (
            "You are a helpful AI coding assistant with access to tools "
            "(terminal, file editing, search, web, etc.). You operate in a "
            "conversational loop: the user gives you a task, you call tools "
            "to accomplish it, and you report back concisely."
        ),
    }
    if scrubbed and scrubbed[0].get("role") == "system":
        scrubbed[0] = system_msg
    else:
        scrubbed.insert(0, system_msg)

    fixture = {
        "name": output_name,
        "description": description,
        "model": model_guess,
        "context_length": context_length,
        "source": f"~/.hermes/sessions/{source_file}",
        "truncated_to": truncate_at,
        "scrubbed_at": datetime.now().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "scrubbing_passes": [
            "redact_sensitive_text (agent.redact)",
            "username paths replaced with /home/user",
            "personal handles (all case variants of the maintainer name) replaced with 'user'",
            "email addresses replaced with contributor@example.com",
            "git 'Author: Name <addr>' header lines normalised",
            "reasoning scratchpad blocks stripped from assistant content",
            "think tag blocks stripped from assistant content",
            "messaging-platform user mentions replaced with <@user>",
            "first user message paraphrased to remove personal voice",
            "subsequent user messages kept verbatim (after above redactions)",
            "system prompt replaced with generic public-safe placeholder",
            "orphan empty-assistant messages and trailing tool messages dropped",
            "tool outputs preserved verbatim (truncation disabled so the compressor sees real load)",
        ],
        "messages": scrubbed,
    }
    return fixture


def main() -> int:
    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)
    for spec in SPECS:
        source_file, output_name, description, paraphrase, model, ctx, truncate = spec
        fixture = build_fixture(
            source_file=source_file,
            output_name=output_name,
            description=description,
            first_user_paraphrase=paraphrase,
            model_guess=model,
            context_length=ctx,
            truncate_at=truncate,
        )
        out_path = FIXTURES_DIR / f"{output_name}.json"
        with out_path.open("w") as fh:
            json.dump(fixture, fh, indent=2, ensure_ascii=False)
        size_kb = out_path.stat().st_size / 1024
        print(f"  {output_name}.json  {size_kb:.1f} KB  {len(fixture['messages'])} msgs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
