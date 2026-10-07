"""The lookup ladder: address in, ranked doors out. Stops at the first good answer.

See docs/car-to-curb-plan.md section 8. Each step is its own function so it can be tested
with saved responses (no live network in tests).
"""

from .models import ResolveRequest, ResolveResult


def geocode(request: ResolveRequest):
    """Step 1 (BE-2). Address -> point with Nominatim, 1 request/s, identifying User-Agent.
    If the request already has lat/lon (from Apple's geocoder on the phone), use those.
    TODO (BE-2)
    """
    raise NotImplementedError("BE-2")


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
