"""Expected behavior for app/scoring.py. Remove the skip marker when BE-4 is implemented."""

import pytest

from app.scoring import band, combine, score_door

todo = pytest.mark.skip(reason="TODO BE-4: implement score_door and combine")


@todo
def test_main_entrance():
    assert score_door({"entrance": "main"}, None, on_outline=True, has_footway=False) == 0.90


@todo
def test_excluded_values_are_never_used():
    for value in ["exit", "emergency", "garage", "no"]:
        assert score_door({"entrance": value}, None, True, False) is None


@todo
def test_private_access_is_excluded():
    assert score_door({"entrance": "yes", "access": "private"}, None, True, False) is None


@todo
def test_address_on_the_door_wins():
    tags = {"entrance": "yes", "addr:housenumber": "77"}
    assert score_door(tags, "77", True, False) == 1.0


@todo
def test_combined_value_uses_best_part():
    assert score_door({"entrance": "main;garage"}, None, True, False) == 0.90


@todo
def test_adjustments_and_cap():
    tags = {"entrance": "main", "wheelchair": "yes"}
    assert score_door(tags, None, on_outline=True, has_footway=True) == 0.95  # 1.00 capped


@todo
def test_combine_agreeing_sources():
    assert combine([0.90, 0.65]) == 0.95  # 0.965 capped
    assert combine([0.45, 0.45]) == pytest.approx(0.6975)


def test_bands():
    assert band(0.92) == "found"
    assert band(0.65) == "likely"
    assert band(0.30) == "facade"
