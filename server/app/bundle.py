"""Pilot bundle assembly: one pilot site in, one contract-valid ResolveResult out.

The MVP ships precomputed bundles instead of a live server (docs/car-to-curb-plan.md sections 2
and 8); each bundle has exactly the shape of contract/resolve.example.json (section 10).
scripts/build_bundles.py is the command-line wrapper.

Each ladder step is a stage with a typed input and output (see `Stages`). The default stages are
resolver.geocode and the app/doors.py functions; tests and the offline mode swap them out. A stage that still raises
NotImplementedError("BE-3") is reported as "blocked on BE-3", and the other sites still build.
"""

import itertools
import json
import logging
import math
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, TypeVar

import httpx
from pydantic import BaseModel, Field

from . import doors, resolver, scoring
from .geo import Frame, closest_on_line
from .merge import merge_candidates
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
log = logging.getLogger(__name__)
COMBINE_FALLBACK_NOTE = (
    "scoring.combine blocked on BE-4: merged doors use the best score, no agreement step"
)


class PilotSite(BaseModel):
    # The id becomes the file name bundles/<id>.json, so keep it to a safe slug.
    id: str = Field(pattern=r"^[a-z0-9][a-z0-9-]*$")
    label: str | None = None  # for people (test runs, logs); never sent to the app
    address: str
    name: str | None = None
    scenario: Literal["same_side", "driveway", "opposite", "campus"]


class Facade(BaseModel):
    """Output of the facade_fallback stage (BE-5): fallback candidates plus the street side."""

    candidates: list[Candidate]
    street_side: StreetSide | None = None


@dataclass(frozen=True)
class Stages:
    """The ladder, one typed callable per step. Outputs may be models or plain dicts."""

    geocode: Callable[[ResolveRequest], GeocodedPoint] = resolver.geocode
    find_building: Callable[[GeocodedPoint], Building] = doors.find_building
    read_entrances: Callable[[Building, str | None], list[Candidate]] = doors.read_entrances
    facade_fallback: Callable[[Building, GeocodedPoint], Facade] = doors.facade_fallback
    path_checks: Callable[[Building, Candidate, StreetSide | None], PathChecks] = doors.path_checks


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
    notes: tuple[str, ...] = ()

    @property
    def ok(self) -> bool:
        return self.bundle is not None

    def describe(self) -> str:
        if self.bundle is not None:
            top = self.bundle.candidates[0]
            ok = f"ok ({self.bundle.status}, top door: {top.band} {top.confidence:.2f})"
            return "; ".join([ok, *self.notes])
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


def has_housenumber(c: Candidate, housenumber: str | None) -> bool:
    """True if one of the candidate's OSM tags says addr:housenumber=<the destination's>."""
    if not housenumber:
        return False
    want = housenumber.strip().lower()
    return any(
        want in {n.strip().lower() for n in p.tags.get("addr:housenumber", "").split(";")}
        for p in c.provenance
        if p.tags
    )


def meters_to_street(c: Candidate, street_side: StreetSide | None) -> float:
    """Distance from the candidate to the entrance street's centerline (0 when unknown)."""
    if street_side is None or not street_side.centerline:
        return 0.0
    f = Frame(c.lat, c.lon)
    return closest_on_line((0.0, 0.0), [f.xy(lon, lat) for lon, lat in street_side.centerline])[0]


def rank(
    candidates: list[Candidate],
    street_side: StreetSide | None = None,
    housenumber: str | None = None,
) -> list[Candidate]:
    """Cap confidence, set the band from scoring.band, sort best first, keep the top 5.

    Equal confidence (e.g. several main doors capped at 0.95, E2E I-5) is broken by: the door
    tagged with the destination's house number, then the door nearest the entrance street (plan
    section 8: walking distance from the expected drop-off), then the original order.
    Ids are reassigned c1..cN in rank order so they stay unique across stages.
    """
    capped = []
    for c in candidates:
        confidence = min(c.confidence, scoring.CAP)
        capped.append(
            c.model_copy(update={"confidence": confidence, "band": scoring.band(confidence)})
        )
    # sorted() is stable, so the original order is the last tie-break.
    best = sorted(
        capped,
        key=lambda c: (
            -round(c.confidence, 6),
            not has_housenumber(c, housenumber),
            meters_to_street(c, street_side),
        ),
    )[:MAX_CANDIDATES]
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
    # The number, the mapped name and the pilot site's name, which often differ (E2E I-10).
    names = [building.housenumber or point.housenumber, building.name, site.name]
    text = list(dict.fromkeys(t for t in names if t))
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


