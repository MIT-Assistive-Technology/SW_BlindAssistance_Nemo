"""Score pilot entrance bundles against golden ground truth (QA-2 / BE-12).

Pure functions over plain dicts, standard library only. scripts/evaluate_bundles.py does the
file I/O and writes the report. Targets come from docs/car-to-curb-plan.md: section 2 (report
n and a 95% interval with every number; confident-wrong as "k in N" with its 95% upper bound),
section 8 (street-photo doors: median <= 4 m, p90 <= 8 m, never spoken as `main`) and section
18 (M1 go/no-go: correct building at every site, correct building side >= 90%).

Joining golden sites to bundles
-------------------------------
Bundles are written as bundles/<pilot id>.json with destination_id "dst_<pilot id>"
(app/bundle.py). Golden ids and pilot ids both reuse the Nominatim fixture ids, so the join
tries, in order:
  1. golden `id` == bundle id (file stem, or destination_id without "dst_");
  2. golden `fixture_id` == bundle id;
  3. golden `address` == a pilot site's `address` (case, spaces and punctuation ignored),
     then that pilot site's id == bundle id.
The scenario always comes from the golden file (it is the surveyed truth); a pilot site that
files the same place under another scenario is reported as a note, not silently merged.

Missing data is never a pass: a site without usable truth or without a bundle is listed under
"skipped" with every reason that applies and counts toward no rate.
"""

import itertools
import math
import re
import statistics
from collections.abc import Iterable

EARTH_RADIUS_M = 6_371_008.8  # mean Earth radius (IUGG)
Z95 = 1.959963984540054  # two-sided 95% normal quantile

TOP5_RADIUS_M = 5.0  # "the true entrance is among the top 5" = some candidate within 5 m
CONFIDENT_WRONG_M = 10.0  # top band "main" but farther than this from the true door
WITHIN_M = (3.0, 5.0, 10.0)
MIN_MEASURED_SITES = 5  # below this, every verdict is NOT ENOUGH DATA

# M1 thresholds. Plan section 18 sets the building and building-side rows; the 10 m row is
# the resolver target the team set for M1 (it is not spelled out in section 18). Section 8 sets
# the street-photo rows. Raise these once met; never lower them quietly.
M1_BUNDLED_SITES = 10
M1_WITHIN_10M_RATE = 0.80
M1_SIDE_RATE = 0.90
STREET_PHOTO_MEDIAN_M = 4.0
STREET_PHOTO_P90_M = 8.0

SCENARIOS = ("same_side", "driveway", "opposite", "campus")
_SCENARIO_ALIASES = {"opposite_side": "opposite"}  # golden spelling -> pilot spelling

GO, NO_GO, NOT_ENOUGH, NOT_EVALUATED, REPORT_ONLY = (
    "GO",
    "NO-GO",
    "NOT ENOUGH DATA",
    "NOT EVALUATED",
    "REPORT ONLY",
)


# ---------------------------------------------------------------- math


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in meters."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(a)))


def wilson_interval(k: int, n: int, z: float = Z95) -> tuple[float, float] | None:
    """Wilson score interval for k successes in n trials; None when n == 0."""
    if n <= 0:
        return None
    if not 0 <= k <= n:
        raise ValueError(f"need 0 <= k <= n, got k={k}, n={n}")
    p = k / n
    denom = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    lo = 0.0 if k == 0 else max(0.0, center - half)  # exact at the ends, no float fuzz
    hi = 1.0 if k == n else min(1.0, center + half)
    return lo, hi


def upper_bound_95(k: int, n: int) -> float | None:
    """95% upper bound on a rate: rule of three (3/n, capped at 1) when k == 0, else Wilson."""
    if n <= 0:
        return None
    if k == 0:
        return min(1.0, 3 / n)
    return wilson_interval(k, n)[1]


