"""Ladder steps 2, 3 and 5 plus path checks: building, doors, facade, street side (BE-3/5/7).

docs/car-to-curb-plan.md sections 6, 8 and 9. Map data comes from app/overpass.py (two cached
queries per destination); scoring rules from app/scoring.py. Every function takes plain models
so app/bundle.py can run them as stages, and tests can feed saved Overpass responses.
"""

import functools
import math
import re

from . import overpass
from .geo import Frame, XY, closest_on_line, door_side_of_road, inside, line_crosses
from .models import Building, Candidate, PathChecks, Provenance, Speak, StreetSide
from .resolver import GeocodedPoint
from .scoring import ADDRESS_POINT, FACADE_FALLBACK, score_door

SAME_NUMBER_M = 30  # plan section 8: a building with the house number within 30 m
CENTERLINE_KEEP_M = 60  # street_side centerline: this far either side of the door (I-12)
CURB_OFFSET_M = 6  # expected drop-off: this far from the centerline toward the door
CROSSING_MAX_M = 150  # farther than this, "nearest marked crossing" is no help
NOT_A_ROAD = {"driveway", "parking_aisle", "drive-through"}  # service=*: separate warning class
UNMARKED = {"unmarked", "no", "informal"}
FOOTWAYS = {"footway", "path", "pedestrian", "steps", "corridor", "cycleway"}

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
    else the nearest."""
    raw = client().run(overpass.buildings_query(point.lat, point.lon, point.osm_ref))
    outlines = overpass.parse_buildings(raw)
    if not outlines:
        raise LookupError("no building outline at or within 40 m of the address")
    f = Frame(point.lat, point.lon)
    here = (0.0, 0.0)

    def rings_xy(o: overpass.Outline) -> list[list[XY]]:
        return [[f.xy(*p) for p in ring[:-1]] for ring in o.rings]

    def wall_distance(o: overpass.Outline) -> float:
        return min(closest_on_line(here, ring + ring[:1])[0] for ring in rings_xy(o))

    def size(o: overpass.Outline) -> float:
        from .geo import area

        return area(rings_xy(o)[0])

    containing = [o for o in outlines if any(inside(here, r) for r in rings_xy(o))]
    chosen = min(containing, key=lambda o: (o.is_part, size(o))) if containing else None
    if chosen is None and point.osm_ref:
        chosen = next((o for o in outlines if o.ref == point.osm_ref), None)
    if chosen is None:
        near = sorted(outlines, key=lambda o: (o.is_part, wall_distance(o)))
        same_number = [
            o
            for o in near
            if point.housenumber
            and o.tags.get("addr:housenumber") == point.housenumber
            and wall_distance(o) <= SAME_NUMBER_M
        ]
        chosen = (same_number or near)[0]
    return Building(
        osm_id=chosen.ref,
        name=chosen.tags.get("name"),
        housenumber=chosen.tags.get("addr:housenumber"),
        footprint=[[lon, lat] for lon, lat in chosen.footprint],
    )


@functools.lru_cache(maxsize=64)
def _area(osm_id: str, footprint: tuple[tuple[float, float], ...]) -> overpass.BuildingArea:
    query = overpass.area_query(osm_id, overpass.bbox_around([list(p) for p in footprint]))
    return overpass.parse_area(client().run(query), osm_id)


def area_for(building: Building) -> overpass.BuildingArea:
    return _area(building.osm_id, tuple((p[0], p[1]) for p in building.footprint))


# ---------------------------------------------------------------------------------------------
# Step 3: read and score the doors (BE-3 rules, BE-4 scores)
# ---------------------------------------------------------------------------------------------


def _label(tags: dict[str, str]) -> str:
    values = [v.strip() for v in tags.get("entrance", "").split(";")]
    kind = (
        "Main entrance"
        if "main" in values or "routing:entrance" in tags
        else "Side entrance"
        if "secondary" in values
        else "Service door"
        if "service" in values
        else "Door"
    )
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

    A node within 5 m that belongs to ANOTHER building's outline is that building's door
    (row houses share walls), so it is skipped.
    """
    a = area_for(building)
    other_buildings = {
        n for w in a.ways_at_doors if "building" in w.tags or "building:part" in w.tags
        for n in w.nodes
    }
    footway_nodes = {
        n for w in a.ways_at_doors if w.tags.get("highway") in FOOTWAYS for n in w.nodes
    }
    out = []
    for node_id, e in sorted(a.entrances.items()):
        on_outline = node_id in a.outline_nodes
        if not on_outline and (node_id in other_buildings):
            continue
        tags = e["tags"]
        score = score_door(
            tags,
            dest_housenumber,
            on_outline=on_outline,
            has_footway=node_id in footway_nodes,
            site_entrance=node_id in a.site_entrances,
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
                label=_label(tags),
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
    return re.sub(r"[^a-z0-9 ]", "", name.lower()).strip()


def _street_name(point: GeocodedPoint) -> str | None:
    """'77 Massachusetts Avenue' -> 'massachusetts avenue'."""
    if not point.street:
        return None
    return _norm(re.sub(r"^\s*\d+[a-z]?(?:-\d+[a-z]?)?\s+", "", point.street, flags=re.I))


def entrance_street(
    a: overpass.BuildingArea, f: Frame, target: XY, street: str | None
) -> overpass.Way | None:
    """The address's street if it is mapped nearby, else the nearest named through road."""
    roads = [w for w in a.roads if _is_road(w)]

    def dist(w: overpass.Way) -> float:
        return closest_on_line(target, [f.xy(*p) for p in w.coords])[0]

    if street:
        same = [w for w in roads if _norm(w.tags.get("name", "")) == street]
        if same:
            return min(same, key=dist)
    named = [w for w in roads if w.tags.get("name") and w.tags.get("highway") != "service"]
    pool = named or roads
    return min(pool, key=dist) if pool else None


def _clip(pts: list[XY], idx: int, q: XY, keep: float) -> list[XY]:
    """The polyline within `keep` meters (along it) either side of q, which is on segment idx."""
    back, d, i = [q], 0.0, idx
    while i >= 0 and d < keep:
        d += math.dist(back[-1], pts[i])
        back.append(pts[i])
        i -= 1
    fwd, d, i = [q], 0.0, idx + 1
    while i < len(pts) and d < keep:
        d += math.dist(fwd[-1], pts[i])
        fwd.append(pts[i])
        i += 1
    line = back[:0:-1] + fwd
    return [p for k, p in enumerate(line) if k == 0 or p != line[k - 1]]


def street_side(a: overpass.BuildingArea, door: Candidate, street: str | None) -> StreetSide | None:
    """The street_side block for `door`. The centerline is clipped to 60 m either side of the
    door, so a long or curved way still gives the local road direction (E2E I-12)."""
    f = Frame(door.lat, door.lon)
    here = (0.0, 0.0)
    road = entrance_street(a, f, here, street)
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


def facade_fallback(building: Building, point: GeocodedPoint) -> dict:
    """The middle of the street-facing side (0.30), then the address point (0.20), plus the
    street_side block for the best door (or the facade when there is no door).

    The address point is snapped to the nearest wall: Nominatim often returns a point deep
    inside the building, and guiding to it would point through walls (E2E I-11).
    """
    a = area_for(building)
    street = _street_name(point)
    f = Frame(building.footprint[0][1], building.footprint[0][0])
    ring = [f.xy(lon, lat) for lon, lat in building.footprint]
    edges = [(p, q) for p, q in zip(ring, ring[1:], strict=False) if p != q]
    centroid = (sum(x for x, _ in ring[:-1]) / (len(ring) - 1),
                sum(y for _, y in ring[:-1]) / (len(ring) - 1))
    candidates = []

    road = entrance_street(a, f, centroid, street)
    if road is not None and edges:
        rpts = [f.xy(*p) for p in road.coords]

        def facing(edge: tuple[XY, XY]) -> tuple[float, float]:
            mid = ((edge[0][0] + edge[1][0]) / 2, (edge[0][1] + edge[1][1]) / 2)
            # Nearest wall to the street; among near-ties prefer the longer wall (the front).
            return (round(closest_on_line(mid, rpts)[0] / 3), -math.dist(*edge))

        p, q = min(edges, key=facing)
        lon, lat = f.lonlat((p[0] + q[0]) / 2, (p[1] + q[1]) / 2)
        name = road.tags.get("name")
        candidates.append(
            Candidate(
                id="facade",
                lat=lat,
                lon=lon,
                confidence=FACADE_FALLBACK,
                band="facade",
                label=f"Street-facing side on {name} (approximate)" if name
                else "Street-facing side (approximate)",
                provenance=[Provenance(source="geometry_fallback", ref=road.ref)],
            )
        )

    addr = f.xy(point.lon, point.lat)
    if inside(addr, ring[:-1]) and edges:
        addr = closest_on_line(addr, ring)[1]
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
    anchor = max(doors, key=lambda c: c.confidence) if doors else candidates[0]
    return {"candidates": candidates, "street_side": street_side(a, anchor, street)}


# ---------------------------------------------------------------------------------------------
# Path checks (BE-7)
# ---------------------------------------------------------------------------------------------


def _marked(crossing: dict) -> bool:
    t = crossing["tags"]
    return t.get("crossing") not in UNMARKED and t.get("crossing:markings") != "no"


def path_checks(building: Building, door: Candidate, side: StreetSide | None) -> PathChecks:
    """From the expected drop-off (the entrance street's curb nearest the door) to the door:
    does the straight line cross another road? If so, the nearest marked crossing.

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
        marked = [c for c in a.crossings if _marked(c)]
        best = min(marked, key=lambda c: math.dist(start, f.xy(c["lon"], c["lat"])), default=None)
        if best is not None and math.dist(start, f.xy(best["lon"], best["lat"])) <= CROSSING_MAX_M:
            nearest = [best["lon"], best["lat"]]

    node_id = next(
        (int(p.ref.split("/")[1]) for p in door.provenance
         if p.source == "osm_tag" and p.ref and p.ref.startswith("node/")),
        None,
    )
    footway = node_id is not None and any(
        w.tags.get("highway") in FOOTWAYS and node_id in w.nodes for w in a.ways_at_doors
    )
    return PathChecks(crosses_road=crosses, nearest_crossing=nearest, footway_to_entrance=footway)
