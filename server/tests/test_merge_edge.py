"""Adversarial edge tests for app/merge.py (BE-6), written from the spec, not the implementation.

Spec summary (docs/car-to-curb-plan.md section 8, "Combining"):
- Cluster door candidates within radius_m (haversine). Chains are bounded (cluster diameter cap).
- geometry_fallback candidates never merge with, or boost, real doors.
- Evidence classes: osm_tag -> "osm", mapillary_cv -> "photos", crowd -> "crowd". `combine` gets
  the best score per class; same-class duplicates are not agreement.
- The merged candidate takes position, label, speak and id from its strongest member (ties:
  osm_tag first, then input order). Provenance is the deduplicated union, in a stable order.
  Confidence is combine(...) clamped to <= 0.95.
- Pure and deterministic. Empty in, empty out.

Safety decision for bad coordinates (documented here because the spec is silent): a candidate
with NaN, infinite or missing lat/lon must make merge_candidates raise ValueError (or TypeError
for None). Silently passing it through would let it reach a bundle where the phone would steer a
blind rider toward a meaningless point; failing loudly makes the offline bundle build report the
site as failed instead.
"""

import copy
import itertools
import math
import random
import time

import pytest

from app.merge import merge_candidates
from app.models import Candidate, Provenance, Speak

R_EARTH = 6_371_008.8  # mean Earth radius, meters
BOSTON = (42.36, -71.06)
CAP = 0.95
CLASS = {"osm_tag": "osm", "mapillary_cv": "photos", "crowd": "crowd"}


def offset(lat, lon, north_m=0.0, east_m=0.0):
    """Exact-enough point at a haversine distance: north along a meridian, east along a parallel.

    Pure north moves are exact on a sphere. Pure east moves solve the haversine formula for dlon
    at constant latitude, so haversine(p, offset(p, east_m=d)) == d.
    """
    lat2 = lat + math.degrees(north_m / R_EARTH)
    if east_m:
        s = math.sin(abs(east_m) / (2 * R_EARTH)) / math.cos(math.radians(lat2))
        dlon = math.degrees(2 * math.asin(s))
        lon = lon + math.copysign(dlon, east_m)
    return lat2, lon


def cand(ref, conf, source="osm_tag", at=BOSTON, *, north=0.0, east=0.0, label=None, **extra):
    lat, lon = offset(at[0], at[1], north, east)
    band = "facade" if source == "geometry_fallback" else "door"
    return Candidate(
        id=f"id-{ref}",
        lat=lat,
        lon=lon,
        confidence=conf,
        band=band,
        label=label or f"label-{ref}",
        speak=Speak(door=f"speak-{ref}"),
        provenance=[Provenance(source=source, ref=ref)],
        **extra,
    )


class FakeCombine:
    """Best score plus 0.05 per extra class; records every call."""

    def __init__(self, result=None):
        self.calls: list[dict[str, float]] = []
        self.result = result

    def __call__(self, best_by_class):
        self.calls.append(dict(best_by_class))
        if self.result is not None:
            return self.result
        return max(best_by_class.values()) + 0.05 * (len(best_by_class) - 1)


def merge(cands, **kw):
    kw.setdefault("combine", FakeCombine())
    return merge_candidates(list(cands), **kw)


def refs(c: Candidate) -> set[str]:
    return {p.ref for p in c.provenance if p.ref is not None}


def by_ref(out, ref) -> Candidate:
    [hit] = [c for c in out if ref in refs(c)]
    return hit


def multi_class_calls(fake: FakeCombine):
    return [call for call in fake.calls if len(call) > 1]


# --- basics -------------------------------------------------------------------------------------


def test_empty_in_empty_out():
    assert merge([]) == []


def test_single_candidate_survives_unchanged_in_position_and_id():
    c = cand("node/1", 0.75)
    [out] = merge([c])
    assert (out.id, out.lat, out.lon, out.label) == (c.id, c.lat, c.lon, c.label)
    assert out.confidence == pytest.approx(0.75)


def test_input_is_not_mutated():
    cands = [cand("node/1", 0.75), cand("img/1", 0.65, "mapillary_cv", north=1)]
    before = copy.deepcopy([c.model_dump() for c in cands])
    merge(cands)
    assert [c.model_dump() for c in cands] == before


