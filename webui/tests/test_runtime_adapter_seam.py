import importlib
from pathlib import Path
import io
import queue

def test_runtime_adapter_interface_and_legacy_journal_methods_exist():
    runtime = importlib.import_module("api.runtime_adapter")

    required = (
        "start_run",
        "observe_run",
        "get_run",
        "cancel_run",
        "respond_approval",
        "respond_clarify",
        "queue_message",
        "update_goal",
    )
    for name in required:
        assert hasattr(runtime.RuntimeAdapter, name)
        assert hasattr(runtime.LegacyJournalRuntimeAdapter, name)
        assert hasattr(runtime.RunnerRuntimeAdapter, name)

    assert runtime.runtime_adapter_mode({}) == "legacy-direct"
    assert runtime.runtime_adapter_enabled({}) is False
    assert runtime.runtime_adapter_mode({"ARES_WEBUI_RUNTIME_ADAPTER": "legacy-journal"}) == "legacy-journal"
    assert runtime.runtime_adapter_enabled({"ARES_WEBUI_RUNTIME_ADAPTER": "legacy-journal"}) is True
    assert runtime.runtime_adapter_mode({"ARES_WEBUI_RUNTIME_ADAPTER": "runner-local"}) == "runner-local"
    assert runtime.runtime_adapter_runner_enabled({"ARES_WEBUI_RUNTIME_ADAPTER": "runner-local"}) is True
    assert runtime.runtime_adapter_mode({"ARES_WEBUI_RUNTIME_ADAPTER": "sidecar"}) == "legacy-direct"


def test_runtime_adapter_factory_selects_only_explicit_default_off_modes():
    runtime = importlib.import_module("api.runtime_adapter")
    calls = []

    class FakeRunnerClient:
        pass

    def legacy_factory():
        calls.append("legacy")
        return runtime.LegacyJournalRuntimeAdapter(start_run_delegate=lambda request: {"stream_id": "s"})

    def runner_factory():
        calls.append("runner")
        return FakeRunnerClient()

    assert runtime.build_runtime_adapter(environ={}) is None

    legacy = runtime.build_runtime_adapter(
        environ={"ARES_WEBUI_RUNTIME_ADAPTER": "legacy-journal"},
        legacy_adapter_factory=legacy_factory,
        runner_client_factory=runner_factory,
    )
    assert isinstance(legacy, runtime.LegacyJournalRuntimeAdapter)

    runner = runtime.build_runtime_adapter(
        environ={"ARES_WEBUI_RUNTIME_ADAPTER": "runner-local"},
        legacy_adapter_factory=legacy_factory,
        runner_client_factory=runner_factory,
    )
    assert isinstance(runner, runtime.RunnerRuntimeAdapter)
    assert calls == ["legacy", "runner"]


def test_runner_local_factory_requires_injected_client_and_does_not_fallback_to_legacy():
    runtime = importlib.import_module("api.runtime_adapter")
    calls = []

    def legacy_factory():
        calls.append("legacy")
        return runtime.LegacyJournalRuntimeAdapter(start_run_delegate=lambda request: {"stream_id": "s"})

    try:
        runtime.build_runtime_adapter(
            environ={"ARES_WEBUI_RUNTIME_ADAPTER": "runner-local"},
            legacy_adapter_factory=legacy_factory,
        )
    except NotImplementedError as exc:
        assert "runner client factory" in str(exc)
    else:
        raise AssertionError("runner-local must require an injected runner client factory")

    assert calls == []


def test_legacy_journal_adapter_start_run_delegates_without_owning_runtime_state():
    runtime = importlib.import_module("api.runtime_adapter")
    calls = []

    def start_delegate(request):
        calls.append(request)
        return {
            "stream_id": "stream-123",
            "session_id": request.session_id,
            "status": "started",
            "active_controls": ["cancel"],
        }

    adapter = runtime.LegacyJournalRuntimeAdapter(start_run_delegate=start_delegate)
    request = runtime.StartRunRequest(
        session_id="s1",
        message="hello",
        attachments=[{"name": "a.txt"}],
        workspace="/tmp/work",
        profile="default",
        provider="openai-codex",
        model="gpt-5.5",
        toolsets=["terminal"],
        source="webui",
        metadata={"k": "v"},
    )

    result = adapter.start_run(request)

    assert calls == [request]
    assert result.session_id == "s1"
    assert result.stream_id == "stream-123"
    assert result.run_id == "stream-123"
    assert result.status == "started"
    assert result.active_controls == ["cancel"]


