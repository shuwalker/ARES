"""ARES Mail Triage — AppleScript driver for Apple Mail.

Thin macOS-only glue. All logic lives in rules.py.
"""

from __future__ import annotations

import subprocess
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .models import EmailMessage


def _run(script: str) -> str:
    """Execute AppleScript and return stdout. Raises RuntimeError on failure."""
    # Write to file for multi-line scripts (avoids inline parsing issues)
    # Use a deterministic temp path to avoid shell escaping nightmares
    with open("/tmp/ares-mail-driver.scpt", "w") as f:
        f.write(script)
    result = subprocess.run(
        ["osascript", "/tmp/ares-mail-driver.scpt"],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def _escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


# ---------------------------------------------------------------------------
# Fetch unread
# ---------------------------------------------------------------------------

def fetch_unread() -> list[EmailMessage]:
    """Return all unread messages from every account's inbox."""
    from .models import EmailMessage

    script = r'''
tell application "Mail"
    set output to ""
    set allAccounts to every account
    repeat with acct in allAccounts
        set acctName to name of acct
        set theInbox to missing value
        set inboxBoxName to ""
        try
            set theInbox to mailbox "INBOX" of acct
            set inboxBoxName to "INBOX"
        end try
        if theInbox is missing value then
            try
                set theInbox to mailbox "Inbox" of acct
                set inboxBoxName to "Inbox"
            end try
        end if
        if theInbox is not missing value then
            set unreadMsgs to (messages of theInbox whose read status is false)
            repeat with i from 1 to count of unreadMsgs
                set theMsg to item i of unreadMsgs
                set msgId to message id of theMsg
                set msgSender to sender of theMsg
                set msgSubject to subject of theMsg
                set msgHeaders to all headers of theMsg
                if msgHeaders contains "List-Unsubscribe" then
                    set hasUnsub to "1"
                else
                    set hasUnsub to "0"
                end if
                set output to output & acctName & "|||" & inboxBoxName & "|||" & msgId & "|||" & msgSender & "|||" & msgSubject & "|||" & hasUnsub & linefeed
            end repeat
        end if
    end repeat
    return output
end tell
'''
    raw = _run(script)
    messages: list[EmailMessage] = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        parts = line.split("|||")
        if len(parts) >= 6:
            messages.append(
                EmailMessage(
                    account=parts[0].strip(),
                    inbox_name=parts[1].strip(),
                    id=parts[2].strip(),
                    sender=parts[3].strip(),
                    subject=parts[4].strip(),
                    has_unsubscribe=parts[5].strip() == "1",
                )
            )
    return messages


# ---------------------------------------------------------------------------
# Junk folder discovery
# ---------------------------------------------------------------------------

def discover_junk_mailboxes() -> dict[str, str]:
    """Read all mailboxes, pick the junk folder per account."""
    import re

    script = r'''
tell application "Mail"
    set output to ""
    set allAccounts to every account
    repeat with acct in allAccounts
        set acctName to name of acct
        set allBoxes to every mailbox of acct
        repeat with mbox in allBoxes
            set output to output & acctName & "|||" & (name of mbox) & linefeed
        end repeat
    end repeat
    return output
end tell
'''
    raw = _run(script)
    junk_re = re.compile(r"junk|spam|bulk", re.IGNORECASE)
    junk_map: dict[str, str] = {}
    for line in raw.splitlines():
        if not line.strip():
            continue
        parts = line.split("|||")
        if len(parts) == 2:
            account, box = parts[0].strip(), parts[1].strip()
            if junk_re.search(box):
                if account not in junk_map:
                    junk_map[account] = sorted(
                        [b for b in [box] if junk_re.search(b)], key=len
                    )[0]
                else:
                    # Prefer shortest match
                    if len(box) < len(junk_map[account]):
                        junk_map[account] = box
    return junk_map


# ---------------------------------------------------------------------------
# Move messages
# ---------------------------------------------------------------------------

def move_to_junk(msgs: list[EmailMessage], junk_map: dict[str, str]) -> list[EmailMessage]:
    """Move classified junk messages to their account's junk folder."""
    moved: list[EmailMessage] = []
    # Group by account
    by_account: dict[str, list[EmailMessage]] = {}
    for msg in msgs:
        by_account.setdefault(msg.account, []).append(msg)

    for account, acct_msgs in by_account.items():
        junk_box = junk_map.get(account)
        if not junk_box:
            continue
        safe_account = _escape(account)
        safe_junk = _escape(junk_box)
        for msg in acct_msgs:
            safe_id = _escape(msg.id)
            safe_inbox = _escape(msg.inbox_name)
            script = f'''
tell application "Mail"
    try
        set acct to account "{safe_account}"
        set theInbox to mailbox "{safe_inbox}" of acct
        set theJunk to missing value
        repeat with mbox in (every mailbox of acct)
            if name of mbox is "{safe_junk}" then
                set theJunk to mbox
                exit repeat
            end if
        end repeat
        if theJunk is not missing value then
            set matches to (every message of theInbox whose message id is "{safe_id}")
            if (count of matches) > 0 then
                move matches to theJunk
            end if
        end if
    end try
end tell
'''
            try:
                _run(script)
                moved.append(msg)
            except RuntimeError as e:
                # Log but don't crash
                print(f"  ⚠ Could not move '{msg.subject[:45]}': {e}")
    return moved


def move_to_inbox(msgs: list[EmailMessage]) -> list[EmailMessage]:
    """Rescue messages from junk back to inbox."""
    moved: list[EmailMessage] = []
    for msg in msgs:
        safe_id = _escape(msg.id)
        safe_account = _escape(msg.account)
        script = f'''
tell application "Mail"
    try
        set acct to account "{safe_account}"
        set theInbox to missing value
        repeat with mbox in (every mailbox of acct)
            set boxName to name of mbox
            if boxName is "INBOX" or boxName is "Inbox" then
                set theInbox to mbox
                exit repeat
            end if
        end repeat
        if theInbox is not missing value then
            repeat with mbox in (every mailbox of acct)
                set msgsFound to (every message of mbox whose message id is "{safe_id}")
                if (count of msgsFound) > 0 then
                    move msgsFound to theInbox
                    exit repeat
                end if
            end repeat
        end if
    end try
end tell
'''
        try:
            _run(script)
            moved.append(msg)
        except RuntimeError as e:
            print(f"  ⚠ Could not rescue '{msg.subject[:45]}': {e}")
    return moved


# ---------------------------------------------------------------------------
# Junk folder scan (for rescues)
# ---------------------------------------------------------------------------

def scan_junk_folders(junk_map: dict[str, str], limit: int = 100) -> list[EmailMessage]:
    from .models import EmailMessage

    messages: list[EmailMessage] = []
    count = 0
    for account, junk_box in junk_map.items():
        if count >= limit:
            break
        safe_account = _escape(account)
        safe_junk = _escape(junk_box)
        script = f'''
tell application "Mail"
    set output to ""
    set acct to account "{safe_account}"
    repeat with mbox in (every mailbox of acct)
        if name of mbox is "{safe_junk}" then
            set junkMsgs to messages of mbox
            set msgCount to count of junkMsgs
            -- Only scan up to 50 per account to stay within overall limit
            set scanCount to msgCount
            if scanCount > 50 then set scanCount to 50
            repeat with i from 1 to scanCount
                set theMsg to item i of junkMsgs
                set msgId to message id of theMsg
                set msgSender to sender of theMsg
                set msgSubject to subject of theMsg
                set output to output & "{safe_account}" & "|||" & "{safe_junk}" & "|||" & msgId & "|||" & msgSender & "|||" & msgSubject & linefeed
            end repeat
            exit repeat
        end if
    end repeat
    return output
end tell
'''
        try:
            raw = _run(script)
            for line in raw.splitlines():
                if not line.strip() or count >= limit:
                    break
                parts = line.split("|||")
                if len(parts) >= 5:
                    messages.append(
                        EmailMessage(
                            account=parts[0].strip(),
                            inbox_name=parts[1].strip(),  # actually the junk box name here
                            id=parts[2].strip(),
                            sender=parts[3].strip(),
                            subject=parts[4].strip(),
                        )
                    )
                    count += 1
        except RuntimeError as e:
            print(f"  ⚠ Could not read junk folder for {account}: {e}")
    return messages
