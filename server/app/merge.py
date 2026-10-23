"""Merge duplicate door candidates (BE-6, docs/car-to-curb-plan.md section 8).

The ladder can report one physical door more than once: an OSM entrance node, a street-photo
detection a few meters off, a rider confirmation. Candidates within ~4 m become one candidate
whose confidence is `combine(best_by_class)` (best independent class, one agreement step,
capped). Pure and deterministic; no I/O.

Rules
-----
- Evidence class = the class of the candidate's first provenance entry that has one
  (osm_tag -> "osm", mapillary_cv -> "photos", crowd -> "crowd"). Only the best score per class
  reaches `combine`, so same-class duplicates never count as agreement.
- Candidates with geometry_fallback provenance (street-facing guesses), or with no evidence
  class at all, are never merged and never boost a door; they pass through as they are.
- Two OSM entrance nodes with different refs (or no ref) are two mapped doors, not a duplicate:
  they never share a cluster. The same OSM ref seen twice is a duplicate and merges.
- Clustering is greedy and seeded by strength. Candidates are ranked by confidence (highest
  first), then osm_tag before other sources, then input order. The strongest unassigned
  candidate seeds a cluster; the cluster then repeatedly admits, in rank order, any unassigned
  candidate that is within `radius_m` of some member (single linkage) AND within
  2 x `radius_m` of every member (so a chain can never stretch a cluster past 2 x radius).
  Example: A-B-C-D in a line 3 m apart, radius 4 m -> {A, B, C} (A-C is 6 m) and D alone
  (A-D is 9 m), when A is the strongest.
- Building faces: when a `same_face(a, b)` predicate is given, candidates of DIFFERENT evidence
  classes only share a cluster if they are on the same face (checked against every member of
  another class). A photo hit around a corner must not boost the door on the next wall.
  None keeps the distance-only behavior.
- Contested evidence joins the nearest door: a candidate within reach of two distinct OSM
  doors joins the cluster of the one it is nearest to (measured to the nearest cluster member).
  On an exact tie it joins the stronger door's cluster (the one seeded first), so input order
  only matters among fully tied candidates.
- The merged candidate keeps the strongest member's id, position, band, label and speak; its
  provenance is the union of the members' (duplicates dropped, first-seen order).
- Merged confidence = combine(best_by_class), never below the best member's score and capped at
  scoring.CAP. A non-finite or too-low combine result is replaced by the best member's score
  and logged: merging must never demote a door. Singletons skip combine and are only capped.
- A candidate with a non-finite position raises ValueError: a NaN door must fail the site's
  build loudly, never reach a bundle.

Known limitation: one physical door mapped twice under different OSM refs (a node on the
building way plus a stray node, or one door on two building parts) stays as two near-identical
candidates and uses two of the five slots. That is the safe side of the trade-off; a later dedup
could also merge "same entrance/ref/name tags within 1 m".
"""

import json
import logging
import math
from collections.abc import Callable

from .evaluate import haversine_m
from .models import Candidate
from .scoring import CAP

log = logging.getLogger(__name__)
EVIDENCE_CLASS = {"osm_tag": "osm", "mapillary_cv": "photos", "crowd": "crowd"}


def _evidence_class(c: Candidate) -> str | None:
    if any(p.source == "geometry_fallback" for p in c.provenance):
        return None
    return next(
        (EVIDENCE_CLASS[p.source] for p in c.provenance if p.source in EVIDENCE_CLASS), None
    )


def _osm_ref(c: Candidate) -> str | None:
    return next((p.ref for p in c.provenance if p.source == "osm_tag"), None)


def _distinct_osm_doors(a: Candidate, b: Candidate) -> bool:
    if _evidence_class(a) != "osm" or _evidence_class(b) != "osm":
        return False
    ref_a, ref_b = _osm_ref(a), _osm_ref(b)
    return ref_a is None or ref_a != ref_b


def _clamp(c: Candidate) -> Candidate:
    return c if c.confidence <= CAP else c.model_copy(update={"confidence": CAP})


def merge_candidates(
    candidates: list[Candidate],
    *,
    radius_m: float = 4.0,
    combine: Callable[[dict[str, float]], float],
    same_face: Callable[[Candidate, Candidate], bool] | None = None,
) -> list[Candidate]:
    """Merge candidates within `radius_m` of each other; see the module docstring for the rules.

    Returns merged doors and untouched fallback candidates in seed order (strongest seed first).
    """
    for c in candidates:
        if not (math.isfinite(c.lat) and math.isfinite(c.lon)):
            raise ValueError(f"candidate {c.id} has a non-finite position ({c.lat}, {c.lon})")
    order = sorted(
        range(len(candidates)),
        key=lambda i: (
            -candidates[i].confidence,
            _evidence_class(candidates[i]) != "osm",
            i,
        ),
    )
    ranked = [candidates[i] for i in order]
    cls = [_evidence_class(c) for c in ranked]
    n = len(ranked)
    dist = [[haversine_m(a.lat, a.lon, b.lat, b.lon) for b in ranked] for a in ranked]

    def compatible(i: int, j: int) -> bool:
        """May i and j share a cluster (ignoring distance)?"""
        if _distinct_osm_doors(ranked[i], ranked[j]):
            return False
        return same_face is None or cls[i] == cls[j] or same_face(ranked[i], ranked[j])

    out: list[Candidate] = []
    assigned = [False] * n
    for s in range(n):
        if assigned[s]:
            continue
        assigned[s] = True
        seed = ranked[s]
        if cls[s] is None:
            out.append(_clamp(seed))
            continue
        cluster = [s]
        grew = True
        while grew:
            grew = False
            for j in range(n):
                if assigned[j] or cls[j] is None:
                    continue
                reach = min(dist[j][m] for m in cluster)
                if (
                    reach > radius_m
                    or any(dist[j][m] > 2 * radius_m for m in cluster)
                    or not all(compatible(j, m) for m in cluster)
                    # A distinct OSM door that is strictly nearer claims j for its own cluster.
                    or any(
                        not assigned[d]
                        and cls[d] == "osm"
                        and dist[j][d] < reach
                        and compatible(j, d)
                        and not all(compatible(d, m) for m in cluster)
                        for d in range(n)
                    )
                ):
                    continue
                assigned[j] = True
                cluster.append(j)
                grew = True
        if len(cluster) == 1:
            out.append(_clamp(seed))
            continue
        best_by_class: dict[str, float] = {}
        for m in cluster:  # strongest first, so setdefault keeps each class's best
            best_by_class.setdefault(cls[m], ranked[m].confidence)
        provenance = list(
            {
                json.dumps(p.model_dump(mode="json"), sort_keys=True): p
                for m in cluster
                for p in ranked[m].provenance
            }.values()
        )
        best = max(best_by_class.values())
        combined = combine(best_by_class)
        if not math.isfinite(combined) or combined < best:
            log.warning(
                "combine(%s) returned %r, below the best member score; using %.2f",
                best_by_class,
                combined,
                best,
            )
            combined = best
        confidence = min(combined, CAP)
        out.append(seed.model_copy(update={"confidence": confidence, "provenance": provenance}))
    return out
