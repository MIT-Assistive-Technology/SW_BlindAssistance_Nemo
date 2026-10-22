"""OSM entrance coverage audit for the MIT + Kendall pilot area (BE-9).

Run from server/:

    python scripts/audit_entrances.py           # read the saved Overpass pull in data/
    python scripts/audit_entrances.py --fetch   # one Overpass query, saved, then audited

Writes docs/audit/pilot-entrance-coverage.md and .csv: every named or addressed building
with no usable entrance node on its outline, MIT buildings with addresses first. That is the
list the field team surveys and maps (task MAP-1). Exclusion rules follow
docs/car-to-curb-plan.md section 9 and reuse the EXCLUDE sets in app/scoring.py.
"""

import argparse
import csv
import itertools
import json
import re
import sys
import time
from pathlib import Path

import httpx

SERVER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER))  # so `app` imports when run as a plain script

from app.scoring import EXCLUDE, EXCLUDE_ACCESS

RAW = SERVER / "data" / "overpass_pilot_entrances.json"
DOCS = SERVER.parent / "docs" / "audit"
ENDPOINT = "https://overpass-api.de/api/interpreter"
USER_AGENT = "MIT-AT-CarToCurb/0.1 (student project audit)"
BBOX = (42.354, -71.106, 42.366, -71.078)  # south, west, north, east

QUERY = """[out:json][timeout:60];
(
  way[building]({s},{w},{n},{e});
  rel[building][type=multipolygon]({s},{w},{n},{e});
)->.bld;
.bld out geom;
way(r.bld:"outer")->.outer;
.outer out geom;
(way.bld; .outer;)->.outlines;
(
  node(w.outlines)[entrance];
  node(w.outlines)[door];
  node(w.outlines)["routing:entrance"];
)->.ent;
rel(bw.outlines)[type=site]->.site;
(.ent; node(r.site:"entrance");)->.ent;
.ent out body;
.site out body;
"""

COLUMNS = ["priority", "status", "name", "address", "osm_id", "osm_url", "lat", "lon"]


def fetch(path: Path = RAW) -> None:
    """One Overpass query for the whole bbox. On error, back off once, then give up."""
    s, w, n, e = BBOX
    query = QUERY.format(s=s, w=w, n=n, e=e)
    headers = {"User-Agent": USER_AGENT}
    for attempt in range(2):
        try:
            r = httpx.post(ENDPOINT, data={"data": query}, headers=headers, timeout=90)
            r.raise_for_status()
            break
        except httpx.HTTPError as exc:
            if attempt:
                raise SystemExit(f"Overpass failed twice, stopping: {exc}") from exc
            print(f"Overpass error ({exc}); backing off 60 s once")
            time.sleep(60)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(r.content)
    print(f"saved {len(r.content):,} bytes to {path}")


def door_status(tags: dict[str, str]) -> str | None:
    """'usable', 'excluded', or None when the node isn't a door we would ever consider."""
    if tags.get("railway") == "subway_entrance" or tags.get("indoor") == "door":
        return None
    if tags.get("barrier") in {"entrance", "gate"} and "entrance" not in tags:
        return None
    if not any(k in tags for k in ("entrance", "door", "routing:entrance")):
        return None
    if tags.get("access") in EXCLUDE_ACCESS or tags.get("foot") in EXCLUDE_ACCESS:
        return "excluded"
    if "entrance" in tags:
        parts = {p.strip() for p in tags["entrance"].split(";") if p.strip()}
        if parts and parts <= EXCLUDE:
            return "excluded"
    return "usable"


def centroid(el: dict) -> tuple[float, float]:
    """Area centroid of a way's ring (shoelace, fine at campus scale); bbox center otherwise."""
    pts = [(g["lon"], g["lat"]) for g in el.get("geometry") or []]
    a = cx = cy = 0.0
    for (x0, y0), (x1, y1) in itertools.pairwise(pts):
        cross = x0 * y1 - x1 * y0
        a += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    if abs(a) > 1e-14:
        return round(cy / (3 * a), 6), round(cx / (3 * a), 6)
    b = el["bounds"]  # relations (out geom gives bounds) and degenerate ways
    return round((b["minlat"] + b["maxlat"]) / 2, 6), round((b["minlon"] + b["maxlon"]) / 2, 6)


MIT_REF = re.compile(r"^(E|W|N|NE|NW)?\d+[A-Z]*$")  # MIT building numbers: 7, E25, NW12A


def is_mit(tags: dict[str, str]) -> bool:
    """Heuristic: few MIT outlines carry operator=*, but most have a campus ref or
    building=university (the only university in this bbox north of the river)."""
    text = " ".join(tags.get(k, "") for k in ("operator", "owner", "name", "official_name"))
    return (
        "Massachusetts Institute of Technology" in text
        or "MIT" in text.split()
        or bool(MIT_REF.match(tags.get("ref", "")))
        or tags.get("building") in {"university", "college", "dormitory"}
    )


def address(tags: dict[str, str]) -> str:
    street = " ".join(x for x in (tags.get("addr:housenumber"), tags.get("addr:street")) if x)
    return ", ".join(x for x in (street, tags.get("addr:city")) if x)


