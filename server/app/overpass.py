"""Overpass queries and parsing for the lookup ladder (BE-3, BE-5, BE-7).

Two small queries per destination instead of the plan's single one (section 9):
  1. `buildings_query`: building outlines around the geocoded point, plus the outline that
     CONTAINS the point (`is_in`). `around:40` measures distance to the walls, so a point deep
     inside a large building (CambridgeSide) matched nothing (E2E finding I-1).
  2. `area_query`: for the chosen building, its outlines, door nodes on or near them, site
     relations, the ways that touch those doors, and every road and marked crossing in a box
     around the footprint. `way(around.outlines:60)` returned no roads at 8 of 10 pilot sites
     (I-2), so roads come from a plain bounding box instead.

Responses are cached on disk by query text (default server/data/overpass_cache, 7 days); the
public Overpass instance allows apps only ~100 queries/day. Offline mode reads the cache only.
Tests and the offline bundle build point the cache at tests/fixtures/overpass.
"""

import hashlib
import json
import math
import os
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

import httpx

from .geo import EARTH_R, Frame, area

# Tried in turn when one fails; OVERPASS_URL (comma-separated) overrides the list.
DEFAULT_URLS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
)
DEFAULT_CACHE = Path(__file__).resolve().parents[1] / "data" / "overpass_cache"
CACHE_MAX_AGE_S = 7 * 24 * 3600
TIMEOUT_S = 180.0
RETRY_CODES = {429, 500, 502, 503, 504}
RETRY_WAITS_S = (5, 15, 30, 60)  # after each failure (rotating mirrors); then give up
MIN_INTERVAL_S = 2.0  # between live queries, to stay polite to the public instance
BUILDING_RADIUS_M = 40
NEAR_OUTLINE_M = 5  # plan section 8: doors within 5 m of the outline count, with a penalty
AREA_MARGIN_M = 80  # roads and crossings this far around the footprint

ROAD_HIGHWAYS = (
    "motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service"
)


class OverpassUnavailable(Exception):
    """Overpass failed, or offline mode has no cached response for this query."""


# ---------------------------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------------------------


def buildings_query(lat: float, lon: float, osm_ref: str | None = None) -> str:
    """Buildings around (lat, lon), the one containing it, and Nominatim's own match."""
    p = f"{lat:.7f},{lon:.7f}"
    exact = ""
    if osm_ref and osm_ref.split("/")[0] in {"way", "relation"}:
        kind, osm_id = osm_ref.split("/", 1)
        if osm_id.isdigit():
            exact = f"  {'rel' if kind == 'relation' else 'way'}({osm_id})[building];\n"
    return (
        "[out:json][timeout:90];\n"
        f"is_in({p})->.a;\n"
        "(\n"
        "  way(pivot.a)[building];\n"
        "  rel(pivot.a)[building];\n"
        f"  way(around:{BUILDING_RADIUS_M},{p})[building];\n"
        f"  rel(around:{BUILDING_RADIUS_M},{p})[building][type=multipolygon];\n"
        f'  way(around:{BUILDING_RADIUS_M},{p})["building:part"];\n'
        f"{exact}"
        ");\n"
        "out body geom;\n"
    )


def area_query(building_ref: str, bbox: tuple[float, float, float, float]) -> str:
    """Everything the ladder needs about one building. bbox = (south, west, north, east)."""
    kind, osm_id = building_ref.split("/", 1)
    b = ",".join(f"{v:.7f}" for v in bbox)
    is_rel = kind == "relation"
    return (
        "[out:json][timeout:90];\n"
        f"{'rel' if is_rel else 'way'}({osm_id})->.b;\n"
        # The relation's own record (member roles) tells parse_area which ways are its outline.
        + (".b out body;\n" if is_rel else "")
        + '(way.b; way(r.b:"outer");)->.outlines;\n'
        ".outlines out body geom;\n"
        "(\n"
        "  node(w.outlines)[entrance];\n"
        "  node(w.outlines)[door];\n"
        '  node(w.outlines)["routing:entrance"];\n'
        f"  node(around.outlines:{NEAR_OUTLINE_M})[entrance];\n"
        f"  node(around.outlines:{NEAR_OUTLINE_M})[door];\n"
        f'  node(around.outlines:{NEAR_OUTLINE_M})["routing:entrance"];\n'
        ")->.ent;\n"
        # A site lists the building way, or for a multipolygon building the relation itself.
        "(rel(bw.outlines)[type=site]; rel(br.b)[type=site];)->.site;\n"
        '(.ent; node(r.site:"entrance");)->.ent;\n'
        ".ent out body;\n"
        ".site out body;\n"
        "way(bn.ent);\n"  # footways to the doors, and other buildings the doors belong to
        "out body geom;\n"
        f'way({b})[highway~"^({ROAD_HIGHWAYS})(_link)?$"];\n'
        "out body geom;\n"
        f"node({b})[highway=crossing];\n"
        "out body;\n"
    )


