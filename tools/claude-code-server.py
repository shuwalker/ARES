#!/usr/bin/env python3
"""
Claude Code → OpenAI-compatible API adapter v4

Architecture: Claude Code CLI as reasoning engine, Hermes as tool executor.

Claude speaks in its own native format. We don't fight it — we translate.

Tool calls come in as <function_calls> XML blocks. We parse them and convert
to OpenAI tool_calls format for Hermes. Hermes executes, sends results back,
and we feed the full conversation history to Claude on the next turn.

Key design decisions:
- NO --dangerously-skip-permissions: We're not asking Claude to execute
  anything, just propose tool calls. Less risk, fewer guardrails to fight.
- NO forced JSON format: Let Claude output <function_calls> naturally,
  parse that format directly. More reliable than coercing foreign formats.
- NO env stripping: Claude CLI needs its OAuth session to authenticate.
- Stateless: Each request is a fresh CLI invocation with full history.
"""

import json
import os
import pathlib
import re
import subprocess
import sys
import time
import uuid
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

CLAUDE_BIN = "/opt/homebrew/bin/claude"

# Empty MCP config to suppress all MCP tools with --strict-mcp-config.
# Written to /tmp at import time.
_EMPTY_MCP_CONFIG = "/tmp/claude_code_empty_mcp.json"
pathlib.Path(_EMPTY_MCP_CONFIG).write_text('{"mcpServers":{}}')


# ============================================================================
# TOOL DEFINITION FORMATTER
# ============================================================================

def _format_tool_definitions(tools: list) -> str:
    """Format OpenAI-style tool definitions for Claude's system prompt.

    Claude Code CLI with --tools "" doesn't know about our tools.
    We inject them into the system prompt so Claude proposes tool calls
    using its native <function_calls> format.
    """
    if not tools:
        return ""
    lines = []
    for t in tools:
        fn = t.get("function", {})
        name = fn.get("name", "")
        desc = fn.get("description", "")
        params = fn.get("parameters", {}).get("properties", {})
        required = fn.get("parameters", {}).get("required", [])

        param_strs = []
        for pname, pdef in params.items():
            ptype = pdef.get("type", "string")
            pdesc = pdef.get("description", "")
            req = "required" if pname in required else "optional"
            param_strs.append(f"    - {pname} ({ptype}, {req}): {pdesc}")

        param_block = "\n".join(param_strs) if param_strs else "    (no parameters)"
        lines.append(f"  {name}:\n{param_block}\n    Description: {desc}")

    return "\n".join(lines)


# ============================================================================
# PROMPT BUILDER
# ============================================================================

def _extract_text(content) -> str:
    """Extract plain text from OpenAI-style content (str or list of blocks)."""
    if isinstance(content, list):
        return " ".join(c.get("text", "") for c in content if c.get("type") == "text").strip()
    return content or ""


