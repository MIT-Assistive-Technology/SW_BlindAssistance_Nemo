"""Door scoring (BE-4). Plain rules, no ML.

The numbers only RANK doors; riders hear one of three bands (see `band`). With ~10 pilot
sites and no calibration data, the decimals are not probabilities. Calibrate each band's
real precision in the October audit. Tables match docs/car-to-curb-plan.md sections 8-9.
"""

# Base score by entrance=* value.
BASE = {
    "main": 0.90,
    "yes": 0.75,
    "entrance": 0.75,
    "staircase": 0.85,  # residential destinations; penalize otherwise
    "home": 0.85,  # residential destinations
    "shop": 0.55,  # 0.85 when the shop is the destination
    "secondary": 0.60,
    "service": 0.20,  # last resort, with a spoken warning
}
UNKNOWN_VALUE = 0.50
EXCLUDE = {"exit", "emergency", "garage", "no", "parking", "loading_dock", "basement"}
EXCLUDE_ACCESS = {"private", "no", "delivery"}
CAP = 0.95  # nothing is certain until the phone's camera confirms the door
AGREEMENT_STEP = 0.05

# Non-OSM evidence.
MAPILLARY_MULTI_VIEW = 0.65
MAPILLARY_SINGLE = 0.45
FACADE_FALLBACK = 0.30
ADDRESS_POINT = 0.20


def score_door(
    tags: dict[str, str],
    dest_housenumber: str | None,
    on_outline: bool,
    has_footway: bool,
) -> float | None:
    """Score one OSM entrance node. Returns None when the door must never be used.

    TODO (BE-4):
      1. Split tags["entrance"] on ";" and drop values in EXCLUDE; None if nothing is left.
      2. None if access or foot is in EXCLUDE_ACCESS.
      3. Return CAP if tags["addr:housenumber"] == dest_housenumber (address match ranks first,
         but the cap still holds).
      4. Start from the best BASE value (UNKNOWN_VALUE for unlisted values).
      5. Adjust: wheelchair yes/designated +0.05, wheelchair no -0.05, has_footway +0.05,
         not on_outline -0.10, level != "0" -0.10, door=overhead -0.10.
      6. Return min(score, CAP).
    tests/test_scoring.py has the expected values; remove its skip marker when done.
    """
    raise NotImplementedError("BE-4")


def combine(best_by_class: dict[str, float]) -> float:
    """Merge evidence for one spot (sources within ~8 m of each other).

    `best_by_class` maps an evidence class to its best score, e.g.
    {"osm": 0.90, "photos": 0.65}. Classes must be independent: an OSM node traced from
    street photos belongs to the "photos" class, not "osm". The sources are not independent
    enough for noisy-OR, so: take the best score, add AGREEMENT_STEP once when 2+ classes
    agree, and cap at CAP.

    Example: combine({"osm": 0.90, "photos": 0.65}) -> 0.95; combine({"osm": 0.75}) -> 0.75.
    TODO (BE-4)
    """
    raise NotImplementedError("BE-4")


def band(confidence: float) -> str:
    """Spoken band: "main" (>= 0.85), "door" (>= 0.45), "facade" (< 0.45)."""
    if confidence >= 0.85:
        return "main"
    if confidence >= 0.45:
        return "door"
    return "facade"
