"""Checks for the golden-location kit (QA-1, QA-7). Nothing here calls a network service.

golden/locations.json is validated against golden/schema.json with a small JSON Schema subset
validator below, because `jsonschema` isn't a server dependency. The validator refuses any schema
keyword it doesn't implement, so it can't silently check less than the schema says. If
`jsonschema` is installed, test_matches_real_jsonschema cross-checks with it.

The file is JSON, not YAML: PyYAML isn't a server dependency either.
"""

import copy
import itertools
import json
import math
import re
from collections import Counter
from pathlib import Path

import pytest

GOLDEN = Path(__file__).resolve().parents[2] / "golden"
SCHEMA = json.loads((GOLDEN / "schema.json").read_text(encoding="utf-8"))
LOCATIONS = json.loads((GOLDEN / "locations.json").read_text(encoding="utf-8"))["locations"]
FIXTURES = json.loads(
    (Path(__file__).parent / "fixtures" / "nominatim" / "addresses.json").read_text(
        encoding="utf-8"
    )
)["addresses"]

# Plan section 18: 4 same side, 2 driveways, 2 opposite (measured only), 2 campus (measured only).
PLAN_MIX = {"same_side": 4, "driveway": 2, "opposite_side": 2, "campus": 2}

TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "boolean": bool,
    "null": type(None),
    "number": (int, float),
    "integer": int,
}
ANNOTATIONS = {"$schema", "$id", "title", "description", "format"}
SUPPORTED = ANNOTATIONS | {
    "type", "enum", "const", "required", "properties", "additionalProperties", "items",
    "minItems", "uniqueItems", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
    "pattern", "minLength", "allOf", "if", "then", "else",
}  # fmt: skip


def _type_ok(value, name):
    if name in ("number", "integer") and isinstance(value, bool):
        return False
    return isinstance(value, TYPES[name])


