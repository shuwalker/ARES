import json
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

# Dynamically add email assistant tools directory to python search path
repo_root = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(repo_root / "tools" / "email_ai_assistant"))
import ares_mail_config
from mail_assistant import EmailMessage, ThreadNode, ClassificationResult

from api import email_routes


# ── Mock handler helpers ─────────────────────────────────────────────────────

class _MockHandler:
    """Minimal BaseHTTPRequestHandler stand-in for route testing."""

    def __init__(self, headers=None):
        self.sent_headers = []
        self.status = None
        self.body = bytearray()
        self.wfile = self

    def send_response(self, status):
        self.status = status

    def send_header(self, name, value):
        self.sent_headers.append((name, value))

    def end_headers(self):
        pass

    def write(self, data):
        self.body.extend(data)

    def get_json(self):
        return json.loads(bytes(self.body).decode("utf-8"))


# ── Config Tests ─────────────────────────────────────────────────────────────

def test_ares_mail_config_env_precedence(monkeypatch):
    monkeypatch.setenv("ARES_MAIL_ASSISTANT_NAME", "Test Assistant")
    monkeypatch.setenv("ARES_MAIL_NAS_PATH", "/Volumes/Backup/Mail")
    monkeypatch.setenv("ARES_MAIL_KEEP_ADDRESSES", "keep1@ex.com, keep2@ex.com")
    monkeypatch.setenv("ARES_MAIL_WORK_DOMAINS", "corp.com, internal.net")

    assert ares_mail_config.assistant_name() == "Test Assistant"
    assert ares_mail_config.nas_archive_path() == "/Volumes/Backup/Mail"
    assert ares_mail_config.extra_keep_addresses() == ["keep1@ex.com", "keep2@ex.com"]
    assert ares_mail_config.extra_work_domains() == ["corp.com", "internal.net"]


# ── Route Handler Tests ───────────────────────────────────────────────────────

@pytest.fixture
def mock_assistant(monkeypatch):
    mock_cls = MagicMock()
    mock_inst = mock_cls.return_value
    monkeypatch.setattr(email_routes, "_mail_assistant_cls", mock_cls)
    return mock_inst


def test_handle_email_unread_get(mock_assistant):
    # Setup mock dataclass return data
    msg = EmailMessage(
        id="123",
        subject="Test subject",
        sender="bob@example.com",
        date_received="2026-07-06T22:00:00",
        is_read=False,
        body_plain="Hello text",
        body_html="<html>Hello html</html>",
    )
    mock_assistant.list_unread.return_value = [msg]

    handler = _MockHandler()
    parsed = SimpleNamespace(query="limit=5")

    email_routes.handle_email_unread_get(handler, parsed)
    assert handler.status == 200

    data = handler.get_json()
    assert data["ok"] is True
    assert len(data["messages"]) == 1
    assert data["messages"][0]["id"] == "123"
    assert data["messages"][0]["body_html"] == "<html>Hello html</html>"
    mock_assistant.list_unread.assert_called_once_with(limit=5)


def test_handle_email_all_get(mock_assistant):
    msg1 = EmailMessage(id="1", subject="S1", sender="b@e.com", date_received="d1", is_read=True)
    msg2 = EmailMessage(id="2", subject="S2", sender="b@e.com", date_received="d2", is_read=False)
    mock_assistant.scan_all.return_value = [msg1, msg2]

    handler = _MockHandler()
    parsed = SimpleNamespace(query="limit=100")

    email_routes.handle_email_all_get(handler, parsed)
    assert handler.status == 200

    data = handler.get_json()
    assert data["ok"] is True
    assert data["total"] == 2
    assert data["unread"] == 1
    assert data["read"] == 1
    mock_assistant.scan_all.assert_called_once_with(limit=100)


def test_handle_email_all_get_uses_bounded_default(mock_assistant):
    mock_assistant.scan_all.return_value = []
    handler = _MockHandler()

    email_routes.handle_email_all_get(handler, SimpleNamespace(query=""))

    assert handler.status == 200
    mock_assistant.scan_all.assert_called_once_with(limit=50)


def test_handle_email_all_get_reports_mail_unavailable(mock_assistant):
    mock_assistant.scan_all.side_effect = TimeoutError("Mail did not respond")
    handler = _MockHandler()

    email_routes.handle_email_all_get(handler, SimpleNamespace(query=""))

    assert handler.status == 503
    assert handler.get_json()["error"] == "Mail notifications are currently unavailable"


def test_handle_email_message_get(mock_assistant):
    msg = EmailMessage(id="42", subject="Hi", sender="alice@example.com", date_received="d", is_read=True, body_plain="content")
    mock_assistant.read_message.return_value = msg

    handler = _MockHandler()
    parsed = SimpleNamespace(query="id=42")

    email_routes.handle_email_message_get(handler, parsed)
    assert handler.status == 200

    data = handler.get_json()
    assert data["ok"] is True
    assert data["message"]["id"] == "42"
    mock_assistant.read_message.assert_called_once_with("42")