def _build_prompt(messages: list, tools: list) -> tuple[str, str]:
    """
    Convert OpenAI messages + tools into (system_prompt, user_prompt).

    Tool definitions are injected into the system prompt so Claude knows
    what's available and proposes calls using <function_calls> XML.

    Multi-turn history includes tool call/result messages so Claude has
    full context. Tool results are truncated to avoid context bloat.
    """
    system_parts = []
    turns = []

    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")

        if role == "system":
            system_parts.append(_extract_text(content))
        elif role == "user":
            turns.append(("Human", _extract_text(content)))
        elif role == "assistant":
            text = _extract_text(content)
            tool_calls = msg.get("tool_calls")
            if tool_calls:
                # Reconstruct what Claude said: text + proposed tool calls
                parts = []
                if text:
                    parts.append(text)
                # Show tool calls in Claude's native format for context continuity
                for tc in tool_calls:
                    fn = tc.get("function", {})
                    name = fn.get("name", "")
                    args_raw = fn.get("arguments", "{}")
                    if isinstance(args_raw, str):
                        try:
                            args = json.loads(args_raw)
                        except json.JSONDecodeError:
                            args = {}
                    else:
                        args = args_raw if isinstance(args_raw, dict) else {}
                    parts.append(f'<function_calls>\n<invoke name="{name}">\n<parameter name="arguments">{json.dumps(args)}</parameter>\n</invoke>\n</function_calls>')
                turns.append(("Assistant", "\n\n".join(parts)))
            elif text:
                turns.append(("Assistant", text))
        elif role == "tool":
            # Tool result from Hermes execution — truncate long results
            name = msg.get("name", "tool")
            result = _extract_text(content)
            max_result_len = 2000
            if len(result) > max_result_len:
                result = result[:max_result_len] + f"\n... [truncated, {len(result)} chars total]"
            turns.append(("Tool_Result", f"[{name}] {result}"))

    # Build system prompt with tool definitions
    system_prompt = "\n\n".join(system_parts)

    if tools:
        tool_block = _format_tool_definitions(tools)
        args_example = json.dumps({"param": "value"})
        tool_instructions = f"""\
You have access to the following tools:

{tool_block}

When you need to use a tool, respond with a <function_calls> block in this exact format:

<function_calls>
<invoke name="tool_name">
<parameter name="arguments">{args_example}</parameter>
</invoke>
</function_calls>

You can call multiple tools by including multiple <invoke> blocks.
After receiving tool results, you can call more tools or provide a final text answer.
If you can answer directly without tools, just respond in plain text — no XML needed.
NEVER propose destructive or dangerous operations (rm -rf /, format drives, fork bombs, etc.)."""
        system_prompt = f"{system_prompt}\n\n{tool_instructions}".strip() if system_prompt else tool_instructions.strip()

    if not turns:
        return system_prompt, ""

    if len(turns) == 1:
        return system_prompt, turns[0][1]

    # Multi-turn: embed prior turns with clear markers, then append only the
    # current turn. Do not duplicate the latest user/tool message inside the
    # history and again at the end; that confused tool-use decisions.
    prior_turns = turns[:-1]
    current_turn = turns[-1][1]
    lines = []
    if prior_turns:
        lines.append("<conversation_history>")
        for label, text in prior_turns:
            lines.append(f"{label}: {text}")
        lines.append("</conversation_history>")
        lines.append("")
    lines.append(current_turn)

    return system_prompt, "\n".join(lines)


# ============================================================================
# NATIVE FORMAT PARSER
# ============================================================================

def _parse_function_calls_xml(content: str) -> list | None:
    """
    Parse Claude's native <function_calls> format.

    Claude Code outputs tool calls like:
    <function_calls>
    <invoke name="terminal">
    <parameter name="arguments">{"command": "ls -la"}</parameter>
    </invoke>
    </function_calls>

    Returns list of OpenAI-format tool_calls dicts, or None.
    """
    if not content or ("<function_calls>" not in content and "<invoke" not in content):
        return None

    # Find all <invoke> blocks inside <function_calls>
    invoke_pattern = re.compile(
        r'<invoke\s+name=["\']([^"\']+)["\']>(.*?)</invoke>',
        re.DOTALL
    )

    # Extract the function_calls block. Claude Code usually emits the wrapper,
    # but under some prompts it emits bare <invoke> blocks. Treat those as tool
    # calls too so raw XML does not leak into the final assistant message.
    fc_match = re.search(r'<function_calls>(.*?)</function_calls>', content, re.DOTALL)
    if fc_match:
        fc_block = fc_match.group(1)
    elif "<invoke" in content and "</invoke>" in content:
        fc_block = content
    else:
        return None

    calls = []

    for m in invoke_pattern.finditer(fc_block):
        name = m.group(1)
        invoke_body = m.group(2)

        # Extract parameters — Claude uses two formats:
        # 1. <parameter name="arguments">{"key": "val"}</parameter>  (single JSON blob)
        # 2. <parameter name="command">ls -la</parameter>             (individual params)
        args = {}

        # Try format 1: single "arguments" parameter containing JSON
        param_match = re.search(r'<parameter\s+name=["\']arguments["\']>(.*?)</parameter>', invoke_body, re.DOTALL)
        if param_match:
            args_str = param_match.group(1).strip()
            try:
                args = json.loads(args_str)
            except json.JSONDecodeError:
                args_str_fixed = args_str.rstrip(",").strip()
                try:
                    args = json.loads(args_str_fixed)
                except json.JSONDecodeError:
                    args = {"_raw_arguments": args_str}
        else:
            # Try format 2: individual named parameters
            # e.g. <parameter name="command">ls -la /tmp</parameter>
            for pm in re.finditer(r'<parameter\s+name=["\']([^"\']+)["\']>(.*?)</parameter>', invoke_body, re.DOTALL):
                param_name = pm.group(1)
                param_value = pm.group(2).strip()
                # Try to parse as JSON first (for nested objects/arrays)
                try:
                    args[param_name] = json.loads(param_value)
                except (json.JSONDecodeError, ValueError):
                    args[param_name] = param_value

        # Clean argument values — strip prompt artifacts
        args = _clean_arguments(name, args)

        calls.append({
            "type": "function",
            "function": {
                "name": name,
                "arguments": json.dumps(args),
            },
            "id": f"call_{uuid.uuid4().hex[:8]}",
        })

    return calls if calls else None


