#!/usr/bin/env python3
"""Fill `route` in every pilot bundle.

Two tiers, best first:

1. FOOTWAY GRAPH (new). The server's Overpass fixtures
   (server/tests/fixtures/overpass/*.json) already contain every way touching
   each door — footways, paths, steps, sidewalks — plus roads and crossings.
   We build a graph of walkable ways and route the door back to the street
   through it, so the polyline follows paths a human mapper drew instead of
   straight-line guesses through buildings.

2. GEOMETRIC (fallback). Sidewalk offset from the centerline, straight to the
   door. Used when no walkable way connects — still correct on the door's
   side of the street, but a straight guess.

`path_checks.crosses_road` sites anchor at the marked crossing instead of the
sidewalk, so the only crossing happens where the bundle says it should.

These routes follow OSM path geometry — still worth a field walk, but they
respect buildings instead of drawing through them. Sites with no walkable
connection fall back or are skipped with a reason.

Writes both copies: server/bundles and app/nemo-software/Resources/PilotBundles.

Usage:
    python3 server/fill_routes.py            # fill/upgrade routes
    python3 server/fill_routes.py --force    # regenerate all
    python3 server/fill_routes.py --check    # print what it would do
"""

import json
import math
import sys
from heapq import heappop, heappush
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_BUNDLES = ROOT / "app" / "nemo-software" / "Resources" / "PilotBundles"
SERVER_BUNDLES = ROOT / "server" / "bundles"
FIXTURES = ROOT / "server" / "tests" / "fixtures" / "overpass"

M_PER_DEG_LAT = 111_320.0
APPROACH_M = 35.0       # geometric fallback: how far down the sidewalk to start
SIDEWALK_M = 7.0        # geometric fallback: centerline -> sidewalk offset
FAR_SIDE_M = 10.0       # geometric fallback: how far past the crossing to start
MIN_SEG_M = 2.0
SNAP_MAX_M = 25.0       # max distance to snap the door / target onto the graph
TARGET_MAX_M = 60.0     # only route to street-side targets within this of the door

# Ways a pedestrian may actually walk. Roads without foot=* stay out of the
# graph, so a route can never be drawn down the middle of Mass Ave.
WALKABLE = {
    "footway", "path", "pedestrian", "steps", "sidewalk", "crossing",
    "living_street", "corridor", "track",
}
BLOCKED_HIGHWAY = {"steps"} & set()  # steps allowed; flag separately later
BAND_RANK = {"door": 0, "main": 1, "facade": 2}


def to_m(lat, lon, origin):
    return (
        (lon - origin[1]) * M_PER_DEG_LAT * math.cos(math.radians(origin[0])),
        (lat - origin[0]) * M_PER_DEG_LAT,
    )


def to_geo(east, north, origin):
    lat = origin[0] + north / M_PER_DEG_LAT
    lon = origin[1] + east / (M_PER_DEG_LAT * math.cos(math.radians(origin[0])))
    return [round(lon, 7), round(lat, 7)]


def normalize(x, y):
    length = math.hypot(x, y)
    return (0.0, 0.0) if length == 0 else (x / length, y / length)


def pick_entrance(candidates):
    if not candidates:
        return None
    return max(
        candidates,
        key=lambda c: (c.get("confidence", 0), -BAND_RANK.get(c.get("band"), 3)),
    )


def nearest_on_centerline(line_lonlat, door_lat, door_lon):
    origin = (door_lat, door_lon)
    pts = [to_m(p[1], p[0], origin) for p in line_lonlat]
    best = None
    for i in range(len(pts) - 1):
        ax, ay = pts[i]
        bx, by = pts[i + 1]
        dx, dy = bx - ax, by - ay
        length2 = dx * dx + dy * dy
        t = 0.0 if length2 == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / length2))
        px, py = ax + t * dx, ay + t * dy
        d2 = px * px + py * py
        if best is None or d2 < best[0]:
            best = (d2, (px, py), normalize(dx, dy))
    if best is None:
        return None
    return best[1], best[2], math.sqrt(best[0])


# --------------------------------------------------------------------------
# Walkable graph from cached Overpass responses
# --------------------------------------------------------------------------

