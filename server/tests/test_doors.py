"""app/doors.py on hand-written Overpass responses (tests/osm_builder.py), all in local meters.

Done criteria from docs/car-to-curb-plan.md: BE-3 on a multipolygon building and a door=*-only
node, BE-5 on a corner building, BE-7 each path check on a fixture.
"""

import itertools
import math

import pytest
from osm_builder import Osm, lonlat, save, xy

from app import bundle, doors, geo, overpass
from app.models import Building, Candidate, DataVersion, Provenance
from app.resolver import GeocodedPoint


@pytest.fixture(autouse=True)
def offline_client(tmp_path):
    """Every test reads only the responses it saved; nothing touches the network."""
    doors.CLIENT = overpass.Client(cache_dir=tmp_path, offline=True)
    doors._area.cache_clear()
    yield doors.CLIENT
    doors.CLIENT = None
    doors._area.cache_clear()


def point(x: float, y: float, **kwargs) -> GeocodedPoint:
    lon, lat = lonlat(x, y)
    return GeocodedPoint(lat=lat, lon=lon, source="nominatim", precision="house", **kwargs)


def save_buildings(p: GeocodedPoint, osm: Osm) -> None:
    save(doors.CLIENT, overpass.buildings_query(p.lat, p.lon, p.osm_ref), osm.response())


def building(ref: str, corners: list[tuple[float, float]]) -> Building:
    ring = [list(lonlat(x, y)) for x, y in corners]
    return Building(osm_id=ref, footprint=ring + ring[:1])


def save_area(b: Building, osm: Osm) -> None:
    save(doors.CLIENT, doors.area_query(b), osm.response())
    save(doors.CLIENT, doors.paths_query(b), osm.response())


def at(c: Candidate | list[float]) -> tuple[float, float]:
    """Local meters of a candidate or a [lon, lat] pair."""
    return xy(c.lon, c.lat) if isinstance(c, Candidate) else xy(*c)