def test_legacy_journal_adapter_observe_and_get_run_use_journal_and_live_state(tmp_path):
    runtime = importlib.import_module("api.runtime_adapter")
    run_journal = importlib.import_module("api.run_journal")

    run_journal.append_run_event("s1", "r1", "token", {"text": "a"}, session_dir=tmp_path)
    run_journal.append_run_event("s1", "r1", "done", {"ok": True}, session_dir=tmp_path)

    adapter = runtime.LegacyJournalRuntimeAdapter(
        session_dir=tmp_path,
        live_stream_lookup=lambda run_id: run_id == "live-run",
    )

    replay = adapter.observe_run("r1", cursor="0")
    assert [event["type"] for event in replay.events] == ["token", "done"]
    assert replay.last_event_id == "r1:2"

    completed = adapter.get_run("r1")
    assert completed.run_id == "r1"
    assert completed.session_id == "s1"
    assert completed.status == "completed"
    assert completed.terminal_state == "completed"
    assert completed.last_event_id == "r1:2"

    live = adapter.get_run("live-run")
    assert live.run_id == "live-run"
    assert live.status == "running"
    assert live.active_controls == ["cancel"]


def test_legacy_journal_adapter_controls_delegate_to_existing_handlers():
    runtime = importlib.import_module("api.runtime_adapter")
    calls = []
    adapter = runtime.LegacyJournalRuntimeAdapter(
        cancel_delegate=lambda run_id: calls.append(("cancel", run_id)) or True,
        approval_delegate=lambda run_id, approval_id, choice: calls.append(("approval", run_id, approval_id, choice)) or True,
        clarify_delegate=lambda run_id, clarify_id, response: calls.append(("clarify", run_id, clarify_id, response)) or True,
    )

    assert adapter.cancel_run("r1").accepted is True
    assert adapter.respond_approval("r1", "a1", "once").accepted is True
    assert adapter.respond_clarify("r1", "c1", "answer").accepted is True
    assert calls == [
        ("cancel", "r1"),
        ("approval", "r1", "a1", "once"),
        ("clarify", "r1", "c1", "answer"),
    ]


def test_legacy_journal_adapter_queue_and_goal_delegate_without_owning_runtime_state():
    runtime = importlib.import_module("api.runtime_adapter")
    calls = []
    adapter = runtime.LegacyJournalRuntimeAdapter(
        queue_delegate=lambda run_id, message, mode: calls.append(("queue", run_id, message, mode)) or True,
        goal_delegate=lambda session_id, action, text: calls.append(("goal", session_id, action, text)) or {
            "ok": True,
            "action": action,
            "message": "Goal updated.",
        },
    )

    queued = adapter.queue_message("r1", "follow up", mode="queue")
    goal = adapter.update_goal("s1", "set", "finish the task")

    assert queued.accepted is True
    assert goal.accepted is True
    assert goal.payload["action"] == "set"
    assert calls == [
        ("queue", "r1", "follow up", "queue"),
        ("goal", "s1", "set", "finish the task"),
    ]


def test_legacy_journal_adapter_cancel_returns_bounded_not_active_status():
    runtime = importlib.import_module("api.runtime_adapter")
    calls = []
    adapter = runtime.LegacyJournalRuntimeAdapter(
        cancel_delegate=lambda run_id: calls.append(run_id) or False,
    )

    result = adapter.cancel_run("already-finished-run")

    assert calls == ["already-finished-run"]
    assert result.accepted is False
    assert result.status == "not-active"
    assert result.safe_message == "Legacy control did not accept the request."


def test_legacy_journal_adapter_approval_and_clarify_return_bounded_not_active_status():
    runtime = importlib.import_module("api.runtime_adapter")
    calls = []
    adapter = runtime.LegacyJournalRuntimeAdapter(
        approval_delegate=lambda run_id, approval_id, choice: calls.append(("approval", run_id, approval_id, choice)) or False,
        clarify_delegate=lambda run_id, clarify_id, response: calls.append(("clarify", run_id, clarify_id, response)) or False,
    )

    approval = adapter.respond_approval("already-finished-run", "stale-approval", "deny")
    clarify = adapter.respond_clarify("already-finished-run", "stale-clarify", "answer")

    assert calls == [
        ("approval", "already-finished-run", "stale-approval", "deny"),
        ("clarify", "already-finished-run", "stale-clarify", "answer"),
    ]
    assert approval.accepted is False
    assert approval.status == "not-active"
    assert clarify.accepted is False
    assert clarify.status == "not-active"


