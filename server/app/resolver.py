"""The lookup ladder: address in, ranked doors out. Stops at the first good answer.

See docs/car-to-curb-plan.md section 8. Each step is its own function so it can be tested
with saved responses (no live network in tests).
"""

import math
import os
import re
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Literal

import httpx

from .models import ResolveRequest, ResolveResult
from .scoring import EXCLUDE, EXCLUDE_ACCESS

# ---------------------------------------------------------------------------------------------
# Step 1: geocode (BE-2)
# ---------------------------------------------------------------------------------------------

DEFAULT_NOMINATIM_URL = "https://nominatim.openstreetmap.org"
NOMINATIM_TIMEOUT_S = 10.0
PILOT_STATE = "Massachusetts"
# Cambridge + Boston (west, south, east, north). Used only when an address has no city.
PILOT_VIEWBOX = "-71.19,42.23,-70.99,42.42"
# Two house-level matches farther apart than this mean the address is ambiguous.
AMBIGUOUS_M = 200.0

# Local nicknames Nominatim doesn't expand on its own ("St", "Ave" etc. it already handles).
_STREET_NICKNAMES = [
    (re.compile(r"\bmass\.?\s+ave(nue)?\b\.?", re.IGNORECASE), "Massachusetts Avenue"),
    (re.compile(r"\bcomm\.?\s+ave(nue)?\b\.?", re.IGNORECASE), "Commonwealth Avenue"),
]
_STATE_NAMES = {"ma": "Massachusetts", "mass": "Massachusetts", "massachusetts": "Massachusetts"}
_COUNTRY_NAMES = {"us", "usa", "u.s.", "u.s.a.", "united states", "united states of america"}
_POSTCODE = re.compile(r"\b\d{5}(?:-\d{4})?\b")
_HOUSENUMBER = re.compile(r"^\s*(\d+[a-z]?(?:-\d+[a-z]?)?)\b", re.IGNORECASE)
_UNIT_WORDS = r"(?:apt|apartment|unit|suite|ste|room|rm|floor|fl)"
# "Apt 3" as its own comma-separated part, and "... Fl 14" / "... #3" at the end of the street.
_UNIT_PART = re.compile(rf"^(?:{_UNIT_WORDS}\b|#)", re.IGNORECASE)
_UNIT_SUFFIX = re.compile(rf"(?:\s+{_UNIT_WORDS}\b\.?|\s*#)\s*[\w-]+$", re.IGNORECASE)

# Results that are a stop named after the address, not the address (the "77 Mass Ave" trap).
_TRANSIT = {
    ("highway", "bus_stop"),
    ("highway", "platform"),
    ("amenity", "bus_station"),
    ("railway", "station"),
    ("railway", "halt"),
    ("railway", "tram_stop"),
    ("railway", "platform"),
    ("railway", "subway_entrance"),
}
_OSM_TYPES = {"n": "node", "w": "way", "r": "relation"}


class GeocodeNotFound(Exception):
    """No street- or house-level match. Maps to 404 GEOCODE_NOT_FOUND."""


class GeocodeAmbiguous(GeocodeNotFound):
    """The address has no city and matches places far apart (e.g. Cambridge and Boston)."""


class UpstreamUnavailable(Exception):
    """Nominatim timed out, rate-limited us or errored. Maps to 503 UPSTREAM_UNAVAILABLE."""


@dataclass(frozen=True)
class Entrance:
    """A door Nominatim lists for the matched building, after the exit/emergency exclusions."""

    ref: str  # "node/123", the same style as the contract's provenance refs
    lat: float
    lon: float
    entrance: str  # the raw entrance=* value, e.g. "main" or "main;exit"
    tags: dict[str, str]


@dataclass(frozen=True)
class GeocodedPoint:
    lat: float
    lon: float
    source: Literal["request", "nominatim"]
    housenumber: str | None = None
    # "house": an address point or building. "street": only the street matched, so the point
    # is somewhere along it. "unknown": coordinates came from the phone.
    precision: Literal["house", "street", "unknown"] = "unknown"
    osm_ref: str | None = None  # e.g. "way/123" when Nominatim matched a building
    category: str | None = None
    type: str | None = None
    entrances: tuple[Entrance, ...] = ()