# --- distance -----------------------------------------------------------------------------------


@pytest.mark.parametrize("direction", ["north", "east"])
def test_boundary_3_99_m_merges(direction):
    fake = FakeCombine()
    out = merge(
        [cand("node/1", 0.75), cand("img/1", 0.65, "mapillary_cv", **{direction: 3.99})],
        combine=fake,
    )
    assert len(out) == 1
    assert {"osm": 0.75, "photos": 0.65} in fake.calls


@pytest.mark.parametrize("direction", ["north", "east"])
def test_boundary_4_01_m_does_not_merge(direction):
    fake = FakeCombine()
    out = merge(
        [cand("node/1", 0.75), cand("img/1", 0.65, "mapillary_cv", **{direction: 4.01})],
        combine=fake,
    )
    assert len(out) == 2
    assert multi_class_calls(fake) == []
    assert by_ref(out, "node/1").confidence == pytest.approx(0.75)


def test_boston_longitude_scaling():
    """At 42.36 deg, a degree of longitude is ~82 km, not ~111 km.

    3.5 m east must merge and 4.5 m east must not. An implementation that forgets cos(lat)
    (or swaps lat and lon) gets one of these wrong.
    """
    near = merge([cand("node/1", 0.75), cand("img/1", 0.65, "mapillary_cv", east=3.5)])
    far = merge([cand("node/1", 0.75), cand("img/2", 0.65, "mapillary_cv", east=4.5)])
    assert len(near) == 1
    assert len(far) == 2


def test_custom_radius_is_respected():
    pair = [cand("node/1", 0.75), cand("img/1", 0.65, "mapillary_cv", north=6)]
    assert len(merge(pair)) == 2
    assert len(merge(pair, radius_m=8.0)) == 1


def test_identical_coordinates_merge():
    fake = FakeCombine()
    out = merge([cand("node/1", 0.75), cand("img/1", 0.65, "mapillary_cv")], combine=fake)
    assert len(out) == 1
    assert refs(out[0]) == {"node/1", "img/1"}


# --- evidence classes ---------------------------------------------------------------------------


def test_three_source_agreement():
    fake = FakeCombine()
    out = merge(
        [
            cand("img/1", 0.65, "mapillary_cv", north=1),
            cand("node/1", 0.90),
            cand("crowd/1", 0.50, "crowd", east=1),
        ],
        combine=fake,
    )
    assert len(out) == 1
    assert {"osm": 0.90, "photos": 0.65, "crowd": 0.50} in fake.calls
    assert out[0].confidence == pytest.approx(CAP)  # 0.90 + 0.10, clamped
    assert refs(out[0]) == {"img/1", "node/1", "crowd/1"}


def test_same_class_duplicates_are_not_agreement():
    """Two OSM nodes 1 m apart: combine sees one "osm" entry, the best of the two."""
    fake = FakeCombine()
    out = merge([cand("node/1", 0.60), cand("node/2", 0.75, north=1)], combine=fake)
    assert multi_class_calls(fake) == []
    for call in fake.calls:
        assert set(call) <= {"osm"}
    assert max(c.confidence for c in out) == pytest.approx(0.75)


def test_best_score_per_class_is_passed():
    fake = FakeCombine()
    merge(
        [
            cand("img/1", 0.45, "mapillary_cv"),
            cand("img/2", 0.65, "mapillary_cv", north=1),
            cand("node/1", 0.60, east=1),
        ],
        combine=fake,
    )
    assert {"osm": 0.60, "photos": 0.65} in fake.calls


# --- geometry fallback --------------------------------------------------------------------------


def test_facade_one_metre_from_real_door_never_merges_or_boosts():
    fake = FakeCombine()
    door = cand("node/1", 0.75)
    facade = cand("facade/1", 0.30, "geometry_fallback", north=1)
    out = merge([facade, door], combine=fake)
    assert len(out) == 2
    assert by_ref(out, "node/1").confidence == pytest.approx(0.75)
    assert by_ref(out, "facade/1").confidence == pytest.approx(0.30)
    for call in fake.calls:
        assert all(k in {"osm", "photos", "crowd"} for k in call)
    for c in out:
        sources = {p.source for p in c.provenance}
        assert not ("geometry_fallback" in sources and len(sources) > 1)


