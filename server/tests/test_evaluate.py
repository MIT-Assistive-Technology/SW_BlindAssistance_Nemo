"""QA-2 / BE-12: bundle evaluation against golden truth.

Everything here is synthetic: made-up truth and bundles built in memory or in tmp_path.
Nothing is written to golden/locations.json and nothing calls a network.
"""

import importlib.util
import json
import math
from pathlib import Path

import pytest

from app import evaluate as ev

SERVER = Path(__file__).resolve().parents[1]
REPO = SERVER.parent

_spec = importlib.util.spec_from_file_location(
    "evaluate_bundles", SERVER / "scripts" / "evaluate_bundles.py"
)
cli = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cli)

LAT0, LON0 = 42.3600, -71.0900  # synthetic door, not a real survey
M_PER_DEG = math.radians(ev.EARTH_RADIUS_M)


def offset(lat, lon, east_m=0.0, north_m=0.0):
    return (
        lat + north_m / M_PER_DEG,
        lon + east_m / (M_PER_DEG * math.cos(math.radians(lat))),
    )


def centerline_east(north_m=10.0):
    """[lon, lat] road running west -> east, `north_m` north of the synthetic door."""
    a = offset(LAT0, LON0, -50, north_m)
    b = offset(LAT0, LON0, 50, north_m)
    return [[a[1], a[0]], [b[1], b[0]]]


def location(
    site_id,
    scenario="same_side",
    measured=True,
    uncertain=False,
    building="way/1",
    drop_offs=None,
    **extra,
):
    loc = {
        "id": site_id,
        "status": "measured" if measured else "template",
        "address": f"{site_id} Test St, Cambridge, MA",
        "fixture_id": None,
        "scenario": scenario,
        "counts_toward_april": scenario in ("same_side", "driveway"),
        "entrance_truth": {
            "lat": LAT0 if measured else None,
            "lon": LON0 if measured else None,
        },
        "drop_off_points": drop_offs
        if drop_offs is not None
        else [
            {
                "id": "front",
                "street": "Test St",
                "curb_side": "right",
                "side_vs_door": "same",
            }
        ],
        "truth_uncertain": uncertain,
        **extra,
    }
    if building:
        loc["building_osm_id"] = building
    return loc


def candidate(east_m=0.0, north_m=0.0, band="main", source="osm_tag"):
    lat, lon = offset(LAT0, LON0, east_m, north_m)
    return {
        "lat": lat,
        "lon": lon,
        "band": band,
        "confidence": 0.9,
        "provenance": [{"source": source}],
    }


def bundle(site_id, candidates=None, side="right", building="way/1", street="Test Street"):
    b = {
        "destination_id": f"dst_{site_id}",
        "building": {"osm_id": building},
        "candidates": candidates if candidates is not None else [candidate(1.0)],
        "street_side": None,
    }
    if side:
        b["street_side"] = {
            "entrance_street": street,
            "centerline": centerline_east(),
            "door_side_of_road": side,
        }
    return b


# ---------------------------------------------------------------- math


def test_haversine_known_distances():
    assert ev.haversine_m(LAT0, LON0, LAT0, LON0) == 0
    assert ev.haversine_m(0, 0, 1, 0) == pytest.approx(111_195, rel=1e-4)
    lat, lon = offset(LAT0, LON0, east_m=3, north_m=4)
    assert ev.haversine_m(LAT0, LON0, lat, lon) == pytest.approx(5.0, abs=0.01)


def test_wilson_interval_matches_reference_values():
    lo, hi = ev.wilson_interval(5, 10)
    assert (lo, hi) == (pytest.approx(0.2366, abs=1e-4), pytest.approx(0.7634, abs=1e-4))
    lo, hi = ev.wilson_interval(0, 10)
    assert lo == 0 and hi == pytest.approx(0.2775, abs=1e-4)
    assert ev.wilson_interval(10, 10)[1] == 1.0
    assert ev.wilson_interval(0, 0) is None
    with pytest.raises(ValueError):
        ev.wilson_interval(3, 2)


def test_upper_bound_uses_rule_of_three_only_at_zero():
    assert ev.upper_bound_95(0, 10) == pytest.approx(0.3)
    assert ev.upper_bound_95(0, 2) == 1.0  # 3/2 capped
    assert ev.upper_bound_95(1, 10) == pytest.approx(ev.wilson_interval(1, 10)[1])
    assert ev.upper_bound_95(0, 0) is None


