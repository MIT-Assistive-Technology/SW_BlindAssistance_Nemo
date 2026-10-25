"""Geometry helpers (BE-3, BE-5, BE-7, CV-5). Work in local (east, north) meters.

Buildings and streets are small, so an equirectangular projection around a nearby point is
accurate to centimeters here. Plain Python, no shapely or pyproj: shapely's native library
doesn't load on every team laptop, and nothing below needs it.

Worked examples: docs/car-to-curb-plan.md sections 6 (side of street) and 8 (street photos).
"""

import math
from collections.abc import Sequence
from dataclasses import dataclass

EARTH_R = 6_371_008.8

XY = tuple[float, float]


@dataclass(frozen=True)
class Frame:
    """Local meters around (lat0, lon0): x = east, y = north."""

    lat0: float
    lon0: float

    @property
    def _kx(self) -> float:
        return math.radians(1) * EARTH_R * math.cos(math.radians(self.lat0))

    def xy(self, lon: float, lat: float) -> XY:
        return ((lon - self.lon0) * self._kx, (lat - self.lat0) * math.radians(1) * EARTH_R)

    def lonlat(self, x: float, y: float) -> tuple[float, float]:
        return (self.lon0 + x / self._kx, self.lat0 + y / (math.radians(1) * EARTH_R))


def closest_on_segment(p: XY, a: XY, b: XY) -> tuple[float, XY]:
    """(distance, nearest point) from p to segment a-b."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2))
    q = (a[0] + t * dx, a[1] + t * dy)
    return math.dist(p, q), q


def closest_on_line(p: XY, pts: Sequence[XY]) -> tuple[float, XY, int]:
    """(distance, nearest point, segment index) from p to the polyline pts."""
    if len(pts) == 1:
        return math.dist(p, pts[0]), pts[0], 0
    best = None
    for i in range(len(pts) - 1):
        d, q = closest_on_segment(p, pts[i], pts[i + 1])
        if best is None or d < best[0]:
            best = (d, q, i)
    assert best is not None, "empty polyline"
    return best


def inside(p: XY, ring: Sequence[XY]) -> bool:
    """Point in polygon (even-odd). `ring` may or may not repeat its first point."""
    hit = False
    n = len(ring)
    for i in range(n):
        (x1, y1), (x2, y2) = ring[i], ring[(i + 1) % n]
        if (y1 > p[1]) != (y2 > p[1]) and p[0] < x1 + (p[1] - y1) * (x2 - x1) / (y2 - y1):
            hit = not hit
    return hit


def area(ring: Sequence[XY]) -> float:
    n = len(ring)
    return (
        abs(
            sum(
                ring[i][0] * ring[(i + 1) % n][1] - ring[(i + 1) % n][0] * ring[i][1]
                for i in range(n)
            )
        )
        / 2
    )


def segments_cross(p1: XY, p2: XY, q1: XY, q2: XY) -> bool:
    """True if segments p1-p2 and q1-q2 intersect or touch."""

    def orient(a: XY, b: XY, c: XY) -> int:
        v = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        return 0 if abs(v) < 1e-9 else (1 if v > 0 else -1)

    def on(a: XY, b: XY, c: XY) -> bool:
        return (
            min(a[0], b[0]) - 1e-9 <= c[0] <= max(a[0], b[0]) + 1e-9
            and min(a[1], b[1]) - 1e-9 <= c[1] <= max(a[1], b[1]) + 1e-9
        )

    o1, o2 = orient(p1, p2, q1), orient(p1, p2, q2)
    o3, o4 = orient(q1, q2, p1), orient(q1, q2, p2)
    if o1 != o2 and o3 != o4:
        return True
    return any(
        o == 0 and on(a, b, c)
        for o, a, b, c in ((o1, p1, p2, q1), (o2, p1, p2, q2), (o3, q1, q2, p1), (o4, q1, q2, p2))
    )


def line_crosses(a: XY, b: XY, pts: Sequence[XY]) -> bool:
    """True if segment a-b crosses or touches the polyline pts."""
    return any(segments_cross(a, b, pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def door_side_of_road(road_dir: tuple[float, float], road_to_door: tuple[float, float]) -> str:
    """Which side of the road the door is on, relative to the centerline's direction.

    `road_dir` is the centerline direction (first -> last point) and `road_to_door` the vector
    from the nearest centerline point to the door, both in local (east, north) meters.
    cross = road_dir.east * road_to_door.north - road_dir.north * road_to_door.east
    negative -> "right", positive -> "left".
    Example: road running east (1, 0), door 15 m south (0, -15) -> "right".
    The phone never does this with the car's GPS position: it only compares the car's course
    with the road direction (see the app's Geo.sameSide).
    """
    cross = road_dir[0] * road_to_door[1] - road_dir[1] * road_to_door[0]
    if cross == 0:
        raise ValueError("the door is on the centerline, or the road has no direction")
    return "right" if cross < 0 else "left"


def photo_ray_bearing(compass_angle: float, x_px: float, width_px: float, fov_deg: float) -> float:
    """Bearing from a street photo's camera to a detected door, 0..360. Pinhole model.

    offset = atan((2 * x_px / width_px - 1) * tan(fov_deg / 2))
    bearing = compass_angle + offset
    Take fov from Mapillary `camera_parameters` (normalized focal length) for perspective
    images; spherical images need separate handling.
    Examples: photo_ray_bearing(90, 700, 1000, 60) ~= 103.0
              photo_ray_bearing(30, 350, 1000, 60) ~= 20.2
    TODO (CV-5)
    """
    raise NotImplementedError("CV-5")


def ray_hits_outline(origin, bearing_deg, outline):
    """Where a ray from `origin` (east, north) at `bearing_deg` first hits the building outline.

    Use shapely: build a long LineString along the bearing and intersect it with the outline's
    exterior; return the closest hit. Examples (wall at x = 20):
      origin (0, 0), bearing 103.0 -> about (20, -4.6)
      origin (10, -30), bearing 20.2 -> about (20, -2.8)
    Later (offline batch only): triangulate rays with each other before snapping to the wall,
    and cluster with DBSCAN eps ~= 4 m.
    TODO (CV-5)
    """
    raise NotImplementedError("CV-5")