def _parse_tool_calls_json(content: str) -> list | None:
    """
    Fallback: Parse {"tool_calls": [...]} JSON format.

    Some models or prompts might still produce JSON-format tool calls.
    This is the secondary parse path, not the primary one.
    """
    if not content:
        return None

    text = content.strip()

    # Direct JSON parse
    try:
        obj = json.loads(text)
        if isinstance(obj, dict) and "tool_calls" in obj:
            return _normalize_json_tool_calls(obj["tool_calls"])
    except json.JSONDecodeError:
        pass

    # JSON in markdown code block
    code_match = re.search(r'```(?:json)?\s*\n?(.*?)\n?```', text, re.DOTALL)
    if code_match:
        try:
            obj = json.loads(code_match.group(1).strip())
            if isinstance(obj, dict) and "tool_calls" in obj:
                return _normalize_json_tool_calls(obj["tool_calls"])
        except json.JSONDecodeError:
            pass

    # Deep nested JSON search
    depth = 0
    start = -1
    for i, c in enumerate(text):
        if c == '{':
            if depth == 0:
                start = i
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0 and start >= 0:
                try:
                    obj = json.loads(text[start:i+1])
                    if isinstance(obj, dict) and "tool_calls" in obj:
                        return _normalize_json_tool_calls(obj["tool_calls"])
                except json.JSONDecodeError:
                    pass
                start = -1

    return None


def _parse_tool_calls(content: str) -> list | None:
    """
    Parse tool calls from Claude's response.

    Priority:
    1. Claude's native <function_calls> XML format (primary)
    2. JSON {"tool_calls": [...]} format (fallback for compatibility)
    """
    # Primary: Claude's native XML format
    result = _parse_function_calls_xml(content)
    if result:
        return result

    # Fallback: JSON format
    result = _parse_tool_calls_json(content)
    if result:
        return result

    return None


def _normalize_json_tool_calls(calls: list) -> list:
    """Normalize JSON-format tool_calls into OpenAI format."""
    normalized = []
    for call in calls:
        name = call.get("name", call.get("function", {}).get("name", ""))
        args = call.get("arguments", call.get("function", {}).get("arguments", {}))

        if isinstance(args, str):
            try:
                args = json.loads(args)
            except json.JSONDecodeError:
                args = {}
        elif not isinstance(args, dict):
            args = {}

        args = _clean_arguments(name, args)

        normalized.append({
            "type": "function",
            "function": {
                "name": name,
                "arguments": json.dumps(args),
            },
            "id": f"call_{uuid.uuid4().hex[:8]}",
        })

    return normalized


