"""Geometry helpers (BE-5, BE-7, CV-5). Work in local meters; convert lat/lon with pyproj.

Worked examples: docs/car-to-curb-plan.md sections 6 (side of street) and 8 (street photos).
"""


def door_side_of_road(road_dir: tuple[float, float], road_to_door: tuple[float, float]) -> str:
    """Which side of the road the door is on, relative to the centerline's direction.

    `road_dir` is the centerline direction (first -> last point) and `road_to_door` the vector
    from the nearest centerline point to the door, both in local (east, north) meters.
    cross = road_dir.east * road_to_door.north - road_dir.north * road_to_door.east
    negative -> "right", positive -> "left".
    Example: road running east (1, 0), door 15 m south (0, -15) -> "right".
    The phone never does this with the car's GPS position: it only compares the car's course
    with the road direction (see the app's Geo.sameSide).
    TODO (BE-5)
    """
    raise NotImplementedError("BE-5")


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