def box(osm: Osm, first_id: int, x0, y0, x1, y1) -> list[int]:
    """Closed counter-clockwise rectangle of new untagged nodes."""
    ids = osm.path(first_id, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
    return ids + ids[:1]


# ---------------------------------------------------------------------------------------------
# find_building (BE-3)
# ---------------------------------------------------------------------------------------------


def test_point_deep_inside_a_big_building_is_found(offline_client):
    # E2E I-1: CambridgeSide. The walls are 100 m away; is_in returns the outline anyway.
    osm = Osm()
    osm.way(1, box(osm, 10, -100, -100, 100, 100), building="retail", name="Mall")
    osm.way(2, box(osm, 20, 110, 0, 120, 10), building="yes")  # a small one, nearer to nothing
    p = point(0, 0)
    save_buildings(p, osm)
    b = doors.find_building(p)
    assert b.osm_id == "way/1" and b.name == "Mall"
    assert len(b.footprint) == 5 and b.footprint[0] == b.footprint[-1]


def test_containing_building_beats_a_containing_building_part():
    osm = Osm()
    osm.way(1, box(osm, 10, 0, 0, 30, 30), building="yes")
    osm.way(2, box(osm, 20, 5, 5, 15, 15), **{"building:part": "yes"})
    p = point(10, 10)
    save_buildings(p, osm)
    assert doors.find_building(p).osm_id == "way/1"


def test_smallest_containing_building_wins():
    osm = Osm()
    osm.way(1, box(osm, 10, 0, 0, 100, 100), building="yes")
    osm.way(2, box(osm, 20, 5, 5, 15, 15), building="yes")
    p = point(10, 10)
    save_buildings(p, osm)
    assert doors.find_building(p).osm_id == "way/2"


def test_multipolygon_building_contains_the_point():
    osm = Osm()
    a, b, c, d = osm.path(10, [(0, 0), (40, 0), (40, 30), (0, 30)])
    osm.way(11, [a, b, c], out=False)
    osm.way(12, [c, d, a], out=False)
    osm.rel(5, [("way", 11, "outer"), ("way", 12, "outer")], type="multipolygon", building="yes")
    osm.way(2, box(osm, 20, 45, 0, 50, 5), building="yes")  # nearer wall, but outside
    p = point(38, 2)
    save_buildings(p, osm)
    assert doors.find_building(p).osm_id == "relation/5"


def test_nominatims_building_is_used_when_no_outline_contains_the_point():
    osm = Osm()
    osm.way(1, box(osm, 10, 5, 0, 15, 10), building="yes")  # 5 m away
    osm.way(2, box(osm, 20, -30, 0, -20, 10), building="yes")  # 20 m away
    p = point(0, 5, osm_ref="way/2")
    save_buildings(p, osm)
    assert doors.find_building(p).osm_id == "way/2"


def test_house_number_within_30_m_beats_a_nearer_building():
    osm = Osm()
    osm.way(1, box(osm, 10, 5, 0, 15, 10), building="yes", **{"addr:housenumber": "75"})
    osm.way(2, box(osm, 20, -30, 0, -20, 10), building="yes", **{"addr:housenumber": "77;79"})
    p = point(0, 5, housenumber="77")
    save_buildings(p, osm)
    assert doors.find_building(p).osm_id == "way/2"


def test_house_number_farther_than_30_m_loses_to_the_nearest():
    osm = Osm()
    osm.way(1, box(osm, 10, 5, 0, 15, 10), building="yes")
    osm.way(2, box(osm, 20, -50, 0, -35, 10), building="yes", **{"addr:housenumber": "77"})
    p = point(0, 5, housenumber="77")
    save_buildings(p, osm)
    assert doors.find_building(p).osm_id == "way/1"


def test_nearest_whole_building_otherwise():
    osm = Osm()
    osm.way(1, box(osm, 10, 2, 0, 4, 2), **{"building:part": "yes"})  # nearest, but a part
    osm.way(2, box(osm, 20, 12, 0, 20, 10), building="yes")
    osm.way(3, box(osm, 30, -30, 0, -20, 10), building="yes")
    p = point(0, 1)
    save_buildings(p, osm)
    assert doors.find_building(p).osm_id == "way/2"


def test_no_outlines_is_a_lookup_error():
    p = point(0, 0)
    save_buildings(p, Osm())
    with pytest.raises(LookupError):
        doors.find_building(p)


# ---------------------------------------------------------------------------------------------
# read_entrances (BE-3 rules, BE-4 scores)
# ---------------------------------------------------------------------------------------------

# A 20 x 15 m building, way 100. Doors (node id: where, tags):
#   2  front wall      entrance=main
#   6  east wall       door=hinged only, with a footway to it
#   7  3 m in front    entrance=yes, near but not on the outline
#   8  west wall       entrance=exit             (excluded)
#   9  back wall       entrance=garage           (excluded)
#  11  back wall       amenity=loading_dock      (excluded)
#  13  neighbour's wall, 2 m from ours, entrance=main (the neighbour's door)
#  14  front wall      entrance=yes, role=entrance in a site relation
#  16  front wall      entrance=main;exit, addr:housenumber=77
FRONT = [(0, 0), (20, 0), (20, 15), (0, 15)]


def door_scene(as_relation: bool = False) -> tuple[Building, Osm]:
    osm = Osm()
    n1, n3, n4, n5 = osm.path(1000, FRONT)
    osm.node(2, 10, 0, entrance="main")
    osm.node(6, 20, 7, door="hinged")
    osm.node(7, 10, -3, entrance="yes")
    osm.node(8, 0, 7, entrance="exit")
    osm.node(9, 5, 15, entrance="garage")
    osm.node(11, 15, 15, amenity="loading_dock", entrance="yes")
    osm.node(13, -2, 5, entrance="main")
    osm.node(14, 15, 0, entrance="yes")
    osm.node(16, 5, 0, entrance="main;exit", **{"addr:housenumber": "77"})
    ring = [n1, 16, 2, 14, n3, 6, n4, 11, 9, n5, 8, n1]
    if as_relation:
        osm.way(101, ring[:7], out=False)
        osm.way(102, ring[6:], out=False)
        osm.rel(
            100, [("way", 101, "outer"), ("way", 102, "outer")], type="multipolygon", building="yes"
        )
        osm.way(101, ring[:7])
        osm.way(102, ring[6:])
        ref = "relation/100"
    else:
        osm.way(100, ring, building="yes")
        ref = "way/100"
    a, b, c = osm.path(1100, [(-12, 0), (-2, 0), (-2, 15)])
    osm.way(200, [a, b, 13, c, osm.node(1104, -12, 15, out=False), a], building="house")
    osm.rel(
        300,
        [("way" if not as_relation else "relation", 100, ""), ("node", 14, "entrance")],
        type="site",
    )
    osm.way(400, [6, osm.node(1200, 30, 7, out=False)], highway="footway")
    return building(ref, FRONT), osm


def scores(cands: list[Candidate]) -> dict[str, float]:
    return {c.id: c.confidence for c in cands}


@pytest.mark.parametrize("as_relation", [False, True], ids=["way", "multipolygon"])
def test_read_entrances_rules(as_relation):
    b, osm = door_scene(as_relation)
    save_area(b, osm)
    got = doors.read_entrances(b, "12")
    assert scores(got) == {
        "osm2": 0.90,  # main, on the outline
        "osm6": 0.80,  # door=* only counts as entrance=yes (0.75), +0.05 for the footway
        "osm7": 0.65,  # yes, within 5 m but not on the outline: -0.10
        "osm14": 0.90,  # site relation role=entrance counts as main
        "osm16": 0.90,  # main;exit keeps "main"
    }
    labels = {c.id: c.label for c in got}
    assert labels["osm14"] == "Main entrance" and labels["osm6"] == "Door"
    door6 = next(c for c in got if c.id == "osm6")
    assert door6.speak is not None and door6.speak.door == "hinged"
    assert door6.provenance[0].ref == "node/6"


def test_house_number_door_ranks_first():
    b, osm = door_scene()
    save_area(b, osm)
    assert scores(doors.read_entrances(b, "77"))["osm16"] == 0.95


# Fix R1: a site relation's entrance far from the building (a campus gate) is no door, and a
# site entrance tagged service is not lifted to "Main entrance".
def test_r1_far_site_entrance_is_dropped_and_service_site_entrance_is_not_main():
    b, osm = door_scene()
    osm.node(15, 10, -180, entrance="main")  # the campus gate, 180 m south, on a footway
    osm.way(401, [15, osm.node(1201, 10, -170, out=False)], highway="footway")
    for e in osm.elements:
        if e["type"] == "node" and e["id"] == 14:
            e["tags"]["entrance"] = "service"
        if e["type"] == "relation" and e["id"] == 300:
            e["members"].append({"type": "node", "ref": 15, "role": "entrance"})
    save_area(b, osm)
    got = {c.id: c for c in doors.read_entrances(b, None)}
    assert "osm15" not in got
    assert got["osm14"].confidence == 0.20 and got["osm14"].label == "Service door"
    assert got["osm2"].confidence == 0.90  # the real main door is untouched


# Fix R4: a neighbour mapped as a multipolygon has its tags on the relation; its outer way is
# untagged. Its door, 3 m from our wall, is not ours.
def test_r4_door_of_a_multipolygon_neighbour_is_skipped():
    osm = Osm()
    osm.way(1, box(osm, 10, 0, 0, 20, 20), building="yes")
    a, b_, c, d = osm.path(30, [(23, 0), (33, 0), (33, 20), (23, 20)])
    osm.node(40, 23, 10, entrance="main")
    osm.way(51, [a, b_, c, d, 40, a])  # the untagged outer way, as `way(bn.ent)` returns it
    osm.rel(50, [("way", 51, "outer")], type="multipolygon", building="yes")
    b = building("way/1", [(0, 0), (20, 0), (20, 20), (0, 20)])
    save_area(b, osm)
    assert doors.read_entrances(b, None) == []


def test_door_of_the_neighbouring_building_is_skipped_but_a_shared_wall_door_is_not():
    b, osm = door_scene()
    # Node 13 now also sits on our own outline: a door in a shared wall belongs to both.
    for e in osm.elements:
        if e["type"] == "way" and e["id"] == 100:
            e["nodes"].insert(-1, 13)
    save_area(b, osm)
    assert "osm13" in scores(doors.read_entrances(b, None))


# ---------------------------------------------------------------------------------------------
# facade_fallback and street_side (BE-5): a corner building
# ---------------------------------------------------------------------------------------------
#
#            Side Street (x = 31.5, runs north)
#   (0,20) +-------------+ (30,20)   |
#          |   building  |           |
#          |   way 500   * door 7    |    (east wall, only in some tests)
#   (0,0)  +----+--------+ (30,0)    |
#             (12,0) extra node on the front wall
#   ---------------------------------------  Main Street (y = -10, runs east)
#
# The address is "1 Main Street". Side Street is nearer the building's centre (17 m vs 18 m),
# so "the nearest road" would pick it; the front faces Main Street.

CORNER = [(0, 0), (12, 0), (30, 0), (30, 20), (0, 20)]


def corner_scene(
    door: bool = False,
    main: list[tuple[float, float]] | None = None,
    side: bool = True,
    roads: bool = True,
    outline: list[tuple[float, float]] = CORNER,
) -> tuple[Building, Osm]:
    osm = Osm()
    ids = osm.path(5000, outline)
    ring = ids[:3] + ([osm.node(7, 30, 10, entrance="main")] if door else []) + ids[3:]
    osm.way(500, ring + ids[:1], building="yes")
    if roads:
        osm.way(
            900,
            osm.path(9000, main or [(-100, -10), (150, -10)]),
            highway="residential",
            name="Main Street",
        )
        if side:
            osm.way(
                901,
                osm.path(9100, [(31.5, -100), (31.5, 100)]),
                highway="residential",
                name="Side Street",
                oneway="yes",
            )
    return building("way/500", outline), osm


def facade(b: Building, osm: Osm, street: str = "1 Main Street", where=(10, 10)) -> dict:
    save_area(b, osm)
    return doors.facade_fallback(b, point(*where, housenumber="1", street=street))


def test_facade_faces_the_address_street_not_the_nearest_road():
    b, osm = corner_scene()
    out = facade(b, osm)
    fac, addr = out["candidates"]
    assert fac.id == "facade" and fac.confidence == 0.30 and fac.band == "facade"
    # The middle of the whole front wall, not of one of its two pieces.
    assert at(fac) == pytest.approx((15, 0), abs=0.05)
    assert fac.label == "Street-facing side on Main Street (approximate)"
    assert fac.provenance[0].ref == "way/900"
    # E2E I-11: the address point (10, 10) is inside, so it is snapped to the front wall.
    assert addr.id == "addr" and addr.confidence == 0.20
    assert at(addr) == pytest.approx((10, 0), abs=0.05)


# Fix R16: the front is the LONGEST facing wall, not the nearest one (a bay window or porch).
def test_r16_front_is_the_longest_facing_wall_not_the_nearest():
    bay = [(0, 0), (10, 0), (10, -1), (14, -1), (14, 0), (30, 0), (30, 20), (0, 20)]
    b, osm = corner_scene(side=False, outline=bay)
    assert at(facade(b, osm)["candidates"][0]) == pytest.approx((22, 0), abs=0.05)


# Fix R16: a wall that does not face the street never becomes the front, even when it is long
# and near the street (the side wall of a wing that sticks out toward the road).
def test_r16_a_wall_that_does_not_face_the_street_is_never_the_front():
    wing = [(0, 0), (20, 0), (20, -6), (24, -6), (24, 0), (30, 0), (30, 20), (0, 20)]
    b, osm = corner_scene(side=False, outline=wing)
    assert at(facade(b, osm)["candidates"][0]) == pytest.approx((22, -6), abs=0.05)


@pytest.mark.parametrize("street", ["1 Main St.", "Main St", "1 main street"])
def test_street_abbreviations_match_osm_names(street):
    b, osm = corner_scene()
    assert at(facade(b, osm, street=street)["candidates"][0]) == pytest.approx((15, 0), abs=0.05)


def test_without_a_known_street_the_nearest_named_road_is_used():
    b, osm = corner_scene()
    fac = facade(b, osm, street="1 Unknown Road")["candidates"][0]
    assert at(fac) == pytest.approx((30, 10), abs=0.05)  # east wall, facing Side Street


def test_address_point_outside_the_building_is_kept():
    b, osm = corner_scene()
    addr = facade(b, osm, where=(10, -5))["candidates"][1]
    assert at(addr) == pytest.approx((10, -5), abs=0.05)


def test_street_side_for_the_facade_when_there_is_no_door():
    b, osm = corner_scene()
    side = facade(b, osm)["street_side"]
    assert side.entrance_street == "Main Street" and side.road_way == "way/900"
    assert side.door_side_of_road == "left"  # road runs east, the building is north of it
    assert side.oneway is False


def test_door_side_flips_with_the_centerline_direction():
    b, osm = corner_scene(main=[(150, -10), (-100, -10)])  # drawn westward
    assert facade(b, osm)["street_side"].door_side_of_road == "right"


def test_street_side_uses_the_street_the_door_faces():
    # Plan section 6, corner building: the door is on Side Street, not the address street.
    b, osm = corner_scene(door=True)
    side = facade(b, osm)["street_side"]
    assert side.entrance_street == "Side Street" and side.road_way == "way/901"
    assert side.door_side_of_road == "left"  # road runs north, the door is west of it
    assert side.oneway is True


def test_street_side_anchor_prefers_the_door_with_the_house_number():
    b, osm = corner_scene(door=True)
    # A second main door on the front wall. "1;3" is not an exact match, so both score 0.90;
    # only the tie-break looks inside the ";" list.
    osm.node(8, 20, 0, entrance="main", **{"addr:housenumber": "1;3"})
    for e in osm.elements:
        if e["type"] == "way" and e["id"] == 500:
            e["nodes"].insert(2, 8)
    out = facade(b, osm)
    assert out["street_side"].entrance_street == "Main Street"


# Fix R7: implied and non-"yes" oneways count as oneway.
@pytest.mark.parametrize(
    ("tags", "oneway"),
    [
        ({"oneway": "yes"}, True),
        ({"oneway": "-1"}, True),
        ({"oneway": "reversible"}, True),
        ({"oneway": "alternating"}, True),
        ({"junction": "roundabout"}, True),
        ({"junction": "circular"}, True),
        ({"highway": "motorway"}, True),
        ({"highway": "motorway_link"}, True),
        ({"highway": "motorway", "oneway": "no"}, False),
        ({"junction": "roundabout", "oneway": "no"}, False),
        ({"highway": "residential"}, False),
        ({"oneway": "no"}, False),
    ],
)
def test_r7_oneway_includes_implied_oneways(tags, oneway):
    assert doors._oneway(tags) is oneway


def test_r7_street_side_reports_a_roundabout_as_oneway():
    b, osm = corner_scene(side=False)
    for e in osm.elements:
        if e["type"] == "way" and e["id"] == 900:
            e["tags"]["junction"] = "roundabout"
    assert facade(b, osm)["street_side"].oneway is True


def test_centerline_is_clipped_to_60_m_each_side_of_the_door():
    # E2E I-12: a 1 km road with only two nodes.
    b, osm = corner_scene(main=[(-500, -10), (500, -10)], side=False)
    cl = [at(p) for p in facade(b, osm)["street_side"].centerline]
    assert cl[0] == pytest.approx((-45, -10), abs=0.1)
    assert cl[-1] == pytest.approx((75, -10), abs=0.1)


def test_clipping_keeps_the_local_direction_of_a_road_that_doubles_back():
    # First-to-last of the whole way points west-south-west, which would say "right".
    b, osm = corner_scene(main=[(-100, -10), (100, -10), (100, -300), (-2000, -300)], side=False)
    side = facade(b, osm)["street_side"]
    assert side.door_side_of_road == "left"
    assert all(math.isclose(at(p)[1], -10, abs_tol=0.1) for p in side.centerline)


def test_no_roads_means_no_street_side_but_still_an_address_point():
    b, osm = corner_scene(roads=False)
    out = facade(b, osm, where=(10, 8))
    assert out["street_side"] is None
    assert [c.id for c in out["candidates"]] == ["addr"]
    assert at(out["candidates"][0]) == pytest.approx((10, 0), abs=0.05)  # snapped to a wall


def test_degenerate_footprint_gives_only_the_address_point():
    osm = Osm()
    osm.way(900, osm.path(9000, [(-100, -10), (150, -10)]), highway="residential", name="Main")
    b = building("way/501", [(0, 0), (10, 0), (20, 0)])  # a line, no area
    save_area(b, osm)
    out = doors.facade_fallback(b, point(5, 0, street="Main"))
    assert [c.id for c in out["candidates"]] == ["addr"]


# Fix R5: a multipolygon with two wings. The door is on the small wing's south wall, facing
# Middle Street between the wings; the large wing's nearest wall faces the other way.
#
#   ---- North Street (y = 125) ----
#   wing B (0..10, 100..110), door 7 at (5, 100) on its south wall
#   ---- Middle Street (y = 60) ----
#   wing A (0..40, 0..30), the largest ring: the contract's footprint
def test_r5_street_side_uses_the_ring_the_door_is_on():
    osm = Osm()
    a = box(osm, 10, 0, 0, 40, 30)
    b1, b2, b3, b4 = osm.path(20, [(0, 100), (10, 100), (10, 110), (0, 110)])
    osm.node(7, 5, 100, entrance="main")
    osm.way(601, a)
    osm.way(602, [b1, 7, b2, b3, b4, b1])
    osm.rel(
        600, [("way", 601, "outer"), ("way", 602, "outer")], type="multipolygon", building="yes"
    )
    for way, y, name in [(900, 60, "Middle Street"), (901, 125, "North Street")]:
        osm.way(way, osm.path(way * 10, [(-100, y), (150, y)]), highway="residential", name=name)
    p = point(20, 15, street="1 Unknown Road")
    save_buildings(p, osm)
    b = doors.find_building(p)
    assert b.osm_id == "relation/600" and len(doors.rings_of(b)) == 2
    assert doors.rings_of(b)[0] == b.footprint  # the contract's footprint is the largest ring
    save_area(b, osm)
    door = next(c for c in doors.read_entrances(b, None) if c.id == "osm7")
    side = doors.street_side_for(b, door, p)
    assert side.entrance_street == "Middle Street"
    assert side.door_side_of_road == "left"  # road runs east, the door is north of it


# Fix R10: two main doors tie at 0.90. facade_fallback's anchor (lowest node id) is door 7 on
# the east wall, facing the diagonal Side Street; rank puts door 8 on the front wall first. The
# bundle's street_side and path_checks must describe door 8 and Main Street.
def test_r10_street_side_describes_the_top_candidate():
    osm = Osm()
    ids = osm.path(5000, [(0, 0), (30, 0), (30, 20), (0, 20)])
    osm.node(7, 30, 18, entrance="main")
    osm.node(8, 28, 0, entrance="main")
    osm.way(500, [ids[0], 8, ids[1], 7, ids[2], ids[3], ids[0]], building="yes")
    osm.way(
        900, osm.path(9000, [(-100, -10), (150, -10)]), highway="residential", name="Main Street"
    )
    osm.way(901, osm.path(9100, [(32, -10), (52, 100)]), highway="residential", name="Side Street")
    b = building("way/500", [(0, 0), (30, 0), (30, 20), (0, 20)])
    save_area(b, osm)
    p = point(15, 10, housenumber="1", street="1 Main Street")
    assert doors.facade_fallback(b, p)["street_side"].entrance_street == "Side Street"  # anchor
    stages = bundle.Stages(geocode=lambda request: p, find_building=lambda point: b)
    site = bundle.PilotSite(id="r10", address="1 Main Street", scenario="same_side")
    report = bundle.run_site(site, stages, DataVersion(osm="2026-10-01", model="none"))
    assert report.ok, report.describe()
    assert report.bundle.candidates[0].provenance[0].ref == "node/8"
    assert report.bundle.street_side.entrance_street == "Main Street"
    assert report.bundle.street_side.road_way == "way/900"


def test_r10_house_number_tie_break_ignores_case():
    c = Candidate(
        id="x",
        lat=0,
        lon=0,
        confidence=0.9,
        band="main",
        label="Door",
        provenance=[Provenance(source="osm_tag", tags={"addr:housenumber": "77a"})],
    )
    assert doors._has_number(c, "77A") and bundle.has_housenumber(c, "77A")


# ---------------------------------------------------------------------------------------------
# path_checks (BE-7)
# ---------------------------------------------------------------------------------------------
#
#   building (0..30, 0..20), door 7 at (15, 0) on the front wall
#   ---- Frontage Road (y = -20) ----   between the door and the drop-off
#   ---- Main Street (y = -40) -------  the address street: the car stops here, curb y = -34


def path_scene(between: dict | None, crossings=(), footway=True) -> tuple[Building, Osm]:
    osm = Osm()
    a, b, c, d = osm.path(5000, [(0, 0), (30, 0), (30, 20), (0, 20)])
    osm.node(7, 15, 0, entrance="main")
    osm.way(500, [a, 7, b, c, d, a], building="yes")
    osm.way(900, osm.path(9000, [(-200, -40), (200, -40)]), highway="primary", name="Main Street")
    ids = [
        osm.node(800 + i, x, y, **{"highway": "crossing"} | tags)
        for i, (x, y, tags) in enumerate(crossings)
    ]
    if between is not None:
        # Crossing nodes at y = -20 are nodes of Frontage Road's way, as in OSM.
        on_road = sorted(
            (i for i, (_, y, _) in zip(ids, crossings) if y == -20), key=lambda i: osm.coords[i]
        )
        w, e = osm.path(9100, [(-200, -20), (200, -20)])
        osm.way(901, [w, *on_road, e], **between)
    if footway:
        osm.way(950, [7, osm.node(9500, 15, -15, out=False)], highway="footway")
    else:  # a footway passing near the door, not reaching it
        osm.way(950, osm.path(9600, [(0, -2), (30, -2)]), highway="footway")
    return building("way/500", [(0, 0), (30, 0), (30, 20), (0, 20)]), osm


def run_path(b: Building, osm: Osm, door_id: str = "osm7"):
    out = facade(b, osm, street="Main Street", where=(15, -1))
    side = out["street_side"]
    door = next(c for c in doors.read_entrances(b, None) if c.id == door_id)
    return side, doors.path_checks(b, door, side)


FRONTAGE = {"highway": "residential", "name": "Frontage Road"}


def test_crossing_a_second_road_points_to_the_nearest_marked_crossing():
    b, osm = path_scene(
        FRONTAGE,
        crossings=[
            (16, -20, {"crossing": "unmarked"}),  # nearest, but no paint
            (18, -20, {"crossing:markings": "no", "crossing": "traffic_signals"}),
            (25, -20, {}),  # unknown: not assumed marked
            (40, -20, {"crossing": "marked"}),  # the answer
            (60, -20, {"crossing": "zebra"}),
        ],
    )
    side, checks = run_path(b, osm)
    assert side.entrance_street == "Main Street"  # the address street, though Frontage is nearer
    assert checks.crosses_road is True
    assert at(checks.nearest_crossing) == pytest.approx((40, -20), abs=0.05)
    assert checks.footway_to_entrance is True


def bbox_has(bbox, x, y) -> bool:
    lon, lat = lonlat(x, y)
    south, west, north, east = bbox
    return south <= lat <= north and west <= lon <= east


def test_marked_crossing_farther_than_150_m_is_no_help():
    # 175 m from the drop-off (15, -34), but inside the crossing box: live data returns it.
    b, osm = path_scene(FRONTAGE, crossings=[(190, -20, {"crossing": "marked"})])
    assert bbox_has(overpass.bbox_around(b.footprint, overpass.CROSSING_MARGIN_M), 190, -20)
    _, checks = run_path(b, osm)
    assert checks.crosses_road is True and checks.nearest_crossing is None


# Fix R13: a crossing 106 m from the drop-off is outside the 80 m road box but inside the
# crossing box the query really uses, so live data can return it.
def test_r13_crossing_between_80_and_150_m_is_in_the_query_box_and_used():
    b, osm = path_scene(FRONTAGE, crossings=[(120, -20, {"crossing": "marked"})])
    assert not bbox_has(overpass.bbox_around(b.footprint), 120, -20)
    crossing_box = overpass.bbox_around(b.footprint, overpass.CROSSING_MARGIN_M)
    assert bbox_has(crossing_box, 120, -20)
    assert ",".join(f"{v:.7f}" for v in crossing_box) in doors.area_query(b)
    _, checks = run_path(b, osm)
    assert at(checks.nearest_crossing) == pytest.approx((120, -20), abs=0.05)


# Fix R8: a marked crossing tagged on the traffic-signals node itself.
def test_r8_crossing_on_a_traffic_signals_node_is_used():
    signals = {"highway": "traffic_signals", "crossing": "traffic_signals"}
    b, osm = path_scene(FRONTAGE, crossings=[(30, -20, signals)])
    _, checks = run_path(b, osm)
    assert at(checks.nearest_crossing) == pytest.approx((30, -20), abs=0.05)


# Fix R2: the crosswalk must be over the road the walk crosses, never over the entrance street.
#   door 7 at (10, 0); Frontage Rd (y = -4) between the curb and the door, crosswalk at (60, -4)
#   Main Street (y = -15), the entrance street, crosswalk at (12, -15) right by the drop-off
def test_r2_nearest_crossing_is_on_the_crossed_road_not_the_entrance_street():
    osm = Osm()
    a, b_, c, d = osm.path(5000, [(0, 0), (20, 0), (20, 20), (0, 20)])
    osm.node(7, 10, 0, entrance="main")
    osm.way(500, [a, 7, b_, c, d, a], building="yes")
    osm.node(810, 12, -15, highway="crossing", crossing="marked")
    osm.node(811, 60, -4, highway="crossing", crossing="marked")
    w, e = osm.path(9000, [(-200, -15), (200, -15)])
    osm.way(900, [w, 810, e], highway="primary", name="Main Street")
    w, e = osm.path(9100, [(-200, -4), (200, -4)])
    osm.way(901, [w, 811, e], highway="residential", name="Frontage Road")
    b = building("way/500", [(0, 0), (20, 0), (20, 20), (0, 20)])
    out = facade(b, osm, street="Main Street", where=(10, -1))
    door = next(c for c in doors.read_entrances(b, None) if c.id == "osm7")
    checks = doors.path_checks(b, door, out["street_side"])
    assert out["street_side"].entrance_street == "Main Street"
    assert checks.crosses_road is True
    assert at(checks.nearest_crossing) == pytest.approx((60, -4), abs=0.05)


# Fix R2: a crosswalk node shared by the entrance street and a way named like the crossed road
# (a Frontage Road spur meeting Main Street at (14, -15)) is still over the entrance street.
def test_r2_crossing_shared_with_the_entrance_street_is_not_used():
    osm = Osm()
    a, b_, c, d = osm.path(5000, [(0, 0), (20, 0), (20, 20), (0, 20)])
    osm.node(7, 10, 0, entrance="main")
    osm.way(500, [a, 7, b_, c, d, a], building="yes")
    osm.node(811, 60, -4, highway="crossing", crossing="marked")
    osm.node(812, 14, -15, highway="crossing", crossing="marked")
    w, e = osm.path(9000, [(-200, -15), (200, -15)])
    osm.way(900, [w, 812, e], highway="primary", name="Main Street")
    w, e = osm.path(9100, [(-200, -4), (200, -4)])
    osm.way(901, [w, 811, e], highway="residential", name="Frontage Road")
    (s,) = osm.path(9200, [(14, -60)])
    osm.way(902, [812, s], highway="residential", name="Frontage Road")
    b = building("way/500", [(0, 0), (20, 0), (20, 20), (0, 20)])
    out = facade(b, osm, street="Main Street", where=(10, -1))
    door = next(c for c in doors.read_entrances(b, None) if c.id == "osm7")
    checks = doors.path_checks(b, door, out["street_side"])
    assert out["street_side"].entrance_street == "Main Street"
    assert at(checks.nearest_crossing) == pytest.approx((60, -4), abs=0.05)


@pytest.mark.parametrize("service", ["driveway", "parking_aisle", "drive-through"])
def test_driveway_or_parking_aisle_is_not_a_road_crossing(service):
    b, osm = path_scene({"highway": "service", "service": service})
    side, checks = run_path(b, osm)
    assert checks.crosses_road is False and checks.nearest_crossing is None
    # Fix R14: but it is a warning ("Driveway ahead. Listen for cars.").
    door = next(c for c in doors.read_entrances(b, None) if c.id == "osm7")
    assert doors.path_warnings(b, door, side) == ["driveway"]


# Fix R17 (d): a highway drawn as an area (a parking lot) is not a road to cross.
def test_r17_area_highway_is_not_a_road_crossing():
    _, checks = run_path(*path_scene({"highway": "service", "area": "yes"}))
    assert checks.crosses_road is False


# Fix R14: a door on the back wall, dropped off at the front: the line goes through the building.
def test_r14_line_through_the_building_is_a_warning():
    b, osm = path_scene(None)
    osm.node(8, 15, 20, entrance="yes")
    for e in osm.elements:
        if e["type"] == "way" and e["id"] == 500:
            e["nodes"].insert(4, 8)  # between (30, 20) and (0, 20)
    side, _ = run_path(b, osm)
    back = next(c for c in doors.read_entrances(b, None) if c.id == "osm8")
    front = next(c for c in doors.read_entrances(b, None) if c.id == "osm7")
    assert doors.path_warnings(b, back, side) == ["through_building"]
    assert doors.path_warnings(b, front, side) == []


def test_r14_path_warnings_become_bundle_notes():
    b, osm = path_scene({"highway": "service", "service": "driveway"})
    save_area(b, osm)
    p = point(15, -1, street="Main Street")
    stages = bundle.Stages(geocode=lambda request: p, find_building=lambda point: b)
    site = bundle.PilotSite(id="r14", address="1 Main Street", scenario="driveway")
    report = bundle.run_site(site, stages, DataVersion(osm="2026-10-01", model="none"))
    assert report.ok, report.describe()
    assert "path warning: driveway" in report.notes


def test_nothing_in_between():
    _, checks = run_path(*path_scene(None))
    assert checks.crosses_road is False


def test_footway_must_contain_the_door_node():
    _, checks = run_path(*path_scene(None, footway=False))
    assert checks.footway_to_entrance is False


# Fix R17 (a): only a footway-type way at the door counts, not a driveway ending there.
def test_r17_a_driveway_at_the_door_is_not_a_footway():
    b, osm = path_scene(None, footway=False)
    osm.way(960, [7, osm.node(9700, 25, -1, out=False)], highway="service", service="driveway")
    _, checks = run_path(b, osm)
    assert checks.footway_to_entrance is False


# Fix R17 (b): the drop-off is 6 m in from the centerline, so a side road meeting the entrance
# street right opposite the door (a T junction, its end node drawn 2 m past Main Street's
# centerline) is not "crossed".
def test_r17_side_road_at_the_drop_off_junction_is_not_crossed():
    b, osm = path_scene(None)
    osm.way(970, osm.path(9800, [(15, -38), (15, -200)]), highway="residential", name="South Rd")
    _, checks = run_path(b, osm)
    assert checks.crosses_road is False


# Fix R17 (e): a named service road (a campus drive) never beats a named public street when the
# address street is unknown.
def test_r17_named_service_road_loses_to_a_named_street():
    b, osm = path_scene({"highway": "service", "name": "Campus Drive"})
    side = facade(b, osm, street="1 Unknown Road", where=(15, -1))["street_side"]
    assert side.entrance_street == "Main Street"


def test_facade_candidate_and_unknown_street_side():
    b, osm = path_scene(FRONTAGE)
    save_area(b, osm)
    fac = Candidate(
        id="facade",
        lat=0,
        lon=0,
        confidence=0.3,
        band="facade",
        label="x",
        provenance=[Provenance(source="geometry_fallback", ref="way/900")],
    )
    # Fix R6: with no street side nothing was checked; "crosses no road" would overstate it,
    # so the walk is assumed to cross one, with no crossing to point to.
    checks = doors.path_checks(b, fac, None)
    assert checks.crosses_road is True and checks.nearest_crossing is None
    assert doors.path_warnings(b, fac, None) == []


def test_r6_site_without_an_entrance_street_builds_with_null_street_side():
    b, osm = corner_scene(roads=False)
    save_area(b, osm)
    p = point(10, 8, housenumber="1", street="1 Main Street")
    stages = bundle.Stages(geocode=lambda request: p, find_building=lambda point: b)
    site = bundle.PilotSite(id="r6", address="1 Main Street", scenario="same_side")
    report = bundle.run_site(site, stages, DataVersion(osm="2026-10-01", model="none"))
    assert report.ok, report.describe()
    assert report.bundle.street_side is None
    assert report.bundle.path_checks.crosses_road is True
    assert report.bundle.path_checks.nearest_crossing is None
    assert bundle.NO_STREET_SIDE_NOTE in report.notes


# ---------------------------------------------------------------------------------------------
# door_street: which road street_side describes
# ---------------------------------------------------------------------------------------------
#
#   building (0..30, 0..20), door 7 on the front wall at (15, 0), facing south
#   address street: "Address Street"; other roads as each test places them


def street_scene(roads: list[tuple[str, list[tuple[float, float]], dict]]) -> tuple[Building, Osm]:
    osm = Osm()
    a, b_, c, d = osm.path(5000, [(0, 0), (30, 0), (30, 20), (0, 20)])
    osm.node(7, 15, 0, entrance="main")
    osm.way(500, [a, 7, b_, c, d, a], building="yes")
    for k, (name, pts, tags) in enumerate(roads):
        osm.way(900 + k, osm.path(9000 + 100 * k, pts), name=name, **tags)
    return building("way/500", [(0, 0), (30, 0), (30, 20), (0, 20)]), osm


def side_of(b: Building, osm: Osm):
    save_area(b, osm)
    door = next(c for c in doors.read_entrances(b, None) if c.id == "osm7")
    return doors.street_side_for(b, door, point(15, 10, housenumber="1", street="1 Address St"))


RES = {"highway": "residential"}


def test_near_address_street_wins_though_the_door_does_not_face_it():
    # MIT Stata: the door's wall faces Facing Street 45 m away; the address street passes the
    # building's corner, 27 m from the door and 70 degrees off its wall's normal (not facing).
    # The walk from its curb misses the building, and the car stops on the address street.
    b, osm = street_scene(
        [
            ("Address Street", [(4, -109), (76, 91)], RES),
            ("Facing Street", [(-100, -45), (150, -45)], RES),
        ]
    )
    assert side_of(b, osm).entrance_street == "Address Street"


def test_far_address_street_loses_to_a_near_facing_road():
    # MIT Kresge: the address street is 150 m away; the door faces a street 40 m away.
    b, osm = street_scene(
        [
            ("Address Street", [(-100, -150), (150, -150)], RES),
            ("Facing Street", [(-100, -40), (150, -40)], RES),
        ]
    )
    side = side_of(b, osm)
    assert side.entrance_street == "Facing Street" and side.road_way == "way/901"


def test_address_street_behind_the_building_loses_to_a_facing_road():
    # MIT Medical: the address street runs behind the building; walking from its curb to the
    # door would go through the building. The facing road is used.
    b, osm = street_scene(
        [
            ("Address Street", [(-100, 30), (150, 30)], RES),
            ("Facing Street", [(-100, -50), (150, -50)], RES),
        ]
    )
    assert side_of(b, osm).entrance_street == "Facing Street"


def test_no_road_within_the_limit_gives_no_street_side():
    # CambridgeSide: the nearest road is 83 m from the only door; a road behind the building
    # (even the address street) and a facing service road do not count either.
    far = doors.ENTRANCE_STREET_MAX_M + 5
    b, osm = street_scene(
        [
            ("Address Street", [(-100, 30), (150, 30)], RES),
            ("Far Street", [(-100, -far), (150, -far)], RES),
            ("Mall Drive", [(-100, -20), (150, -20)], {"highway": "service"}),
        ]
    )
    assert side_of(b, osm) is None


def test_facade_label_names_only_the_street_that_street_side_names():
    # The address street the front faces is 100 m away: no street_side, so the facade label
    # must not name it (MIT Media Lab's label once said Amherst while street_side said Carleton).
    b, osm = corner_scene(main=[(-100, -100), (150, -100)])
    out = facade(b, osm)
    assert out["candidates"][0].label == "Street-facing side (approximate)"
    assert out["street_side"] is None


def test_road_just_within_the_limit_is_used():
    near = doors.ENTRANCE_STREET_MAX_M - 5
    b, osm = street_scene([("Far Street", [(-100, -near), (150, -near)], RES)])
    assert side_of(b, osm).entrance_street == "Far Street"


def test_address_street_counts_when_its_nearest_curb_is_behind_a_corner():
    # MIT Hayden: the address street's point nearest the door is behind the building, but its
    # curb farther along has a clear walk; that point is also path_checks' drop-off.
    # Nearest: (15, 30), behind the building; clear from about (-26, -8), 33 m away.
    b, osm = street_scene([("Address Street", [(15, 30), (-30, 30), (0, -60)], RES)])
    side = side_of(b, osm)
    assert side is not None and side.entrance_street == "Address Street"
    door = next(c for c in doors.read_entrances(b, None) if c.id == "osm7")
    assert doors.path_warnings(b, door, side) == []


def test_centerline_runs_on_through_the_next_way_of_the_same_name():
    # MIT Stratton: OSM splits the street at the point nearest the door; the centerline keeps
    # going through the next way of the same name instead of stopping there.
    b, osm = street_scene(
        [
            ("Address Street", [(-100, -30), (15, -30)], RES),
            ("Address Street", [(15, -30), (150, -30)], RES),
        ]
    )
    side = side_of(b, osm)
    f = geo.Frame(side.centerline[0][1], side.centerline[0][0])
    pts = [f.xy(*p) for p in side.centerline]
    length = sum(math.dist(p, q) for p, q in itertools.pairwise(pts))
    assert length == pytest.approx(2 * doors.CENTERLINE_KEEP_M, abs=0.5)


def test_a_road_with_only_a_ref_can_be_the_entrance_street():
    b, osm = street_scene([("Address Street", [(-100, -150), (150, -150)], RES)])
    osm.way(990, osm.path(9900, [(-100, -20), (150, -20)]), ref="MA 2A", highway="primary")
    side = side_of(b, osm)
    assert side.entrance_street == "MA 2A"


# ---------------------------------------------------------------------------------------------
# Crossing ways, the entrance street's crosswalk, steps and descents at the door
# ---------------------------------------------------------------------------------------------

LIGHTS = {
    "highway": "footway",
    "footway": "crossing",
    "crossing": "traffic_signals",
    "crossing:markings": "zebra",
}


# Fix R8 (finished): a signalised crosswalk mapped only as a footway=crossing way over a
# highway=traffic_signals node (no crossing=* on the node) is a marked crossing.
def test_r8_crossing_way_over_a_plain_signal_node_is_used():
    b, osm = path_scene(FRONTAGE, crossings=[(30, -20, {"highway": "traffic_signals"})])
    ends = [osm.node(9600, 30, -15, out=False), 800, osm.node(9601, 30, -25, out=False)]
    osm.way(960, ends, **LIGHTS)
    _, checks = run_path(b, osm)
    assert at(checks.nearest_crossing) == pytest.approx((30, -20), abs=0.05)


def test_r8_unmarked_crossing_way_is_not_used():
    b, osm = path_scene(FRONTAGE, crossings=[(30, -20, {"highway": "traffic_signals"})])
    ends = [osm.node(9600, 30, -15, out=False), 800, osm.node(9601, 30, -25, out=False)]
    osm.way(960, ends, highway="footway", footway="crossing", crossing="unmarked")
    _, checks = run_path(b, osm)
    assert checks.crosses_road is True and checks.nearest_crossing is None


#   building (0..30, 0..20), main door 7 at (15, 0)
#   Main Street (y = -20) in two ways split at signal node 70 (x = 15, abeam the door);
#   crosswalk way 960 over node 70, a second marked crosswalk over node 71 at x = 100.
def split_street_scene(crosswalk: dict | None = None, oneway: bool = False):
    osm = Osm()
    a, b_, c, d = osm.path(5000, [(0, 0), (30, 0), (30, 20), (0, 20)])
    osm.node(7, 15, 0, entrance="main")
    osm.way(500, [a, 7, b_, c, d, a], building="yes")
    osm.node(70, 15, -20, highway="traffic_signals")
    osm.node(71, 100, -20, out=False)
    road = {"highway": "primary", "name": "Main Street"} | ({"oneway": "yes"} if oneway else {})
    west = osm.path(9000, [(-200, -20), (-100, -20)])
    osm.way(900, [*west, 70], **road)
    if oneway:  # the east half drawn against the direction of the west half
        osm.way(901, [osm.node(9010, 200, -20, out=False), 71, 70], **road)
    else:
        osm.way(901, [70, 71, osm.node(9010, 200, -20, out=False)], **road)
    far = [osm.node(9700, 100, -12, out=False), 71, osm.node(9701, 100, -28, out=False)]
    osm.way(961, far, highway="footway", footway="crossing", **{"crossing:markings": "zebra"})
    if crosswalk is not None:
        ends = [osm.node(9600, 15, -12, out=False), 70, osm.node(9601, 15, -28, out=False)]
        osm.way(960, ends, **crosswalk)
    b = building("way/500", [(0, 0), (30, 0), (30, 20), (0, 20)])
    return b, facade(b, osm, street="Main Street", where=(15, -1))["street_side"]


def test_street_side_crossing_is_the_marked_crosswalk_over_the_entrance_street():
    _, side = split_street_scene(LIGHTS)
    assert side.entrance_street == "Main Street"
    assert at(side.crossing) == pytest.approx((15, -28), abs=0.05)  # far kerb, not node 70


def test_street_side_crossing_skips_an_unmarked_crosswalk():
    _, side = split_street_scene({"highway": "footway", "footway": "crossing", "crossing": "no"})
    assert at(side.crossing) == pytest.approx((100, -28), abs=0.05)  # next marked one, far kerb


def test_street_side_crossing_farther_than_150_m_is_none():
    b, osm = corner_scene()
    osm.node(880, 180, -10, out=False)
    road = next(e for e in osm.elements if e.get("id") == 900)
    road["nodes"].insert(1, 880)
    road["geometry"].insert(1, {"lat": osm.coords[880][1], "lon": osm.coords[880][0]})
    osm.way(960, [osm.node(9600, 180, -2, out=False), 880], **LIGHTS)
    side = facade(b, osm)["street_side"]
    assert side.entrance_street == "Main Street" and side.crossing is None


def test_centerline_continues_into_the_next_way_of_the_same_street():
    _, side = split_street_scene()
    xs = [at(p)[0] for p in side.centerline]
    assert min(xs) == pytest.approx(-45, abs=0.1) and max(xs) == pytest.approx(75, abs=0.1)
    assert side.door_side_of_road == "left"  # the centerline runs east, the door is north


def test_centerline_never_joins_a_oneway_way_drawn_the_other_way():
    _, side = split_street_scene(oneway=True)
    xs = [at(p)[0] for p in side.centerline]
    assert max(xs) == pytest.approx(15, abs=0.1)  # way 900 ends at the signal


#   door 7 (entrance=yes) at (15, 0) on the front wall; the given ways reach it from the south.
def steps_scene(*ways: tuple[list[tuple[float, float]], dict]) -> Candidate:
    osm = Osm()
    a, b_, c, d = osm.path(5000, [(0, 0), (30, 0), (30, 20), (0, 20)])
    osm.node(7, 15, 0, entrance="yes")
    osm.way(500, [a, 7, b_, c, d, a], building="yes")
    osm.way(900, osm.path(9000, [(-200, -20), (200, -20)]), highway="primary", name="Main Street")
    for i, (pts, tags) in enumerate(ways):
        ids = [
            7 if p == (15, 0) else osm.node(9600 + 10 * i + k, *p, out=False)
            for k, p in enumerate(pts)
        ]
        osm.way(960 + i, ids, **tags)
    b = building("way/500", [(0, 0), (30, 0), (30, 20), (0, 20)])
    save_area(b, osm)
    doors._area.cache_clear()  # several scenes per test share one building id
    return next(c for c in doors.read_entrances(b, None) if c.id == "osm7")


STEPS_UP = {"highway": "steps", "incline": "up", "step_count": "17"}


def test_step_count_comes_from_the_steps_that_lead_to_the_door():
    door = steps_scene(([(15, -6), (15, 0)], STEPS_UP))
    assert door.speak.step_count == 17
    assert door.confidence == pytest.approx(0.80)  # 0.75 + footway; going up: no penalty


def test_steps_ending_near_the_door_count_and_untagged_steps_give_no_count():
    assert steps_scene(([(15, -8), (15, -2)], STEPS_UP)).speak.step_count == 17
    assert steps_scene(([(15, -8), (15, -4)], STEPS_UP)).speak is None  # 4 m: not at the door
    assert steps_scene(([(15, -6), (15, 0)], {"highway": "steps"})).speak is None


def test_a_step_free_path_to_the_door_means_no_step_count():
    door = steps_scene(
        ([(15, -6), (15, 0)], STEPS_UP),
        ([(25, -6), (15, 0)], {"highway": "footway", "wheelchair": "yes"}),
    )
    assert door.speak is None


@pytest.mark.parametrize(
    "pts, incline",
    [([(15, -6), (15, 0)], "down"), ([(15, 0), (15, -6)], "up"), ([(15, -6), (15, 0)], "-8%")],
    ids=["down-to-door", "up-away-from-door", "negative-grade"],
)
def test_a_door_every_path_descends_to_scores_like_a_lower_level_door(pts, incline):
    door = steps_scene((pts, {"highway": "footway", "incline": incline}))
    assert door.confidence == pytest.approx(0.70)  # 0.75 + footway - 0.10


def test_one_level_path_to_the_door_means_no_descent_penalty():
    door = steps_scene(
        ([(15, -6), (15, 0)], {"highway": "footway", "incline": "down"}),
        ([(25, -6), (15, 0)], {"highway": "footway"}),
    )
    assert door.confidence == pytest.approx(0.80)


def test_names_of_reads_alt_and_official_names_and_the_name_after_its_ref():
    p = point(10, 10)
    osm = Osm()
    tags = {
        "building": "university",
        "name": "7 Rogers Building",
        "ref": "7",
        "alt_name": "MIT Building 7",
        "official_name": "William Barton Rogers Building",
    }
    osm.way(500, box(osm, 5000, 0, 0, 20, 20), **tags)
    save_buildings(p, osm)
    b = doors.find_building(p)
    assert doors.names_of(b) == [
        "MIT Building 7",
        "William Barton Rogers Building",
        "Rogers Building",
    ]
    assert doors.names_of(building("way/1", [(0, 0), (1, 0), (1, 1)])) == []


def test_only_the_ways_at_this_door_decide_its_steps():
    osm = Osm()
    a, b_, c, d = osm.path(5000, [(0, 0), (30, 0), (30, 20), (0, 20)])
    osm.node(7, 15, 0, entrance="yes")
    osm.node(8, 25, 0, entrance="yes")
    osm.way(500, [a, 7, 8, b_, c, d, a], building="yes")
    osm.way(900, osm.path(9000, [(-200, -20), (200, -20)]), highway="primary", name="Main Street")
    osm.way(960, [osm.node(9600, 15, -6, out=False), 7], **STEPS_UP)
    osm.way(961, [osm.node(9610, 25, -6, out=False), 8], highway="footway", incline="down")
    b = building("way/500", [(0, 0), (30, 0), (30, 20), (0, 20)])
    save_area(b, osm)
    found = {c.id: c for c in doors.read_entrances(b, None)}
    assert found["osm7"].speak.step_count == 17 and found["osm7"].confidence == pytest.approx(0.80)
    assert found["osm8"].speak is None and found["osm8"].confidence == pytest.approx(0.70)
