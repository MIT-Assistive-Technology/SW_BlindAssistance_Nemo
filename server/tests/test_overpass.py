"""app/overpass.py: query text, the cached client (no live network), and parsing."""

import json
import os
import time

import httpx
import pytest
from osm_builder import ORIGIN, Osm, save, xy

from app import overpass

# ---------------------------------------------------------------------------------------------
# Query builders
# ---------------------------------------------------------------------------------------------


def test_buildings_query_has_is_in_and_the_radius():
    q = overpass.buildings_query(42.36, -71.09)
    assert "is_in(42.3600000,-71.0900000)->.a;" in q
    assert "way(pivot.a)[building];" in q
    assert "rel(pivot.a)[building];" in q
    assert "way(around:40,42.3600000,-71.0900000)[building];" in q
    assert 'way(around:40,42.3600000,-71.0900000)["building:part"];' in q
    assert q.rstrip().endswith("out body geom;")


@pytest.mark.parametrize(
    "ref, line",
    [("way/123", "way(123)[building];"), ("relation/45", "rel(45)[building];")],
)
def test_buildings_query_fetches_nominatims_own_building(ref, line):
    assert line in overpass.buildings_query(42.36, -71.09, ref)


@pytest.mark.parametrize("ref", ["node/5", "way/abc", "nonsense", None])
def test_buildings_query_ignores_refs_that_are_not_buildings(ref):
    assert overpass.buildings_query(42.36, -71.09, ref) == overpass.buildings_query(42.36, -71.09)


def test_area_query_for_a_way_and_a_relation():
    bbox = (42.35, -71.1, 42.37, -71.08)
    way_q = overpass.area_query("way/9", bbox)
    rel_q = overpass.area_query("relation/9", bbox)
    assert way_q.splitlines()[1] == "way(9)->.b;"
    assert rel_q.splitlines()[1] == "rel(9)->.b;"
    # Only the relation needs its own record, for the outer members' ids.
    assert ".b out body;" in rel_q and ".b out body;" not in way_q
    for q in (way_q, rel_q):
        assert "node(around.outlines:5)[entrance];" in q
        assert "rel(br.b)[type=site]" in q and "rel(bw.outlines)[type=site]" in q
        assert "way(bn.ent)->.dw;" in q
        assert "rel(bw.dw)[building];" in q  # Fix R4: multipolygon neighbours
        assert "way(42.3500000,-71.1000000,42.3700000,-71.0800000)[highway~" in q
        assert "node(42.3500000,-71.1000000,42.3700000,-71.0800000)[highway=crossing];" in q
        # Fix R8: crossings tagged on traffic-signal nodes
        assert "node(42.3500000,-71.1000000,42.3700000,-71.0800000)[crossing];" in q


# Fix R13: crossings come from a box CROSSING_MAX_M wider than the road box, so a crossing up to
# 150 m from a drop-off anywhere in the road box can be returned.
def test_r13_crossing_box_covers_crossing_max_m_beyond_the_road_box():
    assert overpass.CROSSING_MARGIN_M >= overpass.AREA_MARGIN_M + overpass.CROSSING_MAX_M
    ring = [list(ORIGIN.lonlat(x, y)) for x, y in [(0, 0), (20, 0), (20, 10), (0, 0)]]
    q = overpass.area_query_for("way/9", [ring])
    road = ",".join(f"{v:.7f}" for v in overpass.bbox_around(ring))
    cross = ",".join(f"{v:.7f}" for v in overpass.bbox_around(ring, overpass.CROSSING_MARGIN_M))
    assert f"way({road})[highway~" in q
    assert f"node({cross})[highway=crossing];" in q and f"node({road})[highway" not in q


# Fix R5: the boxes cover every outer ring, not only the largest.
def test_r5_area_query_box_covers_every_ring():
    big = [list(ORIGIN.lonlat(x, y)) for x, y in [(0, 0), (40, 0), (40, 30), (0, 0)]]
    wing = [list(ORIGIN.lonlat(x, y)) for x, y in [(0, 200), (10, 200), (10, 210), (0, 200)]]
    q = overpass.area_query_for("relation/9", [big, wing])
    north = overpass.bbox_around(big + wing)[2]
    road_line = next(line for line in q.splitlines() if "[highway~" in line)
    assert f"{north:.7f}" in road_line  # the road box reaches past the wing


def test_bbox_around_grows_the_footprint_by_the_margin():
    square = [list(ORIGIN.lonlat(x, y)) for x, y in [(0, 0), (20, 0), (20, 10), (0, 10), (0, 0)]]
    south, west, north, east = overpass.bbox_around(square, margin_m=80)
    sw, ne = xy(west, south), xy(east, north)
    assert sw == pytest.approx((-80, -80), abs=0.5)
    assert ne == pytest.approx((100, 90), abs=0.5)


# ---------------------------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------------------------

