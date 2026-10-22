# Bundle evaluation against golden truth (M1)

bundles: `server/bundles`, golden: `golden/locations.json`.

Regenerate from `server/` with `python scripts/evaluate_bundles.py`. Method: `server/app/evaluate.py` docstring. Targets: docs/car-to-curb-plan.md sections 2, 8, 18.

> **NOT ENOUGH DATA:** 0 measured site(s) with a bundle; at least 5 are needed before any number here means something. Missing truth is never counted as a pass.

## Verdict: NOT ENOUGH DATA

| Criterion | Verdict | Reason |
|---|---|---|
| Bundles for 10 golden sites | NOT ENOUGH DATA | 0 golden site(s) have a bundle; plan section 18 needs 10 |
| Correct building at every site | NOT ENOUGH DATA | only 0 measured site(s); need at least 5 |
| Correct building side >= 90% | NOT ENOUGH DATA | side of street decidable at 0 site(s); need 5 (record curb_side and side_vs_door on site) |
| Top door within 10 m at >= 80% of sites | NOT ENOUGH DATA | only 0 measured site(s); need at least 5 |
| Street-photo doors: median <= 4 m, p90 <= 8 m, never main | NOT EVALUATED | 0 measured site(s) with a street-photo candidate |
| Confident-wrong (top 'main' > 10 m off) | REPORT ONLY | 0 in 0 (no measured sites, no bound) |

## Coverage

- Golden sites: 10; with a bundle: 0; measured and scored: 0; skipped: 10.
- Skip reasons (a site can have several): truth_null 10, truth_uncertain 0, no_bundle 10, bundle_has_no_candidates 0.

| Skipped site | Scenario | Bundle | Reasons |
|---|---|---|---|
| cambridge-city-hall | same_side | - | truth_null, no_bundle |
| cambridge-public-library | same_side | - | truth_null, no_bundle |
| brattle-theatre | same_side | - | truth_null, no_bundle |
| harvard-smith-center | same_side | - | truth_null, no_bundle |
| cambridgeside | driveway | - | truth_null, no_bundle |
| museum-of-fine-arts | driveway | - | truth_null, no_bundle |
| mit-84-mass-ave | opposite | - | truth_null, no_bundle |
| boston-public-library | opposite | - | truth_null, no_bundle |
| mit-77-mass-ave | campus | - | truth_null, no_bundle |
| mit-stata | campus | - | truth_null, no_bundle |

## Distance error (top candidate to surveyed door)

Shares with Wilson 95% CI. p90 is nearest-rank, so with n < 10 it is the maximum.

| Group | n | <= 3 m | <= 5 m | <= 10 m | True door in top 5 | Median m | p90 m |
|---|---:|---|---|---|---|---:|---:|
| Overall | 0 | - | - | - | - | - | - |
| April-gating | 0 | - | - | - | - | - | - |
| same_side | 0 | - | - | - | - | - | - |
| driveway | 0 | - | - | - | - | - | - |
| opposite | 0 | - | - | - | - | - | - |
| campus | 0 | - | - | - | - | - | - |

## Band honesty and side of street

- Confident-wrong (top band `main`, > 10 m off): 0 in 0 (no measured sites, no bound).
- Side of street: agree 0, disagree 0, unknown 0.
- Street-photo candidates: n 0, median - m, p90 - m.