def validate(value, schema, path="$"):
    """Return a list of error strings. Supports the JSON Schema subset schema.json uses."""
    errors = []
    unknown = set(schema) - SUPPORTED
    assert not unknown, f"validator doesn't support {sorted(unknown)} at {path}"

    if "type" in schema:
        names = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(_type_ok(value, n) for n in names):
            return [f"{path}: expected {names}, got {value!r}"]
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: {value!r} not in {schema['enum']}")
    if "const" in schema and value != schema["const"]:
        errors.append(f"{path}: expected {schema['const']!r}, got {value!r}")

    if isinstance(value, dict):
        errors += [f"{path}: missing {k}" for k in schema.get("required", []) if k not in value]
        props = schema.get("properties", {})
        for key, sub in value.items():
            if key in props:
                errors += validate(sub, props[key], f"{path}.{key}")
            elif schema.get("additionalProperties") is False:
                errors.append(f"{path}: unexpected field {key}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            errors.append(f"{path}: needs at least {schema['minItems']} items")
        if schema.get("uniqueItems") and len({json.dumps(v) for v in value}) != len(value):
            errors.append(f"{path}: items not unique")
        if "items" in schema:
            for i, item in enumerate(value):
                errors += validate(item, schema["items"], f"{path}[{i}]")
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            errors.append(f"{path}: shorter than {schema['minLength']}")
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errors.append(f"{path}: {value!r} doesn't match {schema['pattern']}")
    if _type_ok(value, "number"):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{path}: {value} < {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{path}: {value} > {schema['maximum']}")
        if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
            errors.append(f"{path}: {value} <= {schema['exclusiveMinimum']}")
        if "exclusiveMaximum" in schema and value >= schema["exclusiveMaximum"]:
            errors.append(f"{path}: {value} >= {schema['exclusiveMaximum']}")

    for sub in schema.get("allOf", []):
        errors += validate(value, sub, path)
    if "if" in schema:
        branch = "then" if not validate(value, schema["if"], path) else "else"
        if branch in schema:
            errors += validate(value, schema[branch], path)
    return errors


def distance_m(a, b):
    """Haversine distance in metres; plenty for points a few metres apart."""
    p1, p2 = math.radians(a["lat"]), math.radians(b["lat"])
    dp, dl = p2 - p1, math.radians(b["lon"] - a["lon"])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * 6371008.8 * math.asin(math.sqrt(h))


def measured_entry():
    """A filled-in entry used only to prove the checks reject bad data. Not a real site."""
    entry = copy.deepcopy(LOCATIONS[0])
    m1 = {"lat": 0.0, "lon": 0.0, "method": "rtk", "measured_on": "2000-01-01"}
    m2 = {"lat": 0.00001, "lon": 0.0, "method": "rtk", "measured_on": "2000-01-02"}
    entry["status"] = "measured"
    entry["entrance_truth"].update(
        lat=0.000005,
        lon=0.0,
        method="rtk",
        measured_on=["2000-01-01", "2000-01-02"],
        measurements=[m1, m2],
        spread_m=round(distance_m(m1, m2), 2),
    )
    return entry


@pytest.mark.parametrize("entry", LOCATIONS, ids=[e["id"] for e in LOCATIONS])
def test_entry_matches_schema(entry):
    assert validate(entry, SCHEMA) == []


def test_ids_unique():
    ids = [e["id"] for e in LOCATIONS]
    assert len(ids) == len(set(ids))
    for e in LOCATIONS:
        drops = [d["id"] for d in e["drop_off_points"]]
        assert len(drops) == len(set(drops)), e["id"]


def test_scenario_mix_matches_plan():
    assert Counter(e["scenario"] for e in LOCATIONS) == PLAN_MIX
    tags = {t for e in LOCATIONS for t in e["tags"]}
    # Plan 18: "the same building with drop-offs on both sides, and one on a one-way street".
    assert {"both_sides_dropoff", "one_way"} <= tags
    for e in LOCATIONS:
        if "both_sides_dropoff" in e["tags"]:
            assert {d["side_vs_door"] for d in e["drop_off_points"]} >= {"same", "opposite"}


def test_fixture_links_point_at_real_fixtures():
    by_id = {f["id"]: f for f in FIXTURES}
    for e in LOCATIONS:
        if e["fixture_id"] is not None:
            assert by_id[e["fixture_id"]]["address"] == e["address"], e["id"]


def test_templates_hold_no_invented_values():
    for e in (e for e in LOCATIONS if e["status"] == "template"):
        truth = e["entrance_truth"]
        assert (truth["lat"], truth["lon"], truth["spread_m"]) == (None, None, None), e["id"]
        assert truth["measurements"] == [] and truth["measured_on"] == [], e["id"]
        assert all(d["lat"] is None and d["lon"] is None for d in e["drop_off_points"]), e["id"]
        assert e["osm_snapshot"]["distance_to_truth_m"] is None, e["id"]


def test_measured_truth_is_consistent():
    """spread_m is the largest gap between measurements; the truth point is their average."""
    for e in [*(e for e in LOCATIONS if e["status"] == "measured"), measured_entry()]:
        truth = e["entrance_truth"]
        ms = truth["measurements"]
        spread = max(distance_m(a, b) for a, b in itertools.combinations(ms, 2))
        assert truth["spread_m"] == pytest.approx(spread, abs=0.1), e["id"]
        mean = {
            "lat": sum(m["lat"] for m in ms) / len(ms),
            "lon": sum(m["lon"] for m in ms) / len(ms),
        }
        assert distance_m(truth, mean) < 0.5, e["id"]


def test_schema_rejects_bad_entries():
    good = measured_entry()
    assert validate(good, SCHEMA) == []

    one_measurement = copy.deepcopy(good)
    one_measurement["entrance_truth"]["measurements"].pop()
    wide_spread = copy.deepcopy(good)
    wide_spread["entrance_truth"]["spread_m"] = 2.5
    osm_truth = copy.deepcopy(good)
    osm_truth["entrance_truth"]["method"] = "osm"
    phone_gps = copy.deepcopy(good)
    phone_gps["entrance_truth"]["measurements"][0]["method"] = "phone_gps"
    wrong_gate = copy.deepcopy(good)
    wrong_gate["counts_toward_april"] = not wrong_gate["counts_toward_april"]
    extra = copy.deepcopy(good)
    extra["rider_name"] = "x"

    for bad in (one_measurement, wide_spread, osm_truth, phone_gps, wrong_gate, extra):
        assert validate(bad, SCHEMA) != []

    wide_spread["truth_uncertain"] = True
    assert validate(wide_spread, SCHEMA) == []


def test_matches_real_jsonschema():
    jsonschema = pytest.importorskip("jsonschema")
    jsonschema.Draft202012Validator.check_schema(SCHEMA)
    for e in LOCATIONS:
        jsonschema.Draft202012Validator(SCHEMA).validate(e)
