"""Geodesy helpers. Coordinates are (lat, lon) in degrees, distances in metres."""

from __future__ import annotations

import math
from collections.abc import Sequence

EARTH_RADIUS_M = 6_371_008.8

LatLon = tuple[float, float]


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(min(1.0, a)))


def bearing_deg(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Initial bearing from point 1 to point 2, clockwise from north, in [0, 360)."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return math.degrees(math.atan2(y, x)) % 360.0


def polyline_length_m(points: Sequence[LatLon]) -> float:
    return sum(haversine_m(*a, *b) for a, b in zip(points, points[1:], strict=False))


def point_along(points: Sequence[LatLon], distance_m: float) -> tuple[LatLon, int]:
    """Point at `distance_m` from the start of the polyline.

    Returns the point and the index of the segment it lies on. Distances outside the
    polyline are clamped to its ends.
    """
    if not points:
        raise ValueError("empty polyline")
    if distance_m <= 0 or len(points) == 1:
        return points[0], 0
    remaining = distance_m
    for i in range(len(points) - 1):
        a, b = points[i], points[i + 1]
        seg = haversine_m(*a, *b)
        if remaining <= seg:
            t = remaining / seg if seg > 0 else 0.0
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), i
        remaining -= seg
    return points[-1], len(points) - 2


def turn_angle_deg(bearing_in: float, bearing_out: float) -> float:
    """Signed turn in (-180, 180]: positive = right, negative = left."""
    diff = (bearing_out - bearing_in) % 360.0
    return diff - 360.0 if diff > 180.0 else diff
