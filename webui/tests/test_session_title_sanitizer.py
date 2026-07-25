"""Sidebar titles must survive agent-injected prompt wrappers.

Titling on the raw first user turn produced dozens of identical unreadable
rows ("<conversation_history> …", "# Role You are the Founding Engineer …").
"""

from api.models import sanitize_session_title


def test_strips_wrapper_block_and_keeps_user_text():
    raw = "<ide_opened_file>opened /tmp/x.py</ide_opened_file>fix the parser please"
    assert sanitize_session_title(raw) == "fix the parser please"


def test_unwraps_when_turn_is_only_a_wrapper_block():
    raw = "<conversation_history> Assistant: Parallel verification got killed</conversation_history>"
    assert sanitize_session_title(raw) == "Parallel verification got killed"


def test_drops_role_preamble_but_keeps_the_instruction():
    raw = "# Role You are the Founding Engineer at Test Co. You own the full-stack build"
    assert sanitize_session_title(raw) == "You own the full-stack build"


def test_keeps_preamble_when_nothing_else_remains():
    # Better a preamble than an empty sidebar row.
    assert sanitize_session_title("# Role You are the lead agent.") == "You are the lead agent."


def test_strips_speaker_prefix():
    assert sanitize_session_title("Human: reply with exactly one word") == "reply with exactly one word"


def test_plain_prompt_is_untouched():
    raw = "i was told we had these issues not sure if we already solved it"
    assert sanitize_session_title(raw) == raw


def test_empty_falls_back():
    assert sanitize_session_title("", "Session") == "Session"
    assert sanitize_session_title("   ", "Session") == "Session"


def test_title_is_length_capped():
    assert len(sanitize_session_title("word " * 200)) <= 80
