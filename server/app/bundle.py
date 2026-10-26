"""Pilot bundle assembly: one pilot site in, one contract-valid ResolveResult out.

The MVP ships precomputed bundles instead of a live server (docs/car-to-curb-plan.md sections 2
and 8); each bundle has exactly the shape of contract/resolve.example.json (section 10).
scripts/build_bundles.py is the command-line wrapper.

Each ladder step is a stage with a typed input and output (see `Stages`). The default stages are
the resolver functions; tests and the offline mode swap them out. A stage that still raises
NotImplementedError("BE-3") is reported as "blocked on BE-3", and the other sites still build.
"""

import json
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, TypeVar

import httpx
from pydantic import BaseModel, Field

from . import resolver, scoring
from .models import (
    Building,
    Candidate,
    DataVersion,
    PathChecks,
    Recognize,
    ResolveRequest,
    ResolveResult,
    StreetSide,
)
from .resolver import GeocodedPoint

MAX_CANDIDATES = 5
OSM_ATTRIBUTION = "© OpenStreetMap contributors"
MAPILLARY_ATTRIBUTION = "Street-level imagery © Mapillary contributors, CC BY-SA 4.0"
MODEL_VERSION = "none"  # no CV model in the MVP bundles

T = TypeVar("T")


class PilotSite(BaseModel):
    # The id becomes the file name bundles/<id>.json, so keep it to a safe slug.
    id: str = Field(pattern=r"^[a-z0-9][a-z0-9-]*$")
    address: str
    name: str | None = None
    scenario: Literal["same_side", "driveway", "opposite", "campus"]


class Facade(BaseModel):
    """Output of the facade_fallback stage (BE-5): fallback candidates plus the street side."""

    candidates: list[Candidate]
    street_side: StreetSide | None = None


def path_checks_todo(building: Building, door: Candidate, street_side: StreetSide | None):
    """Path checks from the drop-off to `door` (plan section 8). TODO (BE-7)."""
    raise NotImplementedError("BE-7")


@dataclass(frozen=True)
class Stages:
    """The ladder, one typed callable per step. Outputs may be models or plain dicts."""

    geocode: Callable[[ResolveRequest], GeocodedPoint] = resolver.geocode
    find_building: Callable[[GeocodedPoint], Building] = resolver.find_building
    read_entrances: Callable[[Building, str | None], list[Candidate]] = resolver.read_entrances
    facade_fallback: Callable[[Building, GeocodedPoint], Facade] = resolver.facade_fallback
    path_checks: Callable[[Building, Candidate, StreetSide | None], PathChecks] = path_checks_todo


class StageError(Exception):
    def __init__(self, stage: str, cause: Exception):
        super().__init__(f"{stage}: {cause}")
        self.stage, self.cause = stage, cause

    @property
    def blocked_on(self) -> str | None:
        """The task ID a NotImplementedError stub names, e.g. "BE-3"."""
        if isinstance(self.cause, NotImplementedError):
            return str(self.cause) or "an unimplemented step"
        return None


@dataclass(frozen=True)
class SiteReport:
    site_id: str
    bundle: ResolveResult | None = None
    error: StageError | None = None

    @property
    def ok(self) -> bool:
        return self.bundle is not None

    def describe(self) -> str:
        if self.bundle is not None:
            top = self.bundle.candidates[0]
            return f"ok ({self.bundle.status}, top door: {top.band} {top.confidence:.2f})"
        assert self.error is not None
        if self.error.blocked_on:
            return f"blocked on {self.error.blocked_on} ({self.error.stage})"
        cause = self.error.cause
        return f"failed at {self.error.stage}: {type(cause).__name__}: {cause}"


def _stage(name: str, run: Callable[[], T]) -> T:
    """Run one stage; any failure, including an output of the wrong shape, names the stage."""
    try:
        return run()
    except Exception as exc:
        raise StageError(name, exc) from exc


def rank(candidates: list[Candidate]) -> list[Candidate]:
    """Cap confidence, set the band from scoring.band, sort best first, keep the top 5.

    Ids are reassigned c1..cN in rank order so they stay unique across stages.
    """
    capped = []
    for c in candidates:
        confidence = min(c.confidence, scoring.CAP)
        capped.append(
            c.model_copy(update={"confidence": confidence, "band": scoring.band(confidence)})
        )
    best = sorted(capped, key=lambda c: c.confidence, reverse=True)[:MAX_CANDIDATES]
    return [c.model_copy(update={"id": f"c{i}"}) for i, c in enumerate(best, start=1)]


