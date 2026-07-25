"""Transport-neutral local usage analytics for the ARES dashboard."""

from __future__ import annotations

from collections import Counter
from contextlib import closing
import json
import sqlite3
import time
from typing import Any


def _usage_int(value: Any) -> int:
    try:
        return max(int(float(value or 0)), 0)
    except (TypeError, ValueError):
        return 0


def _cost_float(value: Any) -> float:
    try:
        if isinstance(value, str):
            value = value.strip().replace("$", "").replace(",", "")
        return max(float(value or 0), 0.0)
    except (TypeError, ValueError):
        return 0.0


def _duration_seconds(row: dict[str, Any], start_key: str, end_key: str) -> float | None:
    """Session wall-clock span from existing timestamps, or None if unknown.

    None (not 0) is returned for a still-open session (missing end) so it is
    excluded from duration averages rather than dragging them toward zero.
    """
    try:
        start = float(row.get(start_key) or 0)
        end = float(row.get(end_key) or 0)
    except (TypeError, ValueError):
        return None
    if start <= 0 or end <= 0 or end < start:
        return None
    return end - start


def _accumulate_bucket(
    stats: dict[str, dict[str, Any]],
    key: str,
    *,
    input_tokens: int,
    output_tokens: int,
    cache_tokens: int,
    cost: float,
    duration_seconds: float | None,
) -> None:
    bucket = stats.setdefault(
        key,
        {
            "sessions": 0,
            "input_tokens": 0,
            "output_tokens": 0,
            "cache_read_tokens": 0,
            "cost": 0.0,
            "duration_seconds": 0.0,
            "duration_sessions": 0,
        },
    )
    bucket["sessions"] += 1
    bucket["input_tokens"] += input_tokens
    bucket["output_tokens"] += output_tokens
    bucket["cache_read_tokens"] += cache_tokens
    bucket["cost"] += cost
    if duration_seconds is not None:
        bucket["duration_seconds"] += duration_seconds
        bucket["duration_sessions"] += 1


