"""
ARES WebUI — Monarch Money API routes.

Thin wrapper around api/monarch.py MonarchClient.
Exposes read-only + action endpoints for the Finance panel.
"""

from __future__ import annotations

import json
import logging
from urllib.parse import parse_qs

from api.helpers import bad, j
from api.monarch import get_client, reset_client

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------


def handle_monarch_status_get(handler, parsed):
    """GET /api/monarch/status — connection status."""
    client = get_client()
    return j(handler, client.get_status())


def handle_monarch_connect_post(handler, parsed, body):
    """POST /api/monarch/connect — connect to Monarch Money.

    Body: { "email": "...", "password": "...", "mfa_secret": "..." }
    All fields optional — tries saved session first.
    """
    email = (body or {}).get("email")
    password = (body or {}).get("password")
    mfa_secret = (body or {}).get("mfa_secret")
    client = get_client()
    result = client.connect(email=email, password=password, mfa_secret=mfa_secret)
    return j(handler, result)


def handle_monarch_disconnect_post(handler, parsed, body):
    """POST /api/monarch/disconnect — disconnect and clear session."""
    client = get_client()
    result = client.disconnect()
    return j(handler, result)


def handle_monarch_reconnect_post(handler, parsed, body):
    """POST /api/monarch/reconnect — attempt reconnect with saved session."""
    client = get_client()
    result = client.reconnect()
    return j(handler, result)


# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------


def handle_monarch_accounts_get(handler, parsed):
    """GET /api/monarch/accounts — list all accounts."""
    client = get_client()
    try:
        accounts = client.get_accounts()
        return j(handler, {"success": True, "accounts": accounts})
    except Exception as e:
        logger.error(f"Monarch accounts error: {e}")
        return j(handler, {"success": False, "error": str(e)})


def handle_monarch_transactions_get(handler, parsed):
    """GET /api/monarch/transactions — list transactions.

    Query params: limit (default 100), offset (default 0)
    """
    qs = parse_qs(parsed.query or "")
    limit = int(qs.get("limit", [100])[0])
    offset = int(qs.get("offset", [0])[0])
    client = get_client()
    try:
        txns = client.get_transactions(limit=limit, offset=offset)
        return j(handler, {"success": True, "transactions": txns})
    except Exception as e:
        logger.error(f"Monarch transactions error: {e}")
        return j(handler, {"success": False, "error": str(e)})


def handle_monarch_budgets_get(handler, parsed):
    """GET /api/monarch/budgets — list budgets.

    Query params: month (optional, YYYY-MM format)
    """
    qs = parse_qs(parsed.query or "")
    month = qs.get("month", [None])[0]
    client = get_client()
    try:
        budgets = client.get_budgets(month=month)
        return j(handler, {"success": True, "budgets": budgets})
    except Exception as e:
        logger.error(f"Monarch budgets error: {e}")
        return j(handler, {"success": False, "error": str(e)})


def handle_monarch_budget_set_post(handler, parsed, body):
    """POST /api/monarch/budget/set — adjust a budget amount.

    Body: { "amount": 500.0, "category_id": "...", ... }
    """
    if not body:
        return bad(handler, "Missing request body")
    client = get_client()
    try:
        result = client.set_budget_amount(
            amount=body.get("amount", 0),
            category_id=body.get("category_id"),
            category_group_id=body.get("category_group_id"),
            timeframe=body.get("timeframe", "month"),
            start_date=body.get("start_date"),
            apply_to_future=body.get("apply_to_future", False),
        )
        return j(handler, result)
    except Exception as e:
        logger.error(f"Monarch budget set error: {e}")
        return j(handler, {"success": False, "error": str(e)})


def handle_monarch_cashflow_get(handler, parsed):
    """GET /api/monarch/cashflow — cashflow data."""
    client = get_client()
    try:
        cashflow = client.get_cashflow()
        summary = client.get_cashflow_summary()
        return j(handler, {"success": True, "cashflow": cashflow, "summary": summary})
    except Exception as e:
        logger.error(f"Monarch cashflow error: {e}")
        return j(handler, {"success": False, "error": str(e)})


def handle_monarch_recurring_get(handler, parsed):
    """GET /api/monarch/recurring — recurring transactions."""
    client = get_client()
    try:
        recurring = client.get_recurring_transactions()
        return j(handler, {"success": True, "recurring": recurring})
    except Exception as e:
        logger.error(f"Monarch recurring error: {e}")
        return j(handler, {"success": False, "error": str(e)})


def handle_monarch_holdings_get(handler, parsed):
    """GET /api/monarch/holdings — investment holdings."""
    client = get_client()
    try:
        holdings = client.get_account_holdings()
        return j(handler, {"success": True, "holdings": holdings})
    except Exception as e:
        logger.error(f"Monarch holdings error: {e}")
        return j(handler, {"success": False, "error": str(e)})


def handle_monarch_refresh_post(handler, parsed, body):
    """POST /api/monarch/refresh — request account refresh."""
    client = get_client()
    try:
        result = client.request_refresh()
        return j(handler, {"success": True, "result": result})
    except Exception as e:
        logger.error(f"Monarch refresh error: {e}")
        return j(handler, {"success": False, "error": str(e)})


def handle_monarch_transaction_create_post(handler, parsed, body):
    """POST /api/monarch/transaction/create — create a transaction.

    Body: { "date": "2024-01-15", "account_id": "...", "amount": -29.99,
            "merchant_name": "Netflix", "category_id": "...", "notes": "" }
    """
    if not body:
        return bad(handler, "Missing request body")
    client = get_client()
    try:
        result = client.create_transaction(
            date=body.get("date"),
            account_id=body.get("account_id"),
            amount=body.get("amount", 0),
            merchant_name=body.get("merchant_name"),
            category_id=body.get("category_id"),
            notes=body.get("notes", ""),
            update_balance=body.get("update_balance", False),
        )
        return j(handler, result)
    except Exception as e:
        logger.error(f"Monarch transaction create error: {e}")
        return j(handler, {"success": False, "error": str(e)})


def handle_monarch_transaction_update_post(handler, parsed, body):
    """POST /api/monarch/transaction/update — update a transaction.

    Body: { "transaction_id": "...", "category_id": "...", ... }
    """
    if not body:
        return bad(handler, "Missing request body")
    txn_id = body.pop("transaction_id", None)
    if not txn_id:
        return bad(handler, "Missing transaction_id")
    client = get_client()
    try:
        result = client.update_transaction(txn_id, **body)
        return j(handler, result)
    except Exception as e:
        logger.error(f"Monarch transaction update error: {e}")
        return j(handler, {"success": False, "error": str(e)})
