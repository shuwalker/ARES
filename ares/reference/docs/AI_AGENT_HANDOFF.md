# AI Agent Handoff Guide

The ARES core architecture is **complete and verified**. This guide tells AI agents where to pick up for feature development.

## Status

✅ **READY FOR AGENT IMPLEMENTATION**

- All core files have scaffolding with detailed docstrings explaining what to build
- All imports verify
- All interfaces are defined
- The codebase is clean and modular

## How to Hand Off Tasks to AI Agents

### Pattern 1: Implement a Single File

**Example:** Implement `ares/memory/context.py`

```
Prompt:
  "Implement ares/memory/context.py according to the spec in its docstring.
   It should retrieve memory context and inject it into LLM prompts.
   Reference: docs/file-structure.md for the architecture.
   Use the existing memory/vector_store.py and memory/fact_store.py as examples."
```

The file already has a detailed docstring that explains:
- What the module does
- Key functions to implement
- Expected behavior
- Constraints and notes

### Pattern 2: Complete a Provider

**Example:** Finish the Anthropic provider

```
Prompt:
  "Implement ares/llm/providers/anthropic.py using the anthropic SDK.
   Follow the interface defined in ares/llm/base.py.
   The docstring explains what to do. Reference the existing
   ares/llm/router.py to understand how providers are called."
```

Each provider file has:
- Import instructions
- Interface requirements
- Configuration expectations
- Error handling patterns

### Pattern 3: Integrate an External System

**Example:** Wire OpenClaw to the computer tool

```
Prompt:
  "Update ares/tools/computer.py to integrate with the external OpenClaw
   gateway. The file has a WebSocket connection stub. Complete it.
   Reference docs/file-structure.md and QUICKSTART.md for context."
```

The tool files have:
- Current implementation (can be enhanced)
- Documented interfaces
- Configuration hooks
- Example request/response patterns

## Priority Implementation Order

### 🔴 Critical Path (Blocking Other Features)

1. **ares/memory/context.py** — Dependency for task execution
   ```
   Spec: docs/file-structure.md → memory → context.py
   Docstring: Read the file for full details
   Time: ~2-3 hours
   ```

2. **ares/llm/providers/anthropic.py** — Main LLM integration
   ```
   Spec: Use llm/base.py as interface
   Docstring: File explains all steps
   Time: ~3-4 hours
   ```

3. **ares/llm/providers/local.py** — Local LLM fallback
   ```
   Spec: LM Studio OpenAI-compatible API
   Docstring: File explains configuration
   Time: ~2 hours
   ```

4. **ares/daemon/server.py** — Daemon network layer
   ```
   Spec: FastAPI-based HTTP/WebSocket server
   Docstring: File has detailed structure
   Time: ~4-5 hours
   ```

### 🟡 High Priority (Enable Features)

5. **ares/memory/vector_store.py** — Semantic search backend
   ```
   Status: Exists, may need ChromaDB integration updates
   Time: ~1-2 hours
   ```

6. **ares/scheduler/service.py** — Job scheduler
   ```
   Status: Partial code exists
   Time: ~2-3 hours
   ```

7. **ares/events/triggers.py** — Event system
   ```
   Status: Partial implementation
   Time: ~2-3 hours
   ```

8. **ares/mcp/server.py** — Claude Desktop integration
   ```
   Spec: Expose ARES tools as MCP tools
   Time: ~4-5 hours
   ```

### 🟢 Testing & Polish

