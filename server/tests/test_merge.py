"""Tests for app/merge.py (BE-6). A fake combine keeps them independent of BE-4's scoring."""

import itertools
import math

import pytest
from test_bundle import SITE, VERSION, fake_stages

from app import bundle, scoring
from app.merge import merge_candidates
from app.models import Candidate

LAT, LON = 42.3592, -71.0930
M_PER_DEG_LAT = 111_195.0  # matches haversine_m's Earth radius to < 0.1%


def fake_combine(best_by_class):
    best = max(best_by_class.values())
    return best + 0.05 if len(best_by_class) >= 2 else best


def cand(cid, confidence, source="osm_tag", ref=None, north_m=0.0, label=None):
    return Candidate(
        id=cid,
        lat=LAT + north_m / M_PER_DEG_LAT,
        lon=LON,
        confidence=confidence,
        band="door",
        label=label or cid,
        provenance=[{"source": source, "ref": ref if ref is not None else cid}],
    )


def merge(cands, **kw):
    return merge_candidates(cands, combine=fake_combine, **kw)


def test_empty_and_single():
    assert merge([]) == []
    one = cand("a", 0.8)
    assert merge([one]) == [one]
    assert merge([cand("a", 1.0)])[0].confidence == scoring.CAP


def test_two_sources_2m_apart_merge_with_one_step():
    (m,) = merge([cand("osm", 0.75), cand("pho", 0.65, "mapillary_cv", north_m=2)])
    assert m.confidence == pytest.approx(0.80)
    assert [p.source for p in m.provenance] == ["osm_tag", "mapillary_cv"]


def test_6m_apart_do_not_merge():
    out = merge([cand("osm", 0.75), cand("pho", 0.65, "mapillary_cv", north_m=6)])
    assert [c.confidence for c in out] == [0.75, 0.65]


def test_same_class_duplicates_merge_without_bump():
    (m,) = merge([cand("p1", 0.45, "mapillary_cv", north_m=1), cand("p2", 0.65, "mapillary_cv")])
    assert m.id == "p2" and m.confidence == 0.65
    (m,) = merge([cand("a", 0.9, ref="node/1"), cand("b", 0.75, ref="node/1", north_m=1)])
    assert m.confidence == 0.9


def test_distinct_osm_doors_stay_separate():
    out = merge([cand("a", 0.9, ref="node/1"), cand("b", 0.75, ref="node/2", north_m=1)])
    assert len(out) == 2


def test_facade_never_merges_or_boosts():
    door = cand("osm", 0.75)
    facade = cand("fac", 0.30, "geometry_fallback", north_m=1)
    out = merge([facade, door, cand("fac2", 0.30, "geometry_fallback", north_m=0.5)])
    assert [c.id for c in out] == ["osm", "fac", "fac2"]
    assert out[0] == door


def test_provenance_union_dedups_in_stable_order():
    a = cand("a", 0.9, ref="node/1")
    b = cand("b", 0.65, "mapillary_cv", ref="img/1", north_m=1)
    c = b.model_copy(update={"id": "c", "confidence": 0.45})  # same photo evidence again
    d = cand("d", 0.5, "crowd", ref="r/1", north_m=2)
    (m,) = merge([d, c, b, a])
    assert [(p.source, p.ref) for p in m.provenance] == [
        ("osm_tag", "node/1"),
        ("mapillary_cv", "img/1"),
        ("crowd", "r/1"),
    ]
    assert m.confidence == pytest.approx(0.95)


def test_strongest_member_keeps_position_label_and_id():
    weak = cand("osm", 0.6, label="Side door")
    strong = cand("pho", 0.65, "mapillary_cv", north_m=3, label="Front door")
    (m,) = merge([weak, strong])
    assert (m.id, m.lat, m.lon, m.label) == ("pho", strong.lat, strong.lon, "Front door")


def test_tie_prefers_osm_then_input_order():
    (m,) = merge([cand("pho", 0.7, "mapillary_cv"), cand("osm", 0.7, north_m=1)])
    assert m.id == "osm"
    (m,) = merge([cand("p1", 0.7, "crowd"), cand("p2", 0.7, "mapillary_cv", north_m=1)])
    assert m.id == "p1"


