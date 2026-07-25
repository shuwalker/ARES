"""Error boundary shared by the modular FastAPI routers."""

from __future__ import annotations

from typing import Any


class CoreApiError(Exception):
    def __init__(
        self,
        status_code: int,
        message: str,
        *,
        code: str | None = None,
        context: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.message = message
        self.code = code
        self.context = context or {}

    def payload(self) -> dict[str, Any]:
        payload: dict[str, Any] = {"error": self.message}
        if self.code:
            payload["code"] = self.code
        payload.update(self.context)
        return payload
