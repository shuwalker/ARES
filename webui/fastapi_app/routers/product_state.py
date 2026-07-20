"""Bounded profile-scoped state for first-party UI modules."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field

from ..errors import CoreApiError
from ..request_context import RequestIdentity, require_identity, require_mutation_identity


router = APIRouter(prefix="/api/product-state", tags=["product-state"])


class ProductStateWrite(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    state: dict[str, Any]
    expected_revision: int | None = Field(default=None, ge=0)


def _translate(operation):
    from api.product_state import ProductStateConflict, ProductStateError

    try:
        return operation()
    except ProductStateConflict as exc:
        raise CoreApiError(409, str(exc), code="product_state_conflict") from exc
    except ProductStateError as exc:
        raise CoreApiError(400, str(exc), code="invalid_product_state") from exc


@router.get("/{module}")
def get_product_state(
    module: str,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    from api.product_state import read_product_state

    return _translate(lambda: read_product_state(identity.profile, module))


@router.put("/{module}")
def put_product_state(
    module: str,
    payload: ProductStateWrite,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.product_state import write_product_state

    return _translate(
        lambda: write_product_state(
            identity.profile,
            module,
            payload.state,
            expected_revision=payload.expected_revision,
        )
    )