def test_facade_at_identical_coordinates_still_separate():
    out = merge([cand("node/1", 0.30), cand("facade/1", 0.30, "geometry_fallback")])
    assert len(out) == 2
    assert by_ref(out, "node/1").band == "door"
    assert by_ref(out, "facade/1").provenance[0].source == "geometry_fallback"


def test_stronger_facade_never_becomes_the_door_position():
    """Even if a fallback somehow scores higher, it must not donate position to a real door."""
    out = merge([cand("node/1", 0.20), cand("facade/1", 0.30, "geometry_fallback", north=1)])
    door = by_ref(out, "node/1")
    assert door.id == "id-node/1"
    assert "facade/1" not in refs(door)


# --- strongest member ---------------------------------------------------------------------------


def test_merged_takes_position_label_speak_id_from_strongest():
    strong = cand("img/1", 0.80, "mapillary_cv", north=2, label="Photo door")
    weak = cand("node/1", 0.60, label="OSM door")
    [out] = merge([weak, strong])
    assert (out.lat, out.lon) == (strong.lat, strong.lon)
    assert out.label == "Photo door"
    assert out.speak == strong.speak
    assert out.id == strong.id


def test_tie_prefers_osm_tag_over_input_order():
    photo = cand("img/1", 0.70, "mapillary_cv", north=1, label="Photo door")
    osm = cand("node/1", 0.70, label="OSM door")
    [out] = merge([photo, osm])
    assert out.id == osm.id
    assert out.label == "OSM door"
    assert (out.lat, out.lon) == (osm.lat, osm.lon)


def test_tie_same_class_falls_back_to_input_order():
    a = cand("img/1", 0.65, "mapillary_cv", north=1)
    b = cand("img/2", 0.65, "mapillary_cv")
    c = cand("crowd/1", 0.50, "crowd", east=1)
    [out] = merge([a, b, c])
    assert out.id == a.id
    [out] = merge([b, a, c])
    assert out.id == b.id


# --- confidence clamp ---------------------------------------------------------------------------


def test_confidence_already_above_cap_is_clamped_when_merged():
    [out] = merge([cand("node/1", 0.99), cand("img/1", 0.65, "mapillary_cv", north=1)])
    assert out.confidence <= CAP


def test_singleton_above_cap_is_clamped():
    """Spec ambiguity: does a single-member cluster go through combine/clamp? Safer if yes."""
    [out] = merge([cand("node/1", 0.99)])
    assert out.confidence <= CAP


def test_combine_returning_more_than_one_is_clamped():
    fake = FakeCombine(result=1.7)
    [out] = merge(
        [cand("node/1", 0.75), cand("img/1", 0.65, "mapillary_cv", north=1)], combine=fake
    )
    assert out.confidence == pytest.approx(CAP)
    Candidate.model_validate(out.model_dump())  # still contract-valid


# --- provenance ---------------------------------------------------------------------------------


def test_duplicate_provenance_entries_are_deduplicated():
    tags = {"entrance": "main"}
    a = cand("node/1", 0.75)
    a = a.model_copy(
        update={"provenance": [Provenance(source="osm_tag", ref="node/1", tags=tags)] * 2}
    )
    b = cand("img/1", 0.65, "mapillary_cv", north=1)
    b = b.model_copy(
        update={
            "provenance": [
                Provenance(source="mapillary_cv", ref="img/1"),
                Provenance(source="osm_tag", ref="node/1", tags=dict(tags)),
            ]
        }
    )
    [out] = merge([a, b])
    dumped = [p.model_dump() for p in out.provenance]
    assert len(dumped) == len({repr(sorted(d.items())) for d in dumped}) == 2
    assert dumped[0]["ref"] == "node/1"  # strongest member's provenance leads, or input order


def test_provenance_order_is_stable_across_runs():
    cands = [
        cand("img/1", 0.65, "mapillary_cv", north=1),
        cand("node/1", 0.75),
        cand("crowd/1", 0.5, "crowd", east=1),
    ]
    first = [p.ref for p in merge(cands)[0].provenance]
    for _ in range(5):
        assert [p.ref for p in merge(cands)[0].provenance] == first


# --- chains, determinism, permutations ----------------------------------------------------------


