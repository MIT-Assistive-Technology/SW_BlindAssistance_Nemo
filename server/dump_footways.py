#!/usr/bin/env python3
"""Dump walkable OSM ways near each pilot bundle's entrance.

For hand-placing `route` polylines. Scans the cached Overpass fixtures, finds
every way tagged as walkable (footway, path, sidewalk, steps, crossing,
pedestrian, corridor, living_street) with at least one node within RADIUS_M
of the bundle's target entrance, and writes a readable file per site:

    server/route_work/<site>.txt

Each line group is one way: its OSM way id, highway tag, and [lon, lat]
geometry — the real path coordinates, ready to trace into a route.

Usage: python3 server/dump_footways.py
"""

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLES = ROOT / "server" / "bundles"
FIXTURES = ROOT / "server" / "tests" / "fixtures" / "overpass"
OUT = ROOT / "server" / "route_work"

RADIUS_M = 200.0
M_PER_DEG_LAT = 111_320.0
WALKABLE = {
    "footway", "path", "pedestrian", "steps", "sidewalk", "crossing",
    "living_street", "corridor", "track",
}
BAND_RANK = {"door": 0, "main": 1, "facade": 2}


def dist_m(a_lat, a_lon, b_lat, b_lon):
    dx = (b_lon - a_lon) * M_PER_DEG_LAT * math.cos(math.radians(a_lat))
    dy = (b_lat - a_lat) * M_PER_DEG_LAT
    return math.hypot(dx, dy)


def pick_entrance(candidates):
    if not candidates:
        return None
    return max(
        candidates,
        key=lambda c: (c.get("confidence", 0), -BAND_RANK.get(c.get("band"), 3)),
    )


def load_ways():
    """All ways from all fixtures: way_id -> {tags, geometry, nodes}."""
    ways = {}
    for path in sorted(FIXTURES.glob("*.json")):
        try:
            elements = json.loads(path.read_text()).get("response", {}).get(
                "elements", [])
        except json.JSONDecodeError:
            continue
        for e in elements:
            if e["type"] != "way":
                continue
            geom = e.get("geometry") or []
            if not geom:
                continue
            ways[e["id"]] = {
                "tags": e.get("tags") or {},
                "geometry": geom,
                "nodes": e.get("nodes") or [],
            }
    return ways


def main():
    ways = load_ways()
    print(f"loaded {len(ways)} ways from fixtures")
    OUT.mkdir(exist_ok=True)

    for bundle_path in sorted(BUNDLES.glob("*.json")):
        bundle = json.loads(bundle_path.read_text())
        entrance = pick_entrance(bundle.get("candidates") or [])
        name = bundle.get("destination_id", bundle_path.stem)
        if entrance is None:
            print(f"  {name}: no entrance, skipped")
            continue
        lat, lon = entrance["lat"], entrance["lon"]

        lines = [
            f"# {name}  door=({lat}, {lon})",
            f"# street={bundle.get('street_side', {}).get('entrance_street')} "
            f"door_side={bundle.get('street_side', {}).get('door_side_of_road')} "
            f"crossing={bundle.get('street_side', {}).get('crossing')} "
            f"crosses_road={bundle.get('path_checks', {}).get('crosses_road')}",
            "",
        ]
        seen = set()
        for wid, way in sorted(ways.items()):
            highway = way["tags"].get("highway")
            if highway not in WALKABLE:
                continue
            if way["tags"].get("foot") == "no":
                continue
            nearest = min(
                dist_m(lat, lon, g["lat"], g["lon"]) for g in way["geometry"])
            if nearest > RADIUS_M:
                continue
            seen.add(wid)
            lines.append(
                f"way/{wid}  highway={highway}  nearest={nearest:.0f}m  "
                f"name={way['tags'].get('name')}  surface={way['tags'].get('surface')}"
            )
            for g in way["geometry"]:
                d = dist_m(lat, lon, g["lat"], g["lon"])
                lines.append(f"  [{g['lon']}, {g['lat']}]   # {d:.0f}m")
            lines.append("")

        (OUT / f"{bundle_path.stem}.txt").write_text("\n".join(lines) + "\n")
        print(f"  {name}: {len(seen)} ways -> {bundle_path.stem}.txt")


if __name__ == "__main__":
    main()