def load_walk_graph(fixture_dir):
    """Parse every cached Overpass response into a node graph.

    Nodes are (lat, lon) tuples keyed by OSM node id. Edges connect
    consecutive nodes of the same walkable way. Returns (nodes, adjacency,
    tags_by_node) or (None, None, None) if nothing usable is cached.
    """
    nodes = {}       # node_id -> (lat, lon)
    adj = {}         # node_id -> [(other_id, dist_m)]
    tags = {}        # way_id -> highway tag (for diagnostics)

    for path in sorted(fixture_dir.glob("*.json")):
        try:
            data = json.loads(path.read_text())
            elements = data.get("response", {}).get("elements", [])
        except (json.JSONDecodeError, KeyError):
            continue
        node_geo = {}  # way-scope: node id -> (lat, lon)
        for e in elements:
            if e["type"] == "node":
                node_geo[e["id"]] = (e["lat"], e["lon"])
        for e in elements:
            if e["type"] != "way":
                continue
            e_tags = e.get("tags") or {}
            highway = e_tags.get("highway")
            if highway not in WALKABLE:
                continue
            if e_tags.get("foot") == "no":
                continue
            ids = e.get("nodes") or []
            geom = e.get("geometry") or []
            # geometry[] aligns 1:1 with nodes[] for 'out body geom' responses
            coords = {}
            for nid, g in zip(ids, geom):
                coords[nid] = (g["lat"], g["lon"])
            tags[e["id"]] = highway
            for a, b in zip(ids, ids[1:]):
                pa = coords.get(a) or node_geo.get(a)
                pb = coords.get(b) or node_geo.get(b)
                if pa is None or pb is None:
                    continue
                nodes.setdefault(a, pa)
                nodes.setdefault(b, pb)
                ax, ay = to_m(pa[0], pa[1], pa)
                bx, by = to_m(pb[0], pb[1], pa)
                d = math.hypot(bx - ax, by - ay)
                adj.setdefault(a, []).append((b, d))
                adj.setdefault(b, []).append((a, d))

    if not nodes:
        return None, None, None
    return nodes, adj, tags


def snap(nodes, lat, lon, max_m):
    """Nearest graph node to (lat, lon) within max_m."""
    origin = (lat, lon)
    best = None
    for nid, (nlat, nlon) in nodes.items():
        x, y = to_m(nlat, nlon, origin)
        d2 = x * x + y * y
        if best is None or d2 < best[0]:
            best = (d2, nid)
    if best is None or math.sqrt(best[0]) > max_m:
        return None
    return best[1]


def dijkstra(nodes, adj, start, goal):
    """Shortest path start -> goal. Returns [node_id, ...] or None."""
    if start is None or goal is None:
        return None
    dist = {start: 0.0}
    prev = {}
    heap = [(0.0, start)]
    while heap:
        d, u = heappop(heap)
        if u == goal:
            break
        if d > dist.get(u, math.inf):
            continue
        for v, w in adj.get(u, []):
            nd = d + w
            if nd < dist.get(v, math.inf):
                dist[v] = nd
                prev[v] = u
                heappush(heap, (nd, v))
    if goal not in dist:
        return None
    path = [goal]
    while path[-1] != start:
        path.append(prev[path[-1]])
    path.reverse()
    return path


def graph_route(bundle, graph):
    """Route the door back to the street along walkable ways.

    The target is the marked crossing for crosses_road sites, else the
    sidewalk-side point nearest the door on the centerline.
    """
    nodes, adj, _ = graph
    entrance = pick_entrance(bundle.get("candidates") or [])
    street = bundle.get("street_side") or {}
    line = street.get("centerline") or []
    checks = bundle.get("path_checks") or {}
    if entrance is None or len(line) < 2:
        return None, "no entrance candidates" if entrance is None else "centerline missing"

    door = (entrance["lat"], entrance["lon"])
    start = snap(nodes, *door, SNAP_MAX_M)
    if start is None:
        return None, "no walkable way within 25 m of the door"

    if checks.get("crosses_road") and street.get("crossing"):
        goal = snap(nodes, street["crossing"][1], street["crossing"][0], SNAP_MAX_M)
        goal_label = "crossing"
    else:
        nearest = nearest_on_centerline(line, *door)
        if nearest is None:
            return None, "could not project door onto centerline"
        near_pt, _, off_axis = nearest
        if off_axis < 2.0:
            return None, "entrance on centerline; side unknown"
        sx, sy = normalize(-near_pt[0], -near_pt[1])
        sw = (near_pt[0] + sx * SIDEWALK_M, near_pt[1] + sy * SIDEWALK_M)
        sw_geo = to_geo(*sw, door)
        goal = snap(nodes, sw_geo[1], sw_geo[0], TARGET_MAX_M)
        goal_label = "sidewalk"
    if goal is None:
        return None, f"no walkable way within range of the {goal_label}"

    path = dijkstra(nodes, adj, start, goal)
    if path is None:
        return None, "walkable graph has no connected path door -> street"

    # Graph runs door -> street; the app wants street -> door.
    coords = [nodes[n] for n in reversed(path)]
    route = [[round(lon, 7), round(lat, 7)] for lat, lon in coords]
    if len(route) < 2:
        return None, "route collapsed"
    return route, None


