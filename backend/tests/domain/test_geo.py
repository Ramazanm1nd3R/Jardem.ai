import math

import pytest

from app.domain.geo import (
    bearing_deg,
    haversine_m,
    point_along,
    polyline_length_m,
    turn_angle_deg,
)


def test_haversine_known_distance():
    # One degree of latitude is ~111.2 km everywhere.
    assert haversine_m(43.0, 76.9, 44.0, 76.9) == pytest.approx(111_195, rel=1e-3)
    # One degree of longitude shrinks with cos(latitude).
    assert haversine_m(43.0, 76.0, 43.0, 77.0) == pytest.approx(
        111_195 * math.cos(math.radians(43.0)), rel=1e-3
    )


def test_haversine_zero_and_symmetric():
    assert haversine_m(43.2, 76.9, 43.2, 76.9) == 0.0
    assert haversine_m(43.2, 76.9, 43.3, 77.0) == pytest.approx(haversine_m(43.3, 77.0, 43.2, 76.9))


def test_haversine_antipodal_is_half_circumference():
    assert haversine_m(0, 0, 0, 180) == pytest.approx(math.pi * 6_371_008.8)


@pytest.mark.parametrize(
    ("target", "expected"),
    [((44.0, 76.9), 0.0), ((43.0, 77.9), 90.0), ((42.0, 76.9), 180.0), ((43.0, 75.9), 270.0)],
)
def test_bearing_cardinal(target, expected):
    assert bearing_deg(43.0, 76.9, *target) == pytest.approx(expected, abs=0.5)


def test_polyline_length_sums_segments():
    pts = [(43.0, 76.9), (43.01, 76.9), (43.01, 76.91)]
    expected = haversine_m(*pts[0], *pts[1]) + haversine_m(*pts[1], *pts[2])
    assert polyline_length_m(pts) == pytest.approx(expected)
    assert polyline_length_m(pts[:1]) == 0.0


def test_point_along_interpolates_within_segment():
    pts = [(43.0, 76.9), (43.01, 76.9), (43.01, 76.92)]
    first = haversine_m(*pts[0], *pts[1])
    p, seg = point_along(pts, first / 4)
    assert seg == 0
    assert p == pytest.approx((43.0025, 76.9))
    p, seg = point_along(pts, first + haversine_m(*pts[1], *pts[2]) / 2)
    assert seg == 1
    assert p == pytest.approx((43.01, 76.91))


def test_point_along_exact_vertex_stays_on_earlier_segment():
    pts = [(43.0, 76.9), (43.01, 76.9), (43.01, 76.92)]
    p, seg = point_along(pts, haversine_m(*pts[0], *pts[1]))
    assert seg == 0
    assert p == pytest.approx(pts[1])


def test_point_along_clamps():
    pts = [(43.0, 76.9), (43.01, 76.9), (43.02, 76.9)]
    assert point_along(pts, -5) == (pts[0], 0)
    assert point_along(pts, 0) == (pts[0], 0)
    assert point_along(pts, 1e9) == (pts[-1], 1)
    assert point_along(pts[:1], 100) == (pts[0], 0)
    with pytest.raises(ValueError):
        point_along([], 1)


def test_point_along_zero_length_segment():
    pts = [(43.0, 76.9), (43.0, 76.9), (43.01, 76.9)]
    p, seg = point_along(pts, 0.0001)
    assert p[0] == pytest.approx(43.0, abs=1e-6)
    assert seg == 1


@pytest.mark.parametrize(
    ("b_in", "b_out", "expected"),
    [(0, 90, 90), (90, 0, -90), (350, 10, 20), (10, 350, -20), (0, 180, 180), (0, 181, -179),
     (45, 45, 0)],
)
def test_turn_angle(b_in, b_out, expected):
    assert turn_angle_deg(b_in, b_out) == pytest.approx(expected)
