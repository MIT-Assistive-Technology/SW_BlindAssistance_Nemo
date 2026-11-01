"""The live API serving prebuilt pilot bundles. No network: the geocoder is faked."""

import copy
import hashlib
import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import main, resolver
from app.resolver import GeocodedPoint

EXAMPLE = json.loads(
    (Path(__file__).resolve().parents[2] / "contract" / "resolve.example.json").read_text(
        encoding="utf-8"
    )
)
# Site B is the example building moved ~1.1 km north, so the two never compete for a point.
SHIFT_LAT = 0.01


def _bundle(site_id: str, osm_id: str, dlat: float) -> dict:
    b = copy.deepcopy(EXAMPLE)
    b["destination_id"] = f"dst_{site_id}"
    b["building"]["osm_id"] = osm_id
    b["building"]["footprint"] = [[lon, lat + dlat] for lon, lat in b["building"]["footprint"]]
    for c in b["candidates"]:
        c["lat"] += dlat
    return b


def _write(path: Path, data) -> None:
    path.write_text(json.dumps(data), encoding="utf-8")


@pytest.fixture
def bundles_dir(tmp_path, monkeypatch):
    out = tmp_path / "bundles"
    out.mkdir()
    _write(out / "site-a.json", _bundle("site-a", "way/101", 0.0))
    _write(out / "site-b.json", _bundle("site-b", "way/202", SHIFT_LAT))
    sites = tmp_path / "sites.json"
    _write(
        sites,
        {
            "sites": [
                {
                    "id": "site-a",
                    "address": "77 Example Ave, Cambridge, MA 02139",
                    "scenario": "campus",
                },
                {
                    "id": "site-b",
                    "address": "10 Other St, Cambridge, MA 02142",
                    "scenario": "same_side",
                },
            ]
        },
    )
    monkeypatch.setenv("BUNDLES_DIR", str(out))
    monkeypatch.setenv("PILOT_SITES", str(sites))
    monkeypatch.delenv("DEV_EXAMPLE", raising=False)
    monkeypatch.setattr(main, "_store", None)
    return out


@pytest.fixture
def client(bundles_dir):
    main.reload_store()
    return TestClient(main.app)


def _fake_geocode(monkeypatch, result):
    calls = []

    def fake(request, **_):
        calls.append(request)
        if isinstance(result, Exception):
            raise result
        return result

    monkeypatch.setattr(resolver, "geocode", fake)
    return calls


def _no_geocode(monkeypatch):
    return _fake_geocode(monkeypatch, AssertionError("geocoder must not be called"))


def test_pilot_address_resolves_without_the_geocoder(client, monkeypatch):
    calls = _no_geocode(monkeypatch)
    r = client.post("/v1/resolve", json={"address": "77 example ave., cambridge, ma"})
    assert r.status_code == 200
    assert r.json()["destination_id"] == "dst_site-a"
    assert r.headers["etag"]
    assert calls == []


def test_address_resolves_by_the_geocoded_building(client, monkeypatch):
    point = GeocodedPoint(
        lat=0.0, lon=0.0, source="nominatim", precision="house", osm_ref="way/202"
    )
    calls = _fake_geocode(monkeypatch, point)
    r = client.post("/v1/resolve", json={"address": "10 Other Street, Cambridge"})
    assert r.status_code == 200
    assert r.json()["destination_id"] == "dst_site-b"
    assert len(calls) == 1


def test_address_resolves_by_the_nearest_footprint(client, monkeypatch):
    # ~20 m east of site B's east wall (lon -71.0929); no matching osm_ref.
    point = GeocodedPoint(lat=42.3693, lon=-71.09266, source="nominatim", precision="house")
    _fake_geocode(monkeypatch, point)
    r = client.post("/v1/resolve", json={"address": "12 Other St, Cambridge"})
    assert r.status_code == 200
    assert r.json()["destination_id"] == "dst_site-b"


def test_street_level_geocode_never_matches_by_distance(client, monkeypatch):
    point = GeocodedPoint(lat=42.3593, lon=-71.0931, source="nominatim", precision="street")
    _fake_geocode(monkeypatch, point)
    r = client.post("/v1/resolve", json={"address": "999 Example Ave, Cambridge"})
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "NOT_FOUND"


def test_lat_lon_inside_the_footprint(client, monkeypatch):
    _no_geocode(monkeypatch)
    r = client.post("/v1/resolve", json={"lat": 42.35925, "lon": -71.0931})
    assert r.status_code == 200
    assert r.json()["destination_id"] == "dst_site-a"
    # Same bytes and ETag as the bundle endpoint.
    g = client.get("/v1/bundles/site-a")
    assert r.content == g.content
    assert r.headers["etag"] == g.headers["etag"]


def test_lat_lon_out_of_range_is_validation(client):
    r = client.post("/v1/resolve", json={"lat": 123, "lon": 0})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "VALIDATION"


def test_non_pilot_destination_is_404_envelope(client, monkeypatch):
    _no_geocode(monkeypatch)
    r = client.post("/v1/resolve", json={"lat": 42.40, "lon": -71.12})  # ~4 km away
    assert r.status_code == 404
    body = r.json()
    assert body["error"]["code"] == "NOT_FOUND"
    assert body["error"]["message"] == "This destination isn't in the pilot yet."
    assert body["error"]["request_id"]