def test_legacy_journal_adapter_queue_and_goal_return_bounded_statuses():
    runtime = importlib.import_module("api.runtime_adapter")
    adapter = runtime.LegacyJournalRuntimeAdapter(
        queue_delegate=lambda run_id, message, mode: False,
        goal_delegate=lambda session_id, action, text: {
            "ok": False,
            "action": action,
            "error": "agent_running",
            "message": "Agent is running.",
        },
    )

    queued = adapter.queue_message("already-finished-run", "follow up")
    goal = adapter.update_goal("s1", "set", "new goal")

    assert queued.accepted is False
    assert queued.status == "not-active"
    assert goal.accepted is False
    assert goal.status == "set"
    assert goal.safe_message == "Agent is running."
    assert goal.payload["error"] == "agent_running"
























def test_rfc_distinguishes_goal_routing_from_queue_route_staging():
    rfc = (Path(__file__).parent.parent / "docs" / "rfcs" / "ares-run-adapter-contract.md").read_text(encoding="utf-8")

    assert "#2544 shipped the first Slice 3c implementation" in rfc
    assert "#2560 shipped the queue-staging clarification" in rfc
    assert "route now uses `RuntimeAdapter.update_goal(...)`" in rfc
    assert "`queue_message(...)` as a staged protocol method only" in rfc
    assert "no new server-side queue endpoint" in rfc
    assert "no server-side queue endpoint or queue\n  scheduler should be added merely for adapter symmetry" in rfc


def test_rfc_defines_slice4_runner_contract_before_runner_code():
    rfc = (Path(__file__).parent.parent / "docs" / "rfcs" / "ares-run-adapter-contract.md").read_text(encoding="utf-8")

    assert "#### Slice 4a: Runner contract gate" in rfc
    assert "docs/test contract PR before any\nrunner code lands" in rfc
    assert "feature-flagged, default-off" in rfc
    assert "The runner, not the main WebUI request process, owns" in rfc
    assert "restart only\n   `ares-webui.service`" in rfc
    assert "profile,\n   workspace, attachments, model/provider, toolset, and source metadata" in rfc
    assert "no removal of the legacy in-process backend" in rfc
    assert "no default-on runner mode" in rfc
    assert "#### Slice 4b: Runner adapter client facade" in rfc
    assert "Status as of 2026-05-20: shipped in v0.51.94 via #2599" in rfc
    assert "delegates to an injected runner client" in rfc
    assert "without relying on process-local `STREAMS`" in rfc


def test_rfc_defines_slice4c_runner_backend_harness_gate():
    rfc = (Path(__file__).parent.parent / "docs" / "rfcs" / "ares-run-adapter-contract.md").read_text(encoding="utf-8")

    assert "#### Slice 4c: Feature-flagged runner backend and restart/reattach harness" in rfc
    assert "Status as of 2026-05-21: shipped in v0.51.105 via #2696" in rfc
    assert "`ARES_WEBUI_RUNTIME_ADAPTER=runner-local`" in rfc
    assert "`legacy-direct` remains the default" in rfc
    assert "No route-shape drift" in rfc
    assert "Restart/reattach harness" in rfc
    assert "discard the first WebUI adapter instance" in rfc
    assert "No runtime-surrogate globals" in rfc
    assert "no live chat route switch to the runner backend before the restart/reattach" in rfc


def test_rfc_defines_slice4d_supervised_runner_route_gate():
    rfc = (Path(__file__).parent.parent / "docs" / "rfcs" / "ares-run-adapter-contract.md").read_text(encoding="utf-8")

    assert "#### Slice 4d: Supervised runner backend route gate" in rfc
    assert "Status as of 2026-05-23: shipped in v0.51.108 via #2744" in rfc
    assert "After `runner-local` selection exists" in rfc
    assert "route-selection harness before live\nbrowser chat can use it" in rfc
    assert "Route remains default-off" in rfc
    assert "Restart/reattach harness proves ownership moved" in rfc
    assert "No public response-shape drift" in rfc
    assert "No runtime-surrogate globals" in rfc
    assert "Explicit context payloads" in rfc
    assert "active-run discovery, session-to-run lookup, command capability\n  metadata, artifact events, and provider/tool routing" in rfc
    assert "WebUI remains the rich workbench while\n  only execution ownership moves" in rfc