def test_chain_is_capped_at_twice_the_radius():
    a = cand("a", 0.9)
    b = cand("b", 0.65, "mapillary_cv", north_m=3)
    c = cand("c", 0.5, "crowd", north_m=6)
    d = cand("d", 0.45, "mapillary_cv", north_m=9)
    (m,) = merge([a, b, c])  # A-C is 6 m <= 8 m: one cluster via single linkage
    assert m.id == "a" and {p.ref for p in m.provenance} == {"a", "b", "c"}
    out = merge([a, b, c, d])  # A-D is 9 m > 8 m: D starts its own cluster
    assert [x.id for x in out] == ["a", "d"]


def test_confidence_is_capped():
    (m,) = merge([cand("a", 0.95), cand("b", 0.9, "mapillary_cv", north_m=1)])
    assert m.confidence == scoring.CAP


def test_deterministic_regardless_of_input_order():
    cands = [
        cand("a", 0.9, ref="node/1"),
        cand("b", 0.65, "mapillary_cv", north_m=3),
        cand("c", 0.5, "crowd", north_m=6),
        cand("d", 0.45, "mapillary_cv", north_m=9),
        cand("e", 0.75, ref="node/2", north_m=2),
        cand("f", 0.3, "geometry_fallback", north_m=1),
    ]
    expected = merge(cands)
    for perm in itertools.permutations(cands):
        assert merge(list(perm)) == expected


def test_radius_boundary_in_meters():
    a = cand("a", 0.5)
    assert len(merge([a, cand("b", 0.5, "crowd", north_m=3.99)])) == 1
    assert len(merge([a, cand("b", 0.5, "crowd", north_m=4.01)])) == 2


def stage_door(confidence, source, ref, north_m=0.0):
    return cand(ref, confidence, source, ref=ref, north_m=north_m).model_dump()


DOORS = [stage_door(0.75, "osm_tag", "node/1"), stage_door(0.65, "mapillary_cv", "img/1", 2)]


def test_bundle_merges_doors_with_combine(monkeypatch):
    monkeypatch.setattr(scoring, "combine", fake_combine)
    report = bundle.run_site(SITE, fake_stages(DOORS), VERSION)

    assert report.ok, report.describe()
    top, facade = report.bundle.candidates
    assert (top.id, top.confidence, top.band) == ("c1", pytest.approx(0.80), "door")
    assert [p.ref for p in top.provenance] == ["node/1", "img/1"]
    assert facade.band == "facade"
    assert bundle.MAPILLARY_ATTRIBUTION in report.bundle.attribution
    assert report.notes == ()


def test_bundle_falls_back_when_combine_is_not_implemented(monkeypatch, caplog):
    def todo(best_by_class):
        raise NotImplementedError("BE-4")

    monkeypatch.setattr(scoring, "combine", todo)
    report = bundle.run_site(SITE, fake_stages(DOORS), VERSION)

    assert report.ok
    top = report.bundle.candidates[0]
    assert top.confidence == 0.75 and len(top.provenance) == 2
    assert report.notes == (bundle.COMBINE_FALLBACK_NOTE,)
    assert report.describe().endswith(bundle.COMBINE_FALLBACK_NOTE)
    assert bundle.COMBINE_FALLBACK_NOTE in caplog.text


@pytest.mark.parametrize("bad", [math.nan, math.inf, -math.inf, -1.0, 0.1])
def test_bad_combine_result_never_demotes_the_door(bad, caplog):
    pair = [cand("osm", 0.75), cand("pho", 0.65, "mapillary_cv", north_m=1)]
    (m,) = merge_candidates(pair, combine=lambda best: bad)
    assert m.confidence == 0.75
    assert "below the best member score" in caplog.text


def test_too_high_combine_result_is_still_capped():
    pair = [cand("osm", 0.9), cand("pho", 0.65, "mapillary_cv", north_m=1)]
    (m,) = merge_candidates(pair, combine=lambda best: 1.7)
    assert m.confidence == scoring.CAP


def test_contested_photo_joins_the_nearest_osm_door():
    doors = [cand("n1", 0.75, ref="node/1"), cand("n2", 0.74, ref="node/2", north_m=6)]
    near_n2 = cand("pho", 0.65, "mapillary_cv", north_m=4)  # 4 m from n1, 2 m from n2
    out = {c.id: c for c in merge([near_n2, *doors])}
    assert out["n1"].confidence == 0.75 and len(out["n1"].provenance) == 1
    assert out["n2"].confidence == pytest.approx(0.79)
    assert [p.ref for p in out["n2"].provenance] == ["node/2", "pho"]

    halfway = cand("pho", 0.65, "mapillary_cv", north_m=3)  # tie: the stronger door wins
    out = {c.id: c for c in merge([*doors, halfway])}
    assert out["n1"].confidence == pytest.approx(0.80)
    assert out["n2"].confidence == 0.74