def bbox_around(footprint: list[list[float]], margin_m: float = AREA_MARGIN_M):
    """(south, west, north, east) of a [lon, lat] footprint, grown by margin_m."""
    lons = [p[0] for p in footprint]
    lats = [p[1] for p in footprint]
    dlat = math.degrees(margin_m / EARTH_R)
    dlon = dlat / math.cos(math.radians(sum(lats) / len(lats)))
    return (min(lats) - dlat, min(lons) - dlon, max(lats) + dlat, max(lons) + dlon)


# ---------------------------------------------------------------------------------------------
# Fetch and cache
# ---------------------------------------------------------------------------------------------


@dataclass
class Client:
    """Runs Overpass queries through an on-disk cache.

    `offline=True` never touches the network. `http` is for tests (httpx.MockTransport).
    """

    cache_dir: Path = field(
        default_factory=lambda: Path(os.environ.get("OVERPASS_CACHE_DIR") or DEFAULT_CACHE)
    )
    offline: bool = field(default_factory=lambda: os.environ.get("OVERPASS_OFFLINE") == "1")
    urls: tuple[str, ...] = field(
        default_factory=lambda: (
            tuple(u.strip() for u in (os.environ.get("OVERPASS_URL") or "").split(",") if u.strip())
            or DEFAULT_URLS
        )
    )
    max_age_s: float = CACHE_MAX_AGE_S
    http: httpx.Client | None = None
    sleep: Callable[[float], None] = time.sleep
    _last_call: float = field(default=0.0, init=False, repr=False)

    def path_for(self, query: str) -> Path:
        return self.cache_dir / f"{hashlib.sha256(query.encode()).hexdigest()[:20]}.json"

    def run(self, query: str) -> dict:
        """The saved response if fresh (or offline), else a live one. When the live query
        fails, a stale saved response is better than none."""
        path = self.path_for(query)
        saved = path.exists()
        if saved:
            fresh = time.time() - path.stat().st_mtime < self.max_age_s
            if fresh or self.offline:
                return _read(path)
        if self.offline:
            raise OverpassUnavailable(
                f"offline: no saved Overpass response {path.name}; run once online to save it"
            )
        try:
            data = self._fetch(query)
        except OverpassUnavailable:
            if saved:
                return _read(path)
            raise
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps({"query": query, "response": data}), encoding="utf-8")
        tmp.replace(path)  # never leave a half-written file in the cache
        return data

    def _fetch(self, query: str) -> dict:
        user_agent = os.environ.get("USER_AGENT", "").strip()
        if not user_agent:
            raise RuntimeError("Set USER_AGENT in server/.env: Overpass asks for one.")
        http = self.http or httpx.Client()
        last = "no attempt"
        try:
            for attempt in range(len(RETRY_WAITS_S) + 1):
                wait = self._last_call + MIN_INTERVAL_S - time.monotonic()
                if wait > 0:
                    self.sleep(wait)
                self._last_call = time.monotonic()
                try:
                    r = http.post(
                        self.urls[attempt % len(self.urls)],
                        data={"data": query},
                        headers={"User-Agent": user_agent},
                        timeout=TIMEOUT_S,
                    )
                except httpx.HTTPError as exc:
                    last = type(exc).__name__
                else:
                    if r.status_code == 200:
                        try:
                            data = r.json()
                        except ValueError:  # an HTML error page sent as 200
                            data = {"remark": "error: the response is not JSON"}
                        # Overpass reports a timeout or memory error as a 200 with a remark.
                        if "error" in str(data.get("remark", "")).lower():
                            last = f"remark: {data['remark']}"
                        else:
                            return data
                    elif r.status_code not in RETRY_CODES:
                        raise OverpassUnavailable(f"Overpass returned HTTP {r.status_code}")
                    else:
                        last = f"HTTP {r.status_code}"
                if attempt < len(RETRY_WAITS_S):
                    self.sleep(RETRY_WAITS_S[attempt])
        finally:
            if self.http is None:
                http.close()
        raise OverpassUnavailable(f"Overpass failed after retries ({last})")


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))["response"]


# ---------------------------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------------------------

LonLat = tuple[float, float]


@dataclass(frozen=True)
class Outline:
    """One building: a way, or a multipolygon relation with one or more outer rings."""

    ref: str  # "way/1" or "relation/2"
    tags: dict[str, str]
    rings: list[list[LonLat]]  # closed outer rings, largest first
    is_part: bool = False  # building:part without building=*

    @property
    def footprint(self) -> list[LonLat]:
        return self.rings[0]


@dataclass(frozen=True)
class Way:
    ref: str
    tags: dict[str, str]
    nodes: tuple[int, ...]
    coords: list[LonLat]