@pytest.mark.parametrize(
    ("values", "p", "expected"),
    [
        ([], 90, None),
        ([7.0], 90, 7.0),
        ([1.0, 9.0], 50, 1.0),
        ([3.0, 1.0, 2.0], 90, 3.0),  # n < 10: p90 is the max
        (list(range(1, 11)), 90, 9),
        (list(range(1, 21)), 90, 18),
    ],
)
def test_percentile_nearest_rank_small_n(values, p, expected):
    assert ev.percentile(values, p) == expected


def test_median_small_n():
    assert ev.median([]) is None
    assert ev.median([4.0]) == 4.0
    assert ev.median([2.0, 6.0]) == 4.0


def test_side_of_line_sign_rule():
    # Road runs east, door is 10 m south of it: right (plan section 6 worked example).
    assert ev.side_of_line(centerline_east(10), LAT0, LON0) == "right"
    assert ev.side_of_line(centerline_east(-10), LAT0, LON0) == "left"
    assert ev.side_of_line(list(reversed(centerline_east(10))), LAT0, LON0) == "left"
    assert ev.side_of_line([[LON0, LAT0]], LAT0, LON0) is None


# ---------------------------------------------------------------- per-site checks


def test_confident_wrong_needs_main_band_and_over_10m():
    loc = location("a")
    far_main = ev.score_site(loc, bundle("a", [candidate(12.0, band="main")]))
    far_door = ev.score_site(loc, bundle("a", [candidate(12.0, band="door")]))
    near_main = ev.score_site(loc, bundle("a", [candidate(8.0, band="main")]))
    assert far_main["confident_wrong"] is True
    assert far_door["confident_wrong"] is False
    assert near_main["confident_wrong"] is False
    assert far_main["error_m"] == pytest.approx(12.0, abs=0.01)


def test_top5_hit_looks_past_the_top_candidate():
    loc = location("a")
    s = ev.score_site(loc, bundle("a", [candidate(20), candidate(9), candidate(4)]))
    assert s["error_m"] == pytest.approx(20, abs=0.01)
    assert s["top5_hit"] is True
    miss = ev.score_site(loc, bundle("a", [candidate(20), candidate(6)]))
    assert miss["top5_hit"] is False


def test_side_agree_and_disagree():
    loc = location("a")  # curb right, door same side -> door right; door is south of road
    assert ev.side_check(loc, bundle("a", side="right"))["verdict"] == "agree"
    assert ev.side_check(loc, bundle("a", side="left"))["verdict"] == "disagree"
    across = location(
        "b",
        drop_offs=[
            {"id": "x", "street": "Test St", "curb_side": "left", "side_vs_door": "opposite"}
        ],
    )
    assert ev.side_check(across, bundle("b", side="right"))["verdict"] == "agree"


def test_side_unknown_cases():
    no_curb = location(
        "a",
        measured=False,
        drop_offs=[{"id": "x", "street": "Test St", "curb_side": None, "side_vs_door": "same"}],
    )
    r = ev.side_check(no_curb, bundle("a"))
    assert (r["verdict"], r["cause"]) == ("unknown", "truth")

    other_street = location(
        "b",
        measured=False,
        drop_offs=[{"id": "x", "street": "Main St", "curb_side": "right", "side_vs_door": "same"}],
    )
    assert ev.side_check(other_street, bundle("b"))["verdict"] == "unknown"

    r = ev.side_check(location("c"), bundle("c", side=None))
    assert (r["verdict"], r["cause"]) == ("unknown", "bundle")

    # Drop-off says door on the left, but the measured door is south (right) of the road.
    conflict = location(
        "d",
        drop_offs=[{"id": "x", "street": "Test St", "curb_side": "left", "side_vs_door": "same"}],
    )
    r = ev.side_check(conflict, bundle("d"))
    assert r["verdict"] == "unknown" and "truth disagrees" in r["reason"]


def test_building_check():
    assert ev.building_check(location("a"), bundle("a"))["verdict"] == "correct"
    assert ev.building_check(location("a"), bundle("a", building="way/9"))["verdict"] == "wrong"
    loc = location("a", building=None)
    assert ev.building_check(loc, bundle("a"))["verdict"] == "not_evaluated"


# ---------------------------------------------------------------- joining and coverage


