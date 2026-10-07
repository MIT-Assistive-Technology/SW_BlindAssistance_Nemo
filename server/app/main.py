"""Entrance resolution service. Run: uvicorn app.main:app --reload (from server/)."""

import json
from pathlib import Path

from fastapi import FastAPI, HTTPException

from . import resolver
from .models import Feedback, Flags, ResolveRequest, ResolveResult

CONTRACT_EXAMPLE = Path(__file__).resolve().parents[2] / "contract" / "resolve.example.json"

app = FastAPI(title="Car to Curb entrance service", version="0.1.0")


def _example() -> ResolveResult:
    return ResolveResult.model_validate(json.loads(CONTRACT_EXAMPLE.read_text(encoding="utf-8")))


@app.get("/v1/health")
def health() -> dict:
    return {"status": "ok", "data_version": _example().data_version.model_dump()}


@app.post("/v1/resolve", response_model=ResolveResult)
def resolve(request: ResolveRequest) -> ResolveResult:
    if not request.address and (request.lat is None or request.lon is None):
        raise HTTPException(status_code=422, detail="Send an address, or lat and lon.")
    try:
        return resolver.resolve(request)
    except NotImplementedError:
        # TODO (BE-6): remove this fallback once the ladder works. Until then the app team
        # gets the contract example, so both sides can build in parallel.
        return _example()


@app.get("/v1/destinations/{destination_id}", response_model=ResolveResult)
def get_destination(destination_id: str) -> ResolveResult:
    # TODO (BE-6): look up the cached result in SQLite; 404 if unknown.
    example = _example()
    if destination_id != example.destination_id:
        raise HTTPException(status_code=404, detail="Unknown destination.")
    return example


@app.post("/v1/destinations/{destination_id}/feedback", status_code=204)
def feedback(destination_id: str, body: Feedback) -> None:
    # TODO (v2): store one vote per install, update crowd confidence (plan section 8).
    raise HTTPException(status_code=501, detail="Feedback is a v2 feature.")


@app.get("/v1/flags", response_model=Flags)
def flags() -> Flags:
    # TODO (BE-8): read from config so a bad source can be turned off without a deploy.
    return Flags()
