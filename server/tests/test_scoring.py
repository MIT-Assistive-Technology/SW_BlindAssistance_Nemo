"""Expected behavior for app/scoring.py (docs/car-to-curb-plan.md sections 8-9)."""

import pytest

from app.scoring import CAP, band, combine, score_door


def test_main_entrance():
    assert score_door({"entrance": "main"}, None, on_outline=True, has_footway=False) == 0.90


def test_excluded_values_are_never_used():
    for value in ["exit", "emergency", "garage", "no", "garage;exit", "loading_dock"]:
        assert score_door({"entrance": value}, None, True, False) is None


def test_private_access_is_excluded():
    assert score_door({"entrance": "yes", "access": "private"}, None, True, False) is None
    assert score_door({"entrance": "yes", "foot": "no"}, None, True, False) is None


def test_ignored_features_are_not_doors():
    for tags in [
        {"entrance": "yes", "railway": "subway_entrance"},
        {"door": "yes", "indoor": "door"},
        {"barrier": "gate", "entrance": "yes"},
        {"entrance": "yes", "amenity": "loading_dock", "access": "permit"},  # E2E I-7
    ]:
        assert score_door(tags, None, True, False) is None


def test_address_on_the_door_ranks_first_but_is_capped():
    tags = {"entrance": "yes", "addr:housenumber": "77"}
    assert score_door(tags, "77", True, False) == CAP


def test_combined_value_uses_best_part():
    assert score_door({"entrance": "main;garage"}, None, True, False) == 0.90


def test_door_only_node_counts_as_entrance_yes():
    assert score_door({"door": "hinged"}, None, True, False) == 0.75


def test_unknown_value_and_non_destination_shop():
    assert score_door({"entrance": "something_new"}, None, True, False) == 0.50
    assert score_door({"entrance": "shop"}, None, True, False) == 0.50


def test_staircase_counts_only_for_residential_addresses():
    assert score_door({"entrance": "staircase"}, None, True, False) == 0.50
    assert score_door({"entrance": "staircase"}, None, True, False, residential=True) == 0.85


def test_routing_and_site_entrances_count_as_main():
    assert score_door({"entrance": "yes", "routing:entrance": "main"}, None, True, False) == 0.90
    assert score_door({"entrance": "yes"}, None, True, False, site_entrance=True) == 0.90


def test_adjustments_and_cap():
    tags = {"entrance": "main", "wheelchair": "yes"}
    assert score_door(tags, None, on_outline=True, has_footway=True) == CAP  # 1.00 capped


def test_penalties():
    assert score_door({"entrance": "main", "wheelchair": "no"}, None, True, False) == 0.85
    assert score_door({"entrance": "main"}, None, on_outline=False, has_footway=False) == 0.80
    assert score_door({"entrance": "main", "level": "1"}, None, True, False) == 0.80
    assert score_door({"entrance": "yes", "door": "overhead"}, None, True, False) == 0.65


def test_adjustments_never_lift_a_plain_door_into_main():
    # E2E I-6: entrance=yes + wheelchair + footway was 0.85000...1 and spoken as "main".
    tags = {"entrance": "yes", "wheelchair": "yes"}
    score = score_door(tags, None, on_outline=True, has_footway=True)
    assert band(score) == "door"
    assert score == 0.80


def test_combine_is_best_plus_one_step():
    assert combine({"osm": 0.90, "photos": 0.65}) == CAP  # 0.90 + 0.05
    assert combine({"osm": 0.75, "photos": 0.65}) == pytest.approx(0.80)
    assert combine({"photos": 0.45}) == 0.45  # one class: no bump


def test_bands():
    assert band(0.95) == "main"
    assert band(0.65) == "door"
    assert band(0.30) == "facade"
