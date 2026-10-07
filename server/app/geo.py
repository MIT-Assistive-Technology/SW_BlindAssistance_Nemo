"""Geometry helpers (BE-5, BE-7, CV-5). Work in local meters; convert lat/lon with pyproj.

Worked examples: docs/car-to-curb-plan.md sections 6 (side of street) and 8 (street photos).
"""


def side_of(direction: tuple[float, float], to_point: tuple[float, float]) -> str:
    """Which side of a direction of travel a point lies on, in local (east, north) meters.

    cross = direction.east * to_point.north - direction.north * to_point.east
    negative -> "right", positive -> "left", near zero -> "unknown".
    Example: side_of((1, 0), (30, -10)) == "right".
    TODO (BE-5)
    """
    raise NotImplementedError("BE-5")


def photo_ray_bearing(compass_angle: float, x_px: float, width_px: float, fov_deg: float) -> float:
    """Bearing from a street photo's camera to a detected door, 0..360.

    bearing = compass_angle + (x_px / width_px - 0.5) * fov_deg
    Example: photo_ray_bearing(90, 700, 1000, 60) == 102.
    TODO (CV-5)
    """
    raise NotImplementedError("CV-5")


def ray_hits_outline(origin, bearing_deg, outline):
    """Where a ray from `origin` (east, north) at `bearing_deg` first hits the building outline.

    Use shapely: build a long LineString along the bearing and intersect it with the outline's
    exterior. Example: origin (0, 0), bearing 102°, wall x = 20 -> about (20, -4.3).
    TODO (CV-5)
    """
    raise NotImplementedError("CV-5")