def test_long_chain_does_not_collapse_into_one_door():
    """Ten candidates 3 m apart span 27 m. Single-linkage would make one 27 m "door"."""
    sources = ["osm_tag", "mapillary_cv"]
    chain = [cand(f"r/{i}", 0.5 + 0.01 * i, sources[i % 2], north=3.0 * i) for i in range(10)]
    out = merge(chain)
    assert len(out) >= 3
    for c in out:
        members = [x for x in chain if x.provenance[0].ref in refs(c)]
        lats = [x.lat for x in members]
        span_m = math.radians(max(lats) - min(lats)) * R_EARTH
        assert span_m <= 2 * 4.0 + 1e-6, f"cluster spans {span_m:.1f} m"


def _canonical(out):
    return sorted(
        (c.id, round(c.lat, 9), round(c.lon, 9), c.label, round(c.confidence, 9), sorted(refs(c)))
        for c in out
    )


PERMUTATION_SETS = {
    # Distinct scores, so no tie-break depends on input order.
    "chain": [
        cand("node/1", 0.75),
        cand("img/1", 0.65, "mapillary_cv", north=3),
        cand("crowd/1", 0.55, "crowd", north=6),
        cand("node/2", 0.60, north=9),
    ],
    "mixed": [
        cand("node/1", 0.90),
        cand("img/1", 0.65, "mapillary_cv", east=2),
        cand("facade/1", 0.30, "geometry_fallback", north=1),
        cand("node/2", 0.50, north=20),
        cand("crowd/1", 0.55, "crowd", north=22),
    ],
}


@pytest.mark.parametrize("name", PERMUTATION_SETS)
def test_input_order_permutation_invariance(name):
    cands = PERMUTATION_SETS[name]
    results = {repr(_canonical(merge(p))) for p in itertools.permutations(cands)}
    assert len(results) == 1, f"{len(results)} different outputs over input orders"


def test_every_input_lands_in_exactly_one_output():
    rng = random.Random(6)
    sources = ["osm_tag", "mapillary_cv", "crowd", "geometry_fallback"]
    cands = [
        cand(
            f"r/{i}",
            round(rng.uniform(0.2, 0.9), 3),
            sources[i % 4],
            north=rng.uniform(0, 60),
            east=rng.uniform(0, 60),
        )
        for i in range(60)
    ]
    out = merge(cands)
    seen = [r for c in out for r in refs(c)]
    assert sorted(seen) == sorted(f"r/{i}" for i in range(60))


def test_ids_are_stable_and_unique():
    cands = [
        cand("node/1", 0.75),
        cand("img/1", 0.65, "mapillary_cv", north=1),
        cand("node/2", 0.60, north=30),
        cand("facade/1", 0.30, "geometry_fallback", north=31),
    ]
    first = [c.id for c in merge(cands)]
    assert first == [c.id for c in merge(cands)]
    assert len(set(first)) == len(first)
    assert set(first) <= {c.id for c in cands}


def test_200_candidates_under_one_second():
    rng = random.Random(42)
    sources = ["osm_tag", "mapillary_cv", "crowd", "geometry_fallback"]
    cands = [
        cand(
            f"r/{i}",
            round(rng.uniform(0.2, 0.9), 3),
            sources[i % 4],
            north=rng.uniform(0, 150),
            east=rng.uniform(0, 150),
        )
        for i in range(200)
    ]
    start = time.perf_counter()
    out = merge(cands)
    assert time.perf_counter() - start < 1.0
    assert 0 < len(out) <= 200


# --- bad coordinates (see module docstring for the decision) ------------------------------------


@pytest.mark.parametrize("bad", [math.nan, math.inf, -math.inf])
def test_non_finite_coordinates_are_rejected(bad):
    good = cand("node/1", 0.75)
    broken = cand("img/1", 0.65, "mapillary_cv").model_copy(update={"lat": bad})
    with pytest.raises(ValueError):
        merge([good, broken])


def test_none_coordinates_are_rejected():
    good = cand("node/1", 0.75)
    broken = Candidate.model_construct(
        **(cand("img/1", 0.65, "mapillary_cv").__dict__ | {"lon": None})
    )
    with pytest.raises((ValueError, TypeError)):
        merge([good, broken])
