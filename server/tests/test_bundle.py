"""Tests for app/bundle.py: pilot bundle assembly with fake stages. Nothing here calls a network."""

import dataclasses
import functools
import json
from pathlib import Path

import pytest

from app import bundle, doors, overpass, resolver, scoring
from app.bundle import Facade, PilotSite, Stages
from app.models import Candidate, DataVersion, ResolveRequest, ResolveResult
from app.resolver import GeocodedPoint, RateLimiter

SERVER = Path(__file__).resolve().parents[1]
FIXTURES = Path(__file__).parent / "fixtures" / "nominatim"
VERSION = DataVersion(osm="2026-10-01", model="none")
SITE = PilotSite(
    id="mit-77-mass-ave",
    address="77 Massachusetts Ave, Cambridge, MA 02139",
    name="MIT Building 7",
    scenario="campus",
)
POINT = GeocodedPoint(lat=42.3592, lon=-71.0934, source="nominatim", housenumber="77")
BUILDING = {
    "osm_id": "way/1",
    "name": None,
    "housenumber": "77",
    "footprint": [
        [-71.0933, 42.3594],
        [-71.0929, 42.3594],
        [-71.0929, 42.3591],
        [-71.0933, 42.3594],
    ],
}
STREET_SIDE = {
    "entrance_street": "Massachusetts Avenue",
    "road_way": "way/2",
    "centerline": [[-71.0928, 42.3595], [-71.0928, 42.359]],
    "door_side_of_road": "right",
    "oneway": False,
}
CHECKS = {"crosses_road": False, "nearest_crossing": None, "footway_to_entrance": True}


def door(confidence, ref, band="door", lon=-71.0930, tags=None):
    """A candidate as a stage might return it; the band is deliberately not trusted."""
    return {
        "id": "x",
        "lat": 42.3592,
        "lon": lon,
        "confidence": confidence,
        "band": band,
        "label": "Door",
        "provenance": [{"source": "osm_tag", "ref": ref, "tags": tags}],
    }


# 25 m east of the doors, so drop_fallbacks_near_doors keeps it.
FACADE = door(0.30, None, band="facade", lon=-71.0927) | {
    "provenance": [{"source": "geometry_fallback"}],
}


def fake_stages(doors, facade=(FACADE,), **overrides) -> Stages:
    stages = Stages(
        geocode=lambda request: POINT,
        find_building=lambda point: BUILDING,
        read_entrances=lambda building, number: list(doors),
        facade_fallback=lambda building, point: Facade(
            candidates=list(facade), street_side=STREET_SIDE
        ),
        street_side=lambda building, top, point: STREET_SIDE,
        path_checks=lambda building, top, street_side: CHECKS,
        path_warnings=lambda building, top, street_side: [],
    )
    return dataclasses.replace(stages, **overrides)


def test_happy_path_is_a_contract_valid_bundle(tmp_path):
    report = bundle.run_site(SITE, fake_stages([door(0.90, "node/3")]), VERSION)

    assert report.ok, report.describe()
    path = bundle.write_bundle(report.bundle, SITE.id, tmp_path)
    data = json.loads(path.read_text(encoding="utf-8"))
    ResolveResult.model_validate(data)
    contract = json.loads((SERVER.parent / "contract" / "resolve.example.json").read_text("utf-8"))
    assert data.keys() == contract.keys()
    assert data["destination_id"] == "dst_mit-77-mass-ave"
    assert data["status"] == "complete"
    assert data["attribution"] == [bundle.OSM_ATTRIBUTION]
    assert data["data_version"] == {"osm": "2026-10-01", "model": "none"}
    assert data["street_side"]["door_side_of_road"] == "right"
    assert data["recognize"] == {"text": ["77", "MIT Building 7"]}
    assert [c["id"] for c in data["candidates"]] == ["c1", "c2"]


def test_candidates_are_sorted_capped_and_at_most_five():
    doors = [door(s, f"node/{i}") for i, s in enumerate([0.5, 1.0, 0.6, 0.75, 0.2, 0.55])]
    result = bundle.run_site(SITE, fake_stages(doors), VERSION).bundle

    confidences = [c.confidence for c in result.candidates]
    assert len(result.candidates) == bundle.MAX_CANDIDATES
    assert confidences == sorted(confidences, reverse=True)
    assert max(confidences) == scoring.CAP
    assert result.candidates[0].provenance[0].ref == "node/1"  # the 1.0 door, capped to 0.95


