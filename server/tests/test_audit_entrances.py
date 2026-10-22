"""BE-9: entrance coverage audit classification, on a hand-made Overpass response."""

import csv
import importlib.util
import json
from pathlib import Path

import pytest

SERVER = Path(__file__).resolve().parents[1]
FIXTURE = SERVER / "tests" / "fixtures" / "audit" / "overpass_tiny.json"

_spec = importlib.util.spec_from_file_location("audit", SERVER / "scripts" / "audit_entrances.py")
audit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(audit)


@pytest.fixture
def buildings():
    data = json.loads(FIXTURE.read_text(encoding="utf-8"))
    return {b["osm_id"]: b for b in audit.classify(data)}


@pytest.mark.parametrize(
    ("tags", "expected"),
    [
        ({"entrance": "main"}, "usable"),
        ({"entrance": "main;garage"}, "usable"),  # best usable part wins
        ({"entrance": "garage;exit"}, "excluded"),
        ({"entrance": "emergency"}, "excluded"),
        ({"entrance": "yes", "foot": "no"}, "excluded"),
        ({"entrance": "yes", "access": "delivery"}, "excluded"),
        ({"door": "hinged"}, "usable"),
        ({"routing:entrance": "main"}, "usable"),
        ({"railway": "subway_entrance", "entrance": "yes"}, None),
        ({"indoor": "door", "door": "hinged"}, None),
        ({"barrier": "gate"}, None),
        ({"name": "Lobby"}, None),
    ],
)
def test_door_status(tags, expected):
    assert audit.door_status(tags) == expected


def test_classify(buildings):
    assert set(buildings) == {1, 2, 3, 4, 5, 6}  # untagged outer way 50 is not a building
    assert buildings[1]["status"] == "usable"
    assert buildings[2]["status"] == "only_excluded"
    assert buildings[3]["status"] == "none"  # subway entrance ignored
    assert buildings[5]["status"] == "usable"  # door on multipolygon outer member
    assert buildings[6]["status"] == "none"  # site entrance node has no door tags
    assert buildings[5]["osm_url"] == "https://www.openstreetmap.org/relation/5"
    assert (buildings[1]["lat"], buildings[1]["lon"]) == (1.0, 1.0)
    assert audit.summary(list(buildings.values())) == {
        "buildings": 6,
        "usable": 2,
        "only_excluded": 1,
        "none": 3,
    }


def test_todo_order_and_reports(buildings, tmp_path):
    rows = audit.write_reports(list(buildings.values()), "test", tmp_path)
    # MIT with address first; unnamed, unaddressed house 4 is left out.
    assert [(r["osm_id"], r["priority"]) for r in rows] == [(3, 1), (2, 3), (6, 4)]
    with (tmp_path / "pilot-entrance-coverage.csv").open(encoding="utf-8") as f:
        csv_rows = list(csv.DictReader(f))
    assert csv_rows[0]["address"] == "1 Ames Street"
    assert csv_rows[1]["osm_url"] == "https://www.openstreetmap.org/way/2"
    md = (tmp_path / "pilot-entrance-coverage.md").read_text(encoding="utf-8")
    assert "| With at least one usable entrance node | 2 | 33.3% |" in md