QUERY = "[out:json];node(1);out;"
FRESH = {"elements": [{"type": "node", "id": 1, "lat": 1.0, "lon": 2.0}]}
OLD = {"elements": []}


@pytest.fixture
def user_agent(monkeypatch):
    monkeypatch.setenv("USER_AGENT", "car-to-curb-tests (test@example.org)")


def mock_client(tmp_path, responses, **kwargs):
    """A Client whose HTTP calls return `responses` in turn; records urls, sleeps, headers."""
    calls, sleeps = [], []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        return responses[len(calls) - 1]

    c = overpass.Client(
        cache_dir=tmp_path,
        offline=False,
        urls=("https://a.example/api", "https://b.example/api"),
        http=httpx.Client(transport=httpx.MockTransport(handler)),
        sleep=sleeps.append,
        **kwargs,
    )
    return c, calls, sleeps


def no_network(request):
    raise AssertionError("the client must not touch the network here")


def test_cache_hit_needs_no_network(tmp_path):
    c = overpass.Client(
        cache_dir=tmp_path,
        offline=False,
        http=httpx.Client(transport=httpx.MockTransport(no_network)),
    )
    save(c, QUERY, FRESH)
    assert c.run(QUERY) == FRESH


def test_stale_cache_is_refetched_and_rewritten(tmp_path, user_agent):
    c, calls, _ = mock_client(tmp_path, [httpx.Response(200, json=FRESH)])
    path = save(c, QUERY, OLD)
    old = time.time() - overpass.CACHE_MAX_AGE_S - 60
    os.utime(path, (old, old))
    assert c.run(QUERY) == FRESH
    assert len(calls) == 1
    assert json.loads(path.read_text(encoding="utf-8")) == {"query": QUERY, "response": FRESH}


def test_stale_cache_is_used_when_overpass_is_down(tmp_path, user_agent):
    c, calls, _ = mock_client(tmp_path, [httpx.Response(400)])
    path = save(c, QUERY, OLD)
    os.utime(path, (0, 0))
    assert c.run(QUERY) == OLD
    assert len(calls) == 1


def test_offline_reads_stale_cache_but_raises_on_a_miss(tmp_path):
    c = overpass.Client(cache_dir=tmp_path, offline=True)
    with pytest.raises(overpass.OverpassUnavailable, match="offline"):
        c.run(QUERY)
    os.utime(save(c, QUERY, OLD), (0, 0))
    assert c.run(QUERY) == OLD


def test_retries_rotate_mirrors_after_a_502(tmp_path, user_agent):
    c, calls, sleeps = mock_client(tmp_path, [httpx.Response(502), httpx.Response(200, json=FRESH)])
    assert c.run(QUERY) == FRESH
    assert [str(r.url) for r in calls] == ["https://a.example/api", "https://b.example/api"]
    assert overpass.RETRY_WAITS_S[0] in sleeps
    assert calls[0].headers["User-Agent"] == "car-to-curb-tests (test@example.org)"
    assert b"data=" in calls[0].content  # the query is POSTed as form field `data`
    assert c.path_for(QUERY).exists()


def test_a_200_with_an_error_remark_is_a_failure(tmp_path, user_agent):
    timeout = {"elements": [], "remark": "runtime error: Query timed out in line 3"}
    c, calls, _ = mock_client(
        tmp_path,
        [
            httpx.Response(200, json=timeout),
            httpx.Response(200, text="<html>busy</html>"),
            httpx.Response(200, json=FRESH),
        ],
    )
    assert c.run(QUERY) == FRESH
    assert len(calls) == 3


def test_gives_up_after_all_retries(tmp_path, user_agent):
    n = len(overpass.RETRY_WAITS_S) + 1
    c, calls, _ = mock_client(tmp_path, [httpx.Response(504)] * n)
    with pytest.raises(overpass.OverpassUnavailable, match="HTTP 504"):
        c.run(QUERY)
    assert len(calls) == n
    assert not c.path_for(QUERY).exists()


def test_a_bad_request_is_not_retried(tmp_path, user_agent):
    c, calls, _ = mock_client(tmp_path, [httpx.Response(400)])
    with pytest.raises(overpass.OverpassUnavailable, match="HTTP 400"):
        c.run(QUERY)
    assert len(calls) == 1


def test_user_agent_is_required(tmp_path, monkeypatch):
    monkeypatch.delenv("USER_AGENT", raising=False)
    c, calls, _ = mock_client(tmp_path, [])
    with pytest.raises(RuntimeError, match="USER_AGENT"):
        c.run(QUERY)
    assert calls == []


# Fix R9: a missing USER_AGENT blocks only live queries; a stale saved answer is still used.
def test_r9_stale_cache_is_used_without_a_user_agent(tmp_path, monkeypatch):
    monkeypatch.delenv("USER_AGENT", raising=False)
    c, calls, _ = mock_client(tmp_path, [])
    os.utime(save(c, QUERY, OLD), (0, 0))
    assert c.run(QUERY) == OLD
    assert calls == []