@pytest.mark.parametrize(
    ("exc", "status", "code"),
    [
        (resolver.GeocodeNotFound("x"), 404, "GEOCODE_NOT_FOUND"),
        (resolver.GeocodeAmbiguous("x"), 422, "VALIDATION"),
        (resolver.UpstreamUnavailable("x"), 503, "UPSTREAM_UNAVAILABLE"),
    ],
)
def test_geocode_errors_map_to_contract_codes(client, monkeypatch, exc, status, code):
    _fake_geocode(monkeypatch, exc)
    r = client.post("/v1/resolve", json={"address": "1 Nowhere Rd, Cambridge"})
    assert r.status_code == status
    assert r.json()["error"]["code"] == code
    if isinstance(exc, resolver.GeocodeAmbiguous):
        assert r.json()["error"]["message"] == (
            "More than one place has this address. Add the city or ZIP code."
        )


def test_slow_geocoder_is_cut_off_within_budget(client, monkeypatch):
    import threading

    release = threading.Event()

    def slow(request, **_):
        release.wait(5)
        raise resolver.GeocodeNotFound("late")

    monkeypatch.setattr(resolver, "geocode", slow)
    monkeypatch.setattr(main, "GEOCODE_BUDGET_S", 0.1)
    try:
        r = client.post("/v1/resolve", json={"address": "1 Slow St, Cambridge"})
    finally:
        release.set()
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "UPSTREAM_UNAVAILABLE"


def test_manifest_lists_every_bundle(client, bundles_dir):
    r = client.get("/v1/bundles")
    assert r.status_code == 200
    by_id = {m["id"]: m for m in r.json()}
    assert set(by_id) == {"site-a", "site-b"}
    a = by_id["site-a"]
    assert a["address"] == "77 Example Ave, Cambridge, MA 02139"
    assert a["osm_id"] == "way/101"
    assert a["data_version"] == EXAMPLE["data_version"]
    assert a["url"] == "/v1/bundles/site-a"
    body = client.get(a["url"]).content
    assert hashlib.sha256(body).hexdigest() == a["sha256"]


def test_bundle_etag_and_304(client):
    r = client.get("/v1/bundles/site-b")
    assert r.status_code == 200
    assert r.json()["building"]["osm_id"] == "way/202"
    etag = r.headers["etag"]
    again = client.get("/v1/bundles/site-b", headers={"If-None-Match": etag})
    assert again.status_code == 304
    assert again.content == b""
    assert again.headers["etag"] == etag
    assert again.headers["cache-control"] == r.headers["cache-control"] == "no-cache"  # I-13
    stale = client.get("/v1/bundles/site-b", headers={"If-None-Match": '"0000"'})
    assert stale.status_code == 200


def test_unknown_bundle_is_404_envelope(client):
    r = client.get("/v1/bundles/no-such-site")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "NOT_FOUND"


@pytest.mark.parametrize(
    "path",
    [
        "/v1/bundles/..%2F..%2Fpilot_sites",
        "/v1/bundles/%2e%2e",
        "/v1/bundles/Site-A",
        "/v1/bundles/site-a.json",
        "/v1/bundles/..\\sites",
    ],
)
def test_traversal_ids_are_rejected(client, path):
    r = client.get(path)
    assert r.status_code in (404, 422)
    assert r.json()["error"]["code"] in ("NOT_FOUND", "VALIDATION")


def test_invalid_bundle_file_is_skipped(bundles_dir):
    bad = _bundle("broken", "way/303", 0.02)
    del bad["candidates"]
    _write(bundles_dir / "broken.json", bad)
    (bundles_dir / "garbage.json").write_text("{not json", encoding="utf-8")
    (bundles_dir / "Bad Name.json").write_text(json.dumps(_bundle("x", "way/9", 0.03)))
    store = main.reload_store()
    assert set(store.by_id) == {"site-a", "site-b"}
    assert sorted(store.skipped) == ["Bad Name.json", "broken.json", "garbage.json"]
    r = TestClient(main.app).get("/v1/bundles/broken")
    assert r.status_code == 404


def test_dev_example_fallback_only_without_bundles(tmp_path, monkeypatch):
    empty = tmp_path / "empty"
    empty.mkdir()
    monkeypatch.setenv("BUNDLES_DIR", str(empty))
    monkeypatch.setattr(main, "_store", None)
    _no_geocode(monkeypatch)
    api = TestClient(main.app)

    monkeypatch.delenv("DEV_EXAMPLE", raising=False)
    main.reload_store()
    r = api.post("/v1/resolve", json={"lat": 42.35925, "lon": -71.0931})
    assert r.status_code == 404

    monkeypatch.setenv("DEV_EXAMPLE", "1")
    r = api.post("/v1/resolve", json={"address": "anything, Cambridge"})
    assert r.status_code == 200
    assert r.json()["destination_id"] == EXAMPLE["destination_id"]


def test_dev_example_is_ignored_once_bundles_exist(client, monkeypatch):
    monkeypatch.setenv("DEV_EXAMPLE", "1")
    _no_geocode(monkeypatch)
    r = client.post("/v1/resolve", json={"lat": 42.40, "lon": -71.12})
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "NOT_FOUND"


def test_health_reports_bundles(client):
    body = client.get("/v1/health").json()
    assert body["status"] == "ok"
    assert body["bundles"] == 2
    assert body["data_version"] == EXAMPLE["data_version"]