@dataclass(frozen=True)
class ParsedAddress:
    street: str  # "77 Massachusetts Avenue"
    city: str | None
    state: str | None
    housenumber: str | None
    postcode: str | None = None  # 5-digit ZIP; only used to choose between results


class RateLimiter:
    """At most one call per `min_interval` seconds across all threads in this process."""

    def __init__(
        self,
        min_interval: float,
        clock: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
    ):
        self.min_interval = min_interval
        self._clock, self._sleep = clock, sleep
        self._lock = threading.Lock()
        self._next_ok = 0.0

    def wait(self) -> None:
        # Sleeping while holding the lock is deliberate: other callers queue behind us.
        with self._lock:
            now = self._clock()
            if now < self._next_ok:
                self._sleep(self._next_ok - now)
                now = self._next_ok
            self._next_ok = now + self.min_interval


_nominatim_limiter = RateLimiter(1.0)  # Nominatim usage policy: max 1 request/s
_CACHE_MAX = 1024
_cache: dict[tuple[tuple[str, str], ...], GeocodedPoint] = {}
_cache_lock = threading.Lock()


def parse_address(address: str) -> ParsedAddress:
    """Split "77 Mass Ave, Cambridge, MA 02139" into the parts of a structured query."""
    parts = [p.strip() for p in address.split(",") if p.strip()]
    parts = [p for p in parts if not _UNIT_PART.match(p)]
    if parts and parts[-1].lower() in _COUNTRY_NAMES:
        parts.pop()
    if not parts:
        return ParsedAddress(street="", city=None, state=None, housenumber=None)

    # The street is the first part that starts with a number ("MIT, 77 Mass Ave, ...").
    i = next((i for i, p in enumerate(parts) if _HOUSENUMBER.match(p)), 0)
    street = _UNIT_SUFFIX.sub("", parts[i]).strip()
    for pattern, full_name in _STREET_NICKNAMES:
        street = pattern.sub(full_name, street)
    number = _HOUSENUMBER.match(street)

    # What's left is "City", "State ZIP", or both in one part ("Cambridge MA 02139").
    rest = parts[i + 1 :]
    state = postcode = None
    if rest:
        last = rest.pop()
        if zip_code := _POSTCODE.search(last):
            postcode = zip_code.group()[:5]
        words = _POSTCODE.sub("", last).split()
        if words and words[-1].lower().rstrip(".") in _STATE_NAMES:
            state = _STATE_NAMES[words.pop().lower().rstrip(".")]
        if words:
            rest.append(" ".join(words))
    return ParsedAddress(
        street=street,
        city=rest[-1] if rest else None,
        state=state,
        housenumber=number.group(1) if number else None,
        postcode=postcode,
    )


def nominatim_params(parsed: ParsedAddress) -> dict[str, str]:
    """The structured /search query. Never free-form `q=`: it matches a bus stop for 77 Mass Ave.

    The ZIP is left out on purpose: OSM's ZIPs are often a little off (it has the State House at
    02108, not 02133), and a mismatched ZIP can make a structured search return nothing. It is
    used afterwards instead, to choose between results (see point_from_results).
    """
    params = {
        "street": parsed.street,
        "state": parsed.state or PILOT_STATE,
        "countrycodes": "us",
        "layer": "address",
        "entrances": "1",
        "addressdetails": "1",
        "format": "jsonv2",
        "limit": "5",
    }
    if parsed.city:
        params["city"] = parsed.city
    else:
        params["viewbox"] = PILOT_VIEWBOX
        params["bounded"] = "1"
    return params