def percentile(values: Iterable[float], p: float) -> float | None:
    """Nearest-rank percentile (the smallest value with at least p% of the data at or below it).

    Conservative for small n: with fewer than 10 values, p90 is the maximum. None when empty.
    """
    xs = sorted(values)
    if not xs:
        return None
    if not 0 < p <= 100:
        raise ValueError("p must be in (0, 100]")
    return xs[max(1, math.ceil(p / 100 * len(xs))) - 1]


def median(values: Iterable[float]) -> float | None:
    xs = list(values)
    return statistics.median(xs) if xs else None


def _local_m(lat0: float, lon0: float, lat: float, lon: float) -> tuple[float, float]:
    """(east, north) meters of (lat, lon) from (lat0, lon0); fine over a city block."""
    k = math.radians(EARTH_RADIUS_M)
    return (lon - lon0) * k * math.cos(math.radians(lat0)), (lat - lat0) * k


def side_of_line(centerline: list[list[float]], lat: float, lon: float) -> str | None:
    """Side ("left" or "right") of a [lon, lat] polyline's direction (first -> last point).

    Uses the nearest segment and the sign rule of plan section 6 / app/geo.py:
    cross = road.east * to_point.north - road.north * to_point.east; negative -> right.
    None for a degenerate line or a point exactly on it.
    """
    pts = [_local_m(lat, lon, la, lo) for lo, la in centerline]
    best = None  # (squared distance, cross)
    for (ax, ay), (bx, by) in itertools.pairwise(pts):
        dx, dy = bx - ax, by - ay
        seg2 = dx * dx + dy * dy
        if seg2 == 0:
            continue
        t = max(0.0, min(1.0, (-ax * dx - ay * dy) / seg2))  # the point is the origin
        cx, cy = ax + t * dx, ay + t * dy
        cross = dx * (0 - ay) - dy * (0 - ax)
        d2 = cx * cx + cy * cy
        if best is None or d2 < best[0]:
            best = (d2, cross)
    if best is None or best[1] == 0:
        return None
    return "left" if best[1] > 0 else "right"


def flip(side: str) -> str:
    return {"left": "right", "right": "left"}[side]


# ---------------------------------------------------------------- normalizing and joining


def normalize_address(text: str | None) -> str:
    return re.sub(r"[^a-z0-9]", "", (text or "").lower())


_STREET_WORDS = {
    "ave": "avenue",
    "av": "avenue",
    "st": "street",
    "rd": "road",
    "blvd": "boulevard",
    "pl": "place",
    "dr": "drive",
    "sq": "square",
    "pkwy": "parkway",
    "ln": "lane",
    "ct": "court",
    "hwy": "highway",
    "ter": "terrace",
}


def normalize_street(text: str | None) -> str:
    words = re.findall(r"[a-z0-9]+", (text or "").lower())
    return " ".join(_STREET_WORDS.get(w, w) for w in words)


def scenario_of(loc: dict) -> str:
    s = loc.get("scenario")
    return _SCENARIO_ALIASES.get(s, s)


def bundle_key(file_stem: str, bundle: dict) -> str:
    """The id a bundle is joined on: its file stem (== pilot id, see app/bundle.write_bundle)."""
    if file_stem:
        return file_stem
    return str(bundle.get("destination_id", "")).removeprefix("dst_")


def join(
    locations: list[dict], bundles: dict[str, dict], pilot_sites: list[dict]
) -> list[tuple[dict, str | None, str | None]]:
    """Pair each golden site with a bundle id. Returns (location, bundle_id, how) per site."""
    by_destination = {
        str(b.get("destination_id", "")).removeprefix("dst_"): key for key, b in bundles.items()
    }
    by_address = {normalize_address(s.get("address")): s.get("id") for s in pilot_sites}

    def find(candidate: str | None) -> str | None:
        if not candidate:
            return None
        if candidate in bundles:
            return candidate
        return by_destination.get(candidate)

    out = []
    for loc in locations:
        for how, candidate in (
            ("id", loc.get("id")),
            ("fixture_id", loc.get("fixture_id")),
            ("address", by_address.get(normalize_address(loc.get("address")))),
        ):
            if hit := find(candidate):
                out.append((loc, hit, how))
                break
        else:
            out.append((loc, None, None))
    return out


