"""Keeps the contract example, the server models and the app's bundled copy in sync (QA-3)."""

import json
from pathlib import Path

from app.models import ResolveResult

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "contract" / "resolve.example.json"
APP_COPY = ROOT / "app" / "nemo-software" / "Resources" / "resolve.example.json"


def test_example_matches_server_models():
    ResolveResult.model_validate(json.loads(CONTRACT.read_text(encoding="utf-8")))


def test_app_bundle_copy_is_identical():
    assert json.loads(APP_COPY.read_text(encoding="utf-8")) == json.loads(
        CONTRACT.read_text(encoding="utf-8")
    ), "Copy contract/resolve.example.json to app/nemo-software/Resources/"


def test_app_pilot_bundles_match_the_server_bundles():
    bundles = ROOT / "server" / "bundles"
    copies = ROOT / "app" / "nemo-software" / "Resources" / "PilotBundles"
    names = sorted(p.name for p in bundles.glob("*.json"))
    assert names == sorted(p.name for p in copies.glob("*.json")), "Copy server/bundles/*.json"
    for name in names:
        assert json.loads((copies / name).read_text("utf-8")) == json.loads(
            (bundles / name).read_text("utf-8")
        ), f"Copy server/bundles/{name} to app/nemo-software/Resources/PilotBundles/"


def test_app_pilot_sites_copy_is_identical():
    copy = ROOT / "app" / "nemo-software" / "Resources" / "pilot_sites.json"
    assert json.loads(copy.read_text("utf-8")) == json.loads(
        (ROOT / "server" / "pilot_sites.json").read_text("utf-8")
    ), "Copy server/pilot_sites.json to app/nemo-software/Resources/"
