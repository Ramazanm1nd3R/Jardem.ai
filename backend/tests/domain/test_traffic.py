import math

import pytest

from app.domain.graph import ARTERIAL_MAX_CLASS
from app.domain.routing import INF, shortest_path
from app.domain.traffic import (
    EMERGENCY_CONGESTION_SHARE,
    EMERGENCY_SPEED_BOOST,
    MIN_FACTOR,
    PEAK_LOSS_BY_CLASS,
    PROBE_TTL_S,
    SNAPSHOT_BUCKET_S,
    Congestion,
    Hotspot,
    TrafficModel,
    congestion_level,
    edge_susceptibility,
    emergency_factor,
    rush_intensity,
    time_of_day_factor,
)
from tests.domain.conftest import edge_between, make_grid

# 03:00 local (UTC+5) — effectively free flow; and 08:30 local — morning peak.
NIGHT = (3 - 5) % 24 * 3600.0
PEAK = 3.5 * 3600.0


@pytest.mark.parametrize(
    ("factor", "level"),
    [(1.0, Congestion.FREE), (0.75, Congestion.FREE), (0.749, Congestion.SLOW),
     (0.5, Congestion.SLOW), (0.499, Congestion.JAM), (0.25, Congestion.JAM),
     (0.249, Congestion.HEAVY), (0.01, Congestion.HEAVY), (0.0, Congestion.CLOSED),
     (-1.0, Congestion.CLOSED)],
)
def test_congestion_level(factor, level):
    assert congestion_level(factor) is level


def test_rush_intensity_profile():
    assert rush_intensity(8.5) == pytest.approx(1.0)
    assert rush_intensity(18.5) == pytest.approx(1.0)
    assert rush_intensity(13.0) == pytest.approx(0.35, abs=0.01)
    assert rush_intensity(3.0) < 0.01
    assert rush_intensity(7.5) == pytest.approx(math.exp(-((1 / 1.2) ** 2)))
    assert rush_intensity(20.1) == pytest.approx(math.exp(-1.0))
    # Wraps around midnight instead of treating 23:59 and 00:01 as a day apart.
    assert rush_intensity(23.9) == pytest.approx(rush_intensity(-0.1))
    assert rush_intensity(0.5) == pytest.approx(rush_intensity(24.5))
    assert all(0.0 <= rush_intensity(h / 4) <= 1.0 for h in range(96))


def test_time_of_day_factor_by_class():
    assert time_of_day_factor(2, 8.5) == pytest.approx(1 - PEAK_LOSS_BY_CLASS[2])
    assert time_of_day_factor(6, 8.5) == pytest.approx(0.88)
    assert time_of_day_factor(2, 3.0) > 0.99
    assert time_of_day_factor(2, 8.5) < time_of_day_factor(4, 8.5) < time_of_day_factor(7, 8.5)


def test_emergency_factor():
    assert emergency_factor(0.0) == 0.0
    assert emergency_factor(-0.5) == 0.0
    assert emergency_factor(1.0) == pytest.approx(EMERGENCY_SPEED_BOOST)
    assert emergency_factor(0.2) == pytest.approx(
        (1 - 0.8 * EMERGENCY_CONGESTION_SHARE) * EMERGENCY_SPEED_BOOST
    )
    # Always at least as fast as ordinary traffic, and monotone in the general factor.
    samples = [i / 20 for i in range(1, 21)]
    assert all(emergency_factor(f) > f for f in samples)
    assert all(emergency_factor(a) < emergency_factor(b) for a, b in zip(samples, samples[1:]))


def test_edge_susceptibility_is_deterministic_and_bounded():
    values = [edge_susceptibility(i, 0) for i in range(2000)]
    assert values == [edge_susceptibility(i, 0) for i in range(2000)]
    assert min(values) >= 0.6 and max(values) <= 1.0
    assert max(values) - min(values) > 0.35
    assert values != [edge_susceptibility(i, 1) for i in range(2000)]
    assert 0.75 < sum(values) / len(values) < 0.85


def test_hotspot_loss_falloff():
    h = Hotspot("h", 43.0, 76.0, 400.0, 0.8, 1e12)
    assert h.loss_at(0) == pytest.approx(0.8)
    assert h.loss_at(100) == pytest.approx(0.6)
    assert h.loss_at(399.9) > 0
    assert h.loss_at(400) == 0.0
    assert h.loss_at(900) == 0.0


def test_free_flow_at_night(grid):
    model = TrafficModel(grid)
    snap = model.snapshot(NIGHT)
    assert all(f > 0.99 for f in snap.factors)
    assert model.segments(NIGHT) == []
    assert model.city_index(NIGHT) == 0
    assert model.local_hour(NIGHT) == pytest.approx(3.0)
    assert model.local_hour(0.0) == pytest.approx(5.0)
    assert TrafficModel(grid, utc_offset_h=0).local_hour(25 * 3600) == pytest.approx(1.0)