# ---------------------------------------------------------------- per site


def truth_point(loc: dict) -> tuple[float, float] | None:
    t = loc.get("entrance_truth") or {}
    lat, lon = t.get("lat"), t.get("lon")
    if isinstance(lat, int | float) and isinstance(lon, int | float):
        return float(lat), float(lon)
    return None


def skip_reasons(loc: dict, bundle: dict | None) -> list[str]:
    """Every reason this site can't be scored. Empty list = scoreable."""
    reasons = []
    if loc.get("status") != "measured" or truth_point(loc) is None:
        reasons.append("truth_null")
    if loc.get("truth_uncertain"):
        reasons.append("truth_uncertain")
    if bundle is None:
        reasons.append("no_bundle")
    elif not bundle.get("candidates"):
        reasons.append("bundle_has_no_candidates")
    return reasons


def _candidate_error(c: dict, truth: tuple[float, float]) -> float:
    return haversine_m(c["lat"], c["lon"], *truth)


def building_check(loc: dict, bundle: dict) -> dict:
    """Correct building: bundle building.osm_id vs golden `building_osm_id`, when present.

    golden/schema.json has no building id field yet, so today this is always not_evaluated.
    """
    want = loc.get("building_osm_id")
    got = (bundle.get("building") or {}).get("osm_id")
    if not want:
        return {"verdict": "not_evaluated", "reason": "golden entry has no building_osm_id"}
    if got == want:
        return {"verdict": "correct", "reason": f"{got}"}
    return {"verdict": "wrong", "reason": f"bundle {got}, truth {want}"}


def side_check(loc: dict, bundle: dict) -> dict:
    """Side of street: bundle street_side.door_side_of_road vs the surveyed side.

    Truth sides come from (a) each drop-off point on the bundle's entrance street with
    curb_side and side_vs_door recorded: door side = curb_side if "same", else the other side;
    and (b) the measured door point against the bundle's own centerline. verdict is "agree",
    "disagree" or "unknown"; `cause` says whether an unknown is a bundle gap (counts against
    the bundle) or a truth gap (excluded).
    """
    ss = bundle.get("street_side")
    if not ss or ss.get("door_side_of_road") not in ("left", "right"):
        return {"verdict": "unknown", "cause": "bundle", "reason": "bundle has no street_side"}
    claimed = ss["door_side_of_road"]
    street = normalize_street(ss.get("entrance_street"))
    truths, notes = [], []
    for p in loc.get("drop_off_points") or []:
        curb, rel = p.get("curb_side"), p.get("side_vs_door")
        if curb not in ("left", "right") or rel not in ("same", "opposite"):
            notes.append(f"{p.get('id')}: curb_side/side_vs_door not recorded")
            continue
        if normalize_street(p.get("street")) != street or not street:
            notes.append(f"{p.get('id')}: on {p.get('street')!r}, bundle uses {street!r}")
            continue
        truths.append((f"drop-off {p.get('id')}", curb if rel == "same" else flip(curb)))
    truth = truth_point(loc)
    centerline = ss.get("centerline") or []
    if truth and len(centerline) >= 2 and (geo := side_of_line(centerline, *truth)):
        truths.append(("door point vs centerline", geo))
    if not truths:
        return {
            "verdict": "unknown",
            "cause": "truth",
            "reason": "; ".join(notes) or "no surveyed side",
        }
    if len({s for _, s in truths}) > 1:
        detail = ", ".join(f"{src}={s}" for src, s in truths)
        return {"verdict": "unknown", "cause": "truth", "reason": f"truth disagrees: {detail}"}
    verdict = "agree" if truths[0][1] == claimed else "disagree"
    sources = ", ".join(src for src, _ in truths)
    return {
        "verdict": verdict,
        "cause": None,
        "reason": f"bundle {claimed}, truth {truths[0][1]} ({sources})",
    }


