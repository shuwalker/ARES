"""
Monarch Money integration for ARES WebUI.

Provides:
- Session-based login with credential caching
- Transaction, account, budget, cashflow retrieval
- Budget adjustment
- Connection health monitoring and auto-reconnect
- Local SQLite cache for offline access and fast queries
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sqlite3
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────

_MONARCH_HOME = Path(os.environ.get("ARES_HOME", str(Path.home() / ".ares")))
_MONARCH_DB = _MONARCH_HOME / "monarch_cache.db"
_SESSION_FILE = _MONARCH_HOME / ".mm_session.pickle"

# ── DB Setup ──────────────────────────────────────────────────────

def _get_cache_db() -> sqlite3.Connection:
    _MONARCH_HOME.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(_MONARCH_DB))
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS accounts (
            id TEXT PRIMARY KEY,
            name TEXT,
            display_name TEXT,
            subtype TEXT,
            current_balance REAL,
            available_balance REAL,
            institution_name TEXT,
            sync_status TEXT,
            updated_at TEXT
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            account_id TEXT,
            date TEXT,
            amount REAL,
            merchant TEXT,
            description TEXT,
            category_name TEXT,
            category_id TEXT,
            pending INTEGER DEFAULT 0,
            recurring INTEGER DEFAULT 0,
            notes TEXT,
            tags TEXT,
            updated_at TEXT
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS budgets (
            id TEXT PRIMARY KEY,
            category_id TEXT,
            category_name TEXT,
            amount REAL,
            spent REAL,
            remaining REAL,
            month TEXT,
            updated_at TEXT
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS cashflow (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            month TEXT,
            income REAL DEFAULT 0,
            expenses REAL DEFAULT 0,
            net REAL DEFAULT 0,
            updated_at TEXT
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS connection_state (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TEXT
        )
    """)
    conn.commit()
    return conn


def _set_connection_state(key: str, value: str) -> None:
    conn = _get_cache_db()
    conn.execute(
        "INSERT OR REPLACE INTO connection_state (key, value, updated_at) VALUES (?, ?, ?)",
        (key, value, datetime.now(timezone.utc).isoformat()),
    )
    conn.commit()
    conn.close()


def _get_connection_state(key: str) -> Optional[str]:
    conn = _get_cache_db()
    row = conn.execute(
        "SELECT value FROM connection_state WHERE key = ?", (key,)
    ).fetchone()
    conn.close()
    return row["value"] if row else None


# ── Monarch Client Wrapper ────────────────────────────────────────