def top_refs(result):
    return [c.provenance[0].ref for c in result.candidates]


def test_tied_main_doors_prefer_the_house_number_then_the_street():
    """E2E I-5: several main doors tie at the 0.95 cap. STREET_SIDE runs at lon -71.0928."""
    far = -71.0933  # ~40 m from the centerline
    near = -71.0929  # ~8 m
    doors = [
        door(0.95, "node/far", lon=far),
        door(0.95, "node/near", lon=near),
        door(1.0, "node/77", lon=far, tags={"addr:housenumber": "77", "entrance": "main"}),
        door(0.95, "node/79", lon=near, tags={"addr:housenumber": "79"}),
    ]
    result = bundle.run_site(SITE, fake_stages(doors), VERSION).bundle
    assert top_refs(result)[:4] == ["node/77", "node/near", "node/79", "node/far"]
    assert {c.confidence for c in result.candidates[:4]} == {scoring.CAP}


def test_ties_keep_the_original_order_without_a_street_side():
    doors = [door(0.95, "node/a", lon=-71.0933), door(0.95, "node/b", lon=-71.0929)]
    ranked = bundle.rank([Candidate.model_validate(d) for d in doors])
    assert [c.provenance[0].ref for c in ranked] == ["node/a", "node/b"]


def test_a_tie_break_never_beats_a_higher_score():
    doors = [door(0.85, "node/77", tags={"addr:housenumber": "77"}), door(0.90, "node/9")]
    result = bundle.run_site(SITE, fake_stages(doors), VERSION).bundle
    assert top_refs(result)[:2] == ["node/9", "node/77"]


@pytest.mark.parametrize(
    ("name", "site_name", "text"),
    [
        ("Brattle Theatre", "Brattle Theatre", ["77", "Brattle Theatre"]),
        (
            "Ray and Maria Stata Center",
            "MIT Building 7",
            ["77", "Ray and Maria Stata Center", "MIT Building 7"],
        ),
        (None, None, ["77"]),
    ],
)
def test_recognize_text_has_number_building_and_site_names(name, site_name, text):
    """E2E I-10: the mapped name and the site name both go in, without repeats."""
    site = SITE.model_copy(update={"name": site_name})
    stages = fake_stages([door(0.9, "node/1")], find_building=lambda p: BUILDING | {"name": name})
    assert bundle.run_site(site, stages, VERSION).bundle.recognize.text == text


# Fix R12: the destination's number always; the building's numbers only when they include it.
@pytest.mark.parametrize(
    ("tagged", "text"),
    [
        ("75", ["77", "MIT Building 7"]),  # a fallback outline that is the neighbour
        ("77;79", ["77", "79", "MIT Building 7"]),
        (None, ["77", "MIT Building 7"]),
    ],
)
def test_r12_recognize_text_keeps_the_destination_number(tagged, text):
    stages = fake_stages(
        [door(0.9, "node/1")], find_building=lambda p: BUILDING | {"housenumber": tagged}
    )
    assert bundle.run_site(SITE, stages, VERSION).bundle.recognize.text == text


# Fix R10: street_side comes from the street_side stage for candidates[0], not the facade's.
def test_r10_street_side_and_path_checks_get_the_top_candidate():
    seen = []
    other = STREET_SIDE | {"entrance_street": "Side Street", "road_way": "way/3"}
    stages = fake_stages(
        [door(0.80, "node/2"), door(0.90, "node/9")],
        street_side=lambda b, top, p: seen.append(top.provenance[0].ref) or other,
        path_checks=lambda b, top, side: seen.append(side.road_way) or CHECKS,
    )
    result = bundle.run_site(SITE, stages, VERSION).bundle
    # rank asks street_side of each candidate in turn (none is on the address street here).
    assert seen[-2:] == ["node/9", "way/3"]
    assert result.street_side.entrance_street == "Side Street"


def test_a_candidate_on_the_address_street_goes_before_one_that_is_not():
    """The car stops on the address's street: a lower door reachable from it goes first."""
    other = STREET_SIDE | {"entrance_street": "Side Street", "road_way": "way/3"}

    def side(b, top, p):
        return STREET_SIDE if top.provenance[0].ref == "node/2" else other

    point = dataclasses.replace(POINT, street="77 Massachusetts Ave")
    stages = fake_stages(
        [door(0.80, "node/2"), door(0.90, "node/9")], street_side=side, geocode=lambda r: point
    )
    result = bundle.run_site(SITE, stages, VERSION).bundle
    assert [c.provenance[0].ref for c in result.candidates[:2]] == ["node/2", "node/9"]
    assert [c.id for c in result.candidates[:2]] == ["c1", "c2"]


