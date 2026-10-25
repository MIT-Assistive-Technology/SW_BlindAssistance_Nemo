import time
import json
import requests
from pathlib import Path

ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    # "https://lz4.overpass-api.de/api/interpreter",
    # "https://z.overpass-api.de/api/interpreter",
    # "https://overpass.kumi.systems/api/interpreter",
]
HEADERS = {
    "User-Agent": "CambridgePilotTest/1.2",
    "Accept": "application/json",
}
RETRY_CODES = {429, 500, 502, 503, 504}

def build_query(lat, lon, timeout=500):
    around = f"around:40,{lat},{lon}"
    return f"""
    [out:json][timeout:{timeout}];
    (
      way({around})[building];
      rel({around})[building][type=multipolygon];
      way({around})["building:part"];
    )->.bld;
    .bld out geom;

    (way.bld; way(r.bld:"outer");)->.outlines;

    (
      node(w.outlines)[entrance];
      node(w.outlines)[door];
      node(w.outlines)["routing:entrance"];
    )->.ent;

    rel(bw.outlines)[type=site]->.site;
    (.ent; node(r.site:"entrance");)->.ent;
    .ent out body;
    .site out body;

    way(bn.ent)[highway~"^(footway|path|pedestrian|steps|corridor)$"];
    out tags geom;

    way(around.outlines:60)[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)(_link)?$"];
    out tags geom;
    """

def post_with_retry(query, max_attempts=6):
    last_error = None
    for attempt in range(max_attempts):
        url = ENDPOINTS[attempt % len(ENDPOINTS)]
        try:
            r = requests.post(url, data={"data": query}, headers=HEADERS, timeout=150)
        except requests.RequestException as e:
            last_error = str(e)
        else:
            if r.status_code == 200:
                data = r.json()
                if "remark" in data:
                    raise RuntimeError(f"Overpass remark: {data['remark']}")
                return data
            if r.status_code not in RETRY_CODES:
                raise RuntimeError(f"HTTP {r.status_code}: {r.text[:200]}")
            last_error = f"HTTP {r.status_code} from {url}"

        wait = min(120, 10 * 2 ** attempt)
        print(f"Attempt {attempt + 1} failed ({last_error}); retrying in {wait}s")
        time.sleep(wait)

    raise RuntimeError(f"All attempts failed. Last error: {last_error}")

def get_pilot_osm(lat, lon, out_path="server/data/pilot_osm.json"):
    data = post_with_retry(build_query(lat, lon))

    seen, unique = set(), []
    for el in data.get("elements", []):
        key = (el["type"], el["id"])
        if key not in seen:
            seen.add(key)
            unique.append(el)
    data["elements"] = unique

    path = Path(out_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=4), encoding="utf-8")
    return data

if __name__ == "__main__":
    get_pilot_osm(42.385, -71.120)