class MonarchClient:
    """Wraps the monarchmoney library with connection management."""

    def __init__(self):
        self._mm = None
        self._connected = False
        self._last_error = None
        self._last_connect_attempt = 0
        self._loop = None

    @property
    def is_connected(self) -> bool:
        return self._connected and self._mm is not None

    def get_status(self) -> dict:
        """Return current connection status."""
        return {
            "connected": self.is_connected,
            "last_error": self._last_error,
            "last_connect_attempt": self._last_connect_attempt,
            "session_file_exists": _SESSION_FILE.exists(),
        }

    def _run_async(self, coro):
        """Run an async coroutine, creating an event loop if needed."""
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            loop = None
        if loop and loop.is_running():
            # We're inside an async context — use run_coroutine_threadsafe
            # or create a new loop in a thread. For simplicity, create a new loop.
            return asyncio.run_coroutine_threadsafe(coro, loop).result()
        else:
            return asyncio.run(coro)

    def connect(self, email: str | None = None, password: str | None = None,
                mfa_secret: str | None = None) -> dict:
        """
        Connect to Monarch Money. Tries saved session first, falls back to
        email/password login. Returns status dict.
        """
        self._last_connect_attempt = time.time()
        try:
            from monarchmoney import MonarchMoney

            self._mm = MonarchMoney(session_file=str(_SESSION_FILE))

            # Try saved session first
            if _SESSION_FILE.exists():
                try:
                    self._run_async(self._mm.login(
                        use_saved_session=True, save_session=True
                    ))
                    self._connected = True
                    self._last_error = None
                    _set_connection_state("connected", "true")
                    _set_connection_state("last_success", datetime.now(timezone.utc).isoformat())
                    logger.info("Monarch: connected via saved session")
                    return {"success": True, "method": "saved_session"}
                except Exception as e:
                    logger.warning(f"Monarch: saved session failed: {e}")

            # Fall back to email/password
            if email and password:
                try:
                    self._run_async(self._mm.login(
                        email=email,
                        password=password,
                        use_saved_session=False,
                        save_session=True,
                        mfa_secret_key=mfa_secret,
                    ))
                    self._connected = True
                    self._last_error = None
                    _set_connection_state("connected", "true")
                    _set_connection_state("last_success", datetime.now(timezone.utc).isoformat())
                    logger.info("Monarch: connected via email/password")
                    return {"success": True, "method": "email_password"}
                except Exception as e:
                    err_str = str(e)
                    if "MFA" in err_str or "multi_factor" in err_str.lower():
                        return {"success": False, "needs_mfa": True, "error": err_str}
                    raise

            return {"success": False, "error": "No credentials available and no saved session"}
        except Exception as e:
            self._connected = False
            self._last_error = str(e)
            _set_connection_state("connected", "false")
            _set_connection_state("last_error", str(e))
            logger.error(f"Monarch: connection failed: {e}")
            return {"success": False, "error": str(e)}

    def reconnect(self) -> dict:
        """Attempt to reconnect using saved session."""
        if not _SESSION_FILE.exists():
            return {"success": False, "error": "No saved session to reconnect with"}
        return self.connect()

    def disconnect(self) -> dict:
        """Disconnect and clear session."""
        self._connected = False
        self._mm = None
        _set_connection_state("connected", "false")
        return {"success": True}

    def _ensure_connected(self) -> bool:
        """Check connection and attempt reconnect if needed."""
        if self.is_connected:
            return True
        result = self.reconnect()
        return result.get("success", False)

    # ── Data Methods ──────────────────────────────────────────────

    def get_accounts(self) -> list[dict]:
        if not self._ensure_connected():
            return self._get_cached_accounts()
        try:
            result = self._run_async(self._mm.get_accounts())
            accounts = result.get("accounts", result) if isinstance(result, dict) else result
            if isinstance(accounts, dict):
                accounts = accounts.get("accounts", [accounts])
            self._cache_accounts(accounts)
            return accounts
        except Exception as e:
            logger.warning(f"Monarch: get_accounts failed, using cache: {e}")
            return self._get_cached_accounts()

    def get_transactions(self, limit: int = 100, offset: int = 0) -> list[dict]:
        if not self._ensure_connected():
            return self._get_cached_transactions(limit, offset)
        try:
            result = self._run_async(self._mm.get_transactions(limit=limit, offset=offset))
            txns = result if isinstance(result, list) else result.get("transactions", [])
            self._cache_transactions(txns)
            return txns
        except Exception as e:
            logger.warning(f"Monarch: get_transactions failed, using cache: {e}")
            return self._get_cached_transactions(limit, offset)

    def get_budgets(self, month: str | None = None) -> list[dict]:
        if not self._ensure_connected():
            return self._get_cached_budgets(month)
        try:
            result = self._run_async(self._mm.get_budgets())
            budgets = result if isinstance(result, list) else result.get("budgets", [])
            self._cache_budgets(budgets, month)
            return budgets
        except Exception as e:
            logger.warning(f"Monarch: get_budgets failed, using cache: {e}")
            return self._get_cached_budgets(month)

    def get_cashflow(self, months: int = 6) -> list[dict]:
        if not self._ensure_connected():
            return self._get_cached_cashflow()
        try:
            result = self._run_async(self._mm.get_cashflow())
            cf = result if isinstance(result, list) else result.get("cashflow", [])
            self._cache_cashflow(cf)
            return cf
        except Exception as e:
            logger.warning(f"Monarch: get_cashflow failed, using cache: {e}")
            return self._get_cached_cashflow()

    def get_cashflow_summary(self) -> dict:
        if not self._ensure_connected():
            return {}
        try:
            result = self._run_async(self._mm.get_cashflow_summary())
            return result if isinstance(result, dict) else {}
        except Exception as e:
            logger.warning(f"Monarch: get_cashflow_summary failed: {e}")
            return {}

    def get_recurring_transactions(self) -> list[dict]:
        if not self._ensure_connected():
            return []
        try:
            result = self._run_async(self._mm.get_recurring_transactions())
            return result if isinstance(result, list) else result.get("recurring_transactions", [])
        except Exception as e:
            logger.warning(f"Monarch: get_recurring failed: {e}")
            return []

    def get_account_holdings(self) -> list[dict]:
        if not self._ensure_connected():
            return []
        try:
            result = self._run_async(self._mm.get_account_holdings())
            return result if isinstance(result, list) else result.get("holdings", [])
        except Exception as e:
            logger.warning(f"Monarch: get_holdings failed: {e}")
            return []

    def set_budget_amount(self, amount: float, category_id: str | None = None,
                           category_group_id: str | None = None,
                           timeframe: str = "month",
                           start_date: str | None = None,
                           apply_to_future: bool = False) -> dict:
        """Adjust a budget amount."""
        if not self._ensure_connected():
            return {"success": False, "error": "Not connected"}
        try:
            result = self._run_async(self._mm.set_budget_amount(
                amount=amount,
                category_id=category_id,
                category_group_id=category_group_id,
                timeframe=timeframe,
                start_date=start_date,
                apply_to_future=apply_to_future,
            ))
            return {"success": True, "result": result}
        except Exception as e:
            logger.error(f"Monarch: set_budget_amount failed: {e}")
            return {"success": False, "error": str(e)}

    def create_transaction(self, date: str, account_id: str, amount: float,
                           merchant_name: str, category_id: str,
                           notes: str = "", update_balance: bool = False) -> dict:
        """Create a new transaction."""
        if not self._ensure_connected():
            return {"success": False, "error": "Not connected"}
        try:
            result = self._run_async(self._mm.create_transaction(
                date=date,
                account_id=account_id,
                amount=amount,
                merchant_name=merchant_name,
                category_id=category_id,
                notes=notes,
                update_balance=update_balance,
            ))
            return {"success": True, "result": result}
        except Exception as e:
            logger.error(f"Monarch: create_transaction failed: {e}")
            return {"success": False, "error": str(e)}

    def update_transaction(self, transaction_id: str, **kwargs) -> dict:
        """Update a transaction's fields."""
        if not self._ensure_connected():
            return {"success": False, "error": "Not connected"}
        try:
            result = self._run_async(self._mm.update_transaction(transaction_id, **kwargs))
            return {"success": True, "result": result}
        except Exception as e:
            logger.error(f"Monarch: update_transaction failed: {e}")
            return {"success": False, "error": str(e)}

    def request_refresh(self, account_ids: list[str] | None = None) -> dict:
        """Request account refresh from Monarch."""
        if not self._ensure_connected():
            return {"success": False, "error": "Not connected"}
        try:
            result = self._run_async(self._mm.request_accounts_refresh_and_wait(
                account_ids=account_ids
            ))
            return {"success": True, "result": result}
        except Exception as e:
            logger.error(f"Monarch: refresh failed: {e}")
            return {"success": False, "error": str(e)}

    # ── Cache Methods ─────────────────────────────────────────────

    def _cache_accounts(self, accounts: list[dict]) -> None:
        conn = _get_cache_db()
        now = datetime.now(timezone.utc).isoformat()
        for acct in accounts:
            conn.execute("""
                INSERT OR REPLACE INTO accounts
                (id, name, display_name, subtype, current_balance, available_balance,
                 institution_name, sync_status, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                acct.get("id"), acct.get("name"), acct.get("display_name"),
                acct.get("subtype"), acct.get("current_balance"),
                acct.get("available_balance"), acct.get("institution_name"),
                acct.get("sync_status"), now,
            ))
        conn.commit()
        conn.close()

    def _get_cached_accounts(self) -> list[dict]:
        conn = _get_cache_db()
        rows = conn.execute("SELECT * FROM accounts ORDER BY name").fetchall()
        conn.close()
        return [dict(r) for r in rows]

    def _cache_transactions(self, txns: list[dict]) -> None:
        conn = _get_cache_db()
        now = datetime.now(timezone.utc).isoformat()
        for t in txns:
            conn.execute("""
                INSERT OR REPLACE INTO transactions
                (id, account_id, date, amount, merchant, description,
                 category_name, category_id, pending, recurring, notes, tags, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                t.get("id"), t.get("account_id"), t.get("date"),
                t.get("amount"), t.get("merchant"), t.get("description"),
                t.get("category_name"), t.get("category_id"),
                1 if t.get("pending") else 0,
                1 if t.get("recurring") else 0,
                t.get("notes"), json.dumps(t.get("tags", [])), now,
            ))
        conn.commit()
        conn.close()

    def _get_cached_transactions(self, limit: int = 100, offset: int = 0) -> list[dict]:
        conn = _get_cache_db()
        rows = conn.execute(
            "SELECT * FROM transactions ORDER BY date DESC LIMIT ? OFFSET ?",
            (limit, offset),
        ).fetchall()
        conn.close()
        return [dict(r) for r in rows]

    def _cache_budgets(self, budgets: list[dict], month: str | None) -> None:
        conn = _get_cache_db()
        now = datetime.now(timezone.utc).isoformat()
        for b in budgets:
            conn.execute("""
                INSERT OR REPLACE INTO budgets
                (id, category_id, category_name, amount, spent, remaining, month, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                b.get("id"), b.get("category_id"), b.get("category_name"),
                b.get("amount"), b.get("spent"), b.get("remaining"),
                month or datetime.now().strftime("%Y-%m"), now,
            ))
        conn.commit()
        conn.close()

    def _get_cached_budgets(self, month: str | None = None) -> list[dict]:
        conn = _get_cache_db()
        if month:
            rows = conn.execute(
                "SELECT * FROM budgets WHERE month = ? ORDER BY category_name",
                (month,),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM budgets ORDER BY month DESC, category_name"
            ).fetchall()
        conn.close()
        return [dict(r) for r in rows]

    def _cache_cashflow(self, cashflow: list[dict]) -> None:
        conn = _get_cache_db()
        now = datetime.now(timezone.utc).isoformat()
        for cf in cashflow:
            conn.execute("""
                INSERT OR REPLACE INTO cashflow
                (month, income, expenses, net, updated_at)
                VALUES (?, ?, ?, ? , ?)
            """, (
                cf.get("month"), cf.get("income", 0),
                cf.get("expenses", 0), cf.get("net", 0), now,
            ))
        conn.commit()
        conn.close()

    def _get_cached_cashflow(self) -> list[dict]:
        conn = _get_cache_db()
        rows = conn.execute(
            "SELECT * FROM cashflow ORDER BY month DESC"
        ).fetchall()
        conn.close()
        return [dict(r) for r in rows]


# ── Singleton ─────────────────────────────────────────────────────

_client: MonarchClient | None = None


def get_client() -> MonarchClient:
    global _client
    if _client is None:
        _client = MonarchClient()
    return _client


def reset_client() -> None:
    global _client
    _client = None