@dataclass
class BuildingArea:
    """Parsed area_query response."""

    outline_nodes: set[int]  # every node of the building's outline ways
    entrances: dict[int, dict]  # node id -> {"lat", "lon", "tags"}
    site_entrances: set[int]
    ways_at_doors: list[Way]  # ways containing a door node (footways, other buildings)
    roads: list[Way]
    crossings: list[dict]  # highway=crossing nodes
    osm_date: str


def _tags(element: dict) -> dict[str, str]:
    return {str(k): str(v) for k, v in (element.get("tags") or {}).items()}


def _coords(element: dict) -> list[LonLat]:
    return [(g["lon"], g["lat"]) for g in element.get("geometry") or [] if g]


def join_rings(ways: list[list[LonLat]]) -> list[list[LonLat]]:
    """Join multipolygon member ways end to end into closed rings."""
    pending = [list(w) for w in ways if len(w) >= 2]
    rings = []
    while pending:
        ring = pending.pop(0)
        grew = True
        while ring[0] != ring[-1] and grew:
            grew = False
            for i, w in enumerate(pending):
                if w[0] == ring[-1]:
                    ring += w[1:]
                elif w[-1] == ring[-1]:
                    ring += w[-2::-1]
                elif w[-1] == ring[0]:
                    ring = w[:-1] + ring
                elif w[0] == ring[0]:
                    ring = w[:0:-1] + ring
                else:
                    continue
                pending.pop(i)
                grew = True
                break
        if len(ring) >= 4 and ring[0] == ring[-1]:
            rings.append(ring)
    return rings


def _ring_area(ring: list[LonLat]) -> float:
    f = Frame(ring[0][1], ring[0][0])
    return area([f.xy(*p) for p in ring[:-1]])


def parse_buildings(raw: dict) -> list[Outline]:
    out: dict[str, Outline] = {}
    for e in raw.get("elements", []):
        tags = _tags(e)
        if "building" not in tags and "building:part" not in tags:
            continue
        if e["type"] == "way":
            ring = _coords(e)
            if len(ring) >= 4 and ring[0] == ring[-1]:
                ref = f"way/{e['id']}"
                out[ref] = Outline(ref, tags, [ring], is_part="building" not in tags)
        elif e["type"] == "relation":
            outer = [
                _coords(m)
                for m in e.get("members", [])
                if m.get("type") == "way" and m.get("role") == "outer"
            ]
            rings = sorted(join_rings(outer), key=_ring_area, reverse=True)
            if rings:
                ref = f"relation/{e['id']}"
                out[ref] = Outline(ref, tags, rings, is_part="building" not in tags)
    return list(out.values())


def parse_area(raw: dict, building_ref: str) -> BuildingArea:
    elements = raw.get("elements", [])
    kind, _, osm_id = building_ref.partition("/")
    outline_way_ids: set[int] = set()
    if kind == "way":
        outline_way_ids.add(int(osm_id))
    for e in elements:
        if e["type"] == "relation" and str(e["id"]) == osm_id and kind == "relation":
            outline_way_ids |= {
                m["ref"]
                for m in e.get("members", [])
                if m.get("type") == "way" and m.get("role") == "outer"
            }

    outline_nodes: set[int] = set()
    entrances: dict[int, dict] = {}
    site_entrances: set[int] = set()
    ways: dict[int, dict] = {}
    crossings: list[dict] = []
    road_pattern = set(ROAD_HIGHWAYS.split("|"))
    for e in elements:
        tags = _tags(e)
        if e["type"] == "node":
            if tags.get("highway") == "crossing":
                crossings.append({"lat": e["lat"], "lon": e["lon"], "tags": tags})
            if {"entrance", "door", "routing:entrance"} & tags.keys():
                entrances[e["id"]] = {"lat": e["lat"], "lon": e["lon"], "tags": tags}
        elif e["type"] == "way":
            if e["id"] in outline_way_ids:
                outline_nodes |= set(e.get("nodes", []))
            ways.setdefault(e["id"], e)
        elif e["type"] == "relation" and tags.get("type") == "site":
            site_entrances |= {
                m["ref"]
                for m in e.get("members", [])
                if m.get("type") == "node" and m.get("role") == "entrance"
            }

    door_ids = set(entrances)
    at_doors, roads = [], []
    for wid, e in ways.items():
        if wid in outline_way_ids:
            continue
        tags = _tags(e)
        way = Way(f"way/{wid}", tags, tuple(e.get("nodes", [])), _coords(e))
        if len(way.coords) < 2:
            continue
        if door_ids & set(way.nodes):
            at_doors.append(way)
        if tags.get("highway", "").removesuffix("_link") in road_pattern:
            roads.append(way)

    stamp = (raw.get("osm3s") or {}).get("timestamp_osm_base", "")[:10] or "unknown"
    return BuildingArea(outline_nodes, entrances, site_entrances, at_doors, roads, crossings, stamp)