def test_rush_hour_slows_arterials_more_than_side_streets():
    arterial = TrafficModel(make_grid(4, 4, road_class=2), seed=1)
    side = TrafficModel(make_grid(4, 4, road_class=6), seed=1)
    a = arterial.snapshot(PEAK).factors
    s = side.snapshot(PEAK).factors
    assert max(a) < min(s)
    for i, f in enumerate(a):
        assert f == pytest.approx(1 - 0.6 * edge_susceptibility(i, 1))
    assert arterial.city_index(PEAK) >= 5
    assert side.city_index(PEAK) == 0  # no arterials at all
    assert arterial.city_index(PEAK) == min(10, round(10 * (1 - sum(a) / len(a)) / 0.7))


def test_snapshot_cached_within_bucket_and_revision(grid):
    model = TrafficModel(grid)
    first = model.snapshot(NIGHT)
    assert model.snapshot(NIGHT + SNAPSHOT_BUCKET_S - 1) is first
    later = model.snapshot(NIGHT + SNAPSHOT_BUCKET_S)
    assert later is not first and later.version == first.version + 1
    model.add_hotspot(Hotspot("h", *grid.nodes[12], 150.0, 0.5, 1e12))
    changed = model.snapshot(NIGHT + SNAPSHOT_BUCKET_S)
    assert changed.version == later.version + 1
    assert model.edge_costs(NIGHT) is model.edge_costs(NIGHT)
    assert model.edge_costs(NIGHT).version != model.edge_costs(NIGHT, "car").version


def test_hotspot_applies_and_expires(grid):
    model = TrafficModel(grid)
    e = edge_between(grid, 12, 13)
    far = edge_between(grid, 0, 1)
    model.add_hotspot(Hotspot("jam", *e.midpoint, 300.0, 0.8, expires_at=NIGHT + 600))
    snap = model.snapshot(NIGHT)
    assert snap.factors[e.id] == pytest.approx(0.2, abs=0.01)
    assert snap.factors[e.twin] == pytest.approx(0.2, abs=0.01)
    assert snap.factors[far.id] > 0.99
    assert [h.id for h in model.hotspots] == ["jam"]
    assert model.expire(NIGHT + 599) is False
    assert model.expire(NIGHT + 600) is True
    assert model.hotspots == []
    assert model.snapshot(NIGHT).factors[e.id] > 0.99
    assert model.remove_hotspot("jam") is False


def test_overlapping_hotspots_multiply_and_clamp(grid):
    model = TrafficModel(grid)
    e = edge_between(grid, 12, 13)
    model.add_hotspot(Hotspot("a", *e.midpoint, 300.0, 0.5, 1e12))
    model.add_hotspot(Hotspot("b", *e.midpoint, 300.0, 0.5, 1e12))
    assert model.snapshot(NIGHT).factors[e.id] == pytest.approx(0.25, abs=0.01)
    model.add_hotspot(Hotspot("c", *e.midpoint, 300.0, 1.0, 1e12))
    assert model.snapshot(NIGHT).factors[e.id] == MIN_FACTOR
    assert model.remove_hotspot("c") is True
    assert model.snapshot(NIGHT).factors[e.id] == pytest.approx(0.25, abs=0.01)


@pytest.mark.parametrize("bad", [dict(severity=0.0), dict(severity=1.01), dict(radius_m=0.0)])
def test_invalid_hotspot_rejected(grid, bad):
    args = dict(id="x", lat=43.24, lon=76.9, radius_m=100.0, severity=0.5, expires_at=1e12)
    args.update(bad)
    model = TrafficModel(grid)
    with pytest.raises(ValueError):
        model.add_hotspot(Hotspot(**args))
    assert model.hotspots == []


def test_closure_blocks_both_directions_and_reroutes(grid):
    model = TrafficModel(grid)
    e = edge_between(grid, 1, 2)
    direct = shortest_path(grid, model.edge_costs(NIGHT), 0, 4)
    assert direct.nodes == (0, 1, 2, 3, 4)
    closure = model.close_road("c1", *e.midpoint, 10.0, expires_at=NIGHT + 100, reason="ДТП")
    assert closure.edge_ids == frozenset({e.id, e.twin})
    assert closure.reason == "ДТП"
    costs = model.edge_costs(NIGHT)
    assert costs.times[e.id] == INF and costs.times[e.twin] == INF
    detour = shortest_path(grid, costs, 0, 4)
    assert e.id not in detour.edges and detour.duration_s > direct.duration_s
    seg = [s for s in model.segments(NIGHT) if s["level"] == "closed"]
    assert len(seg) == 1 and seg[0]["factor"] == 0 and seg[0]["speed_kph"] == 0
    assert [c.id for c in model.closures] == ["c1"]
    assert model.expire(NIGHT + 100) is True
    assert model.closures == []
    assert model.edge_costs(NIGHT).times[e.id] < INF
    assert model.reopen_road("c1") is False


