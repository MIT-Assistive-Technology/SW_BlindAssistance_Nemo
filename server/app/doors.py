"""Ladder steps 2, 3 and 5 plus path checks: building, doors, facade, street side (BE-3/5/7).

docs/car-to-curb-plan.md sections 6, 8 and 9. Map data comes from app/overpass.py (two cached
queries per destination); scoring rules from app/scoring.py. Every function takes plain models
so app/bundle.py can run them as stages, and tests can feed saved Overpass responses.
"""

import functools
import itertools
import math
import re

from . import overpass
from .geo import (
    XY,
    Frame,
    area,
    closest_on_line,
    closest_on_segment,
    door_side_of_road,
    inside,
    line_crosses,
)
from .models import Building, Candidate, PathChecks, Provenance, Speak, StreetSide
from .resolver import GeocodedPoint
from .scoring import ADDRESS_POINT, FACADE_FALLBACK, score_door

SAME_NUMBER_M = 30  # plan section 8: a building with the house number within 30 m
CENTERLINE_KEEP_M = 60  # street_side centerline: this far either side of the door (I-12)
CURB_OFFSET_M = 6  # expected drop-off: this far from the centerline toward the door
CROSSING_MAX_M = 150  # farther than this, "nearest marked crossing" is no help
NOT_A_ROAD = {"driveway", "parking_aisle", "drive-through"}  # service=*: separate warning class
# crossing=* values that mean paint on the road. A bare highway=crossing is not assumed marked.
MARKED = {"marked", "zebra", "uncontrolled", "traffic_signals"}
FOOTWAYS = {"footway", "path", "pedestrian", "steps", "corridor", "cycleway"}

STRAIGHT_COS = math.cos(math.radians(15))  # consecutive edges this straight form one wall
FACING_COS = 0.5  # a wall (or door) faces a road within 60 degrees of its outward normal
FRONT_TOLERANCE_M = 3  # walls up to this much farther from the street than the nearest compete
# Street-type abbreviations, so "77 Massachusetts Ave." matches OSM's "Massachusetts Avenue".
STREET_WORDS = {
    "ave": "avenue",
    "av": "avenue",
    "st": "street",
    "rd": "road",
    "blvd": "boulevard",
    "pl": "place",
    "sq": "square",
    "dr": "drive",
    "ct": "court",
    "ln": "lane",
    "pkwy": "parkway",
    "hwy": "highway",
    "ter": "terrace",
    "terr": "terrace",
    "cir": "circle",
    "n": "north",
    "s": "south",
    "e": "east",
    "w": "west",
}

# Tests replace this with overpass.Client(cache_dir=fixtures, offline=True).
CLIENT: overpass.Client | None = None


def client() -> overpass.Client:
    global CLIENT
    if CLIENT is None:
        CLIENT = overpass.Client()
    return CLIENT


# ---------------------------------------------------------------------------------------------
# Step 2: find the building (BE-3)
# ---------------------------------------------------------------------------------------------


def find_building(point: GeocodedPoint) -> Building:
    """The outline containing the point (a whole building before a building:part, then the
    smallest), else Nominatim's own building, else one with the house number within 30 m,
    else the nearest (whole buildings before parts)."""
    raw = client().run(overpass.buildings_query(point.lat, point.lon, point.osm_ref))
    outlines = overpass.parse_buildings(raw)
    if not outlines:
        raise LookupError("no building outline at or within 40 m of the address")
    f = Frame(point.lat, point.lon)
    here = (0.0, 0.0)
    rings = {o.ref: [[f.xy(*p) for p in ring] for ring in o.rings] for o in outlines}

    def wall_distance(o: overpass.Outline) -> float:
        return min(closest_on_line(here, ring)[0] for ring in rings[o.ref])

    containing = [o for o in outlines if any(inside(here, r[:-1]) for r in rings[o.ref])]
    chosen = (
        min(containing, key=lambda o: (o.is_part, area(rings[o.ref][0][:-1])))
        if containing
        else None
    )
    if chosen is None and point.osm_ref:
        chosen = next((o for o in outlines if o.ref == point.osm_ref), None)
    if chosen is None:
        near = sorted(outlines, key=lambda o: (o.is_part, wall_distance(o)))
        same_number = [
            o
            for o in near
            if point.housenumber
            and point.housenumber in _numbers(o.tags)
            and wall_distance(o) <= SAME_NUMBER_M
        ]
        chosen = (same_number or near)[0]
    return Building(
        osm_id=chosen.ref,
        name=chosen.tags.get("name"),
        housenumber=chosen.tags.get("addr:housenumber"),
        footprint=[[lon, lat] for lon, lat in chosen.footprint],
    )