def attribution(candidates: list[Candidate]) -> list[str]:
    credits = [OSM_ATTRIBUTION]  # geocode and buildings always come from OSM
    if any(p.source == "mapillary_cv" for c in candidates for p in c.provenance):
        credits.append(MAPILLARY_ATTRIBUTION)
    return credits


def assemble(
    site: PilotSite,
    point: GeocodedPoint,
    building: Building,
    ranked: list[Candidate],
    path_checks: PathChecks,
    street_side: StreetSide | None,
    data_version: DataVersion,
) -> ResolveResult:
    """Put the stage outputs into the contract shape and validate the result.

    `ranked` is the output of rank(): capped, banded, best first, at most 5.
    """
    if not ranked:
        raise ValueError("no candidates, not even a facade fallback")
    text = [
        t
        for t in dict.fromkeys(
            [building.housenumber or point.housenumber, building.name or site.name]
        )
        if t
    ]
    result = ResolveResult(
        destination_id=f"dst_{site.id}",
        # Facade only is a weak answer: the app should treat it as partial.
        status="partial" if ranked[0].band == "facade" else "complete",
        building=building,
        candidates=ranked,
        path_checks=path_checks,
        street_side=street_side,
        recognize=Recognize(text=text) if text else None,
        landmarks=None,
        route=None,
        attribution=attribution(ranked),
        data_version=data_version,
    )
    # Round-trip through JSON so nested models built with model_construct are checked too.
    return ResolveResult.model_validate(result.model_dump(mode="json"))


def build_bundle(site: PilotSite, stages: Stages, data_version: DataVersion) -> ResolveResult:
    """Run the ladder for one site. Raises StageError naming the stage that failed."""
    request = ResolveRequest(address=site.address, name=site.name)
    point = _stage("geocode", lambda: stages.geocode(request))
    building = _stage("find_building", lambda: Building.model_validate(stages.find_building(point)))
    doors = _stage(
        "read_entrances",
        lambda: [
            Candidate.model_validate(c) for c in stages.read_entrances(building, point.housenumber)
        ],
    )
    # Always run: besides the fallback doors it builds street_side, which the app needs even
    # when OSM has a main entrance. Fallback candidates rank last, so they never outrank a door.
    facade = _stage(
        "facade_fallback", lambda: Facade.model_validate(stages.facade_fallback(building, point))
    )
    candidates = rank(doors + facade.candidates)
    if not candidates:
        raise StageError("facade_fallback", ValueError("no candidates, not even a facade fallback"))
    checks = _stage(
        "path_checks",
        lambda: PathChecks.model_validate(
            stages.path_checks(building, candidates[0], facade.street_side)
        ),
    )
    return _stage(
        "assemble",
        lambda: assemble(
            site, point, building, candidates, checks, facade.street_side, data_version
        ),
    )


def run_site(site: PilotSite, stages: Stages, data_version: DataVersion) -> SiteReport:
    """Like build_bundle, but a failure becomes a report instead of stopping the run."""
    try:
        return SiteReport(site.id, bundle=build_bundle(site, stages, data_version))
    except StageError as exc:
        return SiteReport(site.id, error=exc)


def load_sites(path: Path) -> list[PilotSite]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    sites = [PilotSite.model_validate(s) for s in raw["sites"]]
    ids = [s.id for s in sites]
    if dupes := sorted({i for i in ids if ids.count(i) > 1}):
        raise ValueError(f"duplicate site ids in {path.name}: {', '.join(dupes)}")
    return sites


def write_bundle(bundle: ResolveResult, site_id: str, out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{site_id}.json"
    text = json.dumps(bundle.model_dump(mode="json"), indent=2, ensure_ascii=False) + "\n"
    path.write_text(text, encoding="utf-8")
    return path


class NoSavedResponse(LookupError):
    """Offline mode: geocode sent a query that no saved Nominatim response matches."""


def _query_key(items) -> tuple:
    return tuple(sorted((str(k), str(v)) for k, v in items))


def replay_client(fixtures: Path) -> httpx.Client:
    """An httpx client that answers Nominatim queries from saved responses, never the network.

    Reads the files scripts/record_nominatim_fixtures.py writes (tests/fixtures/nominatim/).
    """
    saved = {}
    for path in sorted(fixtures.glob("*.json")):
        record = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(record, dict) and {"params", "response"} <= record.keys():
            saved[_query_key(record["params"].items())] = record["response"]

    def handler(request: httpx.Request) -> httpx.Response:
        key = _query_key(request.url.params.multi_items())
        if key not in saved:
            raise NoSavedResponse(
                "no saved Nominatim response for this address; record it with "
                "scripts/record_nominatim_fixtures.py"
            )
        return httpx.Response(200, json=saved[key])

    return httpx.Client(transport=httpx.MockTransport(handler))