def score_site(loc: dict, bundle: dict) -> dict:
    """Metrics for one scoreable site (skip_reasons() returned nothing)."""
    truth = truth_point(loc)
    candidates = bundle["candidates"][:5]
    top = candidates[0]
    errors = [_candidate_error(c, truth) for c in candidates]
    photo = [
        (c, e)
        for c, e in zip(candidates, errors, strict=True)
        if any(p.get("source") == "mapillary_cv" for p in c.get("provenance") or [])
    ]
    top_error = errors[0]
    return {
        "error_m": top_error,
        "top_band": top.get("band"),
        "top_confidence": top.get("confidence"),
        "top_sources": sorted({p.get("source") for p in top.get("provenance") or []}),
        "top5_hit": any(e <= TOP5_RADIUS_M for e in errors),
        "best_of_5_m": min(errors),
        "confident_wrong": top.get("band") == "main" and top_error > CONFIDENT_WRONG_M,
        "building": building_check(loc, bundle),
        "side": side_check(loc, bundle),
        # Best-ranked street-photo candidate, if any (plan section 8 targets).
        "street_photo_error_m": photo[0][1] if photo else None,
        "street_photo_spoken_main": any(c.get("band") == "main" for c, _ in photo),
    }


# ---------------------------------------------------------------- aggregates


def rate(k: int, n: int) -> dict:
    ci = wilson_interval(k, n)
    return {
        "k": k,
        "n": n,
        "rate": k / n if n else None,
        "ci95": list(ci) if ci else None,
    }


def summarize(sites: list[dict]) -> dict:
    """n, share within 3/5/10 m (with Wilson 95% CI), median and p90 top-candidate error."""
    errors = [s["error_m"] for s in sites]
    n = len(errors)
    return {
        "n": n,
        "within": {f"{int(d)}m": rate(sum(e <= d for e in errors), n) for d in WITHIN_M},
        "top5_hit": rate(sum(s["top5_hit"] for s in sites), n),
        "median_m": median(errors),
        "p90_m": percentile(errors, 90),
    }


def _verdict(name: str, status: str, reason: str, **extra) -> dict:
    return {"criterion": name, "verdict": status, "reason": reason, **extra}


def _fmt_ci(r: dict) -> str:
    lo, hi = r["ci95"]
    return f"{r['k']}/{r['n']} = {r['rate']:.0%} (95% CI {lo:.0%}-{hi:.0%})"