def test_rfc_defines_slice4e_runner_chat_start_route_selection_harness():
    rfc = (Path(__file__).parent.parent / "docs" / "rfcs" / "ares-run-adapter-contract.md").read_text(encoding="utf-8")

    assert "#### Slice 4e: Default-off runner chat-start route-selection harness" in rfc
    assert "Status as of 2026-05-24: shipped in v0.51.129 via #2794" in rfc
    assert "route `/api/chat/start` through `build_runtime_adapter(...)`" in rfc
    assert "`legacy-direct` stays default" in rfc
    assert "`legacy-journal`\ncontinues to delegate to the legacy in-process stream path" in rfc
    assert "`runner-local`\ndoes not silently fall back to legacy" in rfc
    assert "return a bounded not-configured error for `runner-local`" in rfc
    assert "`run_id`, `status`, and\n   `active_controls` remain internal" in rfc
    assert "no supervised runner process yet" in rfc


def test_rfc_defines_slice4f_supervised_local_runner_client_gate():
    rfc = (Path(__file__).parent.parent / "docs" / "rfcs" / "ares-run-adapter-contract.md").read_text(encoding="utf-8")

    assert "#### Slice 4f: Supervised local runner client backend gate" in rfc
    assert "Status as of 2026-05-31: shipped in v0.51.188 via #3073 / #3274" in rfc
    assert "The client\ntransport is now implemented behind `ARES_WEBUI_RUNNER_BASE_URL`" in rfc
    assert "`HttpRunnerClient` rejects non-`http(s)` base URL schemes" in rfc
    assert "uses an opener that\ndoes not follow redirects" in rfc
    assert "the configured\nrunner must emit events that are already compatible with the browser SSE event\nnames/payloads" in rfc
    assert "a later runner-owned normalization layer must translate\nAres runtime families such as `token.delta`, `tool.started`, and `done`" in rfc
    assert "After the configured runner-client boundary ships" in rfc
    assert "configured external endpoint or fake-runner fixture" in rfc
    assert "cancel as the first required live control" in rfc
    assert "501 path replaced only when configured" in rfc
    assert "Restart/reattach proves ownership moved" in rfc
    assert "No runtime-surrogate globals" in rfc
    assert "Successful chat-start responses remain limited\n   to the legacy-compatible field whitelist" in rfc
    assert "Unsupported runner controls return safe\n   `unsupported`, `not-active`, or `conflict` results" in rfc
    assert "no permanent WebUI-owned active-run discovery cache" in rfc


def test_rfc_defines_slice4g_supervised_local_runner_process_gate():
    rfc = (Path(__file__).parent.parent / "docs" / "rfcs" / "ares-run-adapter-contract.md").read_text(encoding="utf-8")

    assert "#### Slice 4g: Supervised local runner process harness gate" in rfc
    assert "After #3073 / #3274, WebUI has an explicit configured-runner HTTP client" in rfc
    assert "still does not ship the supervised runner process itself" in rfc
    assert "own\n`AIAgent` execution outside the main WebUI request process" in rfc
    assert "keep WebUI as a client of `ARES_WEBUI_RUNNER_BASE_URL`" in rfc
    assert "without WebUI process-global\n  environment mutation" in rfc
    assert "Process ownership moved" in rfc
    assert "Restart/reattach with a real runner" in rfc
    assert "No runtime-surrogate globals in WebUI" in rfc
    assert "Default-off and reversible" in rfc
    assert "Runner health and failure are observable" in rfc
    assert "no claim that this is the canonical Ares Agent Runtime API" in rfc