def _numbers(tags: dict[str, str]) -> set[str]:
    """addr:housenumber may list several numbers: "77;79"."""
    return {n.strip() for n in tags.get("addr:housenumber", "").split(";") if n.strip()}


@functools.lru_cache(maxsize=64)
def _area(osm_id: str, footprint: tuple[tuple[float, float], ...]) -> overpass.BuildingArea:
    query = overpass.area_query(osm_id, overpass.bbox_around([list(p) for p in footprint]))
    return overpass.parse_area(client().run(query), osm_id)


def area_for(building: Building) -> overpass.BuildingArea:
    return _area(building.osm_id, tuple((p[0], p[1]) for p in building.footprint))


# ---------------------------------------------------------------------------------------------
# Step 3: read and score the doors (BE-3 rules, BE-4 scores)
# ---------------------------------------------------------------------------------------------


def _label(tags: dict[str, str], main: bool = False) -> str:
    values = [v.strip() for v in tags.get("entrance", "").split(";")]
    if main or "main" in values or "routing:entrance" in tags:
        kind = "Main entrance"
    elif "secondary" in values:
        kind = "Side entrance"
    elif "service" in values:
        kind = "Service door"
    else:
        kind = "Door"
    name = tags.get("name") or tags.get("ref")
    return f"{kind} ({name})" if name else kind


def _speak(tags: dict[str, str]) -> Speak | None:
    steps = tags.get("step_count", "")
    speak = Speak(
        door=tags.get("door"),
        automatic_door=tags.get("automatic_door"),
        step_count=int(steps) if steps.isdigit() else None,
    )
    return speak if any(v is not None for v in speak.model_dump().values()) else None


def read_entrances(building: Building, dest_housenumber: str | None) -> list[Candidate]:
    """Door nodes on the outline, or within 5 m of it (-0.10), scored with score_door.

    A node off our outline that is on ANOTHER building's outline is that building's door
    (row houses share walls), so it is skipped. building:part ways don't count as another
    building: they are usually parts of this one.
    """
    a = area_for(building)
    other_buildings = {n for w in a.ways_at_doors if "building" in w.tags for n in w.nodes}
    footway_nodes = {
        n for w in a.ways_at_doors if w.tags.get("highway") in FOOTWAYS for n in w.nodes
    }
    out = []
    for node_id, e in sorted(a.entrances.items()):
        on_outline = node_id in a.outline_nodes
        if not on_outline and node_id in other_buildings:
            continue
        tags = e["tags"]
        site = node_id in a.site_entrances
        score = score_door(
            tags,
            dest_housenumber,
            on_outline=on_outline,
            has_footway=node_id in footway_nodes,
            site_entrance=site,
        )
        if score is None:
            continue
        out.append(
            Candidate(
                id=f"osm{node_id}",
                lat=e["lat"],
                lon=e["lon"],
                confidence=score,
                band="door",  # bundle.rank() sets the band from the score
                label=_label(tags, main=site),
                speak=_speak(tags),
                provenance=[Provenance(source="osm_tag", ref=f"node/{node_id}", tags=tags)],
            )
        )
    return out


# ---------------------------------------------------------------------------------------------
# Step 5: facade fallback and street side (BE-5)
# ---------------------------------------------------------------------------------------------


def _is_road(w: overpass.Way) -> bool:
    return w.tags.get("service") not in NOT_A_ROAD and w.tags.get("area") != "yes"


def _norm(name: str) -> str:
    """'Massachusetts Ave.' and 'Massachusetts Avenue' -> 'massachusetts avenue'."""
    words = re.sub(r"[^a-z0-9 ]", " ", name.lower()).split()
    return " ".join(STREET_WORDS.get(w, w) for w in words)