def _clean_arguments(tool_name: str, args: dict) -> dict:
    """Strip prompt artifacts from argument values."""
    _PREFIX_PATTERNS = [
        r'^this\s+command:\s*',
        r'^this\s+file:\s*',
        r'^the\s+file\s+at\s+',
        r'^the\s+file\s+',
        r'^file\s+at\s+',
        r'^file\s+',
    ]
    for key, value in args.items():
        if isinstance(value, str):
            for pattern in _PREFIX_PATTERNS:
                cleaned = re.sub(pattern, '', value, flags=re.IGNORECASE)
                if cleaned != value:
                    args[key] = cleaned
                    break
    return args


# ============================================================================
# SAFETY FILTER
# ============================================================================

_DANGEROUS_COMMAND_PATTERNS = [
    re.compile(r'\brm\s+-\w*r\w*f\s+/', re.IGNORECASE),
    re.compile(r'\brm\s+-\w*f\w*r\s+/', re.IGNORECASE),
    re.compile(r'\bdd\s+if=/dev/zero', re.IGNORECASE),
    re.compile(r'\bmkfs\b', re.IGNORECASE),
    re.compile(r':\(\)\{.*:\|:&\}', re.IGNORECASE),  # fork bomb
    re.compile(r'\bchmod\s+(-\w*R\s+)?000\s+/', re.IGNORECASE),
    re.compile(r'\bformat\s+[A-Z]:', re.IGNORECASE),
    re.compile(r'\b>\s*/dev/sd', re.IGNORECASE),
    re.compile(r'\bcurl\s+.*\|\s*sh\b', re.IGNORECASE),
    re.compile(r'\bwget\s+.*\|\s*sh\b', re.IGNORECASE),
]


def _is_dangerous_tool_call(tool_calls: list) -> bool:
    """Check if any tool call would execute a destructive operation."""
    for tc in tool_calls:
        fn = tc.get("function", {})
        name = fn.get("name", "")
        args_raw = fn.get("arguments", "{}")
        if isinstance(args_raw, str):
            try:
                args = json.loads(args_raw)
            except json.JSONDecodeError:
                args = {}
        else:
            args = args_raw if isinstance(args_raw, dict) else {}

        if name == "terminal":
            cmd = args.get("command", "")
            for pattern in _DANGEROUS_COMMAND_PATTERNS:
                if pattern.search(cmd):
                    return True
    return False


def _strip_function_calls_xml(content: str) -> str:
    """Remove parsed tool-call XML from content to avoid duplication/leakage."""
    content = re.sub(r'<function_calls>.*?</function_calls>', '', content, flags=re.DOTALL).strip()
    # Also strip bare invoke blocks. Parser accepts these as tool calls, so they
    # should not remain as visible assistant prose.
    content = re.sub(r'<invoke\s+name=["\'][^"\']+["\']>.*?</invoke>', '', content, flags=re.DOTALL).strip()
    return content or ""


# ============================================================================
# CLAUDE CLI INVOCATION
# ============================================================================

def _call_claude(system_prompt: str, user_prompt: str, model: str = None) -> dict:
    """
    Call Claude Code CLI with --tools "" (no built-in tools) and
    --strict-mcp-config with empty config (no MCP tools either).

    Tool definitions are injected via system prompt. Claude proposes
    tool calls in its native <function_calls> format, which we parse
    and convert to OpenAI tool_calls format.
    """
    cmd = [
        CLAUDE_BIN, "-p",
        "--output-format", "json",
        "--tools", "",
        "--strict-mcp-config",
        "--mcp-config", _EMPTY_MCP_CONFIG,
    ]

    if system_prompt:
        cmd.extend(["--system-prompt", system_prompt])

    if model:
        cmd.extend(["--model", model])

    # Strip auth env vars that would override the subscription OAuth.
    # Hermes' .env sets ANTHROPIC_API_KEY (and friends) for its own provider routing;
    # if those leak in, the CLI tries key-auth and gets 401 instead of using the
    # logged-in subscription. Also clear the proxy URL Hermes uses for Ares.
    child_env = {k: v for k, v in os.environ.items() if k not in (
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_BEDROCK_BASE_URL",
        "ANTHROPIC_VERTEX_PROJECT_ID",
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_VERTEX",
    )}

    # Pass prompt via stdin to avoid CLI argument parsing issues
    # with special characters, spaces, and --tools "" empty strings
    result = subprocess.run(
        cmd, capture_output=True, text=True,
        timeout=600, input=user_prompt, env=child_env
    )

    if result.returncode != 0:
        stderr = result.stderr.strip()
        raise RuntimeError(f"Claude Code CLI error (exit {result.returncode}): {stderr or result.stdout[:500]}")

    try:
        data = json.loads(result.stdout.strip())
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Failed to parse Claude Code output: {e}\nOutput: {result.stdout[:500]}")

    return data


