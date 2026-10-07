"""Door scoring (BE-4). Plain rules, no ML.

Tables come from docs/car-to-curb-plan.md sections 8-9. Change the numbers there and here
together, and re-run the golden-location tests (QA-2) after any change.
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

# Non-OSM evidence.
MAPILLARY_MULTI_VIEW = 0.65
MAPILLARY_SINGLE = 0.45
CROWD_CONFIRMED = 0.85
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
      3. Return 1.0 if tags["addr:housenumber"] == dest_housenumber (address match wins).
      4. Start from the best BASE value (UNKNOWN_VALUE for unlisted values).
      5. Adjust: wheelchair yes/designated +0.05, wheelchair no -0.05, has_footway +0.05,
         not on_outline -0.10, level != "0" -0.10, door=overhead -0.10.
      6. Return min(score, CAP).
    tests/test_scoring.py has the expected values; remove its skip marker when done.
    """
    raise NotImplementedError("BE-4")


def combine(scores: list[float]) -> float:
    """Noisy-OR for sources that agree on the same spot (within ~8 m), capped at CAP.

    Example: combine([0.90, 0.65]) -> 1 - 0.10 * 0.35 = 0.965 -> 0.95.
    TODO (BE-4)
    """
    raise NotImplementedError("BE-4")


def band(confidence: float) -> str:
    """Spoken band: "found" (>= 0.75), "likely" (0.45-0.75), "facade" (< 0.45)."""
    if confidence >= 0.75:
        return "found"
    if confidence >= 0.45:
        return "likely"
    return "facade"
