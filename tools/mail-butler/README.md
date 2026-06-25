# Ares Mail Butler 🧹

Server-side email cleaner for all 4 of Matthew's mail accounts.
Connects directly to IMAP — no Mail.app, no AppleScript, no GUI dependency.

## Files

| File | Purpose |
|------|---------|
| `ares-mail-cleaner.py` | Main IMAP cleaner (321 rules: junk/archive/keep) |
| `accounts.template.json` | Credentials template — copy to accounts.json, fill in app passwords |
| `install-rules.applescript` | Optional: install Mail.app rules for client-side filtering |
| `applescript-cleaner.py` | Fallback: AppleScript-based cleaner for when IMAP creds aren't available |
| `archive/` | Old AppleScript cleanup scripts (pre-IMAP approach) |

## Classification

| Category | Action | Count | Examples |
|----------|--------|-------|---------|
| **Junk** | Delete from server | 115 domains | Financial scams, phishing, dating spam, health spam |
| **Archive** | Mark as read | 112 domains | Newsletters, promos, marketing (Quicken, Guns.com, Spotify, etc.) |
| **Keep** | Never touch | 94 domains | PayPal, Amazon, Chase, FPCU, Apple, GitHub, work, family |

## Setup

1. Generate app passwords:
   - Gmail: https://myaccount.google.com/apppasswords
   - Yahoo: https://login.yahoo.com/account/security
   - Outlook: https://account.live.com/activity
   - iCloud: Apple Account → app-specific password

2. Copy `accounts.template.json` to `~/.ares/scripts/mail-rules/accounts.json` and fill in passwords

3. The Hermes cron runs this every 30 min automatically. Falls back to AppleScript cleaner if no passwords configured.

## Cron Integration

Cron job `8998ed2cbc16` (Ares Mail Cleaner) runs every 30 min:
- Tries IMAP cleaner first (server-side, no Mail.app dependency)
- Falls back to AppleScript cleaner if accounts.json has no passwords
- Reports trash/archive counts per account
- Goes silent if inbox is clean