def go_no_go(report: dict) -> dict:
    """M1 verdict per criterion with its reason, then overall.

    Overall is NO-GO if any criterion is NO-GO, GO only if every gating criterion is GO, else
    NOT ENOUGH DATA. Verdicts use the point estimate; the reason also gives the 95% interval.
    """
    measured = report["scored"]
    n = len(measured)
    small = n < MIN_MEASURED_SITES
    small_reason = f"only {n} measured site(s); need at least {MIN_MEASURED_SITES}"
    criteria = []

    bundled = report["coverage"]["golden_sites_with_bundle"]
    criteria.append(
        _verdict(
            "Bundles for 10 golden sites",
            GO if bundled >= M1_BUNDLED_SITES else NOT_ENOUGH,
            f"{bundled} golden site(s) have a bundle; plan section 18 needs {M1_BUNDLED_SITES}",
        )
    )

    checks = [s["building"]["verdict"] for s in measured]
    wrong = [s["id"] for s in measured if s["building"]["verdict"] == "wrong"]
    if wrong:
        status, why = NO_GO, f"wrong building at {', '.join(wrong)} (any one is a no-go)"
    elif small:
        status, why = NOT_ENOUGH, small_reason
    elif "not_evaluated" in checks:
        status = NOT_EVALUATED
        why = (
            f"{checks.count('not_evaluated')} of {n} measured site(s) have no golden "
            "building_osm_id, so 'correct building at every site' can't be shown"
        )
    else:
        status, why = GO, f"correct building at all {n} measured sites"
    criteria.append(_verdict("Correct building at every site", status, why))

    sides = [s["side"] for s in measured]
    decided = [s for s in sides if s["verdict"] != "unknown" or s["cause"] == "bundle"]
    side_rate = rate(sum(s["verdict"] == "agree" for s in decided), len(decided))
    if len(decided) < MIN_MEASURED_SITES:
        status = NOT_ENOUGH
        why = (
            f"side of street decidable at {len(decided)} site(s); need {MIN_MEASURED_SITES} "
            "(record curb_side and side_vs_door on site)"
        )
    else:
        status = GO if side_rate["rate"] >= M1_SIDE_RATE else NO_GO
        why = f"{_fmt_ci(side_rate)} agree; target >= {M1_SIDE_RATE:.0%}"
    criteria.append(_verdict("Correct building side >= 90%", status, why, rate=side_rate))

    w10 = report["overall"]["within"]["10m"]
    if small:
        status, why = NOT_ENOUGH, small_reason
    else:
        status = GO if w10["rate"] >= M1_WITHIN_10M_RATE else NO_GO
        why = f"{_fmt_ci(w10)} within 10 m; target >= {M1_WITHIN_10M_RATE:.0%}"
    criteria.append(_verdict("Top door within 10 m at >= 80% of sites", status, why, rate=w10))

    photo = report["street_photo"]
    if photo["spoken_main"]:
        status = NO_GO
        why = f"street-photo door spoken as main at {', '.join(photo['spoken_main'])}"
    elif photo["n"] < MIN_MEASURED_SITES:
        status = NOT_EVALUATED if photo["n"] == 0 else NOT_ENOUGH
        why = f"{photo['n']} measured site(s) with a street-photo candidate"
    else:
        ok = photo["median_m"] <= STREET_PHOTO_MEDIAN_M and photo["p90_m"] <= STREET_PHOTO_P90_M
        status = GO if ok else NO_GO
        why = (
            f"median {photo['median_m']:.1f} m (<= {STREET_PHOTO_MEDIAN_M:g}), "
            f"p90 {photo['p90_m']:.1f} m (<= {STREET_PHOTO_P90_M:g}), n={photo['n']}"
        )
    # Street photos are a "later" item (plan section 2), so they never gate M1 while absent.
    criteria.append(
        _verdict(
            "Street-photo doors: median <= 4 m, p90 <= 8 m, never main",
            status,
            why,
            gating=status == NO_GO or photo["n"] > 0,
        )
    )

    cw = report["confident_wrong"]
    criteria.append(
        _verdict(
            "Confident-wrong (top 'main' > 10 m off)",
            REPORT_ONLY,
            cw["text"],
            gating=False,
        )
    )

    gating = [c for c in criteria if c.get("gating", True)]
    if any(c["verdict"] == NO_GO for c in gating):
        overall = NO_GO
    elif gating and all(c["verdict"] == GO for c in gating):
        overall = GO
    else:
        overall = NOT_ENOUGH
    return {"overall": overall, "criteria": criteria}


