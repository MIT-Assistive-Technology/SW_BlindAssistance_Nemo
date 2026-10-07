"""Pydantic mirror of the API contract.

Source of truth: contract/resolve.example.json and docs/car-to-curb-plan.md section 10.
Change the contract first, then this file, then app/nemo-software/EntranceAPI/EntranceModels.swift.
tests/test_contract.py keeps them in sync.
"""

from typing import Literal

from pydantic import BaseModel, Field

LonLat = list[float]  # [lon, lat]


class ResolveRequest(BaseModel):
    """Only the destination. Never the rider's location."""

    address: str | None = None
    lat: float | None = None
    lon: float | None = None
    name: str | None = None
    force_refresh: bool = False


class Building(BaseModel):
    osm_id: str
    name: str | None = None
    housenumber: str | None = None
    footprint: list[LonLat]


class Speak(BaseModel):
    door: str | None = None
    automatic_door: str | None = None
    step_count: int | None = None


class Provenance(BaseModel):
    source: Literal["osm_tag", "mapillary_cv", "crowd", "geometry_fallback"]
    ref: str | None = None
    tags: dict[str, str] | None = None


class Candidate(BaseModel):
    id: str
    lat: float
    lon: float
    confidence: float = Field(ge=0, le=1)
    # Spoken state: "main" = map shows the main entrance, "door" = map shows a door,
    # "facade" = no door on the map (street-facing side). Never call a band "found".
    band: Literal["main", "door", "facade"]
    label: str
    speak: Speak | None = None
    provenance: list[Provenance]


class PathChecks(BaseModel):
    crosses_road: bool
    nearest_crossing: LonLat | None = None
    footway_to_entrance: bool


class StreetSide(BaseModel):
    entrance_street: str
    road_way: str
    centerline: list[LonLat]
    # Side of the road the door is on, relative to the centerline's direction (first -> last point).
    door_side_of_road: Literal["left", "right"]
    oneway: bool


class Recognize(BaseModel):
    text: list[str]


class Landmark(BaseModel):
    kind: str
    lat: float
    lon: float
    side: Literal["left", "right"]
    meters_to_door: float
    at_door: bool
    source: str
    speak: str


class DataVersion(BaseModel):
    osm: str
    model: str


class ResolveResult(BaseModel):
    destination_id: str
    # "partial" = weak result now (e.g. facade only); fetch again later for better candidates.
    status: Literal["complete", "partial"]
    building: Building
    candidates: list[Candidate] = Field(max_length=5)
    path_checks: PathChecks
    street_side: StreetSide | None = None
    recognize: Recognize | None = None
    landmarks: list[Landmark] | None = None
    route: list[LonLat] | None = None
    attribution: list[str]
    data_version: DataVersion


class ErrorBody(BaseModel):
    """Every error response is {"error": ErrorBody}."""

    code: Literal[
        "GEOCODE_NOT_FOUND", "UPSTREAM_UNAVAILABLE", "RATE_LIMITED", "VALIDATION", "NOT_FOUND"
    ]
    message: str
    request_id: str | None = None
