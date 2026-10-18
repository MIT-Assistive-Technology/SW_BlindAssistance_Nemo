"""Prebuilt pilot bundles, loaded once and served by the live API (plan sections 2, 10, 11).

Every bundles/<id>.json (written by scripts/build_bundles.py) is validated with ResolveResult.
A file that doesn't validate is logged by name and skipped; the others still load. Each bundle is
re-serialized canonically, and its sha256 is the ETag, so the bytes /v1/bundles/{id} serves and
the hash the manifest lists always agree.

Lookups are in memory only: no Overpass, no disk reads per request.
"""

import hashlib
import json
import logging
import math
import os
import re
from dataclasses import dataclass, field
from pathlib import Path

from pydantic import ValidationError

from . import resolver
from .bundle import load_sites
from .models import ResolveResult
from .resolver import GeocodedPoint

log = logging.getLogger(__name__)

SERVER = Path(__file__).resolve().parents[1]
DEFAULT_BUNDLES_DIR = SERVER / "bundles"
DEFAULT_SITES = SERVER / "pilot_sites.json"
# Same slug rule as bundle.PilotSite.id, so an id can never name a path outside the bundle dir.
BUNDLE_ID = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
MATCH_RADIUS_M = 40.0
_EARTH_R = 6_371_000.0


@dataclass(frozen=True)
class StoredBundle:
    id: str
    result: ResolveResult
    body: bytes  # canonical JSON, exactly what is served
    sha256: str
    address: str | None = None


def address_key(address: str) -> tuple[str, str] | None:
    """(street, city), lowercased, from resolver.parse_address. None without both parts.

    Without a city an address can mean two places (77 Mass Ave is in Cambridge and Boston), so
    those go to the geocoder, which knows how to say "ambiguous".
    """
    parsed = resolver.parse_address(address)
    if not parsed.street or not parsed.housenumber or not parsed.city:
        return None

    def norm(s: str) -> str:
        return " ".join(s.replace(".", " ").lower().split())

    return norm(parsed.street), norm(parsed.city)


def _canonical(result: ResolveResult) -> bytes:
    text = json.dumps(result.model_dump(mode="json"), ensure_ascii=False, separators=(",", ":"))
    return text.encode("utf-8")


def _to_meters(lon: float, lat: float, origin: tuple[float, float]) -> tuple[float, float]:
    """Local equirectangular (east, north) meters around origin (lat, lon). Fine within ~1 km."""
    lat0, lon0 = origin
    x = math.radians(lon - lon0) * math.cos(math.radians(lat0)) * _EARTH_R
    y = math.radians(lat - lat0) * _EARTH_R
    return x, y


def _distance_m(point: GeocodedPoint, footprint: list[list[float]]) -> float:
    """Meters from the point to the footprint ring: 0 inside it, else to the nearest wall.

    A footprint of one point is just that point. Pure Python: a few dozen pilot outlines.
    """
    ring = [_to_meters(lon, lat, (point.lat, point.lon)) for lon, lat in footprint]
    if not ring:
        return math.inf
    if len(ring) == 1:
        return math.hypot(*ring[0])
    edges = list(zip(ring, ring[1:] + ring[:1], strict=True))
    # Even-odd ray cast from the origin (the point) toward +x.
    inside = False
    for (x1, y1), (x2, y2) in edges:
        if (y1 > 0) != (y2 > 0) and x1 + (0 - y1) * (x2 - x1) / (y2 - y1) > 0:
            inside = not inside
    if inside:
        return 0.0
    return min(_to_segment((x1, y1), (x2, y2)) for (x1, y1), (x2, y2) in edges)


def _to_segment(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Distance from the origin to segment a-b."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    length2 = dx * dx + dy * dy
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, -(a[0] * dx + a[1] * dy) / length2))
    return math.hypot(a[0] + t * dx, a[1] + t * dy)