def test_band_comes_from_scoring_band_not_the_stage(monkeypatch):
    doors = [door(0.90, "node/1", band="facade"), door(0.50, "node/2", band="main")]
    result = bundle.run_site(SITE, fake_stages(doors), VERSION).bundle
    assert [c.band for c in result.candidates] == ["main", "door", "facade"]

    seen = []
    monkeypatch.setattr(scoring, "band", lambda c: seen.append(c) or "door")
    result = bundle.run_site(SITE, fake_stages(doors), VERSION).bundle
    assert sorted(seen) == [0.3, 0.5, 0.9]
    assert {c.band for c in result.candidates} == {"door"}


def test_facade_only_is_partial():
    result = bundle.run_site(SITE, fake_stages([]), VERSION).bundle
    assert result.status == "partial"
    assert [c.band for c in result.candidates] == ["facade"]


@pytest.mark.parametrize(
    ("stage", "task"),
    [
        ("find_building", "BE-3"),
        ("read_entrances", "BE-4"),
        ("facade_fallback", "BE-5"),
        ("path_checks", "BE-7"),
    ],
)
def test_a_todo_stage_is_reported_as_blocked(stage, task):
    def todo(*args):
        raise NotImplementedError(task)

    report = bundle.run_site(SITE, fake_stages([door(0.9, "node/1")], **{stage: todo}), VERSION)
    assert not report.ok
    assert report.describe() == f"blocked on {task} ({stage})"


def test_a_stage_with_the_wrong_output_shape_fails_with_its_name():
    stages = fake_stages([], find_building=lambda point: {"osm_id": "way/1"})  # no footprint
    report = bundle.run_site(SITE, stages, VERSION)
    assert report.describe().startswith("failed at find_building: ValidationError")


def test_no_candidates_at_all_is_a_failure():
    report = bundle.run_site(SITE, fake_stages([], facade=()), VERSION)
    assert not report.ok and report.error.stage == "facade_fallback"


def test_one_blocked_site_does_not_stop_the_others():
    def by_site(request):
        if request.address == "bad":
            raise NotImplementedError("BE-3")
        return POINT

    sites = [SITE.model_copy(update={"id": "bad", "address": "bad"}), SITE]
    reports = [bundle.run_site(s, fake_stages([], geocode=by_site), VERSION) for s in sites]
    assert [r.ok for r in reports] == [False, True]


def replay_site(monkeypatch, overpass_dir: Path, site: PilotSite = SITE) -> bundle.SiteReport:
    """Default stages, real geocoder over saved Nominatim responses, Overpass offline."""
    monkeypatch.setenv("USER_AGENT", "MIT-AT-CarToCurb/test")
    monkeypatch.setattr(doors, "CLIENT", overpass.Client(cache_dir=overpass_dir, offline=True))
    monkeypatch.setattr(resolver, "_nominatim_limiter", RateLimiter(0))
    doors._area.cache_clear()
    resolver.clear_geocode_cache()
    try:
        with bundle.replay_client(FIXTURES) as client:
            stages = Stages(geocode=functools.partial(resolver.geocode, client=client))
            return bundle.run_site(site, stages, VERSION)
    finally:
        resolver.clear_geocode_cache()
        doors._area.cache_clear()


# Fix R15: the replay must really run BE-3/5/7 on saved Overpass data, not pass when blocked.
def test_offline_replay_runs_the_whole_ladder_on_saved_overpass_data(monkeypatch):
    report = replay_site(monkeypatch, SERVER / "tests" / "fixtures" / "overpass")
    if not report.ok and isinstance(report.error.cause, overpass.OverpassUnavailable):
        pytest.skip(
            f"no saved Overpass responses for {SITE.id} ({report.error.stage}); "
            "run scripts/build_bundles.py online and commit tests/fixtures/overpass"
        )
    assert report.ok, report.describe()
    result = report.bundle
    assert result.building.osm_id.split("/")[0] in {"way", "relation"}
    assert result.candidates and result.street_side is not None
    assert result.street_side.road_way.startswith("way/")


def test_offline_replay_without_overpass_data_is_blocked_after_geocode(monkeypatch, tmp_path):
    report = replay_site(monkeypatch, tmp_path)
    assert not report.ok and report.error.stage == "find_building"
    assert isinstance(report.error.cause, overpass.OverpassUnavailable)