def test_same_face_predicate_only_gates_different_classes():
    a, b = cand("osm", 0.75), cand("pho", 0.65, "mapillary_cv", north_m=1)
    assert len(merge([a, b], same_face=lambda x, y: False)) == 2
    assert len(merge([a, b], same_face=lambda x, y: True)) == 1
    p1, p2 = cand("p1", 0.65, "mapillary_cv"), cand("p2", 0.45, "mapillary_cv", north_m=1)
    assert len(merge([p1, p2], same_face=lambda x, y: False)) == 1


# A 20 m square building whose south-east corner is at (LAT, LON).
M_PER_DEG_LON = M_PER_DEG_LAT * math.cos(math.radians(LAT))


def at(east_m, north_m):
    return [LON + east_m / M_PER_DEG_LON, LAT + north_m / M_PER_DEG_LAT]


SQUARE = [at(0, 0), at(-20, 0), at(-20, 20), at(0, 20), at(0, 0)]


def point(cid, confidence, source, east_m, north_m):
    lon, lat = at(east_m, north_m)
    c = cand(cid, confidence, source)
    return c.model_copy(update={"lat": lat, "lon": lon})


def test_same_face_on_footprint():
    same_face = bundle.same_face_on(SQUARE)
    door = point("osm", 0.75, "osm_tag", -1, 0)  # south wall, 1 m from the corner
    assert same_face(door, point("p", 0.6, "mapillary_cv", -3, 0))  # same wall
    assert not same_face(door, point("p", 0.6, "mapillary_cv", 0, 2.83))  # round the corner
    assert same_face(door, point("p", 0.6, "mapillary_cv", 0, 1.0))  # both at the corner
    assert bundle.same_face_on([]) is None


# Fix R3: a door node on a straight wall is an outline vertex; both sides are one face.
def test_r3_both_sides_of_a_door_vertex_on_a_straight_wall_are_one_face():
    wall = [at(0, 0), at(-10, 0), at(-20, 0), at(-20, 20), at(0, 20), at(0, 0)]
    same_face = bundle.same_face_on(wall)
    door = point("osm", 0.75, "osm_tag", -10, 0)  # the door vertex itself
    assert same_face(door, point("p", 0.6, "mapillary_cv", -7, -0.5))
    assert same_face(door, point("p", 0.6, "mapillary_cv", -13, -0.5))
    assert not same_face(door, point("p", 0.6, "mapillary_cv", -20.5, 3))  # round the corner


def test_r3_other_rings_are_faces_too():
    wing = [at(0, 40), at(-10, 40), at(-10, 50), at(0, 50), at(0, 40)]
    same_face = bundle.same_face_on(SQUARE, [wing])
    assert same_face(point("a", 0.75, "osm_tag", -3, 40), point("p", 0.6, "mapillary_cv", -6, 40))


@pytest.mark.parametrize(
    ("photo_at", "boosted"),
    [((-3, 0), True), ((0, 2.83), False)],  # 2 m along the wall / 3 m around the corner
)
def test_bundle_only_boosts_with_a_photo_on_the_same_face(monkeypatch, photo_at, boosted):
    monkeypatch.setattr(scoring, "combine", fake_combine)
    building = {"osm_id": "way/9", "housenumber": "77", "footprint": SQUARE}
    doors = [
        point("node/1", 0.75, "osm_tag", -1, 0).model_dump(),
        point("img/1", 0.65, "mapillary_cv", *photo_at).model_dump(),
    ]
    stages = fake_stages(doors, find_building=lambda p: building)
    top = bundle.run_site(SITE, stages, VERSION).bundle.candidates[0]
    assert top.confidence == pytest.approx(0.80 if boosted else 0.75)
    assert (len(top.provenance) == 2) is boosted


def test_combine_fallback_logs_without_notes(monkeypatch, caplog):
    def todo(best_by_class):
        raise NotImplementedError("BE-4")

    monkeypatch.setattr(scoring, "combine", todo)
    pair = [cand("osm", 0.75), cand("pho", 0.65, "mapillary_cv", north_m=1)]
    (m,) = bundle.merge(pair)
    assert m.confidence == 0.75
    assert bundle.COMBINE_FALLBACK_NOTE in caplog.text
