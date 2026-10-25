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


FACADE = door(0.30, None, band="facade") | {
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
        path_checks=lambda building, top, street_side: CHECKS,
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


def test_offline_replay_runs_the_real_geocoder(monkeypatch):
    """Default stages, real geocoder over saved responses, Overpass offline: geocode succeeds and
    the run gets as far as the saved Overpass responses allow."""
    monkeypatch.setenv("USER_AGENT", "MIT-AT-CarToCurb/test")
    offline = overpass.Client(cache_dir=SERVER / "tests" / "fixtures" / "overpass", offline=True)
    monkeypatch.setattr(doors, "CLIENT", offline)
    monkeypatch.setattr(resolver, "_nominatim_limiter", RateLimiter(0))
    resolver.clear_geocode_cache()
    with bundle.replay_client(FIXTURES) as client:
        stages = Stages(geocode=functools.partial(resolver.geocode, client=client))
        report = bundle.run_site(SITE, stages, VERSION)
    resolver.clear_geocode_cache()

    assert report.ok or report.error.stage != "geocode", report.describe()


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
