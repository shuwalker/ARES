"""Regression coverage for stale composer_draft restoration after send."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SESSIONS_JS = ROOT.joinpath("static", "sessions.js").read_text(encoding="utf-8")
MESSAGES_JS = ROOT.joinpath("static", "messages.js").read_text(encoding="utf-8")


def _block(source: str, start_marker: str, end_marker: str) -> str:
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


def test_clear_composer_draft_suppresses_same_session_stale_restore():
    """An async draft-clear POST must not allow old server draft text to repopulate #msg."""
    assert "const _composerDraftRestoreSuppressedUntilBySid = new Map();" in SESSIONS_JS
    assert "function _suppressComposerDraftRestoreAfterSubmit(sid)" in SESSIONS_JS
    clear_body = _block(SESSIONS_JS, "function _clearComposerDraft(sid)", "const SESSION_VIEWED_COUNTS_KEY")
    suppress_idx = clear_body.index("_suppressComposerDraftRestoreAfterSubmit(sid);")
    post_idx = clear_body.index("api('/api/session/draft'")
    assert suppress_idx < post_idx, "restore suppression must be local and immediate before async POST"


def test_non_empty_draft_save_clears_submit_restore_suppression():
    save_body = _block(SESSIONS_JS, "function _saveComposerDraft(sid, text, files)", "function _composerDraftHasPayload")
    assert "_clearComposerDraftRestoreSuppression(sid);" in save_body
    now_body = _block(SESSIONS_JS, "function _saveComposerDraftNow(sid, text, files)", "// Restore composer draft")
    assert "_clearComposerDraftRestoreSuppression(sid);" in now_body


def test_restore_skips_suppressed_non_empty_server_draft_only():
    restore_body = _block(SESSIONS_JS, "function _restoreComposerDraft(draft, targetSid", "// Clear the saved draft")
    assert "const restoreSid = targetSid || (S.session && S.session.session_id);" in restore_body
    assert "const hasServerDraftPayload = _composerDraftHasPayload(text, files);" in restore_body
    assert "hasServerDraftPayload && _isComposerDraftRestoreSuppressed(restoreSid)" in restore_body
    assert "!hasServerDraftPayload) _clearComposerDraftRestoreSuppression(restoreSid);" in restore_body


def test_busy_send_paths_clear_persisted_composer_draft():
    helper_body = _block(MESSAGES_JS, "function _clearComposerAfterQueuedSelectionSend", "function _flushSelectionBlocksToComposer")
    assert "function _clearComposerAfterQueuedSelectionSend()" in helper_body
    assert "const sid=arguments.length?arguments[0]:(S.session&&S.session.session_id);" in helper_body
    assert "_clearComposerDraft(sid)" in helper_body

    in_progress_body = _block(MESSAGES_JS, "if (_sendInProgress) {", "  _sendInProgress = true;")
    assert "_clearComposerAfterQueuedSelectionSend();" in in_progress_body
    assert "_clearComposerDraft(_targetSid);" in in_progress_body

    busy_body = _block(MESSAGES_JS, "if(S.busy||compressionRunning){", "  if(S.session&&(S.session.read_only||S.session.is_read_only))")
    assert "_clearComposerAfterQueuedSelectionSend(S.session&&S.session.session_id);" in busy_body
    assert busy_body.count("_clearComposerAfterQueuedSelectionSend(S.session&&S.session.session_id);") >= 2
    assert "_clearComposerDraft(S.session.session_id)" in busy_body, "delivered steer must clear persisted draft"