def test_join_by_id_fixture_and_address():
    locs = [
        location("by-id"),
        location("golden-x", fixture_id="fx"),
        {**location("golden-y"), "address": "1 Main St., Cambridge MA"},
        location("nothing"),
    ]
    bundles = {"by-id": bundle("by-id"), "fx": bundle("fx"), "pilot-y": bundle("pilot-y")}
    pilot = [{"id": "pilot-y", "address": "1 Main St, Cambridge, MA", "scenario": "campus"}]
    pairs = {loc["id"]: (bid, how) for loc, bid, how in ev.join(locs, bundles, pilot)}
    assert pairs == {
        "by-id": ("by-id", "id"),
        "golden-x": ("fx", "fixture_id"),
        "golden-y": ("pilot-y", "address"),
        "nothing": (None, None),
    }
    report = ev.evaluate(locs, bundles, pilot)
    assert any("golden-y" in n and "'campus'" in n for n in report["notes"])


def test_skipped_sites_are_listed_and_never_scored():
    locs = [
        location("ok"),
        location("template", measured=False),
        location("shaky", uncertain=True),
        location("no-bundle"),
        location("both", measured=False, uncertain=True),
    ]
    bundles = {k: bundle(k) for k in ("ok", "template", "shaky", "both", "extra")}
    r = ev.evaluate(locs, bundles)
    assert [s["id"] for s in r["scored"]] == ["ok"]
    reasons = {s["id"]: s["reasons"] for s in r["skipped"]}
    assert reasons == {
        "template": ["truth_null"],
        "shaky": ["truth_uncertain"],
        "no-bundle": ["no_bundle"],
        "both": ["truth_null", "truth_uncertain"],
    }
    assert r["unmatched_bundles"] == ["extra"]
    assert r["coverage"]["golden_sites_with_bundle"] == 4
    assert r["coverage"]["skip_reasons"]["truth_null"] == 2
    assert r["overall"]["n"] == 1
    assert r["enough_data"] is False
    assert r["go_no_go"]["overall"] == ev.NOT_ENOUGH


def test_scenario_breakdown_and_alias():
    locs = [location("a", "same_side"), location("b", "opposite_side"), location("c", "campus")]
    bundles = {
        "a": bundle("a", [candidate(2)]),
        "b": bundle("b", [candidate(7)]),
        "c": bundle("c", [candidate(30, band="door")]),
    }
    r = ev.evaluate(locs, bundles)
    assert r["by_scenario"]["opposite"]["n"] == 1
    assert r["by_scenario"]["driveway"]["n"] == 0
    assert r["by_scenario"]["driveway"]["median_m"] is None
    assert r["april_gating"]["n"] == 1
    w = r["overall"]["within"]
    assert (w["3m"]["k"], w["5m"]["k"], w["10m"]["k"]) == (1, 1, 2)
    assert r["overall"]["median_m"] == pytest.approx(7, abs=0.01)
    assert r["overall"]["p90_m"] == pytest.approx(30, abs=0.01)


# ---------------------------------------------------------------- go / no-go


def _ten(errors=None, **bundle_kw):
    errors = errors or [1.0] * 10
    scen = ["same_side"] * 4 + ["driveway"] * 2 + ["opposite_side"] * 2 + ["campus"] * 2
    locs = [location(f"s{i}", scen[i]) for i in range(10)]
    bundles = {f"s{i}": bundle(f"s{i}", [candidate(e)], **bundle_kw) for i, e in enumerate(errors)}
    return locs, bundles


def _verdicts(report):
    return {c["criterion"]: c["verdict"] for c in report["go_no_go"]["criteria"]}


def test_all_good_is_go():
    r = ev.evaluate(*_ten())
    assert r["go_no_go"]["overall"] == ev.GO, r["go_no_go"]
    assert r["confident_wrong"]["text"].startswith("0 in 10 (95% upper bound 30%")


def test_wrong_building_anywhere_is_no_go():
    locs, bundles = _ten()
    bundles["s3"]["building"]["osm_id"] = "way/999"
    r = ev.evaluate(locs, bundles)
    assert _verdicts(r)["Correct building at every site"] == ev.NO_GO
    assert r["go_no_go"]["overall"] == ev.NO_GO