CORNER_M = 1.5  # two candidates this close to a shared corner count as the same face


def same_face_on(footprint: list[list[float]]) -> Callable[[Candidate, Candidate], bool] | None:
    """A building-face predicate for merge_candidates, from a [lon, lat] footprint.

    Each candidate snaps to its nearest footprint edge. Same face = same edge, or adjacent
    edges with both candidates within CORNER_M of their shared corner (a door right at a
    corner). Works in local meters around the footprint's first point; buildings are small
    enough for an equirectangular projection. None when the footprint has no usable edge.
    """
    lon0, lat0 = footprint[0] if footprint else (0.0, 0.0)
    kx = math.radians(1) * 6_371_008.8 * math.cos(math.radians(lat0))
    ky = math.radians(1) * 6_371_008.8

    def local(lon: float, lat: float) -> tuple[float, float]:
        return ((lon - lon0) * kx, (lat - lat0) * ky)

    pts = [local(lon, lat) for lon, lat in footprint]
    edges = [(a, b) for a, b in itertools.pairwise(pts) if a != b]
    if not edges:
        return None

    def snap(c: Candidate) -> tuple[int, tuple[float, float]]:
        px, py = local(c.lon, c.lat)
        best = None
        for i, ((ax, ay), (bx, by)) in enumerate(edges):
            dx, dy = bx - ax, by - ay
            t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
            q = (ax + t * dx, ay + t * dy)
            d = math.dist((px, py), q)
            if best is None or d < best[0]:
                best = (d, i, q)
        return best[1], best[2]

    def same_face(a: Candidate, b: Candidate) -> bool:
        (ea, qa), (eb, qb) = snap(a), snap(b)
        if ea == eb:
            return True
        shared = set(edges[ea]) & set(edges[eb])
        return any(math.dist(qa, v) <= CORNER_M and math.dist(qb, v) <= CORNER_M for v in shared)

    return same_face


def merge(
    candidates: list[Candidate],
    notes: list[str] | None = None,
    same_face: Callable[[Candidate, Candidate], bool] | None = None,
) -> list[Candidate]:
    """Merge duplicate doors within ~4 m (app/merge.py) using scoring.combine.

    Until BE-4 implements scoring.combine, fall back to the best score (no agreement step) and
    add COMBINE_FALLBACK_NOTE to `notes` instead of failing the site.
    """

    seen = notes if notes is not None else []

    def combine(best_by_class: dict[str, float]) -> float:
        try:
            return scoring.combine(best_by_class)
        except NotImplementedError:
            if COMBINE_FALLBACK_NOTE not in seen:
                log.warning(COMBINE_FALLBACK_NOTE)
                seen.append(COMBINE_FALLBACK_NOTE)
            return max(best_by_class.values())

    return merge_candidates(candidates, combine=combine, same_face=same_face)


def build_bundle(
    site: PilotSite, stages: Stages, data_version: DataVersion, notes: list[str] | None = None
) -> ResolveResult:
    """Run the ladder for one site. Raises StageError naming the stage that failed.

    Non-fatal remarks (e.g. a teammate's step still stubbed) are appended to `notes`.
    """
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
    merged = _stage(
        "merge",
        lambda: merge(doors + facade.candidates, notes, same_face_on(building.footprint)),
    )
    candidates = rank(merged, facade.street_side, point.housenumber)
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
    notes: list[str] = []
    try:
        result = build_bundle(site, stages, data_version, notes)
        return SiteReport(site.id, bundle=result, notes=tuple(notes))
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