def build_insights(days: int = 30) -> dict[str, Any]:
    """Aggregate WebUI and CLI usage without depending on an HTTP handler."""

    from api.config import SESSION_DIR
    from api.models import _active_state_db_path
    from api.usage import prompt_cache_hit_percent

    days = min(max(int(days), 1), 365)
    now = time.time()
    today = time.localtime(now)
    midnight = time.mktime(
        (today.tm_year, today.tm_mon, today.tm_mday, 0, 0, 0, today.tm_wday, today.tm_yday, today.tm_isdst)
    )
    first_day_ts = midnight - ((days - 1) * 86400)

    rows: list[dict[str, Any]] = []
    index_path = SESSION_DIR / "_index.json"
    try:
        index = json.loads(index_path.read_text(encoding="utf-8")) if index_path.exists() else []
    except (OSError, ValueError, TypeError):
        index = []
    if isinstance(index, list):
        rows.extend(
            row
            for row in index
            if isinstance(row, dict)
            and max(row.get("created_at", 0) or 0, row.get("updated_at", 0) or 0) >= first_day_ts
        )

    model_stats: dict[str, dict[str, Any]] = {}
    provider_stats: dict[str, dict[str, Any]] = {}
    daily: dict[str, dict[str, Any]] = {}
    dow: Counter[int] = Counter()
    hour: Counter[int] = Counter()
    totals = {
        "sessions": 0,
        "messages": 0,
        "input": 0,
        "output": 0,
        "cache": 0,
        "cost": 0.0,
        "duration_seconds": 0.0,
        "duration_sessions": 0,
    }

    def add(
        row: dict[str, Any],
        *,
        cost_key: str = "estimated_cost",
        timestamp: Any = None,
        provider: str | None = None,
        duration_seconds: float | None = None,
    ) -> None:
        input_tokens = _usage_int(row.get("input_tokens"))
        output_tokens = _usage_int(row.get("output_tokens"))
        cache_tokens = _usage_int(row.get("cache_read_tokens"))
        cost = _cost_float(row.get(cost_key))
        totals["sessions"] += 1
        totals["messages"] += _usage_int(row.get("message_count"))
        totals["input"] += input_tokens
        totals["output"] += output_tokens
        totals["cache"] += cache_tokens
        totals["cost"] += cost
        if duration_seconds is not None:
            totals["duration_seconds"] += duration_seconds
            totals["duration_sessions"] += 1
        model = str(row.get("model") or "unknown")
        provider_key = str(provider or "").strip().lower() or "unknown"
        _accumulate_bucket(
            model_stats, model,
            input_tokens=input_tokens, output_tokens=output_tokens,
            cache_tokens=cache_tokens, cost=cost, duration_seconds=duration_seconds,
        )
        _accumulate_bucket(
            provider_stats, provider_key,
            input_tokens=input_tokens, output_tokens=output_tokens,
            cache_tokens=cache_tokens, cost=cost, duration_seconds=duration_seconds,
        )
        raw_ts = timestamp if timestamp is not None else row.get("updated_at", row.get("created_at", 0))
        try:
            local = time.localtime(float(raw_ts or 0))
        except (TypeError, ValueError, OSError):
            return
        if not raw_ts:
            return
        key = time.strftime("%Y-%m-%d", local)
        day = daily.setdefault(
            key,
            {
                "input_tokens": 0, "output_tokens": 0, "cache_read_tokens": 0,
                "sessions": 0, "cost": 0.0, "duration_seconds": 0.0,
            },
        )
        day["input_tokens"] += input_tokens
        day["output_tokens"] += output_tokens
        day["cache_read_tokens"] += cache_tokens
        day["sessions"] += 1
        day["cost"] += cost
        if duration_seconds is not None:
            day["duration_seconds"] += duration_seconds
        dow[local.tm_wday] += 1
        hour[local.tm_hour] += 1

    for row in rows:
        add(
            row,
            provider=row.get("model_provider"),
            duration_seconds=_duration_seconds(row, "created_at", "updated_at"),
        )

    try:
        db_path = _active_state_db_path()
        if db_path and db_path.exists():
            with closing(sqlite3.connect(str(db_path))) as connection:
                connection.row_factory = sqlite3.Row
                columns = {item[1] for item in connection.execute("PRAGMA table_info(sessions)")}
                cache_expr = "COALESCE(cache_read_tokens, 0)" if "cache_read_tokens" in columns else "0"
                source_filter = "AND COALESCE(source, '') != 'webui'" if "source" in columns else ""
                # The `sessions` table is owned by an external runtime (CLI/Telegram
                # agent), not this codebase, so its schema is probed defensively
                # rather than assumed — an unrecognized/missing provider column
                # degrades every row to "unknown" instead of raising.
                if "model_provider" in columns:
                    provider_expr = "model_provider"
                elif "provider" in columns:
                    provider_expr = "provider"
                else:
                    provider_expr = "NULL"
                query = f"""
                    SELECT model, message_count, input_tokens, output_tokens,
                           estimated_cost_usd, {cache_expr} AS cache_read_tokens,
                           started_at, ended_at, {provider_expr} AS row_provider
                    FROM sessions
                    WHERE (started_at >= ? OR ended_at >= ?) {source_filter}
                """
                for db_row in connection.execute(query, (first_day_ts, first_day_ts)):
                    item = dict(db_row)
                    add(
                        item,
                        cost_key="estimated_cost_usd",
                        timestamp=item.get("started_at") or item.get("ended_at"),
                        provider=item.get("row_provider"),
                        duration_seconds=_duration_seconds(item, "started_at", "ended_at"),
                    )
    except (OSError, sqlite3.Error):
        pass

    total_tokens = totals["input"] + totals["output"]

    def finalize_breakdown(stats: dict[str, dict[str, Any]], key_field: str) -> list[dict[str, Any]]:
        breakdown = []
        for key, stat in stats.items():
            row_tokens = stat["input_tokens"] + stat["output_tokens"]
            row_cost = round(stat["cost"], 6)
            duration_sessions = stat["duration_sessions"]
            breakdown.append(
                {
                    key_field: key,
                    "sessions": stat["sessions"],
                    "input_tokens": stat["input_tokens"],
                    "output_tokens": stat["output_tokens"],
                    "cache_read_tokens": stat["cache_read_tokens"],
                    "cost": row_cost,
                    "cache_hit_percent": prompt_cache_hit_percent(
                        stat["cache_read_tokens"], stat["input_tokens"] + stat["cache_read_tokens"]
                    ),
                    "total_tokens": row_tokens,
                    "session_share": round((stat["sessions"] / totals["sessions"]) * 100) if totals["sessions"] else 0,
                    "token_share": round((row_tokens / total_tokens) * 100) if total_tokens else 0,
                    "cost_share": round((row_cost / totals["cost"]) * 100) if totals["cost"] else 0,
                    "duration_seconds": round(stat["duration_seconds"]) if duration_sessions else 0,
                    "average_duration_seconds": (
                        round(stat["duration_seconds"] / duration_sessions) if duration_sessions else 0
                    ),
                }
            )
        breakdown.sort(key=lambda item: (-item["cost"], -item["sessions"], str(item[key_field])))
        return breakdown

    models = finalize_breakdown(model_stats, "model")
    providers = finalize_breakdown(provider_stats, "provider")

    empty_day = {
        "input_tokens": 0, "output_tokens": 0, "cache_read_tokens": 0,
        "sessions": 0, "cost": 0.0, "duration_seconds": 0.0,
    }
    daily_series = []
    for offset in range(days):
        key = time.strftime("%Y-%m-%d", time.localtime(first_day_ts + offset * 86400))
        bucket = daily.get(key, empty_day)
        daily_series.append(
            {
                "date": key,
                "input_tokens": bucket["input_tokens"],
                "output_tokens": bucket["output_tokens"],
                "cache_read_tokens": bucket["cache_read_tokens"],
                "sessions": bucket["sessions"],
                "cost": round(bucket["cost"], 6),
                "duration_seconds": round(bucket["duration_seconds"]),
            }
        )

    return {
        "period_days": days,
        "total_sessions": totals["sessions"],
        "total_messages": totals["messages"],
        "total_input_tokens": totals["input"],
        "total_output_tokens": totals["output"],
        "total_cache_read_tokens": totals["cache"],
        "total_cache_hit_percent": prompt_cache_hit_percent(totals["cache"], totals["input"] + totals["cache"]),
        "total_tokens": total_tokens,
        "total_cost": round(totals["cost"], 6),
        "total_duration_seconds": round(totals["duration_seconds"]),
        "average_session_duration_seconds": (
            round(totals["duration_seconds"] / totals["duration_sessions"]) if totals["duration_sessions"] else 0
        ),
        "models": models,
        "providers": providers,
        "daily_tokens": daily_series,
        "activity_by_day": [
            {"day": label, "sessions": dow.get(index, 0)}
            for index, label in enumerate(("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"))
        ],
        "activity_by_hour": [{"hour": value, "sessions": hour.get(value, 0)} for value in range(24)],
    }


__all__ = ["build_insights"]