@dataclass
class BundleStore:
    by_id: dict[str, StoredBundle] = field(default_factory=dict)
    by_osm_id: dict[str, StoredBundle] = field(default_factory=dict)
    by_address: dict[tuple[str, str], StoredBundle] = field(default_factory=dict)
    skipped: list[str] = field(default_factory=list)  # file names that failed to load

    def __len__(self) -> int:
        return len(self.by_id)

    def get(self, bundle_id: str) -> StoredBundle | None:
        return self.by_id.get(bundle_id) if BUNDLE_ID.match(bundle_id) else None

    def find_address(self, address: str) -> StoredBundle | None:
        key = address_key(address)
        return self.by_address.get(key) if key else None

    def match(self, point: GeocodedPoint) -> StoredBundle | None:
        """The pilot bundle for a geocoded point, or None if it isn't a pilot destination.

        1. The building Nominatim matched is a pilot building (same osm_ref).
        2. Else the nearest pilot footprint (or centroid) within 40 m.
        A street-level geocode (the house number wasn't found) never matches by distance: the
        point is just somewhere on the street, and a nearby pilot building is likely the wrong
        door.
        """
        if point.osm_ref and point.osm_ref in self.by_osm_id:
            return self.by_osm_id[point.osm_ref]
        if point.precision == "street":
            return None
        best, best_m = None, MATCH_RADIUS_M
        for stored in self.by_id.values():
            meters = _distance_m(point, stored.result.building.footprint)
            if meters <= best_m:
                best, best_m = stored, meters
        return best

    def manifest(self) -> list[dict]:
        return [
            {
                "id": b.id,
                "address": b.address,
                "osm_id": b.result.building.osm_id,
                "data_version": b.result.data_version.model_dump(),
                "sha256": b.sha256,
                "url": f"/v1/bundles/{b.id}",
            }
            for b in self.by_id.values()
        ]


def _site_addresses(sites_path: Path) -> dict[str, str]:
    if not sites_path.is_file():
        return {}
    try:
        return {s.id: s.address for s in load_sites(sites_path)}
    except (OSError, ValueError) as exc:
        log.warning(
            "pilot sites file %s not usable (%s); bundles load without addresses",
            sites_path.name,
            type(exc).__name__,
        )
        return {}


def load(bundles_dir: Path | None = None, sites_path: Path | None = None) -> BundleStore:
    """Load every *.json in bundles_dir (default: env BUNDLES_DIR, else server/bundles)."""
    bundles_dir = bundles_dir or Path(os.environ.get("BUNDLES_DIR") or DEFAULT_BUNDLES_DIR)
    sites_path = sites_path or Path(os.environ.get("PILOT_SITES") or DEFAULT_SITES)
    addresses = _site_addresses(sites_path)
    store = BundleStore()
    paths = sorted(bundles_dir.glob("*.json")) if bundles_dir.is_dir() else []
    for path in paths:
        bundle_id = path.stem
        if not BUNDLE_ID.match(bundle_id):
            log.warning("skipping bundle %s: the file name isn't a valid bundle id", path.name)
            store.skipped.append(path.name)
            continue
        try:
            result = ResolveResult.model_validate_json(path.read_bytes())
        except ValidationError as exc:
            # Only the count: error details can echo file contents into the log.
            log.warning("skipping bundle %s: %d contract errors", path.name, exc.error_count())
            store.skipped.append(path.name)
            continue
        except OSError as exc:
            log.warning("skipping bundle %s: %s", path.name, type(exc).__name__)
            store.skipped.append(path.name)
            continue
        body = _canonical(result)
        stored = StoredBundle(
            id=bundle_id,
            result=result,
            body=body,
            sha256=hashlib.sha256(body).hexdigest(),
            address=addresses.get(bundle_id),
        )
        store.by_id[bundle_id] = stored
        osm_id = result.building.osm_id
        if osm_id in store.by_osm_id:
            log.warning(
                "bundles %s and %s share building %s; %s wins the lookup",
                store.by_osm_id[osm_id].id,
                bundle_id,
                osm_id,
                store.by_osm_id[osm_id].id,
            )
        else:
            store.by_osm_id[osm_id] = stored
        if stored.address and (key := address_key(stored.address)):
            store.by_address.setdefault(key, stored)
    log.info(
        "loaded %d pilot bundles from %s (%d skipped)", len(store), bundles_dir, len(store.skipped)
    )
    return store