def classify(data: dict) -> list[dict]:
    """One record per building: its status from the door nodes on its outline(s)."""
    els = data["elements"]
    doors = {e["id"]: door_status(e.get("tags", {})) for e in els if e["type"] == "node"}
    ways = {e["id"]: e for e in els if e["type"] == "way"}
    site_doors: dict[int, set[int]] = {}  # outline way id -> site-relation entrance node ids
    for rel in (
        e for e in els if e["type"] == "relation" and e.get("tags", {}).get("type") == "site"
    ):
        entrances = {
            m["ref"] for m in rel["members"] if m["type"] == "node" and m["role"] == "entrance"
        }
        for m in rel["members"]:
            if m["type"] == "way":
                site_doors.setdefault(m["ref"], set()).update(entrances)

    out = []
    for el in els:
        tags = el.get("tags", {})
        if el["type"] not in ("way", "relation") or tags.get("building", "no") == "no":
            continue
        if el["type"] == "way":
            outline_ids = [el["id"]]
        else:
            outline_ids = [
                m["ref"]
                for m in el.get("members", [])
                if m["type"] == "way" and m.get("role") == "outer"
            ]
        node_ids = set()
        for wid in outline_ids:
            node_ids.update(ways.get(wid, {}).get("nodes", []))
            node_ids.update(site_doors.get(wid, ()))
        found = [doors[i] for i in node_ids if doors.get(i)]
        status = "usable" if "usable" in found else "only_excluded" if found else "none"
        lat, lon = centroid(el)
        kind = "way" if el["type"] == "way" else "relation"
        out.append(
            {
                "kind": kind,
                "osm_id": el["id"],
                "osm_url": f"https://www.openstreetmap.org/{kind}/{el['id']}",
                "name": tags.get("name", ""),
                "address": address(tags),
                "mit": is_mit(tags),
                "status": status,
                "lat": lat,
                "lon": lon,
            }
        )
    return out


def priority(b: dict) -> int:
    """1 MIT with address, 2 MIT without, 3 other named + addressed, 4 the rest."""
    if b["mit"]:
        return 1 if b["address"] else 2
    return 3 if b["address"] and b["name"] else 4


def todo(buildings: list[dict]) -> list[dict]:
    rows = [
        {**b, "priority": priority(b)}
        for b in buildings
        if b["status"] != "usable" and (b["name"] or b["address"])
    ]
    return sorted(rows, key=lambda r: (r["priority"], r["name"] or "~", r["address"]))


def summary(buildings: list[dict]) -> dict[str, int]:
    count = {
        s: sum(b["status"] == s for b in buildings) for s in ("usable", "only_excluded", "none")
    }
    return {"buildings": len(buildings), **count}


def write_reports(buildings: list[dict], fetched: str, out_dir: Path = DOCS) -> list[dict]:
    rows = todo(buildings)
    nums = summary(buildings)
    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "pilot-entrance-coverage.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    pct = lambda k: f"{100 * nums[k] / nums['buildings']:.1f}%" if nums["buildings"] else "-"
    s, w, n, e = BBOX
    labels = {
        1: "MIT, addressed",
        2: "MIT, no address",
        3: "Other, named and addressed",
        4: "Other",
    }
    lines = [
        "# Pilot entrance coverage audit (MIT + Kendall)",
        "",
        f"Source: one Overpass pull of bbox S {s}, W {w}, N {n}, E {e} ({fetched}).",
        "Regenerate with `python scripts/audit_entrances.py` from `server/` (add `--fetch` to",
        "re-pull). Rules: docs/car-to-curb-plan.md section 9 (split `;`, exclude",
        f"{', '.join(sorted(EXCLUDE))}; access/foot {', '.join(sorted(EXCLUDE_ACCESS))}).",
        "",
        "## Summary",
        "",
        "| | Buildings | Share |",
        "|---|---:|---:|",
        f"| Building outlines (ways + multipolygons) | {nums['buildings']} | 100% |",
        f"| With at least one usable entrance node | {nums['usable']} | {pct('usable')} |",
        f"| With door nodes, all excluded | {nums['only_excluded']} | {pct('only_excluded')} |",
        f"| With no door-like node at all | {nums['none']} | {pct('none')} |",
        "",
        f"Named or addressed buildings without a usable entrance: **{len(rows)}**",
        "("
        + ", ".join(f"{labels[p]}: {sum(r['priority'] == p for r in rows)}" for p in labels)
        + ").",
        "",
        "## Buildings to survey",
        "",
        "Priority 1 = MIT with an address, 2 = MIT without one, 3 = other named and addressed,",
        "4 = the rest. Status `only_excluded` means the map has doors here but all are exits,",
        "garages, private or similar, so a usable entrance still needs mapping.",
        "",
        "| Pri | Name | Address | OSM id | Lat, lon | Status |",
        "|---:|---|---|---|---|---|",
    ]
    for r in rows:
        name = (r["name"] or "(unnamed)").replace("|", "/")
        link = f"[{r['kind']}/{r['osm_id']}]({r['osm_url']})"
        lines.append(
            f"| {r['priority']} | {name} | {r['address'] or '-'} | {link} | "
            f"{r['lat']}, {r['lon']} | {r['status']} |"
        )
    lines += ["", "Data (c) OpenStreetMap contributors, ODbL.", ""]
    (out_dir / "pilot-entrance-coverage.md").write_text("\n".join(lines), encoding="utf-8")
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fetch", action="store_true", help="re-pull from Overpass first")
    args = parser.parse_args()
    if args.fetch or not RAW.exists():
        fetch()
    data = json.loads(RAW.read_text(encoding="utf-8"))
    fetched = data.get("osm3s", {}).get("timestamp_osm_base", "unknown date")
    buildings = classify(data)
    rows = write_reports(buildings, fetched)
    print(summary(buildings), f"to_survey={len(rows)}")


if __name__ == "__main__":
    main()