def test_handle_email_message_get_missing_or_invalid_id():
    handler = _MockHandler()
    parsed = SimpleNamespace(query="id=")
    email_routes.handle_email_message_get(handler, parsed)
    assert handler.status == 400

    handler = _MockHandler()
    parsed = SimpleNamespace(query="id=notanumber")
    email_routes.handle_email_message_get(handler, parsed)
    assert handler.status == 400


def test_handle_email_classify_get(mock_assistant):
    msg = EmailMessage(id="101", subject="Buy now", sender="spammer@bad.com", date_received="d", is_read=False, body_plain="spam")
    classification_res = ClassificationResult(
        message_id="101",
        sender="spammer@bad.com",
        subject="Buy now",
        classification="Junk",
        method="LLM",
    )
    mock_assistant.read_message.return_value = msg
    mock_assistant.classify_message.return_value = classification_res

    handler = _MockHandler()
    parsed = SimpleNamespace(query="id=101")

    email_routes.handle_email_classify_get(handler, parsed)
    assert handler.status == 200

    data = handler.get_json()
    assert data["ok"] is True
    assert data["classification"] == "Junk"
    assert data["method"] == "LLM"
    mock_assistant.classify_message.assert_called_once_with(msg)


def test_handle_email_draft_post(mock_assistant):
    mock_assistant.draft_reply.return_value = "This is a draft reply."

    handler = _MockHandler()
    parsed = SimpleNamespace(query="")
    body = {"id": "99", "instruction": "Say yes"}

    email_routes.handle_email_draft_post(handler, parsed, body)
    assert handler.status == 200

    data = handler.get_json()
    assert data["ok"] is True
    assert data["draft"] == "This is a draft reply."
    mock_assistant.draft_reply.assert_called_once_with("99", prompt="Say yes")


def test_handle_email_clean_post(mock_assistant):
    clean_result = {
        "moved_to_junk": ["12"],
        "moved_to_archive": ["13"],
        "total_processed": 2,
    }
    mock_assistant.auto_clean.return_value = clean_result

    handler = _MockHandler()
    parsed = SimpleNamespace(query="")
    body = {"dry_run": False, "limit": 50}

    email_routes.handle_email_clean_post(handler, parsed, body)
    assert handler.status == 200

    data = handler.get_json()
    assert data["ok"] is True
    assert data["result"] == clean_result
    mock_assistant.auto_clean.assert_called_once_with(limit=50, dry_run=False)


def test_handle_email_move_post(mock_assistant):
    mock_assistant.move_to_junk.return_value = True
    mock_assistant.move_to_archive.return_value = True

    # Test move to junk
    handler = _MockHandler()
    body = {"id": "15", "action": "junk"}
    email_routes.handle_email_move_post(handler, None, body)
    assert handler.status == 200
    data = handler.get_json()
    assert data["ok"] is True
    assert data["moved_to"] == "junk"
    mock_assistant.move_to_junk.assert_called_once_with("15")

    # Test move to archive
    handler = _MockHandler()
    body = {"id": "16", "action": "archive", "sender": "test@test.com", "subject": "Test"}
    email_routes.handle_email_move_post(handler, None, body)
    assert handler.status == 200
    data = handler.get_json()
    assert data["ok"] is True
    assert data["moved_to"] == "archive"
    mock_assistant.move_to_archive.assert_called_once_with("16", sender="test@test.com", subject="Test")


def test_handle_email_mark_read_post(mock_assistant):
    mock_assistant.mark_read.return_value = True

    handler = _MockHandler()
    body = {"id": "17"}
    email_routes.handle_email_mark_read_post(handler, None, body)
    assert handler.status == 200
    data = handler.get_json()
    assert data["ok"] is True
    assert data["marked_read"] is True
    mock_assistant.mark_read.assert_called_once_with("17")


def test_handle_email_thread_get(mock_assistant):
    msg = EmailMessage(id="18", subject="S", sender="b@e.com", date_received="d", is_read=True)
    node = ThreadNode(level=0, body="Original message", meta="date: today")
    mock_assistant.read_message.return_value = msg
    mock_assistant.parse_thread.return_value = [node]

    handler = _MockHandler()
    parsed = SimpleNamespace(query="id=18")
    email_routes.handle_email_thread_get(handler, parsed)
    assert handler.status == 200
    data = handler.get_json()
    assert data["ok"] is True
    assert len(data["thread"]) == 1
    assert data["thread"][0]["body"] == "Original message"


def test_handle_email_save_nas_post(mock_assistant):
    mock_assistant.get_archive_subfolder.return_value = "Work"
    mock_assistant.save_to_nas.return_value = True

    handler = _MockHandler()
    body = {"id": "19", "sender": "work@corp.com", "subject": "Project X"}
    email_routes.handle_email_save_nas_post(handler, None, body)
    assert handler.status == 200
    data = handler.get_json()
    assert data["ok"] is True
    assert data["saved"] is True
    assert data["subfolder"] == "Work"
    mock_assistant.get_archive_subfolder.assert_called_once_with("work@corp.com")
    mock_assistant.save_to_nas.assert_called_once_with("19", "work@corp.com", "Project X", "Work")
