"""Hand-written Overpass responses in local meters, for test_overpass.py and test_doors.py.

x = east, y = north, in meters from ORIGIN. Elements look like Overpass `out body geom`: ways
carry both `nodes` and `geometry`, relation members carry `ref`, `role` and (ways) `geometry`.
"""

import json
from pathlib import Path

from app import overpass
from app.geo import Frame

ORIGIN = Frame(42.36, -71.09)


def lonlat(x: float, y: float) -> tuple[float, float]:
    return ORIGIN.lonlat(x, y)


def xy(lon: float, lat: float) -> tuple[float, float]:
    return ORIGIN.xy(lon, lat)


class Osm:
    """Collects elements. `node(..., out=False)` only places a node for way geometry."""

    def __init__(self):
        self.coords: dict[int, tuple[float, float]] = {}  # id -> (lon, lat)
        self.way_nodes: dict[int, list[int]] = {}
        self.elements: list[dict] = []

    def node(self, id: int, x: float, y: float, out: bool = True, **tags) -> int:
        lon, lat = lonlat(x, y)
        self.coords[id] = (lon, lat)
        if out:
            self.elements.append({"type": "node", "id": id, "lat": lat, "lon": lon, "tags": tags})
        return id

    def path(self, first_id: int, points: list[tuple[float, float]]) -> list[int]:
        """Place untagged nodes first_id, first_id + 1, ... at points; return their ids."""
        return [self.node(first_id + i, x, y, out=False) for i, (x, y) in enumerate(points)]

    def _geometry(self, nodes: list[int]) -> list[dict]:
        return [{"lat": self.coords[n][1], "lon": self.coords[n][0]} for n in nodes]

    def way(self, id: int, nodes: list[int], out: bool = True, **tags) -> int:
        self.way_nodes[id] = nodes
        if out:
            self.elements.append(
                {
                    "type": "way",
                    "id": id,
                    "nodes": nodes,
                    "geometry": self._geometry(nodes),
                    "tags": tags,
                }
            )
        return id

    def rel(self, id: int, members: list[tuple[str, int, str]], **tags) -> int:
        out = []
        for kind, ref, role in members:
            m = {"type": kind, "ref": ref, "role": role}
            if kind == "way":
                m["geometry"] = self._geometry(self.way_nodes[ref])
            out.append(m)
        self.elements.append({"type": "relation", "id": id, "members": out, "tags": tags})
        return id

    def response(self) -> dict:
        return {"osm3s": {"timestamp_osm_base": "2026-10-01T00:00:00Z"}, "elements": self.elements}


def save(client: overpass.Client, query: str, response: dict) -> Path:
    """Store a response in the client's cache format, as a live run would."""
    path = client.path_for(query)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"query": query, "response": response}), encoding="utf-8")
    return path
