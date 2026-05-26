"""Core orchestrator for task execution and reasoning pipeline.

Central orchestration engine that manages the flow of tasks through ARES.
Supports both plan-based execution (router decomposes task into steps) and
an agentic loop (LLM decides tool calls iteratively until done).
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from .router import TaskRouter
from .state import StateManager, TaskRecord, TaskState
from .proactive_loop import ProactiveLoop
from .workspace import WorkspaceManager
from .events import CronScheduler
from .gateway import LocalGateway

logger = logging.getLogger(__name__)


class Orchestrator:
    """Central orchestration system for ARES task execution.

    Manages task routing, execution, and state. When an LLM provider is
    available, uses an agentic loop (LLM -> tool calls -> results -> repeat).
    Falls back to plan-based execution via the TaskRouter otherwise.
    """

    def __init__(self, config: Optional[dict[str, Any]] = None) -> None:
        self.config = config or {}

        # Core components
        db_path = Path(self.config.get("db_path", "./data/ares.db"))
        self.state_manager = StateManager(db_path)

        # Injected components
        self.tool_registry = self.config.get("tool_registry")
        self.memory = self.config.get("memory")
        self.llm_provider = self.config.get("llm_provider")

        self.router = TaskRouter(
            llm_provider=self.llm_provider,
            tool_registry=self.tool_registry,
            memory=self.memory,
        )

        self.proactive_loop = ProactiveLoop(
            llm_provider=self.llm_provider,
            memory=self.memory,
        )
        self.workspace_manager = WorkspaceManager()
        self.cron_scheduler = CronScheduler(check_interval=30)
        
        # Start gateway if not disabled by config
        self.enable_gateway = self.config.get("enable_gateway", True)
        if self.enable_gateway:
            self.gateway = LocalGateway(self, host=self.config.get("gateway_host", "127.0.0.1"), port=self.config.get("gateway_port", 8080))
        else:
            self.gateway = None

        # Configuration
        self.max_retries = self.config.get("max_retries", 1)
        self.max_iterations = self.config.get("max_iterations", 15)
        self.security_enabled = self.config.get("security_enabled", True)

        # Runtime state
        self._running = False
        self._start_time: Optional[datetime] = None
        self._active_tasks: dict[str, asyncio.Task[Any]] = {}
        self._event_handlers: dict[str, list[Any]] = {
            "task_created": [],
            "task_started": [],
            "task_completed": [],
            "task_failed": [],
            "step_started": [],
            "step_completed": [],
            # Real-time UI streaming events
            "llm_thinking": [],
            "tool_call_pending": [],
            "tool_call_complete": [],
            "action_approval_requested": [],
        }

        # Approval flow state (keyed by call_id)
        self._pending_approvals: dict[str, asyncio.Event] = {}
        self._rejected_approvals: set[str] = set()
        self.approval_mode: str = self.config.get("approval_mode", "none")
        # "none"      = never ask for approval
        # "dangerous" = ask for shell/computer/file tools
        # "all"       = ask before every tool call

        logger.info("Orchestrator initialized")

    async def initialize(self) -> None:
        """Async initialization: set up database and recover incomplete tasks."""
        logger.info("Orchestrator initializing...")
        await self.state_manager.initialize()

        self._running = True
        self._start_time = datetime.now(timezone.utc)

        await self.recover()
        await self.proactive_loop.start()
        await self.cron_scheduler.start()
        
        if self.gateway:
            await self.gateway.start()
            
        logger.info("Orchestrator ready")

    async def shutdown(self) -> None:
        """Graceful shutdown: cancel tasks, close connections."""
        logger.info("Orchestrator shutting down...")
        self._running = False

        for task_id, task in self._active_tasks.items():
            if not task.done():
                logger.info(f"Cancelling active task: {task_id}")
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass

        if self.gateway:
            await self.gateway.stop()

        await self.proactive_loop.stop()
        await self.cron_scheduler.stop()
        await self.state_manager.shutdown()
        logger.info("Orchestrator shut down complete")

    async def execute(
        self,
        task_description: str,
        context: Optional[dict[str, Any]] = None,
    ) -> TaskRecord:
        """Execute a task end-to-end.

        Args:
            task_description: Description of the task to execute.
            context: Optional context dictionary.

        Returns:
            TaskRecord with final state and results.
        """
        if not self._running:
            raise RuntimeError("Orchestrator not initialized. Call initialize() first.")

        context = context or {}
        logger.info(f"Executing task: {task_description[:100]}")

        task_record = await self.state_manager.create_task(
            description=task_description,
            metadata={"context": context},
        )

        await self._emit_event("task_created", task_record)

        execution_task = asyncio.create_task(
            self._execute_task_internal(task_record, context)
        )
        self._active_tasks[task_record.task_id] = execution_task

        try:
            return await execution_task
        except asyncio.CancelledError:
            logger.info(f"Task cancelled: {task_record.task_id}")
            await self.state_manager.update_task(
                task_record.task_id,
                state=TaskState.FAILED,
                metadata={"error": "Task cancelled"},
            )
            raise
        finally:
            self._active_tasks.pop(task_record.task_id, None)

    async def _execute_task_internal(
        self,
        task_record: TaskRecord,
        context: dict[str, Any],
    ) -> TaskRecord:
        """Internal task execution logic."""
        try:
            task_record = await self.state_manager.update_task(
                task_record.task_id,
                state=TaskState.RUNNING,
            )
            await self._emit_event("task_started", task_record)

            # Initialize git-backed workspace
            await self.workspace_manager.initialize_workspace(task_record)

            # Inject memory context
            memory_context = await self._get_memory_context(task_record.description)
            context.update(memory_context)

            # Use agentic loop if LLM provider is available and enabled
            agentic_enabled = self.config.get("orchestrator", {}).get("agentic_execution", True)
            if self.llm_provider and self.tool_registry and agentic_enabled:
                result = await self._agentic_loop(
                    task_record, context
                )
                task_record = await self.state_manager.update_task(
                    task_record.task_id,
                    state=TaskState.COMPLETED,
                    metadata={"result": result},
                )
                await self._emit_event("task_completed", task_record)

                # Store outcome in memory
                if self.memory:
                    try:
                        await self.memory.remember(
                            f"Task: {task_record.description}\nResult: {str(result)[:500]}",
                            category="task_outcome",
                        )
                    except Exception as e:
                        logger.warning(f"Failed to store task outcome in memory: {e}")

                return task_record

            # Fallback: plan-based execution via router
            plan = await self.router.route(task_record.description, context)

            # Security checks
            if self.security_enabled:
                if plan.requires_confirmation:
                    task_record = await self.state_manager.update_task(
                        task_record.task_id,
                        state=TaskState.PAUSED,
                        metadata={"requires_confirmation": True, "plan": plan.to_dict()},
                    )
                    return task_record

                dangerous_steps = [
                    (i, step)
                    for i, step in enumerate(plan.steps)
                    if step.risk_level == "dangerous"
                ]
                if dangerous_steps:
                    task_record = await self.state_manager.update_task(
                        task_record.task_id,
                        state=TaskState.PAUSED,
                        metadata={"dangerous_steps": [str(s) for s in dangerous_steps]},
                    )
                    return task_record

            # Execute steps
            step_results: dict[int, Any] = {}
            for step_index, step in enumerate(plan.steps):
                if step.depends_on:
                    for dep_index in step.depends_on:
                        if dep_index not in step_results:
                            raise RuntimeError(
                                f"Dependency error: step {dep_index} not completed"
                            )
                result = await self._execute_step(step, task_record, step_index)
                step_results[step_index] = result

            task_record = await self.state_manager.update_task(
                task_record.task_id,
                state=TaskState.COMPLETED,
                metadata={"results": step_results},
            )
            await self._emit_event("task_completed", task_record)
            return task_record

        except Exception as e:
            logger.error(f"Task execution failed: {e}", exc_info=True)
            task_record = await self.state_manager.update_task(
                task_record.task_id,
                state=TaskState.FAILED,
                metadata={"error": str(e)},
            )
            await self._emit_event("task_failed", task_record)
            return task_record

    async def _agentic_loop(
        self,
        task_record: TaskRecord,
        context: dict[str, Any],
    ) -> str:
        """Run the agentic loop: LLM -> tool calls -> results -> repeat.

        Based on the nanobot agent loop pattern. Continues calling the LLM
        with tool results until the LLM responds without tool calls.
        """
        system_prompt = self._build_system_prompt()
        memory_ctx = context.get("memory_context", "")
        if memory_ctx and memory_ctx != "None available":
            system_prompt += f"\n\n{memory_ctx}"

        messages: list[dict[str, Any]] = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": task_record.description},
        ]

        if self.memory:
            try:
                self.memory.add_interaction(
                    role="user",
                    text=task_record.description,
                    task_id=task_record.task_id
                )
            except Exception as e:
                logger.warning(f"Failed to store user interaction in memory: {e}")

        tools = self.tool_registry.get_tool_schemas() if self.tool_registry else []

        import uuid as _uuid

        for iteration in range(self.max_iterations):
            logger.debug(f"Agentic loop iteration {iteration + 1}")

            response = await self.llm_provider.complete(
                messages=messages,
                tools=tools if tools else None,
            )

            if self.memory:
                try:
                    # Determine the agent's response content
                    agent_response_text = response.content or ""
                    if response.tool_calls:
                        tool_calls_text = " ".join([f"Tool call: {tc.function_name}({json.dumps(tc.arguments)})" for tc in response.tool_calls])
                        agent_response_text += " " + tool_calls_text

                    self.memory.add_interaction(
                        role="assistant",
                        text=agent_response_text.strip(),
                        task_id=task_record.task_id
                    )
                except Exception as e:
                    logger.warning(f"Failed to store agent interaction in memory: {e}")


            # Emit thinking event if LLM produced reasoning content
            if response.content:
                await self._emit_event("llm_thinking", {
                    "type": "llm_thinking",
                    "task_id": task_record.task_id,
                    "iteration": iteration + 1,
                    "max_iterations": self.max_iterations,
                    "content": response.content[:2000],
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                })

            # No tool calls — LLM is done
            if not response.tool_calls:
                return response.content or "Task completed."

            # Build assistant message with tool calls
            assistant_msg: dict[str, Any] = {"role": "assistant"}
            if response.content:
                assistant_msg["content"] = response.content
            else:
                assistant_msg["content"] = None

            assistant_msg["tool_calls"] = [
                {
                    "id": tc.id,
                    "type": "function",
                    "function": {
                        "name": tc.function_name,
                        "arguments": json.dumps(tc.arguments),
                    },
                }
                for tc in response.tool_calls
            ]
            messages.append(assistant_msg)

            # Execute each tool call
            for tc in response.tool_calls:
                call_id = str(_uuid.uuid4())
                logger.info(f"Tool call: {tc.function_name}({json.dumps(tc.arguments)[:200]})")

                # Emit pending event
                await self._emit_event("tool_call_pending", {
                    "type": "tool_call_pending",
                    "task_id": task_record.task_id,
                    "call_id": call_id,
                    "tool": tc.function_name,
                    "args": tc.arguments,
                    "iteration": iteration + 1,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                })

                # Optional approval gate
                needs_approval = (
                    self.approval_mode == "all" or
                    (self.approval_mode == "dangerous" and self._is_dangerous_tool(tc.function_name))
                )
                if needs_approval:
                    approval_event = asyncio.Event()
                    self._pending_approvals[call_id] = approval_event
                    await self._emit_event("action_approval_requested", {
                        "type": "action_approval_requested",
                        "call_id": call_id,
                        "tool": tc.function_name,
                        "args": tc.arguments,
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                    })
                    try:
                        await asyncio.wait_for(approval_event.wait(), timeout=300)
                    except asyncio.TimeoutError:
                        self._pending_approvals.pop(call_id, None)
                        result_str = "Error: Approval timed out."
                        messages.append({
                            "role": "tool",
                            "tool_call_id": tc.id,
                            "content": result_str,
                        })
                        continue

                    rejected = call_id in self._rejected_approvals
                    self._pending_approvals.pop(call_id, None)
                    self._rejected_approvals.discard(call_id)

                    if rejected:
                        result_str = "Error: Action rejected by user."
                        await self._emit_event("tool_call_complete", {
                            "type": "tool_call_complete",
                            "task_id": task_record.task_id,
                            "call_id": call_id,
                            "tool": tc.function_name,
                            "result": result_str,
                            "success": False,
                            "rejected": True,
                            "timestamp": datetime.now(timezone.utc).isoformat(),
                        })
                        messages.append({
                            "role": "tool",
                            "tool_call_id": tc.id,
                            "content": result_str,
                        })
                        continue

                step_record = await self.state_manager.add_step(
                    task_record.task_id,
                    action=f"Tool: {tc.function_name}",
                    tool_name=tc.function_name,
                    args=tc.arguments,
                )

                try:
                    result = await self._invoke_tool(tc.function_name, tc.arguments)
                    result_str = json.dumps(result) if not isinstance(result, str) else result
                    step_record = await self.state_manager.complete_step(step_record.step_id, result=result)
                    await self._emit_event("tool_call_complete", {
                        "type": "tool_call_complete",
                        "task_id": task_record.task_id,
                        "call_id": call_id,
                        "tool": tc.function_name,
                        "result": (result_str or "")[:1000],
                        "success": True,
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                    })
                except Exception as e:
                    result_str = f"Error: {e}"
                    logger.warning(f"Tool call failed: {e}")
                    step_record = await self.state_manager.complete_step(step_record.step_id, error=str(e))
                    await self._emit_event("tool_call_complete", {
                        "type": "tool_call_complete",
                        "task_id": task_record.task_id,
                        "call_id": call_id,
                        "tool": tc.function_name,
                        "result": result_str,
                        "success": False,
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                    })

                await self.workspace_manager.record_step(task_record, step_record)

                messages.append({
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": result_str or "Done.",
                })

        return "Max iterations reached without completion."

    def _is_dangerous_tool(self, tool_name: str) -> bool:
        """Categorize a tool as 'dangerous' requiring human intervention.
        # This list defines the boundary of ARES's autonomy. Prefer checking
        # actual capability risk levels from the registry over string matching.
        """
        # 1. Try to check actual capability risk level if registry is available
        if self.tool_registry:
            # Tools are typically called as 'tool_name.capability_name'
            if "." in tool_name:
                tool_part, cap_part = tool_name.split(".", 1)
                tool_obj = self.tool_registry.get(tool_part)
                if tool_obj:
                    for cap in tool_obj.capabilities:
                        if cap.name == cap_part:
                            # MODERATE (writes) and DANGEROUS (execution) both require approval
                            return cap.risk_level in ["dangerous", "moderate"]

        # 2. Fallback to current behavior for generic or legacy tool names
        dangerous_roots = ["shell", "computer", "file", "workspace"]
        # Only consider it dangerous if it doesn't look like a read-only operation
        is_read_only = any(term in tool_name.lower() for term in ["read", "list", "get", "status", "health", "view"])
        
        if is_read_only:
            return False
            
        return any(root in tool_name.lower() for root in dangerous_roots)

    def _build_system_prompt(self) -> str:
        """Build system prompt with tool descriptions."""
        import os
        from pathlib import Path
        
        tools_desc = ""
        if self.tool_registry:
            tools_desc = self.tool_registry.get_tools_for_llm()

        current_file = Path(__file__)
        project_root = current_file.parent.parent.parent
        prompt_path = project_root / "data" / "prompts" / "system_prompt.txt"
        
        try:
            prompt_template = prompt_path.read_text(encoding="utf-8")
        except Exception as e:
            logger.error(f"Failed to read system prompt from {prompt_path}: {e}")
            prompt_template = "You are ARES, an autonomous computer control agent.\n\n{tools_desc}\n\nBe direct and efficient. Execute the task and report results."

        return prompt_template.format(tools_desc=tools_desc)

    async def _execute_step(
        self,
        step: Any,
        task_record: TaskRecord,
        step_index: int,
    ) -> Any:
        """Execute a single step with retry logic."""
        logger.debug(f"Executing step {step_index}: {step.action}")

        step_record = await self.state_manager.add_step(
            task_record.task_id,
            action=step.action,
            tool_name=step.tool_name,
            args=step.args,
        )
        await self._emit_event("step_started", step_record)

        last_error = None
        for attempt in range(self.max_retries + 1):
            try:
                result = await self._invoke_tool(step.tool_name, step.args)

                step_record = await self.state_manager.complete_step(
                    step_record.step_id,
                    result=result,
                )
                await self.workspace_manager.record_step(task_record, step_record)
                await self._emit_event("step_completed", step_record)
                logger.info(f"Step {step_index} completed")
                return result

            except Exception as e:
                last_error = e
                logger.warning(
                    f"Step {step_index} failed (attempt {attempt + 1}/{self.max_retries + 1}): {e}"
                )
                if attempt < self.max_retries:
                    await asyncio.sleep(1 * (2 ** attempt))
                    continue
                else:
                    break

        step_record = await self.state_manager.complete_step(
            step_record.step_id,
            error=str(last_error),
        )
        await self.workspace_manager.record_step(task_record, step_record)
        raise RuntimeError(f"Step {step_index} failed: {last_error}")

    async def _invoke_tool(self, tool_name: str, args: dict[str, Any]) -> Any:
        """Invoke a tool via the tool registry.

        Handles both "tool.action" format (from LLM tool calls) and plain
        tool names (from plan-based execution).
        """
        if not self.tool_registry:
            raise RuntimeError("No tool registry configured")

        # Handle "tool.action" format (e.g., "shell.execute_command")
        if "." in tool_name:
            registry_name, action = tool_name.split(".", 1)
        else:
            registry_name = tool_name
            action = args.pop("action", "execute_command")

        tool = self.tool_registry.get(registry_name)
        if tool is None:
            raise RuntimeError(f"Tool not found: {registry_name}")

        logger.debug(f"Invoking tool: {registry_name}.{action}")
        result = await tool.execute(action, **args)

        if not result.success:
            raise RuntimeError(f"Tool '{registry_name}.{action}' failed: {result.error}")

        return result.data if result.data is not None else result.metadata

    async def recover(self) -> None:
        """Recover incomplete tasks from previous session."""
        logger.info("Checking for incomplete tasks...")
        incomplete_tasks = await self.state_manager.get_incomplete_tasks()

        if not incomplete_tasks:
            logger.info("No incomplete tasks found")
            return

        logger.warning(f"Found {len(incomplete_tasks)} incomplete tasks")
        for task in incomplete_tasks:
            await self.state_manager.update_task(
                task.task_id,
                state=TaskState.RECOVERING,
            )
            logger.info(f"Marked task for recovery: {task.task_id}")
            await self.state_manager.update_task(
                task.task_id,
                state=TaskState.FAILED,
                metadata={"recovery_attempted": True},
            )

    async def _get_memory_context(self, task_description: str) -> dict[str, Any]:
        """Retrieve relevant memory context for a task."""
        if not self.memory:
            return {"memory_context": "None available"}

        try:
            context_str = await self.memory.get_context_for_prompt(task_description)
            if context_str:
                return {"memory_context": context_str}
            return {"memory_context": "None available"}
        except Exception as e:
            logger.warning(f"Failed to get memory context: {e}")
            return {"memory_context": "None available"}

    async def _emit_event(self, event_type: str, data: Any) -> None:
        """Emit an event to all registered handlers."""
        handlers = self._event_handlers.get(event_type, [])
        for handler in handlers:
            try:
                if asyncio.iscoroutinefunction(handler):
                    await handler(data)
                else:
                    handler(data)
            except Exception as e:
                logger.error(f"Error in event handler for {event_type}: {e}")

    def on(self, event_type: str, handler: Any) -> None:
        """Register an event handler."""
        if event_type not in self._event_handlers:
            self._event_handlers[event_type] = []
        self._event_handlers[event_type].append(handler)

    # ------------------------------------------------------------------
    # Checkpoint / Resume
    # ------------------------------------------------------------------

    async def resume(self, task_id: str) -> Optional[TaskRecord]:
        """Resume a previously interrupted or failed task.

        Looks up the task record, resets its state to PENDING, and re-executes it.
        The workspace and step history are preserved so the LLM has context.

        Args:
            task_id: UUID of the task to resume.

        Returns:
            Updated TaskRecord, or None if not found.
        """
        if not self._running:
            raise RuntimeError("Orchestrator not initialized. Call initialize() first.")

        task_record = await self.state_manager.get_task(task_id)
        if task_record is None:
            logger.warning(f"Task not found for resume: {task_id}")
            return None

        logger.info(f"Resuming task: {task_id} (was {task_record.state})")

        # Fetch completed steps from workspace log so LLM gets context
        previous_steps = await self.workspace_manager.load_steps(task_record)
        context: dict[str, Any] = task_record.metadata.get("context", {})
        context["resumed"] = True
        context["previous_steps"] = previous_steps

        # Reset state for re-execution
        task_record = await self.state_manager.update_task(
            task_id,
            state=TaskState.PENDING,
            metadata={"context": context, "resume_count": task_record.metadata.get("resume_count", 0) + 1},
        )

        execution_task = asyncio.create_task(
            self._execute_task_internal(task_record, context)
        )
        self._active_tasks[task_record.task_id] = execution_task
        try:
            return await execution_task
        finally:
            self._active_tasks.pop(task_record.task_id, None)

    async def get_task(self, task_id: str) -> Optional[TaskRecord]:
        """Get a task record by ID."""
        return await self.state_manager.get_task(task_id)

    async def list_tasks(self, limit: int = 50) -> list[TaskRecord]:
        """List recent tasks."""
        return await self.state_manager.list_tasks(limit=limit)

    # ------------------------------------------------------------------
    # MCP Connector Integration
    # ------------------------------------------------------------------

    async def connect_mcp_server(self, server_url: str) -> list[str]:
        """Discover and register all tools from an MCP server.

        This is the 'plug-in' mechanism for extending ARES without code changes.
        Any MCP-compatible server (nanobot plugins, custom tools, etc.) can be
        added at runtime.

        Args:
            server_url: Base URL of the MCP server (e.g., "http://localhost:3001").

        Returns:
            List of tool names registered from the server.

        Example:
            # Connect a web browser MCP server
            tools = await orchestrator.connect_mcp_server("http://localhost:3001")
            # → ["web_browser", "web_search", ...]
        """
        if not self.tool_registry:
            raise RuntimeError("No tool registry configured")

        try:
            from ares.modules.tools.mcp_adapter import MCPDiscovery
            adapters = await MCPDiscovery.discover(server_url)
            registered = []
            for adapter in adapters:
                try:
                    self.tool_registry.register(adapter)
                    registered.append(adapter.name)
                    logger.info(f"MCP tool registered: {adapter.name}")
                except ValueError as e:
                    logger.warning(f"Skipping MCP tool {adapter.name}: {e}")
            return registered
        except Exception as e:
            logger.error(f"Failed to connect MCP server {server_url}: {e}")
            return []

    # ------------------------------------------------------------------
    # Properties
    # ------------------------------------------------------------------

    @property
    def is_running(self) -> bool:
        return self._running

    @property
    def active_tasks(self) -> list[str]:
        return list(self._active_tasks.keys())

    @property
    def uptime(self) -> float:
        if not self._start_time:
            return 0.0
        return (datetime.now(timezone.utc) - self._start_time).total_seconds()
