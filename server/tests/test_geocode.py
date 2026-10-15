"""Tests for resolver.geocode (BE-2). Nothing here calls Nominatim.

Two kinds of test:
- Recorded: replay the real Nominatim responses that scripts/record_nominatim_fixtures.py saved
  for each address in tests/fixtures/nominatim/addresses.json. Skipped until they're recorded.
- Hand-made: tiny made-up responses for cases that are hard to find on demand (a bus stop, a
  city-level fallback, exits in the entrance list, upstream errors).
"""

import json
from pathlib import Path

import httpx
import pytest

from app import resolver
from app.models import ResolveRequest
from app.resolver import (
    PILOT_VIEWBOX,
    GeocodeAmbiguous,
    GeocodeNotFound,
    RateLimiter,
    UpstreamUnavailable,
    geocode,
    nominatim_params,
    parse_address,
)

FIXTURES = Path(__file__).parent / "fixtures" / "nominatim"
MANIFEST = json.loads((FIXTURES / "addresses.json").read_text(encoding="utf-8"))["addresses"]
BY_ID = {entry["id"]: entry for entry in MANIFEST}
FOUND = [e["id"] for e in MANIFEST if e.get("expect") != "not_found"]
NOT_FOUND = [e["id"] for e in MANIFEST if e.get("expect") == "not_found"]
PILOT_AREA = (42.23, 42.42, -71.19, -70.99)  # south, north, west, east
NEAR_M = 300
RECORD_HINT = (
    "No saved response yet. From server/, run: python scripts/record_nominatim_fixtures.py"
)
REAL_LIMITER = resolver._nominatim_limiter  # captured before the fixture below swaps it out
TEST_USER_AGENT = "MIT-AT-CarToCurb/test"
MIT = ResolveRequest(address="77 Massachusetts Ave, Cambridge, MA")


@pytest.fixture(autouse=True)
def _offline(monkeypatch):
    monkeypatch.setenv("USER_AGENT", TEST_USER_AGENT)
    monkeypatch.setenv("NOMINATIM_URL", "https://nominatim.test")
    monkeypatch.setattr(resolver, "_nominatim_limiter", RateLimiter(0))  # don't sleep in tests
    resolver.clear_geocode_cache()
    yield
    resolver.clear_geocode_cache()


# --- Recorded responses ------------------------------------------------------------------------


def _canonical(items) -> tuple:
    return tuple(sorted((str(k), str(v)) for k, v in items))


class Replay:
    """An httpx transport that only answers with saved responses, and keeps every request."""

    def __init__(self, recordings: list[dict]):
        self.responses = {_canonical(r["params"].items()): r["response"] for r in recordings}
        self.requests: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        key = _canonical(request.url.params.multi_items())
        if key not in self.responses:
            raise AssertionError(
                f"geocode() sent a query with no saved response: {dict(key)}. If you changed "
                "the query on purpose, re-record with --force."
            )
        return httpx.Response(200, json=self.responses[key])


def _recording(address_id: str) -> dict:
    path = FIXTURES / f"{address_id}.json"
    if not path.exists():
        pytest.skip(RECORD_HINT)
    return json.loads(path.read_text(encoding="utf-8"))


def _geocode_recorded(address_id: str):
    replay = Replay([_recording(address_id)])
    with httpx.Client(transport=httpx.MockTransport(replay)) as client:
        point = geocode(ResolveRequest(address=BY_ID[address_id]["address"]), client=client)
    return point, replay


def _distance(a, b) -> float:
    return resolver._meters_between(tuple(a), tuple(b))


@pytest.mark.parametrize("address_id", FOUND)
def test_recorded_address_resolves_to_the_house(address_id):
    entry = BY_ID[address_id]
    point, replay = _geocode_recorded(address_id)

    assert len(replay.requests) == 1
    assert replay.requests[0].headers["User-Agent"] == TEST_USER_AGENT
    assert point.source == "nominatim"
    assert point.precision == "house", "only the street matched; choose an address OSM has"
    assert not resolver._is_transit({"category": point.category, "type": point.type})

    expected_number = parse_address(entry["address"]).housenumber.lower()
    numbers = {n.strip().lower() for n in point.housenumber.replace(",", ";").split(";")}
    assert expected_number in numbers

    south, north, west, east = PILOT_AREA
    assert south < point.lat < north and west < point.lon < east
    if "near" in entry:
        meters = _distance((point.lat, point.lon), entry["near"])
        assert meters < NEAR_M, f"{meters:.0f} m from where {entry['address']} should be"
    if "same_as" in entry:
        other, _ = _geocode_recorded(entry["same_as"])
        assert _distance((point.lat, point.lon), (other.lat, other.lon)) < 5