def test_offline_replay_refuses_unsaved_queries(monkeypatch):
    monkeypatch.setenv("USER_AGENT", "MIT-AT-CarToCurb/test")
    monkeypatch.setattr(resolver, "_nominatim_limiter", RateLimiter(0))
    resolver.clear_geocode_cache()
    with bundle.replay_client(FIXTURES) as client, pytest.raises(bundle.NoSavedResponse):
        resolver.geocode(ResolveRequest(address="5 Nowhere St, Cambridge"), client=client)


def test_pilot_sites_are_valid_and_reuse_recorded_addresses():
    sites = bundle.load_sites(SERVER / "pilot_sites.json")
    recorded = json.loads((FIXTURES / "addresses.json").read_text(encoding="utf-8"))["addresses"]
    known = {e["address"] for e in recorded if e.get("expect") != "not_found"}
    assert len(sites) >= 10
    assert {s.address for s in sites} <= known


def test_duplicate_site_ids_are_rejected(tmp_path):
    path = tmp_path / "sites.json"
    site = SITE.model_dump()
    path.write_text(json.dumps({"sites": [site, site]}), encoding="utf-8")
    with pytest.raises(ValueError, match="duplicate"):
        bundle.load_sites(path)


def test_site_ids_must_be_safe_file_names():
    with pytest.raises(ValueError):
        PilotSite(id="../etc", address="1 Broadway", scenario="campus")


def test_fallback_guesses_on_top_of_a_mapped_door_are_dropped():
    on_door = FACADE | {"lon": -71.09302}  # about 1.6 m from the door at -71.0930
    far = FACADE  # 25 m away
    result = bundle.run_site(SITE, fake_stages([door(0.90, "node/3")], (on_door, far)), VERSION)
    assert [c.provenance[0].source for c in result.bundle.candidates] == [
        "osm_tag",
        "geometry_fallback",
    ]
    assert result.bundle.candidates[1].lon == pytest.approx(-71.0927)
    # With no mapped door the guesses are all there is, and they stay.
    alone = bundle.run_site(SITE, fake_stages([], (on_door, far)), VERSION)
    assert len(alone.bundle.candidates) == 2


B7 = PilotSite(
    id="mit-building-7",
    address="77 Massachusetts Ave, Cambridge, MA 02139",
    name="MIT Building 7",
    scenario="campus",
)


def test_building_7_from_the_saved_osm_data(monkeypatch):
    """MIT Building 7 (Lobby 7) on the committed Overpass responses of 2026-10-30, a regression
    pin (c2 below street level is inferred from incline=down tags, not surveyed). Raw OSM:
    node/981493472 entrance=main at the top of steps way/243332876 (step_count=17, but
    ramp=separate, so no count is spoken); node/9279372526 reached only by paths tagged incline=down; crosswalk
    way/84473999 (crossing=traffic_signals) over Massachusetts Avenue at node/579060230."""
    report = replay_site(monkeypatch, SERVER / "tests" / "fixtures" / "overpass", B7)
    assert report.ok, report.describe()
    r = report.bundle
    assert r.building.osm_id == "way/32517230"
    main, side_door = r.candidates  # the facade and address guesses sat on these two doors
    assert main.provenance[0].ref == "node/981493472" and main.band == "main"
    # A ramp exists elsewhere (ramp=separate), so "17 steps" is not the only way in.
    assert main.speak is None
    assert [p.ref for p in main.provenance] == ["node/981493472"]
    assert side_door.provenance[0].ref == "node/9279372526"
    assert side_door.confidence == pytest.approx(0.70) and side_door.speak is None
    # the incline=down ways the 0.10 drop came from are cited
    assert {"way/1005738160", "way/1005738158"} <= {p.ref for p in side_door.provenance}
    s = r.street_side
    assert (s.entrance_street, s.door_side_of_road, s.oneway) == (
        "Massachusetts Avenue",
        "right",
        False,
    )
    # The far-side kerb end of crosswalk way/84473999 (node/10988282760), not the signal node
    # node/579060230 in the middle of the road.
    assert s.crossing == [-71.0936796, 42.3590093]
    # The centerline continues north past the signal into way/1321779881.
    assert max(lat for _, lat in s.centerline) > main.lat + 0.0003
    assert r.path_checks.crosses_road is False and r.path_checks.nearest_crossing is None
    assert r.recognize.text == [
        "77",
        "7 Rogers Building",
        "MIT Building 7",
        "William Barton Rogers Building",
        "Rogers Building",
    ]
