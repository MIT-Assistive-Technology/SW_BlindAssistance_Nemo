"""Entrance resolution service. Run: uvicorn app.main:app --reload (from server/).

MVP: the app uses precomputed bundles for the pilot sites (same JSON shape as
contract/resolve.example.json). This live service is the stretch goal. When it runs:
`/v1/resolve` does cache lookups only (<= 3 s budget, never calls Overpass/Nominatim inline)
and returns 200 with status "partial" when the result is weak.
"""

import json
import uuid
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import resolver
from .models import ResolveRequest, ResolveResult

CONTRACT_EXAMPLE = Path(__file__).resolve().parents[2] / "contract" / "resolve.example.json"

app = FastAPI(title="Car to Curb entrance service", version="0.1.0")


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        self.status, self.code, self.message = status, code, message


def _error(status: int, code: str, message: str) -> JSONResponse:
    body = {"error": {"code": code, "message": message, "request_id": uuid.uuid4().hex}}
    return JSONResponse(status_code=status, content=body)


@app.exception_handler(ApiError)
async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
    return _error(exc.status, exc.code, exc.message)


@app.exception_handler(RequestValidationError)
async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
    return _error(422, "VALIDATION", "The request body doesn't match the contract.")


@app.exception_handler(StarletteHTTPException)
async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    return _error(exc.status_code, "NOT_FOUND" if exc.status_code == 404 else "VALIDATION",
                  str(exc.detail))


def _example() -> ResolveResult:
    return ResolveResult.model_validate(json.loads(CONTRACT_EXAMPLE.read_text(encoding="utf-8")))


@app.get("/v1/health")
def health() -> dict:
    return {"status": "ok", "data_version": _example().data_version.model_dump()}


@app.post("/v1/resolve", response_model=ResolveResult)
def resolve(request: ResolveRequest) -> ResolveResult:
    if not request.address and (request.lat is None or request.lon is None):
        raise ApiError(422, "VALIDATION", "Send an address, or lat and lon.")
    try:
        return resolver.resolve(request)
    except NotImplementedError:
        # TODO (BE-6): remove this fallback once the ladder works. Until then the app team
        # gets the contract example, so both sides can build in parallel.
        return _example()
