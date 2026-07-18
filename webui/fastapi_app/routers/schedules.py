"""Local Profile schedule endpoints."""

from __future__ import annotations

import asyncio
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, ConfigDict, Field

from api.schedules_store import ScheduleStoreError

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity


router = APIRouter(prefix="/api/crons", tags=["schedules"])


class ScheduleCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    prompt: str = Field(min_length=1, max_length=100_000)
    schedule: str = Field(min_length=1, max_length=1024)
    name: str | None = Field(default=None, max_length=256)
    deliver: str | None = Field(default=None, max_length=64)
    skills: list[str] = Field(default_factory=list, max_length=100)
    model: str | None = Field(default=None, max_length=256)
    provider: str | None = Field(default=None, max_length=128)
    profile: str | None = Field(default=None, max_length=128)
    toast_notifications: bool = True


class ScheduleMutation(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    job_id: str = Field(min_length=1, max_length=128)


class SchedulePause(ScheduleMutation):
    reason: str | None = Field(default=None, max_length=1024)


class ScheduleUpdate(ScheduleMutation):
    model_config = ConfigDict(extra="allow", strict=True)
    prompt: str | None = None
    schedule: str | None = None
    name: str | None = None
    deliver: str | None = None
    skills: list[str] | None = None
    model: str | None = None
    provider: str | None = None
    profile: str | None = None
    toast_notifications: bool | None = None


def _profile_call(profile: str | None, operation, args, kwargs):
    with profile_scope(profile):
        return operation(*args, **kwargs)


def _error(exc: ScheduleStoreError) -> CoreApiError:
    return CoreApiError(exc.status_code, str(exc))


async def _call(identity: RequestIdentity, operation, *args, **kwargs):
    try:
        return await asyncio.to_thread(
            _profile_call,
            identity.profile,
            operation,
            args,
            kwargs,
        )
    except ScheduleStoreError as exc:
        raise _error(exc) from exc
    except ModuleNotFoundError as exc:
        if exc.name in {"cron", "cron.jobs", "cron.scheduler"}:
            raise CoreApiError(500, "ARES Agent cron module is unavailable") from exc
        raise


@router.get("")
async def schedules(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    all_profiles: bool = Query(default=False),
):
    from api.schedules_store import list_schedules

    return await _call(identity, list_schedules, all_profiles=all_profiles)


@router.get("/status")
async def status(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    job_id: str | None = Query(default=None, max_length=128),
):
    from api.schedules_store import schedule_status

    return await _call(identity, schedule_status, job_id)


@router.get("/delivery-options")
async def deliveries(identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.schedules_store import delivery_options

    return await _call(identity, delivery_options)


@router.get("/output")
async def output(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    job_id: str = Query(min_length=1, max_length=64),
    limit: str = Query(default="5", max_length=32),
):
    from api.schedules_store import schedule_outputs

    return await _call(identity, schedule_outputs, job_id, limit)


@router.get("/history")
async def history(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    job_id: str = Query(min_length=1, max_length=64),
    offset: str = Query(default="0", max_length=32),
    limit: str = Query(default="50", max_length=32),
):
    from api.schedules_store import schedule_history

    return await _call(identity, schedule_history, job_id, offset, limit)


@router.get("/run")
async def run_detail(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    job_id: str = Query(min_length=1, max_length=64),
    filename: str = Query(min_length=1, max_length=512),
):
    from api.schedules_store import schedule_run_detail

    return await _call(identity, schedule_run_detail, job_id, filename)


@router.get("/recent")
async def recent(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    since: str = Query(default="0", max_length=64),
):
    from api.schedules_store import recent_schedules

    return await _call(identity, recent_schedules, since)


@router.post("/create")
async def create(
    payload: ScheduleCreate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.schedules_store import create_schedule

    return await _call(identity, create_schedule, payload.model_dump())


@router.post("/update")
async def update(
    payload: ScheduleUpdate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.schedules_store import update_schedule

    values: dict[str, Any] = payload.model_dump(exclude_unset=True)
    job_id = values.pop("job_id")
    return await _call(identity, update_schedule, job_id, values)


@router.post("/delete")
async def delete(
    payload: ScheduleMutation,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.schedules_store import delete_schedule

    return await _call(identity, delete_schedule, payload.job_id)


@router.post("/run")
async def run(
    payload: ScheduleMutation,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.schedules_store import run_schedule

    return await _call(identity, run_schedule, payload.job_id)


@router.post("/pause")
async def pause(
    payload: SchedulePause,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.schedules_store import pause_schedule

    return await _call(identity, pause_schedule, payload.job_id, payload.reason)


@router.post("/resume")
async def resume(
    payload: ScheduleMutation,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.schedules_store import resume_schedule

    return await _call(identity, resume_schedule, payload.job_id)
