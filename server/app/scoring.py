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
    "staircase": 0.85,  # residential destinations only (RESIDENTIAL_ONLY)
    "home": 0.85,  # residential destinations only
    "shop": 0.85,  # only when the shop is the destination; score_door can't tell, so 0.50
    "secondary": 0.60,
    "service": 0.20,  # last resort, with a spoken warning
}
UNKNOWN_VALUE = 0.50
EXCLUDE = {"exit", "emergency", "garage", "no", "parking", "loading_dock", "basement"}
# "permit" is not in the plan's list: a permit-only door (seen on a loading dock) is no use.
EXCLUDE_ACCESS = {"private", "no", "delivery", "permit"}
# Plan section 9: never treat these as building entrances.
IGNORE_TAGS = {
    "railway": {"subway_entrance"},
    "indoor": {"door"},
    "barrier": {"entrance", "gate"},
    "amenity": {"loading_dock"},
    "door": {"loading_dock"},
}
RESIDENTIAL_ONLY = {"staircase", "home"}  # 0.85 for a residential address, else UNKNOWN_VALUE
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
    *,
    site_entrance: bool = False,
    residential: bool = False,
    below_street: bool = False,
) -> float | None:
    """Score one OSM entrance node. Returns None when the door must never be used.

    The rule list in docs/car-to-curb-plan.md sections 8-9, in order:
      1. Ignore subway entrances, indoor doors, barriers and loading docks.
      2. Split tags["entrance"] on ";" and drop values in EXCLUDE; None if nothing is left.
         A node with only door=* (no entrance=*) counts as entrance=yes.
      3. None if access or foot is in EXCLUDE_ACCESS.
      4. (Moved to the end, Fix R11.)
      5. Start from the best BASE value (UNKNOWN_VALUE for unlisted values). routing:entrance
         or a site relation's role=entrance (`site_entrance`) count as main, the site role only
         when the node is not entrance=service or secondary (Fix R1). staircase and home
         only count for a residential address; shop never does (we can't tell it's the
         destination).
      6. Adjust: wheelchair yes/designated +0.05, wheelchair no -0.05, has_footway +0.05,
         not on_outline -0.10, level != "0" -0.10, door=overhead -0.10. `below_street`
         (every path to the door goes down toward it) counts as level != "0", once.
      7. Adjustments never lift a door into a higher band than its base value: a plain door
         with good tags is still spoken as "a door", never "the main entrance".
      8. If tags["addr:housenumber"] == dest_housenumber, raise the score to the top of its
         band (0.95 for main, 0.80 for a door, 0.40 for facade): it ranks first in its band but
         never changes the band, so "main" is only spoken for a mapped main entrance.
      9. Return min(score, CAP).
    """
    if any(tags.get(k) in values for k, values in IGNORE_TAGS.items()):
        return None

    raw = tags.get("entrance")
    values = [v.strip() for v in raw.split(";") if v.strip()] if raw else ["yes"]
    usable = [v for v in values if v not in EXCLUDE]
    if not usable:
        return None

    if tags.get("access") in EXCLUDE_ACCESS or tags.get("foot") in EXCLUDE_ACCESS:
        return None

    def base(value: str) -> float:
        if value in RESIDENTIAL_ONLY and not residential:
            return UNKNOWN_VALUE
        if value == "shop":
            return UNKNOWN_VALUE
        return BASE.get(value, UNKNOWN_VALUE)

    start = max(base(v) for v in usable)
    if (site_entrance and site_role_is_main(tags)) or "routing:entrance" in tags:
        start = max(start, BASE["main"])

    score = start
    wheelchair = tags.get("wheelchair")
    if wheelchair in {"yes", "designated"}:
        score += 0.05
    elif wheelchair == "no":
        score -= 0.05
    if has_footway:
        score += 0.05
    if not on_outline:
        score -= 0.10
    if below_street or tags.get("level", "0").strip() not in {"0", ""}:
        score -= 0.10
    if tags.get("door") == "overhead":
        score -= 0.10

    score = round(score, 4)  # 0.75 + 0.05 + 0.05 must not become 0.8500000001
    if band(score) != band(start) and score > start:
        score = BAND_TOP[band(start)]
    # Fix R11: the house number ranks a door first within its own band, after the penalties.
    # A service door tagged with the number is still a service door, never "the main entrance".
    if dest_housenumber is not None and tags.get("addr:housenumber") == dest_housenumber:
        score = max(score, BAND_TOP[band(score)])
    return min(score, CAP)


SITE_NOT_MAIN = {"service", "secondary"}


def site_role_is_main(tags: dict[str, str]) -> bool:
    """Fix R1: a site relation's role=entrance counts as main unless the node itself says it is
    a service or secondary door."""
    values = {v.strip() for v in tags.get("entrance", "").split(";")}
    return not values & SITE_NOT_MAIN


def combine(best_by_class: dict[str, float]) -> float:
    """Merge evidence for one spot (sources within ~8 m of each other).

    `best_by_class` maps an evidence class to its best score, e.g.
    {"osm": 0.90, "photos": 0.65}. Classes must be independent: an OSM node traced from
    street photos belongs to the "photos" class, not "osm". The sources are not independent
    enough for noisy-OR, so: take the best score, add AGREEMENT_STEP once when 2+ classes
    agree, and cap at CAP.

    Example: combine({"osm": 0.90, "photos": 0.65}) -> 0.95; combine({"osm": 0.75}) -> 0.75.
    """
    best = max(best_by_class.values())
    if len(best_by_class) >= 2:
        best += AGREEMENT_STEP
    return min(CAP, round(best, 4))


# Highest score each band may reach through adjustments alone (rule 7 of score_door).
BAND_TOP = {"facade": 0.40, "door": 0.80, "main": CAP}


def band(confidence: float) -> str:
    """Spoken band: "main" (>= 0.85), "door" (>= 0.45), "facade" (< 0.45)."""
    if confidence >= 0.85:
        return "main"
    if confidence >= 0.45:
        return "door"
    return "facade"