9. **tests/unit/*.py** — Unit test suite
   ```
   Files: config, task, router, approver
   Time: ~4-5 hours
   ```

10. **tests/integration/*.py** — End-to-end tests
    ```
    Files: daemon socket, MCP bridge
    Time: ~4-5 hours
    ```

## How to Recognize a Properly Structured File

Each file has this pattern:

```python
"""Module docstring — high-level purpose.

Description of what this module does.
"""

from __future__ import annotations

import logging
from typing import Any, Optional

logger = logging.getLogger(__name__)

# Detailed docstrings in class/function definitions
class MyClass:
    """High-level explanation."""

    def __init__(self):
        """Initialize with full docstring."""
        # Implementation
```

**Signs a file is ready for agent implementation:**
- ✅ Has a detailed module docstring
- ✅ Has class/function docstring templates
- ✅ Shows imports needed
- ✅ Explains responsibilities
- ✅ References other modules
- ✅ Has TODO comments for what to implement

## Testing Your Implementation

```bash
# Test imports
python -c "from ares.module import Class; print('✓ imports work')"

# Run a quick smoke test
python -m pytest tests/unit/test_module.py -v

# Test the full system
python -m ares.cli init
python -m ares.cli start
python -m ares.cli execute "test task"
python -m ares.cli status
```

## Code Quality Standards

All implementations should:

✅ **Type Hints** — Full type hints for all functions
✅ **Docstrings** — Module, class, and function docstrings
✅ **Error Handling** — Try/except with specific exceptions
✅ **Logging** — Use `logger.info()`, `.debug()`, `.error()`
✅ **Async** — Use `async def` and `await` where appropriate
✅ **Testing** — At least basic unit tests
✅ **Imports** — No circular dependencies, clean structure

## Common Patterns in ARES

### Async Context Managers
```python
async with DaemonClient() as client:
    result = await client.execute_task(task)
```

### Pydantic Validation
```python
class MyConfig(BaseModel):
    name: str
    timeout: int = Field(default=300)

    @validator('timeout')
    def validate_timeout(cls, v):
        if v <= 0:
            raise ValueError("timeout must be positive")
        return v
```

### Tool Implementation
```python
class MyTool(BaseTool):
    @property
    def name(self) -> str:
        return "my_tool"

    async def execute(self, action: str, **kwargs) -> ToolResult:
        # Implementation returns ToolResult(success=True/False, data=..., error=...)
```

### LLM Provider
```python
class MyProvider(LLMProvider):
    async def complete(self, messages: list[dict], **kwargs) -> LLMResponse:
        # Call your API
        # Return LLMResponse(content="...", tool_calls=[...], usage=TokenUsage(...))
```

## Useful References

**For Understanding ARES:**
- `docs/ARCHITECTURE.md` — Design decisions
- `docs/file-structure.md` — Where everything lives
- `QUICKSTART.md` — How to use it

**For Implementation Details:**
- Check existing implementations in the same module
- Read the docstrings in the target file
- Look at the interface definitions (base.py files)
- Check config/default.yaml for expected settings

**For Integration:**
- Each feature integrates via the daemon/server.py HTTP layer
- Tools are registered in tools/registry.py
- Memory is accessed via a unified interface
- LLM calls go through the router

## Version Control Notes

All implementations should:
- Create new commits (one per file/feature)
- Include co-author tag: `Co-Authored-By: Claude <noreply@anthropic.com>`
- Write clear commit messages explaining the "why"
- Reference related files in commit body

## Success Criteria

An implementation is done when:

✅ All imports work
✅ Unit tests pass
✅ Module integrates with daemon/server.py
✅ User can interact with it via CLI or API
✅ Error handling is comprehensive
✅ Docstrings explain the behavior
✅ Configuration is validated
✅ Logging is helpful for debugging

## Questions?

Refer to:
1. **File docstring** — Each file explains what it does
2. **docs/file-structure.md** — Where things fit
3. **Existing implementations** — Use them as templates
4. **QUICKSTART.md** — How to test

---

## Quick Start for Agents

1. Pick a file from the Priority list above
2. Read its docstring carefully
3. Read the related base.py or interface definitions
4. Look at similar implementations in the codebase
5. Implement following the documented spec
6. Run `python -c "from module import Class"` to verify imports
7. Run basic tests
8. Commit with clear message

**You have a complete, working scaffold. Go build! 🚀**