# ============================================================================
# HTTP SERVER
# ============================================================================

class ClaudeAPIHandler(BaseHTTPRequestHandler):

    def do_GET(self):
        if self.path == "/health":
            self._json({"status": "ok", "provider": "claude-code-local", "version": "4.0", "architecture": "reasoning-engine"})
        elif self.path == "/v1/models":
            self._json({
                "object": "list",
                "data": [
                    {
                        "id": "claude-code",
                        "object": "model",
                        "created": int(time.time()),
                        "owned_by": "anthropic",
                        "context_length": 200000,
                    }
                ]
            })
        else:
            self._send_error("Not found", 404)

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            self._send_error("Not found", 404)
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        try:
            req = json.loads(body)
            messages = req.get("messages", [])
            tools = req.get("tools", [])
            model_hint = req.get("model", "")
            want_stream = bool(req.get("stream", False))

            system_prompt, user_prompt = _build_prompt(messages, tools)

            if not user_prompt:
                self._send_error("No user message found")
                return

            # Map model names — pass through anything that isn't our generic names
            model = None
            if model_hint and model_hint not in ("claude-code", "claude-code-local"):
                model = model_hint

            # Call Claude Code CLI
            data = _call_claude(system_prompt, user_prompt, model)

            result_text = data.get("result", "")
            is_error = data.get("is_error", False)
            usage = data.get("usage", {})

            # Parse result for tool calls — primary path is native XML format
            tool_calls = _parse_tool_calls(result_text) if tools else None

            prompt_tokens = max(1, usage.get("input_tokens", 0) + usage.get("cache_read_input_tokens", 0))
            completion_tokens = max(1, usage.get("output_tokens", 0))
            cost = data.get("total_cost_usd")
            cid = f"chatcmpl-{uuid.uuid4().hex[:12]}"
            now = int(time.time())

            # Safety gate: block destructive tool calls
            if tool_calls and _is_dangerous_tool_call(tool_calls):
                safe_content = "I cannot execute that command as it would cause irreversible damage to the system. This operation is blocked for safety reasons."
                if want_stream:
                    self._stream_response(cid, now, safe_content, None, "stop",
                                          prompt_tokens, completion_tokens, cost)
                else:
                    message = {"role": "assistant", "content": safe_content}
                    self._json_raw(json.dumps({
                        "id": cid, "object": "chat.completion", "created": now, "model": "claude-code",
                        "choices": [{"index": 0, "message": message, "finish_reason": "stop"}],
                        "usage": {"prompt_tokens": prompt_tokens, "completion_tokens": completion_tokens,
                                  "total_tokens": prompt_tokens + completion_tokens},
                    }))
                return

            # Strip tool call markup from content to avoid duplication
            content_text = result_text
            if tool_calls:
                content_text = _strip_function_calls_xml(result_text)
                # If model only emitted XML with no surrounding prose, content is empty.
                # OpenAI spec allows null content alongside tool_calls; Hermes treats
                # empty + no tool_calls as "empty response" and retries/falls back.
                if not content_text.strip():
                    content_text = ""

            if is_error:
                content_text = f"[Error] {content_text}"

            finish_reason = "tool_calls" if tool_calls else "stop"

            if want_stream:
                self._stream_response(cid, now, content_text, tool_calls, finish_reason,
                                      prompt_tokens, completion_tokens, cost)
                return

            # Non-streaming JSON response
            message = {"role": "assistant"}
            if tool_calls:
                message["tool_calls"] = tool_calls
                message["content"] = content_text
            else:
                message["content"] = content_text

            response_body = {
                "id": cid,
                "object": "chat.completion",
                "created": now,
                "model": "claude-code",
                "choices": [{
                    "index": 0,
                    "message": message,
                    "finish_reason": finish_reason,
                }],
                "usage": {
                    "prompt_tokens": prompt_tokens,
                    "completion_tokens": completion_tokens,
                    "total_tokens": prompt_tokens + completion_tokens,
                }
            }

            if cost is not None:
                response_body["cost_usd"] = cost

            self._json_raw(json.dumps(response_body))

        except json.JSONDecodeError:
            self._send_error("Invalid JSON")
        except subprocess.TimeoutExpired:
            self._send_error("Claude Code CLI timed out (600s)", 504)
        except RuntimeError as e:
            self._send_error(str(e), 502)
        except Exception as e:
            self._send_error(f"Server error: {e}", 500)

    def _stream_response(self, cid, created, content, tool_calls, finish_reason,
                         prompt_tokens, completion_tokens, cost):
        """Emit OpenAI-compatible SSE chunks. Hermes expects streaming."""
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.send_header("X-Accel-Buffering", "no")
            self.end_headers()

            def emit(chunk):
                self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
                self.wfile.flush()

            base = {"id": cid, "object": "chat.completion.chunk", "created": created, "model": "claude-code"}

            # 1. Role chunk
            emit({**base, "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}]})

            # 2. Content chunk(s) — single chunk is fine; Hermes parses delta.content
            if content:
                emit({**base, "choices": [{"index": 0, "delta": {"content": content}, "finish_reason": None}]})

            # 3. Tool calls — emit each as its own delta with index
            if tool_calls:
                for i, tc in enumerate(tool_calls):
                    emit({**base, "choices": [{"index": 0, "delta": {"tool_calls": [{
                        "index": i,
                        "id": tc["id"],
                        "type": "function",
                        "function": {
                            "name": tc["function"]["name"],
                            "arguments": tc["function"]["arguments"],
                        },
                    }]}, "finish_reason": None}]})

            # 4. Final chunk with finish_reason + usage
            final = {**base, "choices": [{"index": 0, "delta": {}, "finish_reason": finish_reason}],
                     "usage": {"prompt_tokens": prompt_tokens, "completion_tokens": completion_tokens,
                               "total_tokens": prompt_tokens + completion_tokens}}
            if cost is not None:
                final["cost_usd"] = cost
            emit(final)

            # 5. Done sentinel, then close the one-shot SSE response. Keeping
            # the socket open after [DONE] makes curl/simple stream readers hang.
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            self.close_connection = True
        except (BrokenPipeError, ConnectionResetError):
            pass  # Client disconnected mid-stream; nothing to do

    def _json(self, data):
        self._json_raw(json.dumps(data))

    def _json_raw(self, body: str):
        enc = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(enc)))
        self.end_headers()
        self.wfile.write(enc)
        self.wfile.flush()

    def _send_error(self, message, code=400):
        try:
            body = json.dumps({"error": {"message": message, "type": "invalid_request_error"}})
            enc = body.encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(enc)))
            self.end_headers()
            self.wfile.write(enc)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, format, *args):
        pass  # Suppress noisy request logging


class ReusableHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    allow_reuse_port = True
    daemon_threads = True


def run_server(port=8555):
    server = ReusableHTTPServer(("127.0.0.1", port), ClaudeAPIHandler)
    print(f"Claude Code adapter v4 on http://127.0.0.1:{port}", file=sys.stderr)
    print(f"OpenAI endpoint: http://127.0.0.1:{port}/v1/chat/completions", file=sys.stderr)
    print(f"Architecture: Claude = reasoning engine (native format), Hermes = tool executor", file=sys.stderr)
    print(f"Parser: <function_calls> XML primary, JSON fallback", file=sys.stderr)
    print(f"Safety filter: ACTIVE ({len(_DANGEROUS_COMMAND_PATTERNS)} patterns)", file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8555
    run_server(port)