def test_77_mass_ave_is_the_building_not_the_bus_stop():
    """The plan's trap: free-form "77 Massachusetts Ave, Cambridge, MA" returns a bus stop."""
    point, replay = _geocode_recorded("mit-77-mass-ave")
    params = replay.requests[0].url.params
    assert "q" not in params
    assert (params["street"], params["city"], params["layer"]) == (
        "77 Massachusetts Ave",
        "Cambridge",
        "address",
    )
    assert point.category not in {"highway", "public_transport"}
    assert point.precision == "house"


@pytest.mark.parametrize("address_id", NOT_FOUND)
def test_recorded_unknown_address_is_not_found(address_id):
    with pytest.raises(GeocodeNotFound):
        _geocode_recorded(address_id)


# --- Hand-made responses -----------------------------------------------------------------------


def _result(
    lat=42.3592,
    lon=-71.0934,
    *,
    housenumber="77",
    rank=30,
    category="building",
    kind="university",
    osm_type="way",
    osm_id=1,
    entrances=None,
) -> dict:
    """A made-up Nominatim jsonv2 result with only the fields geocode reads."""
    return {
        "osm_type": osm_type,
        "osm_id": osm_id,
        "lat": str(lat),
        "lon": str(lon),
        "category": category,
        "type": kind,
        "place_rank": rank,
        "address": {"house_number": housenumber} if housenumber else {},
        "entrances": entrances,
    }


def _serve(results, status=200):
    """A client that answers every request with `results`, plus the list of requests it saw."""
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(status, json=results)

    return httpx.Client(transport=httpx.MockTransport(handler)), seen


def test_phone_coordinates_are_used_without_calling_nominatim():
    client, seen = _serve([])
    request = ResolveRequest(address="77 Mass Ave, Cambridge, MA", lat=42.3592, lon=-71.0934)
    point = geocode(request, client=client)
    assert (point.lat, point.lon, point.source) == (42.3592, -71.0934, "request")
    assert point.housenumber == "77"
    assert seen == []


def test_impossible_phone_coordinates_are_rejected():
    with pytest.raises(ValueError):
        geocode(ResolveRequest(lat=91.0, lon=-71.0))


def test_query_is_structured_never_free_form():
    params = nominatim_params(parse_address("77 Mass Ave, Cambridge, MA 02139"))
    assert "q" not in params
    assert params["street"] == "77 Massachusetts Avenue"
    assert params["city"] == "Cambridge"
    assert params["state"] == "Massachusetts"
    assert params["layer"] == "address"
    assert params["entrances"] == "1"
    assert "postalcode" not in params
    assert "viewbox" not in params


@pytest.mark.parametrize(
    ("address", "street", "city"),
    [
        ("40 Brattle St, Cambridge MA 02138", "40 Brattle St", "Cambridge"),
        ("24 Beacon St, Boston, MA 02133, United States", "24 Beacon St", "Boston"),
        ("1 Broadway Fl 14, Cambridge, MA 02142", "1 Broadway", "Cambridge"),
        ("1 Broadway, Suite 200, Cambridge, MA", "1 Broadway", "Cambridge"),
        ("77 Mass Ave #3, Cambridge", "77 Massachusetts Avenue", "Cambridge"),
        ("MIT, 77 Mass Ave, Cambridge, Mass.", "77 Massachusetts Avenue", "Cambridge"),
        ("10 Flagg St, Cambridge", "10 Flagg St", "Cambridge"),
    ],
)
def test_address_formats(address, street, city):
    parsed = parse_address(address)
    assert (parsed.street, parsed.city) == (street, city)


def test_no_city_searches_only_the_pilot_area():
    params = nominatim_params(parse_address("77 Mass Ave"))
    assert "city" not in params
    assert params["viewbox"] == PILOT_VIEWBOX
    assert params["bounded"] == "1"


def test_skips_a_bus_stop_named_after_the_address():
    bus_stop = _result(
        42.3590,
        -71.0937,
        housenumber=None,
        category="highway",
        kind="bus_stop",
        osm_type="node",
        osm_id=9,
    )
    client, _ = _serve([bus_stop, _result(osm_id=2)])
    assert geocode(MIT, client=client).osm_ref == "way/2"


def test_only_a_bus_stop_is_not_found():
    bus_stop = _result(housenumber=None, category="highway", kind="bus_stop", osm_type="node")
    client, _ = _serve([bus_stop])
    with pytest.raises(GeocodeNotFound):
        geocode(MIT, client=client)


def test_city_level_fallback_is_not_found():
    cambridge = _result(
        42.3736,
        -71.1097,
        housenumber=None,
        rank=16,
        category="boundary",
        kind="administrative",
        osm_type="relation",
    )
    client, _ = _serve([cambridge])
    with pytest.raises(GeocodeNotFound):
        geocode(MIT, client=client)


def test_empty_response_is_not_found():
    client, _ = _serve([])
    with pytest.raises(GeocodeNotFound):
        geocode(MIT, client=client)