def _street_name(point: GeocodedPoint) -> str | None:
    """'77 Massachusetts Ave' -> 'massachusetts avenue'."""
    if not point.street:
        return None
    name = re.sub(r"^\s*\d+[a-z]?(?:-\d+[a-z]?)?\s+", "", point.street, flags=re.I)
    return _norm(name) or None


def _ring_xy(f: Frame, footprint: list[list[float]]) -> list[XY]:
    """The footprint in local meters: closed, without repeated points."""
    pts = [f.xy(lon, lat) for lon, lat in footprint]
    ring = [p for k, p in enumerate(pts) if k == 0 or p != pts[k - 1]]
    if ring and ring[0] != ring[-1]:
        ring.append(ring[0])
    return ring


def _is_ccw(ring: list[XY]) -> bool:
    return sum(a[0] * b[1] - b[0] * a[1] for a, b in itertools.pairwise(ring)) > 0


def _outward(a: XY, b: XY, ccw: bool) -> XY:
    """Unit normal of edge a-b pointing out of a ring with the given orientation."""
    length = math.dist(a, b)
    dx, dy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
    return (dy, -dx) if ccw else (-dy, dx)


def _mid(w: tuple[XY, XY]) -> XY:
    return ((w[0][0] + w[1][0]) / 2, (w[0][1] + w[1][1]) / 2)


def _walls(ring: list[XY]) -> list[tuple[XY, XY]]:
    """Straight walls of a closed ring as (start, end). Consecutive edges within 15 degrees
    are merged, so a front wall split by door or party-wall nodes has one midpoint."""
    edges = list(itertools.pairwise(ring))

    def straight(e1: tuple[XY, XY], e2: tuple[XY, XY]) -> bool:
        u = (e1[1][0] - e1[0][0], e1[1][1] - e1[0][1])
        v = (e2[1][0] - e2[0][0], e2[1][1] - e2[0][1])
        return u[0] * v[0] + u[1] * v[1] > STRAIGHT_COS * math.hypot(*u) * math.hypot(*v)

    # Start at a corner, so the wall through the ring's first node is not cut in two.
    k = next((i for i in range(len(edges)) if not straight(edges[i - 1], edges[i])), 0)
    walls: list[tuple[XY, XY]] = []
    for e in edges[k:] + edges[:k]:
        if walls and straight(walls[-1], e):
            walls[-1] = (walls[-1][0], e[1])
        else:
            walls.append(e)
    return walls


def _wall_normal(ring: list[XY], p: XY) -> XY | None:
    """Outward normal of the wall at p, averaged over the walls meeting there (a corner door)."""
    if len(ring) < 4 or area(ring[:-1]) == 0:
        return None
    ccw = _is_ccw(ring)
    d0 = closest_on_line(p, ring)[0]
    nx = ny = 0.0
    for a, b in itertools.pairwise(ring):
        if closest_on_segment(p, a, b)[0] <= d0 + 0.5:
            n = _outward(a, b, ccw)
            nx, ny = nx + n[0], ny + n[1]
    size = math.hypot(nx, ny)
    return (nx / size, ny / size) if size > 1e-9 else None


def _faces(p: XY, normal: XY, pts: list[XY]) -> bool:
    """True if the nearest point of the polyline pts is in front of p (within 60 degrees)."""
    d, q, _ = closest_on_line(p, pts)
    return d > 0 and (q[0] - p[0]) * normal[0] + (q[1] - p[1]) * normal[1] >= FACING_COS * d


def entrance_street(
    a: overpass.BuildingArea, f: Frame, target: XY, street: str | None, normal: XY | None = None
) -> overpass.Way | None:
    """The road `target` faces. With `normal` (its wall's outward normal) only roads in front
    count when there are any, so a door on a corner building's side wall gets the side street
    (plan section 6: the entrance's street, not the address street). Among those: the
    address's street if mapped, else the nearest named through road, else the nearest road."""
    roads = [w for w in a.roads if _is_road(w)]
    xy = {w.ref: [f.xy(*p) for p in w.coords] for w in roads}
    if normal is not None:
        roads = [w for w in roads if _faces(target, normal, xy[w.ref])] or roads

    def dist(w: overpass.Way) -> float:
        return closest_on_line(target, xy[w.ref])[0]

    same = [w for w in roads if street and _norm(w.tags.get("name", "")) == street]
    named = [w for w in roads if w.tags.get("name") and w.tags.get("highway") != "service"]
    pool = same or named or roads
    return min(pool, key=dist) if pool else None