def evaluate(
    locations: list[dict], bundles: dict[str, dict], pilot_sites: list[dict] | None = None
) -> dict:
    """The whole evaluation as a JSON-ready dict. `bundles` maps bundle id -> bundle dict."""
    pilot_sites = pilot_sites or []
    pilot_scenario = {s.get("id"): s.get("scenario") for s in pilot_sites}
    scored, skipped, notes = [], [], []
    matched_bundles = set()
    for loc, bundle_id, how in join(locations, bundles, pilot_sites):
        bundle = bundles.get(bundle_id) if bundle_id else None
        if bundle_id:
            matched_bundles.add(bundle_id)
            ps = pilot_scenario.get(bundle_id)
            if ps and ps != scenario_of(loc):
                notes.append(
                    f"{loc['id']}: golden scenario {scenario_of(loc)!r}, pilot_sites.json says "
                    f"{ps!r}; the golden one is used"
                )
        base = {"id": loc.get("id"), "scenario": scenario_of(loc), "bundle": bundle_id}
        if reasons := skip_reasons(loc, bundle):
            skipped.append({**base, "reasons": reasons})
            continue
        scored.append(
            {
                **base,
                "join": how,
                "counts_toward_april": bool(loc.get("counts_toward_april")),
                **score_site(loc, bundle),
            }
        )

    n = len(scored)
    with_bundle = sum(1 for s in scored + skipped if s["bundle"])
    k_cw = sum(s["confident_wrong"] for s in scored)
    ub = upper_bound_95(k_cw, n)
    photo_sites = [s for s in scored if s["street_photo_error_m"] is not None]
    photo_errors = [s["street_photo_error_m"] for s in photo_sites]
    side_counts = {v: 0 for v in ("agree", "disagree", "unknown")}
    for s in scored:
        side_counts[s["side"]["verdict"]] += 1

    report = {
        "scored": scored,
        "skipped": skipped,
        "unmatched_bundles": sorted(set(bundles) - matched_bundles),
        "notes": notes,
        "coverage": {
            "golden_sites": len(locations),
            "golden_sites_with_bundle": with_bundle,
            "measured": n,
            "skipped": len(skipped),
            "skip_reasons": {
                r: sum(r in s["reasons"] for s in skipped)
                for r in ("truth_null", "truth_uncertain", "no_bundle", "bundle_has_no_candidates")
            },
        },
        "overall": summarize(scored),
        "april_gating": summarize([s for s in scored if s["counts_toward_april"]]),
        "by_scenario": {
            sc: summarize([s for s in scored if s["scenario"] == sc]) for sc in SCENARIOS
        },
        "confident_wrong": {
            "k": k_cw,
            "n": n,
            "upper95": ub,
            "method": "rule of three" if k_cw == 0 else "Wilson score",
            "sites": [s["id"] for s in scored if s["confident_wrong"]],
            "text": (
                f"{k_cw} in {n} (95% upper bound {ub:.0%}, "
                f"{'rule of three' if k_cw == 0 else 'Wilson'})"
                if n
                else "0 in 0 (no measured sites, no bound)"
            ),
        },
        "side_of_street": side_counts,
        "street_photo": {
            "n": len(photo_sites),
            "median_m": median(photo_errors),
            "p90_m": percentile(photo_errors, 90),
            "spoken_main": [s["id"] for s in photo_sites if s["street_photo_spoken_main"]],
        },
        "enough_data": n >= MIN_MEASURED_SITES,
    }
    report["go_no_go"] = go_no_go(report)
    return report


# ---------------------------------------------------------------- markdown


def _m(x: float | None) -> str:
    return "-" if x is None else f"{x:.1f}"


def _pct(r: dict) -> str:
    if not r["n"]:
        return "-"
    lo, hi = r["ci95"]
    return f"{r['rate']:.0%} ({lo:.0%}-{hi:.0%})"


