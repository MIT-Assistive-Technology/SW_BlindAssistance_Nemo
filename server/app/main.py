"""Entrance resolution service. Run: uvicorn app.main:app --reload (from server/).

MVP: the pilot is served from prebuilt bundles (server/bundles/*.json, or env BUNDLES_DIR),
each in the shape of contract/resolve.example.json. The app downloads every bundle at setup
(GET /v1/bundles, then GET /v1/bundles/{id} with ETags) so guidance works offline.
POST /v1/resolve is for lookups the phone hasn't cached: it maps an address or lat/lon to a pilot
bundle within the 3 s budget and never calls Overpass. Addresses that aren't pilot destinations
get 404 NOT_FOUND.

Privacy (plan section 16): request bodies and addresses are never logged.
"""

import json
import logging
import os
import uuid
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeout
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated

from fastapi import FastAPI, Header, Request
from fastapi import Path as PathParam
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import bundle_store, resolver
from .models import ResolveRequest, ResolveResult
from .resolver import GeocodedPoint

CONTRACT_EXAMPLE = Path(__file__).resolve().parents[2] / "contract" / "resolve.example.json"
# The whole request must finish in 3 s; leave headroom for matching and serialization.
GEOCODE_BUDGET_S = 2.5
NOT_IN_PILOT = "This destination isn't in the pilot yet."

log = logging.getLogger(__name__)
_geocode_pool = ThreadPoolExecutor(max_workers=4, thread_name_prefix="geocode")
_store: bundle_store.BundleStore | None = None


def reload_store() -> bundle_store.BundleStore:
    """(Re)load the bundles from BUNDLES_DIR. Called at startup; tests call it after setenv."""
    global _store
    _store = bundle_store.load()
    return _store


def store() -> bundle_store.BundleStore:
    return _store if _store is not None else reload_store()


@asynccontextmanager
async def _lifespan(_: FastAPI):
    reload_store()
    yield


app = FastAPI(title="Car to Curb entrance service", version="0.2.0", lifespan=_lifespan)


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
    return _error(422, "VALIDATION", "The request doesn't match the contract.")


@app.exception_handler(StarletteHTTPException)
async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    return _error(
        exc.status_code, "NOT_FOUND" if exc.status_code == 404 else "VALIDATION", str(exc.detail)
    )


def _example() -> ResolveResult:
    return ResolveResult.model_validate(json.loads(CONTRACT_EXAMPLE.read_text(encoding="utf-8")))


def _dev_example_enabled(current: bundle_store.BundleStore) -> bool:
    """Contract-example fallback for the app team, only before any bundle exists."""
    return len(current) == 0 and os.environ.get("DEV_EXAMPLE") == "1"


def _bundle_response(stored: bundle_store.StoredBundle) -> Response:
    return Response(
        content=stored.body,
        media_type="application/json",
        headers={"ETag": f'"{stored.sha256}"', "Cache-Control": "no-cache"},
    )


def _etag_matches(if_none_match: str | None, sha256: str) -> bool:
    if not if_none_match:
        return False
    tags = {t.strip().removeprefix("W/").strip('"') for t in if_none_match.split(",")}
    return "*" in tags or sha256 in tags


def _geocode(request: ResolveRequest) -> GeocodedPoint:
    """resolver.geocode on a worker thread, cut off at the request budget.

    A cut-off lookup keeps running and fills the geocode cache, so a retry is fast.
    """
    future = _geocode_pool.submit(resolver.geocode, request)
    try:
        return future.result(timeout=GEOCODE_BUDGET_S)
    except FutureTimeout as exc:
        log.warning("geocode exceeded the %.1f s budget", GEOCODE_BUDGET_S)
        raise ApiError(
            503, "UPSTREAM_UNAVAILABLE", "The address lookup is slow right now. Try again."
        ) from exc
    except resolver.GeocodeAmbiguous as exc:
        raise ApiError(
            422, "VALIDATION", "More than one place has this address. Add the city or ZIP code."
        ) from exc
    except resolver.GeocodeNotFound as exc:
        raise ApiError(404, "GEOCODE_NOT_FOUND", "Couldn't find that address.") from exc
    except resolver.UpstreamUnavailable as exc:
        log.warning("geocoder unavailable: %s", exc)  # the message names no address
        raise ApiError(
            503, "UPSTREAM_UNAVAILABLE", "The address lookup is unavailable. Try again."
        ) from exc
    except RuntimeError as exc:  # e.g. USER_AGENT missing: a deployment problem, not the rider's
        log.error("geocoder misconfigured: %s", exc)
        raise ApiError(
            503, "UPSTREAM_UNAVAILABLE", "The address lookup is unavailable. Try again."
        ) from exc


@app.get("/v1/health")
def health() -> dict:
    current = store()
    versions = sorted((b.result.data_version for b in current.by_id.values()), key=lambda v: v.osm)
    if versions:
        data_version = versions[-1].model_dump()
    elif _dev_example_enabled(current):
        data_version = _example().data_version.model_dump()
    else:
        data_version = None
    return {"status": "ok", "bundles": len(current), "data_version": data_version}


@app.post("/v1/resolve", response_model=ResolveResult)
def resolve(request: ResolveRequest):
    has_point = request.lat is not None and request.lon is not None
    if not request.address and not has_point:
        raise ApiError(422, "VALIDATION", "Send an address, or lat and lon.")
    current = store()
    if _dev_example_enabled(current):
        return _example()

    if has_point:
        if not (-90 <= request.lat <= 90 and -180 <= request.lon <= 180):
            raise ApiError(422, "VALIDATION", "lat must be in [-90, 90] and lon in [-180, 180].")
        point = GeocodedPoint(lat=request.lat, lon=request.lon, source="request")
        found = current.match(point)
    else:
        # A pilot address resolves without the network; anything else goes to the geocoder.
        found = current.find_address(request.address) or current.match(_geocode(request))
    if found is None:
        raise ApiError(404, "NOT_FOUND", NOT_IN_PILOT)
    return _bundle_response(found)


@app.get("/v1/bundles")
def bundles() -> list[dict]:
    """Every pilot bundle, for the app to download and cache at setup."""
    return store().manifest()


@app.get("/v1/bundles/{bundle_id}", response_model=ResolveResult)
def get_bundle(
    bundle_id: Annotated[str, PathParam(pattern=bundle_store.BUNDLE_ID.pattern)],
    if_none_match: Annotated[str | None, Header()] = None,
):
    found = store().get(bundle_id)
    if found is None:
        raise ApiError(404, "NOT_FOUND", "No pilot bundle has that id.")
    if _etag_matches(if_none_match, found.sha256):
        return Response(status_code=304, headers={"ETag": f'"{found.sha256}"'})
    return _bundle_response(found)