def nominatim_search(params: dict[str, str], client: httpx.Client | None = None) -> list[dict]:
    """One rate-limited GET /search. Raises UpstreamUnavailable on any network or HTTP failure."""
    base_url = os.environ.get("NOMINATIM_URL", DEFAULT_NOMINATIM_URL).rstrip("/")
    user_agent = os.environ.get("USER_AGENT", "").strip()
    if not user_agent:
        raise RuntimeError(
            "Set USER_AGENT in server/.env. Nominatim blocks requests without an identifying "
            "User-Agent."
        )
    own_client = client is None
    client = client or httpx.Client()
    try:
        _nominatim_limiter.wait()
        response = client.get(
            f"{base_url}/search",
            params=params,
            headers={"User-Agent": user_agent},
            timeout=NOMINATIM_TIMEOUT_S,
        )
    except httpx.HTTPError as exc:
        raise UpstreamUnavailable(f"Nominatim request failed ({type(exc).__name__}).") from exc
    finally:
        if own_client:
            client.close()
    if response.status_code != 200:
        raise UpstreamUnavailable(f"Nominatim returned HTTP {response.status_code}.")
    try:
        results = response.json()
    except ValueError as exc:
        raise UpstreamUnavailable("Nominatim returned something that isn't JSON.") from exc
    if not isinstance(results, list):
        raise UpstreamUnavailable("Nominatim returned an unexpected response.")
    return results


def point_from_results(results: list[dict], parsed: ParsedAddress) -> GeocodedPoint:
    """Choose the best Nominatim result and convert it. Raises GeocodeNotFound if none fits."""
    # Below rank 26 is a neighborhood or the whole city: Nominatim falls back to those when the
    # street isn't found, and a city center is no use for finding a door.
    usable = [r for r in results if not _is_transit(r) and _rank(r) >= 26]
    houses = [r for r in usable if _rank(r) >= 30]
    streets = [r for r in usable if _rank(r) < 30]
    if parsed.housenumber:
        # Never hand back a different house: 79 Mass Ave is the wrong door for 77.
        houses = [r for r in houses if _housenumber_matches(r, parsed.housenumber)]
    if parsed.postcode:
        # Boston has the same street name in several neighborhoods (465 Huntington Ave is the
        # MFA in 02115 and a house in Hyde Park, 02136). The ZIP picks the right one when OSM
        # has it; otherwise keep Nominatim's order.
        same_zip = [r for r in houses if _postcode_matches(r, parsed.postcode)]
        houses = same_zip or houses
    if len(houses) > 1:
        top = houses[0]
        far = [r for r in houses[1:] if _meters_between(_lat_lon(top), _lat_lon(r)) > AMBIGUOUS_M]
        # Without a city any far match is a different place. With one, Nominatim's order only
        # means something if it ranked the top result higher; a tie is a coin flip.
        if far and (not parsed.city or any(_importance(r) >= _importance(top) for r in far)):
            raise GeocodeAmbiguous(
                "More than one place has this address. Add the city or ZIP code."
            )
    if not houses and not streets:
        raise GeocodeNotFound("Couldn't find that address.")

    best = houses[0] if houses else streets[0]
    lat, lon = _lat_lon(best)
    address = best.get("address") or {}
    return GeocodedPoint(
        lat=lat,
        lon=lon,
        source="nominatim",
        housenumber=address.get("house_number") or parsed.housenumber,
        precision="house" if _rank(best) >= 30 else "street",
        osm_ref=_osm_ref(best.get("osm_type"), best.get("osm_id")),
        category=best.get("category") or best.get("class"),
        type=best.get("type"),
        entrances=_usable_entrances(best.get("entrances")),
    )


def geocode(request: ResolveRequest, *, client: httpx.Client | None = None) -> GeocodedPoint:
    """Step 1 (BE-2). Address -> point with Nominatim, 1 request/s, identifying User-Agent.
    If the request already has lat/lon (from Apple's geocoder on the phone), use those.

    Results are cached for the life of the process (Nominatim's policy requires caching);
    `force_refresh` skips the cache. `client` is for tests, which replay saved responses.
    """
    parsed = parse_address(request.address or "")
    if request.lat is not None and request.lon is not None:
        if not (-90 <= request.lat <= 90 and -180 <= request.lon <= 180):
            raise ValueError("lat must be in [-90, 90] and lon in [-180, 180].")
        return GeocodedPoint(
            lat=request.lat, lon=request.lon, source="request", housenumber=parsed.housenumber
        )
    if not parsed.street:
        raise GeocodeNotFound("Send an address, or lat and lon.")

    params = nominatim_params(parsed)
    key = tuple(sorted(params.items()))
    if not request.force_refresh:
        with _cache_lock:
            if key in _cache:
                return _cache[key]

    point = point_from_results(nominatim_search(params, client), parsed)
    with _cache_lock:
        _cache[key] = point
        while len(_cache) > _CACHE_MAX:
            del _cache[next(iter(_cache))]  # drop the oldest entry
    return point


