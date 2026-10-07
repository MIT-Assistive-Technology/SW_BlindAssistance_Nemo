"""Worked examples from docs/car-to-curb-plan.md. Remove skip markers as each TODO is done."""

import pytest

from app.geo import door_side_of_road, photo_ray_bearing, ray_hits_outline


@pytest.mark.skip(reason="TODO BE-5")
def test_door_side_of_road():
    assert door_side_of_road((1, 0), (0, -15)) == "right"  # road east, door south
    assert door_side_of_road((1, 0), (0, 15)) == "left"
    assert door_side_of_road((0, -1), (-10, 0)) == "right"  # road south, door west (contract)


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