def render_markdown(report: dict, sources: dict[str, str] | None = None) -> str:
    cov, gng = report["coverage"], report["go_no_go"]
    lines = ["# Bundle evaluation against golden truth (M1)", ""]
    if sources:
        lines += [", ".join(f"{k}: `{v}`" for k, v in sources.items()) + ".", ""]
    lines += [
        (
            "Regenerate from `server/` with `python scripts/evaluate_bundles.py`. Method: "
            "`server/app/evaluate.py` docstring. Targets: docs/car-to-curb-plan.md "
            "sections 2, 8, 18."
        ),
        "",
    ]
    if not report["enough_data"]:
        lines += [
            (
                f"> **NOT ENOUGH DATA:** {cov['measured']} measured site(s) with a bundle; at "
                f"least {MIN_MEASURED_SITES} are needed before any number here means something. "
                "Missing truth is never counted as a pass."
            ),
            "",
        ]
    lines += [
        f"## Verdict: {gng['overall']}",
        "",
        "| Criterion | Verdict | Reason |",
        "|---|---|---|",
    ]
    lines += [f"| {c['criterion']} | {c['verdict']} | {c['reason']} |" for c in gng["criteria"]]

    lines += [
        "",
        "## Coverage",
        "",
        (
            f"- Golden sites: {cov['golden_sites']}; with a bundle: "
            f"{cov['golden_sites_with_bundle']}; measured and scored: {cov['measured']}; "
            f"skipped: {cov['skipped']}."
        ),
        "- Skip reasons (a site can have several): "
        + ", ".join(f"{k} {v}" for k, v in cov["skip_reasons"].items())
        + ".",
    ]
    if report["unmatched_bundles"]:
        lines.append(
            "- Bundles with no golden site (not scored): "
            + ", ".join(report["unmatched_bundles"])
            + "."
        )
    lines += [f"- Note: {n}" for n in report["notes"]]
    if report["skipped"]:
        lines += ["", "| Skipped site | Scenario | Bundle | Reasons |", "|---|---|---|---|"]
        lines += [
            f"| {s['id']} | {s['scenario']} | {s['bundle'] or '-'} | {', '.join(s['reasons'])} |"
            for s in report["skipped"]
        ]

    lines += [
        "",
        "## Distance error (top candidate to surveyed door)",
        "",
        "Shares with Wilson 95% CI. p90 is nearest-rank, so with n < 10 it is the maximum.",
        "",
        "| Group | n | <= 3 m | <= 5 m | <= 10 m | True door in top 5 | Median m | p90 m |",
        "|---|---:|---|---|---|---|---:|---:|",
    ]
    groups = [("Overall", report["overall"]), ("April-gating", report["april_gating"])]
    groups += [(sc, report["by_scenario"][sc]) for sc in SCENARIOS]
    for name, g in groups:
        w = g["within"]
        lines.append(
            f"| {name} | {g['n']} | {_pct(w['3m'])} | {_pct(w['5m'])} | {_pct(w['10m'])} | "
            f"{_pct(g['top5_hit'])} | {_m(g['median_m'])} | {_m(g['p90_m'])} |"
        )

    cw, side, photo = report["confident_wrong"], report["side_of_street"], report["street_photo"]
    lines += [
        "",
        "## Band honesty and side of street",
        "",
        f"- Confident-wrong (top band `main`, > {CONFIDENT_WRONG_M:g} m off): {cw['text']}"
        + (f": {', '.join(cw['sites'])}." if cw["sites"] else "."),
        (
            f"- Side of street: agree {side['agree']}, disagree {side['disagree']}, "
            f"unknown {side['unknown']}."
        ),
        (
            f"- Street-photo candidates: n {photo['n']}, median {_m(photo['median_m'])} m, "
            f"p90 {_m(photo['p90_m'])} m."
        ),
    ]
    if report["scored"]:
        lines += [
            "",
            "## Per site",
            "",
            "| Site | Scenario | Error m | Band | Top 5 | Confident-wrong | Building | Side |",
            "|---|---|---:|---|---|---|---|---|",
        ]
        for s in report["scored"]:
            lines.append(
                f"| {s['id']} | {s['scenario']} | {s['error_m']:.1f} | {s['top_band']} | "
                f"{'yes' if s['top5_hit'] else 'no'} | {'YES' if s['confident_wrong'] else 'no'} | "
                f"{s['building']['verdict']} | {s['side']['verdict']}: {s['side']['reason']} |"
            )
    return "\n".join(lines) + "\n"
