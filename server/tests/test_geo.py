"""Worked examples from docs/car-to-curb-plan.md. Remove skip markers as each TODO is done."""

import pytest

from app.geo import photo_ray_bearing, ray_hits_outline, side_of


@pytest.mark.skip(reason="TODO BE-5")
def test_side_of_street():
    assert side_of((1, 0), (30, -10)) == "right"  # same side as the US curb
    assert side_of((1, 0), (30, 20)) == "left"  # across the street


@pytest.mark.skip(reason="TODO CV-5")
def test_photo_ray_bearing():
    assert photo_ray_bearing(90, 700, 1000, 60) == pytest.approx(102)
    assert photo_ray_bearing(30, 350, 1000, 60) == pytest.approx(21)


@pytest.mark.skip(reason="TODO CV-5")
def test_ray_hits_wall():
    from shapely.geometry import Polygon

    building = Polygon([(20, -20), (40, -20), (40, 20), (20, 20)])  # front wall at x = 20
    a = ray_hits_outline((0, 0), 102, building)
    b = ray_hits_outline((10, -30), 21, building)
    assert a == pytest.approx((20, -4.3), abs=0.1)
    assert b == pytest.approx((20, -3.9), abs=0.1)