def _walk(start: XY, pts: list[XY], keep: float) -> list[XY]:
    """From start along pts for `keep` meters, cutting the last segment at exactly `keep`."""
    out, left = [start], keep
    for p in pts:
        d = math.dist(out[-1], p)
        if d >= left:
            t = left / d if d else 0.0
            last = out[-1]
            out.append((last[0] + (p[0] - last[0]) * t, last[1] + (p[1] - last[1]) * t))
            break
        out.append(p)
        left -= d
    return out


def _clip(pts: list[XY], idx: int, q: XY, keep: float) -> list[XY]:
    """The polyline within `keep` meters (along it) either side of q, which is on segment idx."""
    line = _walk(q, pts[idx::-1], keep)[:0:-1] + _walk(q, pts[idx + 1 :], keep)
    return [p for k, p in enumerate(line) if k == 0 or math.dist(p, line[k - 1]) > 1e-6]


def street_side(
    a: overpass.BuildingArea,
    door: Candidate,
    street: str | None,
    footprint: list[list[float]] | None = None,
) -> StreetSide | None:
    """The street_side block for `door`. Given the footprint, the street is the one the door's
    wall faces. The centerline is clipped to 60 m either side of the door, so a long or curved
    way still gives the local road direction (E2E I-12)."""
    f = Frame(door.lat, door.lon)
    here = (0.0, 0.0)
    normal = _wall_normal(_ring_xy(f, footprint), here) if footprint else None
    road = entrance_street(a, f, here, street, normal)
    if road is None:
        return None
    pts = [f.xy(*p) for p in road.coords]
    _, q, idx = closest_on_line(here, pts)
    line = _clip(pts, idx, q, CENTERLINE_KEEP_M)
    road_dir = (line[-1][0] - line[0][0], line[-1][1] - line[0][1])
    try:
        side = door_side_of_road(road_dir, (here[0] - q[0], here[1] - q[1]))
    except ValueError:
        return None
    return StreetSide(
        entrance_street=road.tags.get("name") or road.tags.get("ref") or road.ref,
        road_way=road.ref,
        centerline=[[round(c, 7) for c in f.lonlat(*p)] for p in line],
        door_side_of_road=side,
        oneway=road.tags.get("oneway") in {"yes", "1", "-1", "true"},
    )


def _has_number(c: Candidate, housenumber: str | None) -> bool:
    return bool(housenumber) and any(
        housenumber.strip() in _numbers(p.tags) for p in c.provenance if p.tags
    )