def test_missing_building_truth_blocks_go():
    locs, bundles = _ten()
    del locs[0]["building_osm_id"]
    r = ev.evaluate(locs, bundles)
    assert _verdicts(r)["Correct building at every site"] == ev.NOT_EVALUATED
    assert r["go_no_go"]["overall"] == ev.NOT_ENOUGH


def test_within_10m_below_80_percent_is_no_go():
    r = ev.evaluate(*_ten([1.0] * 7 + [15.0] * 3))
    assert _verdicts(r)["Top door within 10 m at >= 80% of sites"] == ev.NO_GO
    assert r["confident_wrong"]["k"] == 3
    assert r["confident_wrong"]["method"] == "Wilson score"
    assert r["go_no_go"]["overall"] == ev.NO_GO


def test_side_below_90_percent_is_no_go():
    locs, bundles = _ten()
    bundles["s0"]["street_side"]["door_side_of_road"] = "left"
    bundles["s1"]["street_side"] = None  # bundle gap counts against the bundle
    r = ev.evaluate(locs, bundles)
    assert r["go_no_go"]["criteria"][2]["rate"]["k"] == 8
    assert _verdicts(r)["Correct building side >= 90%"] == ev.NO_GO


def test_street_photo_targets_and_never_main():
    locs, _ = _ten()
    bundles = {
        f"s{i}": bundle(f"s{i}", [candidate(e, band="door", source="mapillary_cv")])
        for i, e in enumerate([1, 2, 3, 3, 3, 4, 4, 5, 6, 9])
    }
    r = ev.evaluate(locs, bundles)
    assert r["street_photo"]["median_m"] == pytest.approx(3.5, abs=0.01)
    assert r["street_photo"]["p90_m"] == pytest.approx(6, abs=0.01)
    photo = "Street-photo doors: median <= 4 m, p90 <= 8 m, never main"
    assert _verdicts(r)[photo] == ev.GO

    bundles["s0"]["candidates"][0]["band"] = "main"
    assert _verdicts(ev.evaluate(locs, bundles))[photo] == ev.NO_GO


def test_four_measured_sites_is_not_enough_data():
    locs, bundles = _ten()
    for loc in locs[4:]:
        loc["status"] = "template"
    r = ev.evaluate(locs, bundles)
    assert r["enough_data"] is False
    v = _verdicts(r)
    assert v["Top door within 10 m at >= 80% of sites"] == ev.NOT_ENOUGH
    assert r["go_no_go"]["overall"] == ev.NOT_ENOUGH
    assert "NOT ENOUGH DATA" in ev.render_markdown(r)


# ---------------------------------------------------------------- CLI


def test_cli_writes_markdown_and_json(tmp_path, capsys):
    locs, bundles = _ten()
    golden = tmp_path / "locations.json"
    golden.write_text(json.dumps({"locations": locs}), encoding="utf-8")
    folder = tmp_path / "bundles"
    folder.mkdir()
    for key, b in bundles.items():
        (folder / f"{key}.json").write_text(json.dumps(b), encoding="utf-8")
    (folder / "broken.json").write_text("{not json", encoding="utf-8")
    out = tmp_path / "eval" / "latest.md"

    code = cli.main(
        ["--bundles", str(folder), "--golden", str(golden), "--out", str(out), "--json"]
    )
    assert code == 0
    text = out.read_text(encoding="utf-8")
    assert "## Verdict: GO" in text and "NOT ENOUGH DATA" not in text
    data = json.loads(out.with_suffix(".json").read_text(encoding="utf-8"))
    assert data["overall"]["n"] == 10
    assert any("broken.json" in n for n in data["notes"])
    assert "M1 verdict: GO" in capsys.readouterr().out


def test_cli_on_real_golden_file_with_no_bundles(tmp_path, capsys):
    """The repo today: templates only, no bundles. Must say NOT ENOUGH DATA, never pass."""
    out = tmp_path / "latest.md"
    empty = tmp_path / "bundles"
    empty.mkdir()
    assert cli.main(["--bundles", str(empty), "--out", str(out)]) == 0
    printed = capsys.readouterr().out
    assert "NOT ENOUGH DATA" in printed
    text = out.read_text(encoding="utf-8")
    golden = json.loads((REPO / "golden" / "locations.json").read_text(encoding="utf-8"))
    for loc in golden["locations"]:
        assert f"| {loc['id']} |" in text  # every site listed as skipped
    assert "## Verdict: GO" not in text