def test_closure_falls_back_to_nearest_edge(grid):
    model = TrafficModel(grid)
    e = edge_between(grid, 0, 1)
    lat, lon = e.midpoint
    closure = model.close_road("c", lat - 0.0002, lon, 1.0, 1e12)
    assert closure.edge_ids == frozenset({e.id, e.twin})


def test_probe_overrides_model_and_decays(grid):
    model = TrafficModel(grid)
    e = edge_between(grid, 6, 7)
    free_speed = 50 / 3.6
    assert model.report_probe(e.id, free_speed * 0.3, NIGHT) == pytest.approx(0.3)
    assert model.snapshot(NIGHT).factors[e.id] == pytest.approx(0.3, abs=0.01)
    assert model.snapshot(NIGHT).factors[e.twin] > 0.99
    # A second fresh probe is averaged with the first.
    assert model.report_probe(e.id, free_speed * 0.7, NIGHT + 60) == pytest.approx(0.5)
    # Half-way to expiry the probe carries half the weight.
    half = model.snapshot(NIGHT + 60 + PROBE_TTL_S / 2).factors[e.id]
    assert half == pytest.approx(0.75, abs=0.01)
    assert model.expire(NIGHT + 60 + PROBE_TTL_S) is False
    assert model.expire(NIGHT + 61 + PROBE_TTL_S) is True
    assert model.snapshot(NIGHT).factors[e.id] > 0.99
    # A stale previous probe is not averaged in.
    model.report_probe(e.id, free_speed * 0.2, 0.0)
    assert model.report_probe(e.id, free_speed * 0.8, PROBE_TTL_S + 1) == pytest.approx(0.8)
    assert model.report_probe(e.id, free_speed * 0.8, 2 * PROBE_TTL_S + 1) == pytest.approx(0.8)


def test_probe_is_clamped(grid):
    model = TrafficModel(grid)
    assert model.report_probe(0, 0.0, NIGHT) == MIN_FACTOR
    assert model.report_probe(1, 999.0, NIGHT) == 1.0


def test_edge_costs_profiles(grid):
    model = TrafficModel(grid)
    e = edge_between(grid, 12, 13)
    model.add_hotspot(Hotspot("jam", *e.midpoint, 300.0, 0.8, 1e12))
    car = model.edge_costs(NIGHT, "car")
    emergency = model.edge_costs(NIGHT, "emergency")
    factor = model.snapshot(NIGHT).factors[e.id]
    assert car.times[e.id] == pytest.approx(e.free_time_s / factor)
    assert emergency.times[e.id] == pytest.approx(e.free_time_s / emergency_factor(factor))
    assert all(em < c for em, c in zip(emergency.times, car.times, strict=True))
    with pytest.raises(ValueError):
        model.edge_costs(NIGHT, "bicycle")


def test_segments_report_each_road_once_with_worst_direction(grid):
    model = TrafficModel(grid)
    e = edge_between(grid, 6, 7)
    model.report_probe(e.id, 50 / 3.6 * 0.4, NIGHT)
    segs = model.segments(NIGHT)
    assert len(segs) == 1
    s = segs[0]
    assert s["edge_id"] == min(e.id, e.twin)
    assert (s["level"], s["factor"], s["speed_kph"]) == ("jam", 0.4, 20.0)
    assert s["name"] == e.name
    lat, lon = grid.nodes[6]
    assert [round(lon, 5), round(lat, 5)] in s["geometry"] and len(s["geometry"]) == 2
    inside = (lat - 0.001, lon - 0.001, lat + 0.001, lon + 0.004)
    assert len(model.segments(NIGHT, bbox=inside)) == 1
    assert model.segments(NIGHT, bbox=(0.0, 0.0, 1.0, 1.0)) == []
    assert model.segments(NIGHT, bbox=(lat - 0.001, lon + 0.002, lat + 0.001, lon + 0.004)) == []
    everything = model.segments(NIGHT, include_free=True)
    assert len(everything) == len(grid.edges) // 2
    assert sum(1 for x in everything if x["level"] == "free") == len(everything) - 1


def test_segments_hide_side_streets_unless_closed():
    g = make_grid(3, 3, road_class=ARTERIAL_MAX_CLASS + 2)
    model = TrafficModel(g)
    e = edge_between(g, 0, 1)
    model.report_probe(e.id, 1.0, NIGHT)
    assert model.segments(NIGHT) == []
    assert model.segments(NIGHT, include_free=True) == []
    model.close_road("c", *e.midpoint, 5.0, 1e12)
    assert [s["level"] for s in model.segments(NIGHT)] == ["closed"]
    collector = TrafficModel(make_grid(3, 3, road_class=ARTERIAL_MAX_CLASS + 1))
    collector.report_probe(0, 1.0, NIGHT)
    assert len(collector.segments(NIGHT)) == 1
    assert len(collector.segments(NIGHT, include_free=True)) == 1