# --------------------------------------------------------------------------
# Geometric fallback (unchanged logic)
# --------------------------------------------------------------------------

def geometric_route(bundle):
    entrance = pick_entrance(bundle.get("candidates") or [])
    street = bundle.get("street_side") or {}
    line = street.get("centerline") or []
    checks = bundle.get("path_checks") or {}
    if entrance is None:
        return None, "no entrance candidates"
    if len(line) < 2:
        return None, "centerline missing or too short"

    door = (entrance["lat"], entrance["lon"])
    nearest = nearest_on_centerline(line, *door)
    if nearest is None:
        return None, "could not project door onto centerline"
    near_pt, street_dir, off_axis = nearest
    if off_axis < 2.0:
        return None, "entrance sits on the centerline; can't tell sidewalk side"
    sx, sy = normalize(-near_pt[0], -near_pt[1])
    sidewalk = (near_pt[0] + sx * SIDEWALK_M, near_pt[1] + sy * SIDEWALK_M)

    route_m = []
    if checks.get("crosses_road"):
        crossing = street.get("crossing")
        if not crossing:
            return None, "crosses_road but no crossing point in bundle"
        cx, cy = to_m(crossing[1], crossing[0], door)
        route_m.append((cx - sx * FAR_SIDE_M, cy - sy * FAR_SIDE_M))
        route_m.append((cx, cy))
    else:
        route_m.append(
            (sidewalk[0] - street_dir[0] * APPROACH_M,
             sidewalk[1] - street_dir[1] * APPROACH_M)
        )
    route_m.append(sidewalk)
    route_m.append((0.0, 0.0))

    route, prev = [], None
    for pt in route_m:
        if prev is None or math.hypot(pt[0] - prev[0], pt[1] - prev[1]) >= MIN_SEG_M:
            route.append(to_geo(*pt, door))
            prev = pt
    if len(route) < 2:
        return None, "route collapsed to fewer than 2 points"
    return route, None


def route_length_m(route):
    total = 0.0
    for a, b in zip(route, route[1:]):
        bx, by = to_m(b[1], b[0], (a[1], a[0]))
        total += math.hypot(bx, by)
    return total


def load(path):
    return json.loads(path.read_text())


def main():
    force = "--force" in sys.argv
    check = "--check" in sys.argv
    filled = skipped = present = 0
    tiers = {"graph": 0, "geometric": 0}

    graph = load_walk_graph(FIXTURES)
    if graph[0] is None:
        print("no cached Overpass fixtures; geometric fallback only\n")
    else:
        n_nodes = len(graph[0])
        n_edges = sum(len(v) for v in graph[1].values()) // 2
        print(f"walkable graph: {n_nodes} nodes, {n_edges} edges\n")

    for app_path in sorted(APP_BUNDLES.glob("*.json")):
        if app_path.name == "pilot_sites.json":
            continue
        bundle = load(app_path)
        name = bundle.get("destination_id", app_path.stem)
        if bundle.get("route") and not force:
            present += 1
            continue

        route, reason, tier = None, None, None
        if graph[0] is not None:
            route, reason = graph_route(bundle, graph)
            tier = "graph"
        if route is None:
            route, geo_reason = geometric_route(bundle)
            tier = "geometric" if route else None
            if route is None:
                skipped += 1
                print(f"  SKIP  {name}: {reason or geo_reason}")
                continue
            reason = f"graph failed ({reason}); using geometric"

        if not check:
            bundle["route"] = route
            app_path.write_text(json.dumps(bundle, indent=2) + "\n")
            server_path = SERVER_BUNDLES / app_path.name
            if server_path.exists():
                sb = load(server_path)
                sb["route"] = route
                server_path.write_text(json.dumps(sb, indent=2) + "\n")

        filled += 1
        tiers[tier] += 1
        note = "" if tier == "graph" else f"  [{reason}]"
        print(f"  {'WOULD ' if check else ''}FILL  {name}: {tier}, "
              f"{len(route)} pts, {route_length_m(route):.0f} m{note}")

    print(f"\nfilled={filled} (graph={tiers['graph']}, geometric={tiers['geometric']}) "
          f"already_had_route={present} skipped={skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