def test_runner_runtime_adapter_passes_explicit_start_payload_without_env_mutation(monkeypatch):
    runtime = importlib.import_module("api.runtime_adapter")
    captured = []

    class FakeRunnerClient:
        def start_run(self, request):
            captured.append(request)
            return {
                "run_id": "runner-1",
                "session_id": request.session_id,
                "stream_id": "runner-1",
                "status": "running",
                "active_controls": ["cancel", "approval", "clarify", "goal"],
            }

    before_terminal_cwd = "existing-cwd"
    monkeypatch.setenv("TERMINAL_CWD", before_terminal_cwd)
    adapter = runtime.RunnerRuntimeAdapter(client=FakeRunnerClient())
    request = runtime.StartRunRequest(
        session_id="s-runner",
        message="hello runner",
        attachments=[{"path": "/tmp/a.png", "mime": "image/png"}],
        workspace="/workspace/project",
        profile="research",
        provider="openai-codex",
        model="gpt-5.5",
        toolsets=["terminal", "file"],
        source="webui",
        metadata={"route": "/api/chat/start", "csrf_checked": True},
    )

    result = adapter.start_run(request)

    assert captured == [request]
    assert captured[0].workspace == "/workspace/project"
    assert captured[0].profile == "research"
    assert captured[0].attachments == [{"path": "/tmp/a.png", "mime": "image/png"}]
    assert captured[0].provider == "openai-codex"
    assert captured[0].model == "gpt-5.5"
    assert captured[0].toolsets == ["terminal", "file"]
    assert result.run_id == "runner-1"
    assert result.active_controls == ["cancel", "approval", "clarify", "goal"]
    assert runtime.os.environ["TERMINAL_CWD"] == before_terminal_cwd


def test_runner_runtime_adapter_observe_and_get_survive_adapter_recreation():
    runtime = importlib.import_module("api.runtime_adapter")

    class FakeRunnerClient:
        def __init__(self):
            self.events = []
            self.status = "unknown"

        def start_run(self, request):
            self.status = "running"
            self.events.append({"event_id": "runner-1:1", "seq": 1, "type": "token", "data": {"text": "hi"}})
            self.events.append({"event_id": "runner-1:2", "seq": 2, "type": "done", "data": {"ok": True}})
            self.status = "completed"
            return {"run_id": "runner-1", "session_id": request.session_id, "stream_id": "runner-1", "status": "running"}

        def observe_run(self, run_id, *, cursor=None):
            after = int(cursor or 0)
            return {"run_id": run_id, "events": [e for e in self.events if e["seq"] > after]}

        def get_run(self, run_id):
            return {
                "run_id": run_id,
                "session_id": "s-runner",
                "status": self.status,
                "terminal_state": "completed",
                "last_event_id": self.events[-1]["event_id"],
                "active_controls": [],
            }

    shared_runner = FakeRunnerClient()
    first_webui_process = runtime.RunnerRuntimeAdapter(client=shared_runner)
    first_webui_process.start_run(runtime.StartRunRequest(session_id="s-runner", message="hello"))

    restarted_webui_process = runtime.RunnerRuntimeAdapter(client=shared_runner)
    replay = restarted_webui_process.observe_run("runner-1", cursor="1")
    status = restarted_webui_process.get_run("runner-1")

    assert [event["type"] for event in replay.events] == ["done"]
    assert replay.cursor == "2"
    assert replay.last_event_id == "runner-1:2"
    assert status.status == "completed"
    assert status.terminal_state == "completed"
    assert status.last_event_id == "runner-1:2"


def test_runner_runtime_adapter_controls_are_bounded_and_do_not_use_legacy_state():
    runtime = importlib.import_module("api.runtime_adapter")

    class FakeRunnerClient:
        def cancel_run(self, run_id):
            return {"ok": False, "status": "not-active", "message": "Run is not active."}

    adapter = runtime.RunnerRuntimeAdapter(client=FakeRunnerClient())

    cancel = adapter.cancel_run("finished-run")
    approval = adapter.respond_approval("finished-run", "approval-1", "once")
    clarify = adapter.respond_clarify("finished-run", "clarify-1", "answer")
    queued = adapter.queue_message("finished-run", "next")
    goal = adapter.update_goal("s-runner", "status")

    assert cancel.accepted is False
    assert cancel.status == "not-active"
    assert cancel.safe_message == "Run is not active."
    for result in (approval, clarify, queued, goal):
        assert result.accepted is False
        assert result.status == "unsupported"
        assert "not supported by this runner backend" in (result.safe_message or "")
