from unittest.mock import patch


class _FakeSession:
    def __init__(self, *, is_cli_session=False, session_source=None, source_tag=None):
        self.session_id = "native_webui_001"
        self.title = "Native WebUI"
        self.workspace = "/tmp"
        self.model = "gpt-test"
        self.model_provider = None
        self.messages = []
        self.tool_calls = []
        self.input_tokens = 0
        self.output_tokens = 0
        self.estimated_cost = 0
        self.context_length = 1
        self.threshold_tokens = 0
        self.last_prompt_tokens = 0
        self.active_stream_id = None
        self.pending_user_message = None
        self.pending_attachments = []
        self.pending_started_at = None
        self.composer_draft = {}
        self.is_cli_session = is_cli_session
        self.session_source = session_source
        self.source_tag = source_tag
        self.raw_source = source_tag
        self.source_label = source_tag

    def compact(self):
        return {
            "session_id": self.session_id,
            "title": self.title,
            "workspace": self.workspace,
            "model": self.model,
            "model_provider": self.model_provider,
            "message_count": 0,
            "context_length": self.context_length,
            "threshold_tokens": self.threshold_tokens,
            "last_prompt_tokens": self.last_prompt_tokens,
            "active_stream_id": self.active_stream_id,
            "pending_user_message": self.pending_user_message,
            "composer_draft": self.composer_draft,
            "is_cli_session": self.is_cli_session,
            "session_source": self.session_source,
            "source_tag": self.source_tag,
            "raw_source": self.raw_source,
            "source_label": self.source_label,
        }


def _invoke_api_session(session_obj, *, lookup_cli):
    from fastapi_app.services import AresCoreService

    with patch("api.models.get_session", return_value=session_obj), \
         patch("api.session_access.lookup_cli_session_metadata", side_effect=lookup_cli) as lookup:
        data = AresCoreService().session(
            "native_webui_001", profile=None, load_messages=False, message_limit=None
        )
    return {"data": data, "status": 200}, lookup


def test_api_session_metadata_skips_cli_lookup_for_native_webui_session():
    """Native WebUI sessions should not scan Agent state.db on every metadata load."""
    session = _FakeSession()

    def fail_lookup(_sid):
        raise AssertionError("native WebUI metadata should not query CLI sessions")

    captured, lookup = _invoke_api_session(session, lookup_cli=fail_lookup)

    assert captured["status"] == 200
    assert captured["data"]["session"]["session_id"] == "native_webui_001"
    lookup.assert_not_called()


def test_api_session_metadata_uses_persisted_cli_metadata_without_live_scan():
    """Imported metadata is already persisted and does not require a live scan."""
    session = _FakeSession(is_cli_session=True, session_source="messaging", source_tag="telegram")

    captured, lookup = _invoke_api_session(
        session,
        lookup_cli=lambda _sid: (_ for _ in ()).throw(AssertionError("unexpected CLI scan")),
    )

    assert captured["status"] == 200
    assert captured["data"]["session"]["source_tag"] == "telegram"
    lookup.assert_not_called()
