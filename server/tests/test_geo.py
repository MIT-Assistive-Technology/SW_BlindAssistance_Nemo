"""Worked examples from docs/car-to-curb-plan.md. Remove skip markers as each TODO is done."""

import pytest

from app.geo import (
    Frame,
    closest_on_line,
    door_side_of_road,
    inside,
    line_crosses,
    photo_ray_bearing,
    ray_hits_outline,
)


def test_door_side_of_road():
    assert door_side_of_road((1, 0), (0, -15)) == "right"  # road east, door south
    assert door_side_of_road((1, 0), (0, 15)) == "left"
    assert door_side_of_road((0, -1), (-10, 0)) == "right"  # road south, door west (contract)


def test_door_on_the_centerline_is_an_error():
    with pytest.raises(ValueError):
        door_side_of_road((1, 0), (5, 0))


def test_frame_round_trip_and_scale():
    f = Frame(42.36, -71.09)
    x, y = f.xy(-71.089, 42.361)
    assert x == pytest.approx(82.3, abs=0.2)  # 0.001 deg lon at 42.36 N
    assert y == pytest.approx(111.2, abs=0.2)
    assert f.lonlat(x, y) == pytest.approx((-71.089, 42.361))


def test_inside_and_nearest_point():
    square = [(0, 0), (10, 0), (10, 10), (0, 10)]
    assert inside((5, 5), square)
    assert not inside((15, 5), square)
    d, q, i = closest_on_line((5, -3), square + [square[0]])
    assert (d, q, i) == (3, (5, 0), 0)


def test_line_crosses():
    road = [(-10, 5), (10, 5)]
    assert line_crosses((0, 0), (0, 10), road)
    assert not line_crosses((0, 0), (0, 4), road)


@pytest.mark.skip(reason="TODO CV-5")
def test_photo_ray_bearing_pinhole():
    assert photo_ray_bearing(90, 700, 1000, 60) == pytest.approx(103.0, abs=0.1)
    assert photo_ray_bearing(30, 350, 1000, 60) == pytest.approx(20.2, abs=0.1)
    assert photo_ray_bearing(90, 500, 1000, 60) == pytest.approx(90.0)  # center pixel


@pytest.mark.skip(reason="TODO CV-5")
def test_ray_hits_wall():
    from shapely.geometry import Polygon

    building = Polygon([(20, -20), (40, -20), (40, 20), (20, 20)])  # front wall at x = 20
    a = ray_hits_outline((0, 0), 103.0, building)
    b = ray_hits_outline((10, -30), 20.2, building)
    assert a == pytest.approx((20, -4.6), abs=0.1)
    assert b == pytest.approx((20, -2.8), abs=0.1)
