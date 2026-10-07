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