def facade_fallback(building: Building, point: GeocodedPoint) -> dict:
    """The middle of the street-facing wall (0.30), then the address point (0.20), plus the
    street_side block for the best door (or the facade when there is no door).

    The street-facing wall faces the address's street when it is mapped (a corner building's
    front is on its address street), else the nearest named road. An address point inside the
    building is snapped to that wall: Nominatim often returns a point deep inside, and guiding
    to it would point through walls (E2E I-11).
    """
    a = area_for(building)
    street = _street_name(point)
    f = Frame(building.footprint[0][1], building.footprint[0][0])
    ring = _ring_xy(f, building.footprint)
    usable = len(ring) >= 4 and area(ring[:-1]) > 1.0  # not a degenerate footprint
    candidates = []

    road = front = None
    if usable:
        n = len(ring) - 1
        centroid = (sum(x for x, _ in ring[:-1]) / n, sum(y for _, y in ring[:-1]) / n)
        road = entrance_street(a, f, centroid, street)
    if road is not None:
        rpts = [f.xy(*p) for p in road.coords]
        ccw = _is_ccw(ring)

        def dist(w: tuple[XY, XY]) -> float:
            return closest_on_line(_mid(w), rpts)[0]

        walls = _walls(ring)
        facing = [w for w in walls if _faces(_mid(w), _outward(*w, ccw), rpts)] or walls
        nearest = min(dist(w) for w in facing)
        # The front: the longest wall that faces the street and is about as near as any.
        front = max(
            (w for w in facing if dist(w) <= nearest + FRONT_TOLERANCE_M),
            key=lambda w: math.dist(*w),
        )
        lon, lat = f.lonlat(*closest_on_line(_mid(front), ring)[1])
        name = road.tags.get("name")
        candidates.append(
            Candidate(
                id="facade",
                lat=lat,
                lon=lon,
                confidence=FACADE_FALLBACK,
                band="facade",
                label=f"Street-facing side on {name} (approximate)"
                if name
                else "Street-facing side (approximate)",
                provenance=[Provenance(source="geometry_fallback", ref=road.ref)],
            )
        )

    addr = f.xy(point.lon, point.lat)
    if usable and inside(addr, ring[:-1]):
        addr = closest_on_line(addr, list(front) if front else ring)[1]
    lon, lat = f.lonlat(*addr)
    candidates.append(
        Candidate(
            id="addr",
            lat=lat,
            lon=lon,
            confidence=ADDRESS_POINT,
            band="facade",
            label="Address point (approximate)",
            provenance=[Provenance(source="geometry_fallback", ref=point.osm_ref)],
        )
    )

    doors = read_entrances(building, point.housenumber)
    # The best door; among equal scores the one with the destination's number, then the first.
    anchor = (
        min(doors, key=lambda c: (-c.confidence, not _has_number(c, point.housenumber)))
        if doors
        else candidates[0]
    )
    return {
        "candidates": candidates,
        "street_side": street_side(a, anchor, street, building.footprint),
    }


# ---------------------------------------------------------------------------------------------
# Path checks (BE-7)
# ---------------------------------------------------------------------------------------------


def _marked(crossing: dict) -> bool:
    t = crossing["tags"]
    if "crossing:markings" in t:
        return t["crossing:markings"] != "no"
    return t.get("crossing") in MARKED or t.get("crossing_ref") == "zebra"


def path_checks(building: Building, door: Candidate, side: StreetSide | None) -> PathChecks:
    """From the expected drop-off (the entrance street's curb nearest the door) to the door:
    does the straight line cross another road? If so, the nearest marked crossing within
    150 m of the drop-off.

    Driveways and parking aisles are not road crossings (plan section 8). The contract has no
    field yet for the driveway, through-the-building and off-the-sidewalk warnings.
    """
    a = area_for(building)
    f = Frame(door.lat, door.lon)
    here = (0.0, 0.0)
    crosses = False
    start = None
    if side is not None:
        cl = [f.xy(*p) for p in side.centerline]
        d, q, _ = closest_on_line(here, cl)
        k = min(CURB_OFFSET_M, d) / d if d > 0 else 0.0
        start = (q[0] + (here[0] - q[0]) * k, q[1] + (here[1] - q[1]) * k)
        crosses = any(
            line_crosses(start, here, [f.xy(*p) for p in w.coords])
            for w in a.roads
            if _is_road(w) and w.ref != side.road_way
        )

    nearest = None
    if crosses and start is not None:
        marked = [
            (math.dist(start, f.xy(c["lon"], c["lat"])), c) for c in a.crossings if _marked(c)
        ]
        dist, best = min(marked, key=lambda m: m[0], default=(math.inf, None))
        if best is not None and dist <= CROSSING_MAX_M:
            nearest = [best["lon"], best["lat"]]

    node_id = next(
        (
            int(p.ref.split("/")[1])
            for p in door.provenance
            if p.source == "osm_tag" and p.ref and p.ref.startswith("node/")
        ),
        None,
    )
    footway = node_id is not None and any(
        w.tags.get("highway") in FOOTWAYS and node_id in w.nodes for w in a.ways_at_doors
    )
    return PathChecks(crosses_road=crosses, nearest_crossing=nearest, footway_to_entrance=footway)