def test_street_only_match_is_flagged():
    street = _result(housenumber=None, rank=26, category="highway", kind="primary")
    client, _ = _serve([street])
    point = geocode(MIT, client=client)
    assert point.precision == "street"
    assert point.housenumber == "77"


def test_prefers_the_matching_house_number():
    client, _ = _serve([_result(housenumber="79", osm_id=79), _result(osm_id=77)])
    assert geocode(MIT, client=client).osm_ref == "way/77"


def test_never_returns_a_different_house():
    street = _result(housenumber=None, rank=26, category="highway", kind="primary", osm_id=5)
    client, _ = _serve([_result(housenumber="79", osm_id=79), street])
    point = geocode(MIT, client=client)
    assert (point.osm_ref, point.precision) == ("way/5", "street")

    resolver.clear_geocode_cache()
    client, _ = _serve([_result(housenumber="79", osm_id=79)])
    with pytest.raises(GeocodeNotFound):
        geocode(MIT, client=client)


def test_same_address_in_two_cities_without_a_city_is_ambiguous():
    cambridge = _result(42.3592, -71.0934, osm_id=1)
    boston = _result(42.3497, -71.0880, osm_id=2)
    client, _ = _serve([cambridge, boston])
    with pytest.raises(GeocodeAmbiguous):
        geocode(ResolveRequest(address="77 Mass Ave"), client=client)


def test_entrances_drop_exits_and_private_doors():
    def door(osm_id, value, tags=None):
        return {
            "osm_id": osm_id,
            "type": value,
            "lat": "42.3592",
            "lon": "-71.0933",
            "extratags": tags,
        }

    doors = [
        door(1, "main", {"wheelchair": "yes"}),
        door(2, "exit"),
        door(3, "emergency;exit"),
        door(4, "yes", {"access": "private"}),
        door(5, "service", {"access": "delivery"}),
        door(6, "main;exit"),
    ]
    client, _ = _serve([_result(entrances=doors)])
    entrances = geocode(MIT, client=client).entrances
    assert [e.ref for e in entrances] == ["node/1", "node/6"]
    assert entrances[0].tags == {"wheelchair": "yes"}
    assert (entrances[0].lat, entrances[0].lon) == (42.3592, -71.0933)


def test_sends_an_identifying_user_agent_and_requires_one(monkeypatch):
    client, seen = _serve([_result()])
    geocode(MIT, client=client)
    assert seen[0].headers["User-Agent"] == TEST_USER_AGENT
    assert str(seen[0].url).startswith("https://nominatim.test/search?")

    monkeypatch.delenv("USER_AGENT")
    with pytest.raises(RuntimeError, match="USER_AGENT"):
        geocode(ResolveRequest(address=MIT.address, force_refresh=True), client=client)


@pytest.mark.parametrize("status", [429, 500, 503])
def test_upstream_errors(status):
    client, _ = _serve({"error": "busy"}, status=status)
    with pytest.raises(UpstreamUnavailable):
        geocode(MIT, client=client)


def test_timeout_and_non_json_are_upstream_errors():
    def timeout(request):
        raise httpx.ConnectTimeout("timed out", request=request)

    with pytest.raises(UpstreamUnavailable):
        geocode(MIT, client=httpx.Client(transport=httpx.MockTransport(timeout)))

    html = httpx.MockTransport(lambda request: httpx.Response(200, text="<html>busy</html>"))
    with pytest.raises(UpstreamUnavailable):
        geocode(MIT, client=httpx.Client(transport=html))


def test_results_are_cached_until_force_refresh():
    client, seen = _serve([_result()])
    geocode(MIT, client=client)
    geocode(MIT, client=client)
    assert len(seen) == 1
    geocode(ResolveRequest(address=MIT.address, force_refresh=True), client=client)
    assert len(seen) == 2


def test_every_request_waits_on_the_process_wide_limiter(monkeypatch):
    waits = []

    class Spy:
        def wait(self):
            waits.append(1)

    monkeypatch.setattr(resolver, "_nominatim_limiter", Spy())
    client, _ = _serve([_result()])
    geocode(MIT, client=client)
    geocode(ResolveRequest(address=MIT.address, force_refresh=True), client=client)
    assert len(waits) == 2
    assert REAL_LIMITER.min_interval == 1.0


def test_rate_limiter_spaces_calls_one_second_apart():
    now, slept = [100.0], []

    def sleep(seconds):
        slept.append(seconds)
        now[0] += seconds

    limiter = RateLimiter(1.0, clock=lambda: now[0], sleep=sleep)
    limiter.wait()  # first call goes straight through
    now[0] += 0.25
    limiter.wait()  # 0.25 s later: waits the remaining 0.75 s
    now[0] += 5
    limiter.wait()  # long after: no wait
    assert slept == [pytest.approx(0.75)]