# ---------------------------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------------------------


def square(osm: Osm, first_id: int, x0: float, y0: float, size: float) -> list[int]:
    """Node ids of a closed counter-clockwise square."""
    ids = osm.path(first_id, [(x0, y0), (x0 + size, y0), (x0 + size, y0 + size), (x0, y0 + size)])
    return ids + ids[:1]


def test_parse_buildings_way_relation_and_part():
    osm = Osm()
    osm.way(1, square(osm, 100, 0, 0, 10), building="yes", name="Way building")
    # Multipolygon: its outer ring is split across two member ways, one of them reversed.
    a, b, c, d = osm.path(200, [(50, 0), (70, 0), (70, 20), (50, 20)])
    osm.way(21, [a, b, c], out=False)
    osm.way(22, [a, d, c], out=False)  # runs the "wrong" way, as members often do
    osm.way(23, square(osm, 300, 55, 5, 5), out=False)  # courtyard
    osm.rel(
        2,
        [("way", 21, "outer"), ("way", 22, "outer"), ("way", 23, "inner")],
        type="multipolygon",
        building="yes",
    )
    osm.way(3, square(osm, 400, 2, 2, 4), **{"building:part": "yes"})
    osm.way(4, osm.path(500, [(0, 50), (10, 50), (10, 60)]), building="yes")  # not closed
    osm.node(5, 1, 1, entrance="main")

    got = {o.ref: o for o in overpass.parse_buildings(osm.response())}
    assert set(got) == {"way/1", "relation/2", "way/3"}
    assert got["way/1"].tags["name"] == "Way building" and not got["way/1"].is_part
    assert got["way/3"].is_part
    rel = got["relation/2"]
    assert len(rel.rings) == 1  # the inner ring is not an outline
    ring = [xy(*p) for p in rel.footprint]
    assert ring[0] == ring[-1] and len(ring) == 5
    assert {(round(x), round(y)) for x, y in ring} == {(50, 0), (70, 0), (70, 20), (50, 20)}


def test_join_rings_handles_every_orientation_and_drops_open_rings():
    p = [(0, 0), (1, 0), (1, 1), (0, 1)]
    ring = overpass.join_rings([[p[1], p[2]], [p[0], p[1]], [p[0], p[3]], [p[3], p[2]]])
    assert len(ring) == 1 and ring[0][0] == ring[0][-1] and set(ring[0]) == set(p)
    assert overpass.join_rings([[p[0], p[1], p[2]]]) == []
    two = overpass.join_rings([p + p[:1], [(5, 5), (6, 5), (6, 6), (5, 5)]])
    assert len(two) == 2


def test_parse_area_relation_outline_nodes_and_ways():
    osm = Osm()
    a, b, c, d = osm.path(200, [(0, 0), (20, 0), (20, 20), (0, 20)])
    door = osm.node(250, 10, 0, entrance="main")
    osm.rel(
        2,
        [
            ("way", osm.way(21, [a, door, b, c], out=False), "outer"),
            ("way", osm.way(22, [c, d, a], out=False), "outer"),
        ],
        type="multipolygon",
        building="yes",
    )
    osm.way(21, [a, door, b, c])
    osm.way(22, [c, d, a])
    osm.node(251, 30, -20, highway="crossing", crossing="marked")
    foot = osm.node(260, 10, -15, out=False)
    osm.way(30, [door, foot], highway="footway")
    road = osm.path(270, [(-50, -10), (50, -10)])
    osm.way(31, road, highway="residential", name="Main Street")
    osm.way(32, road, highway="footway", footway="sidewalk")  # not a road

    got = overpass.parse_area(osm.response(), "relation/2")
    assert got.outline_nodes == {a, b, c, d, door}
    assert set(got.entrances) == {door}
    assert [w.ref for w in got.ways_at_doors] == ["way/30"]
    assert [w.ref for w in got.roads] == ["way/31"]
    assert [c["id"] for c in got.crossings] == [251]
    assert got.osm_date == "2026-10-01"


# Fix R8 (crossing=* on a traffic-signals node) and Fix R4 (a neighbour's multipolygon outers).
def test_r4_r8_parse_area_signal_crossings_and_neighbour_relations():
    osm = Osm()
    osm.way(1, square(osm, 100, 0, 0, 10), building="yes")
    osm.node(5, 20, -10, highway="traffic_signals", crossing="traffic_signals")
    osm.way(41, square(osm, 200, 13, 0, 10), out=False)
    osm.rel(40, [("way", 41, "outer")], type="multipolygon", building="yes")
    got = overpass.parse_area(osm.response(), "way/1")
    assert [c["id"] for c in got.crossings] == [5]
    assert got.other_building_ways == {41}
    assert overpass.parse_area(osm.response(), "relation/40").other_building_ways == set()