def clear_geocode_cache() -> None:
    with _cache_lock:
        _cache.clear()


def _rank(result: dict) -> int:
    try:
        return int(result.get("place_rank", 0))
    except (TypeError, ValueError):
        return 0


def _is_transit(result: dict) -> bool:
    category = result.get("category") or result.get("class")
    return category == "public_transport" or (category, result.get("type")) in _TRANSIT


def _importance(result: dict) -> float:
    try:
        return float(result.get("importance") or 0)
    except (TypeError, ValueError):
        return 0.0


def _postcode_matches(result: dict, postcode: str) -> bool:
    found = str((result.get("address") or {}).get("postcode") or "")
    return postcode in {p.strip()[:5] for p in re.split(r"[;,]", found)}


def _housenumber_matches(result: dict, housenumber: str) -> bool:
    """True if the result has this number, or has none that could contradict it."""
    found = str((result.get("address") or {}).get("house_number") or "")
    if not found:
        return True
    return housenumber.lower() in {n.strip().lower() for n in re.split(r"[;,]", found)}


def _lat_lon(result: dict) -> tuple[float, float]:
    return float(result["lat"]), float(result["lon"])


def _osm_ref(osm_type: Any, osm_id: Any) -> str | None:
    if not osm_type or osm_id is None:
        return None
    kind = str(osm_type).lower()
    return f"{_OSM_TYPES.get(kind, kind)}/{osm_id}"


def _usable_entrances(raw: list[dict] | None) -> tuple[Entrance, ...]:
    """Nominatim's entrances include exits, so apply scoring's exclusions (plan section 9)."""
    doors = []
    for item in raw or []:
        value = str(item.get("type") or "yes")
        tags = {str(k): str(v) for k, v in (item.get("extratags") or {}).items()}
        values = [v.strip() for v in value.split(";") if v.strip()]
        if not any(v not in EXCLUDE for v in values):
            continue
        if tags.get("access") in EXCLUDE_ACCESS or tags.get("foot") in EXCLUDE_ACCESS:
            continue
        doors.append(
            Entrance(
                ref=f"node/{item['osm_id']}",
                lat=float(item["lat"]),
                lon=float(item["lon"]),
                entrance=value,
                tags=tags,
            )
        )
    return tuple(doors)


def _meters_between(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Great-circle distance in meters between two (lat, lon) points."""
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 2 * 6_371_000 * math.asin(math.sqrt(h))


def find_building(point):
    """Step 2 (BE-3). Overpass: outline containing the point, else matching house number
    within 30 m, else nearest. Include multipolygon members and building:part ways.
    Cache Overpass responses 7 days; public Overpass allows apps only ~100 queries/day.
    TODO (BE-3)
    """
    raise NotImplementedError("BE-3")


def read_entrances(building, dest_housenumber):
    """Step 3 (BE-4). Entrance nodes that are part of the outline (node(w)), scored with
    scoring.score_door. If any candidate is >= 0.75, the ladder stops here.
    TODO (BE-4)
    """
    raise NotImplementedError("BE-4")


def doors_from_photos(building):
    """Step 4 (CV-2, CV-5, CV-6). Only when step 3 is weak. Mapillary photos within 50 m
    facing the wall -> door detector -> rays (geo.photo_ray_bearing, geo.ray_hits_outline)
    -> DBSCAN clusters. Runs as a background job; /v1/resolve returns 202 meanwhile.
    TODO
    """
    raise NotImplementedError("CV-6")


def facade_fallback(building, point):
    """Step 5 (BE-5). Middle of the street-facing side (0.30), then the address point (0.20).
    Also builds the street_side block (entrance street, centerline, door side, oneway).
    TODO (BE-5)
    """
    raise NotImplementedError("BE-5")


def resolve(request: ResolveRequest) -> ResolveResult:
    """Run the ladder, merge candidates within ~4 m, add path checks (BE-7), landmarks,
    recognize text and street_side, and return the top 5.
    TODO (BE-6)
    """
    raise NotImplementedError("BE-6")
