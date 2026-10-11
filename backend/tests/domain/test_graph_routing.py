import math
import random

import pytest

from app.domain.geo import haversine_m
from app.domain.graph import Edge, RoadGraph
from app.domain.routing import (
    INF,
    EdgeCosts,
    classify_turn,
    maneuvers,
    shortest_path,
    times_from,
    times_to,
)
from tests.domain.conftest import DLAT, DLON, LAT0, LON0, edge_between, make_grid


def test_graph_adjacency_and_twins(grid):
    assert len(grid.nodes) == 25
    assert len(grid.edges) == 2 * (5 * 4 + 5 * 4)
    assert sorted(grid.edges[i].v for i in grid.out[0]) == [1, 5]
    assert sorted(grid.edges[i].u for i in grid.inc[0]) == [1, 5]
    for e in grid.edges:
        twin = grid.edges[e.twin]
        assert (twin.u, twin.v, twin.twin) == (e.v, e.u, e.id)


def test_empty_graph_rejected():
    with pytest.raises(ValueError):
        RoadGraph([], [])


def test_edge_free_time_and_midpoint(grid):
    e = edge_between(grid, 0, 1)
    assert e.free_time_s == pytest.approx(e.length_m / (50 / 3.6))
    assert e.midpoint == pytest.approx((LAT0, LON0 + DLON / 2))
    bent = Edge(0, 0, 1, 10, 3, 50, "", ((0.0, 0.0), (1.0, 1.0), (2.0, 0.0)), -1)
    assert bent.midpoint == (1.0, 1.0)
    four = Edge(0, 0, 1, 10, 3, 50, "", ((0.0, 0.0), (1.0, 0.0), (3.0, 0.0), (4.0, 0.0)), -1)
    assert four.midpoint == (2.0, 0.0)


def test_nearest_node_matches_brute_force(grid):
    rng = random.Random(7)
    for _ in range(200):
        lat = LAT0 + rng.uniform(-2, 6) * DLAT
        lon = LON0 + rng.uniform(-2, 6) * DLON
        brute = min(range(len(grid.nodes)), key=lambda i: haversine_m(lat, lon, *grid.nodes[i]))
        got = grid.nearest_node(lat, lon)
        assert haversine_m(lat, lon, *grid.nodes[got]) == pytest.approx(
            haversine_m(lat, lon, *grid.nodes[brute])
        )


def test_nearest_node_far_outside(grid):
    assert grid.nearest_node(LAT0 - 0.3, LON0 - 0.3) == 0
    assert grid.nearest_node(LAT0 + 0.3, LON0 + 0.3) == 24


@pytest.mark.slow
def test_nearest_node_real_graph(almaty):
    rng = random.Random(3)
    for _ in range(25):
        lat, lon = rng.uniform(43.17, 43.35), rng.uniform(76.78, 77.02)
        brute = min(almaty.nodes, key=lambda p: haversine_m(lat, lon, *p))
        got = almaty.nodes[almaty.nearest_node(lat, lon)]
        assert haversine_m(lat, lon, *got) == pytest.approx(haversine_m(lat, lon, *brute))


def test_heuristic_never_overestimates(grid):
    for a in range(0, 25, 3):
        for b in range(0, 25, 4):
            assert grid.heuristic_m(a, b) <= haversine_m(*grid.nodes[a], *grid.nodes[b]) + 1e-6
    assert grid.heuristic_m(0, 24) > 0.99 * haversine_m(*grid.nodes[0], *grid.nodes[24])


def test_edges_near(grid):
    e = edge_between(grid, 0, 1)
    near = grid.edges_near(*e.midpoint, 5)
    assert sorted(near) == sorted([e.id, e.twin])
    assert sorted(grid.edges_near(*e.midpoint, 0)) == sorted([e.id, e.twin])
    far = haversine_m(*e.midpoint, *edge_between(grid, 1, 2).midpoint)
    assert edge_between(grid, 1, 2).id in grid.edges_near(*e.midpoint, far)
    assert edge_between(grid, 1, 2).id not in grid.edges_near(*e.midpoint, far - 1)
    assert grid.edges_near(10.0, 10.0, 100) == []


def test_from_dict_expands_bidirectional_edges():
    data = {
        "nodes": [[43.0, 76.0], [43.0, 76.01], [43.01, 76.01]],
        "names": ["", "Абая"],
        "edges": [
            [0, 1, 800.0, 2, 60, 1, 1, [43.001, 76.005]],
            [1, 2, 1100.0, 4, 40, 0, 0, []],
        ],
    }
    g = RoadGraph.from_dict(data)
    assert len(g.edges) == 3
    fwd, back, oneway = g.edges
    assert (fwd.u, fwd.v, fwd.twin, fwd.name, fwd.speed_kph) == (0, 1, 1, "Абая", 60.0)
    assert fwd.shape == ((43.0, 76.0), (43.001, 76.005), (43.0, 76.01))
    assert (back.u, back.v, back.twin) == (1, 0, 0)
    assert back.shape == fwd.shape[::-1]
    assert (oneway.id, oneway.twin, oneway.road_class, oneway.length_m) == (2, -1, 4, 1100.0)
    assert g.out[1] == [1, 2]
    assert g.out[2] == []


# --- routing ---------------------------------------------------------------


def test_edge_costs_validation(grid):
    with pytest.raises(ValueError):
        EdgeCosts.build(grid, [1.0])
    bad = [e.free_time_s for e in grid.edges]
    bad[3] = 0.0
    with pytest.raises(ValueError):
        EdgeCosts.build(grid, bad)
    costs = EdgeCosts.free_flow(grid)
    assert costs.max_speed_mps == pytest.approx(50 / 3.6)
    assert costs.version == 0


def test_max_speed_ignores_closed_edges(grid):
    times = [e.free_time_s for e in grid.edges]
    times[0] = INF
    times[1] = times[1] / 2
    assert EdgeCosts.build(grid, times, 5).max_speed_mps == pytest.approx(2 * 50 / 3.6)
    assert EdgeCosts.build(grid, times, 5).version == 5


def test_route_to_self(grid):
    r = shortest_path(grid, EdgeCosts.free_flow(grid), 7, 7)
    assert (r.nodes, r.edges, r.distance_m, r.duration_s) == ((7,), (), 0.0, 0.0)
    assert r.geometry == (grid.nodes[7],)


def test_straight_route(grid):
    costs = EdgeCosts.free_flow(grid)
    r = shortest_path(grid, costs, 0, 4)
    assert r.nodes == (0, 1, 2, 3, 4)
    assert r.distance_m == pytest.approx(4 * haversine_m(*grid.nodes[0], *grid.nodes[1]))
    assert r.duration_s == pytest.approx(r.distance_m / (50 / 3.6))
    assert r.geometry == tuple(grid.nodes[i] for i in range(5))
    assert [grid.edges[e].u for e in r.edges] == [0, 1, 2, 3]


def test_route_avoids_slow_edge(grid):
    times = [e.free_time_s for e in grid.edges]
    times[edge_between(grid, 1, 2).id] *= 50
    r = shortest_path(grid, EdgeCosts.build(grid, times), 0, 4)
    assert (1, 2) not in list(zip(r.nodes, r.nodes[1:], strict=False))
    assert r.nodes[0] == 0 and r.nodes[-1] == 4
    assert r.duration_s == pytest.approx(sum(times[e] for e in r.edges))


def test_route_avoids_closed_edge_and_handles_unreachable(grid):
    times = [e.free_time_s for e in grid.edges]
    for i in grid.inc[24]:
        times[i] = INF
    costs = EdgeCosts.build(grid, times)
    assert shortest_path(grid, costs, 0, 24) is None
    assert times_to(grid, costs, 24)[0] == INF
    assert times_from(grid, costs, 0)[24] == INF
    assert shortest_path(grid, costs, 24, 0) is not None
    assert times_from(grid, costs, 24)[0] < INF


def test_all_closed_graph(grid):
    costs = EdgeCosts.build(grid, [INF] * len(grid.edges))
    assert costs.max_speed_mps == 0
    assert shortest_path(grid, costs, 0, 1) is None


def test_astar_agrees_with_dijkstra_under_random_traffic():
    rng = random.Random(11)
    for trial in range(40):
        g = make_grid(6, 7)
        times = []
        for e in g.edges:
            roll = rng.random()
            times.append(INF if roll < 0.08 else e.free_time_s * rng.uniform(0.6, 6.0))
        costs = EdgeCosts.build(g, times, trial)
        src, dst = rng.randrange(42), rng.randrange(42)
        forward = times_from(g, costs, src)
        backward = times_to(g, costs, dst)
        r = shortest_path(g, costs, src, dst)
        assert forward[dst] == pytest.approx(backward[src])
        if forward[dst] == INF:
            assert r is None
            continue
        assert r.duration_s == pytest.approx(forward[dst])
        assert r.nodes[0] == src and r.nodes[-1] == dst
        assert sum(times[e] for e in r.edges) == pytest.approx(r.duration_s)
        assert sum(g.edges[e].length_m for e in r.edges) == pytest.approx(r.distance_m)
        for a, b in zip(r.edges, r.edges[1:], strict=False):
            assert g.edges[a].v == g.edges[b].u


def test_one_way_respected():
    nodes = [(43.0, 76.0), (43.0, 76.01), (43.0, 76.02)]
    edges = [
        Edge(0, 0, 1, 800, 3, 50, "a", (nodes[0], nodes[1]), -1),
        Edge(1, 1, 2, 800, 3, 50, "b", (nodes[1], nodes[2]), -1),
        Edge(2, 2, 0, 5000, 3, 50, "c", (nodes[2], nodes[0]), -1),
    ]
    g = RoadGraph(nodes, edges)
    costs = EdgeCosts.free_flow(g)
    assert shortest_path(g, costs, 0, 2).edges == (0, 1)
    back = shortest_path(g, costs, 2, 1)
    assert back.edges == (2, 0)
    assert times_to(g, costs, 1)[2] == pytest.approx(back.duration_s)
    assert times_from(g, costs, 2)[1] == pytest.approx(back.duration_s)
    assert times_to(g, costs, 2)[0] == pytest.approx(1600 / (50 / 3.6))


@pytest.mark.slow
def test_real_graph_route_sanity(almaty):
    costs = EdgeCosts.free_flow(almaty)
    src = almaty.nearest_node(43.2380, 76.9450)  # Republic Square area
    dst = almaty.nearest_node(43.3400, 76.9500)  # northern districts
    r = shortest_path(almaty, costs, src, dst)
    crow = haversine_m(*almaty.nodes[src], *almaty.nodes[dst])
    assert crow <= r.distance_m <= 2.0 * crow
    assert r.duration_s == pytest.approx(times_to(almaty, costs, dst)[src])
    assert r.duration_s == pytest.approx(times_from(almaty, costs, src)[dst])
    reachable = sum(1 for t in times_from(almaty, costs, src) if t < math.inf)
    assert reachable == len(almaty.nodes)


@pytest.mark.parametrize(
    ("angle", "kind"),
    [(0, None), (24.9, None), (-24.9, None), (25, "slight_right"), (-25, "slight_left"),
     (59.9, "slight_right"), (60, "right"), (-60, "left"), (90, "right"), (-90, "left"),
     (159.9, "right"), (160, "uturn"), (-160, "uturn"), (180, "uturn")],
)
def test_classify_turn(angle, kind):
    assert classify_turn(angle) == kind


def test_maneuvers(grid):
    costs = EdgeCosts.free_flow(grid)
    assert maneuvers(grid, shortest_path(grid, costs, 3, 3)) == []
    times = [e.free_time_s * 10 for e in grid.edges]
    path = [0, 1, 2, 7, 12, 11]  # east, east, north, north, west
    for a, b in zip(path, path[1:], strict=False):
        times[edge_between(grid, a, b).id] = 1.0
    r = shortest_path(grid, EdgeCosts.build(grid, times), 0, 11)
    assert r.nodes == tuple(path)
    steps = maneuvers(grid, r)
    assert [m.kind for m in steps] == ["depart", "left", "left", "arrive"]
    block_ew = haversine_m(*grid.nodes[0], *grid.nodes[1])
    block_ns = haversine_m(*grid.nodes[2], *grid.nodes[7])
    assert steps[0].distance_m == 0.0 and steps[0].location == grid.nodes[0]
    assert steps[0].street == "street 0-1"
    assert steps[1].distance_m == pytest.approx(2 * block_ew)
    assert steps[1].location == grid.nodes[2] and steps[1].street == "street 2-7"
    assert steps[2].distance_m == pytest.approx(2 * block_ew + 2 * block_ns)
    assert steps[3].distance_m == pytest.approx(r.distance_m)
    assert steps[3].location == grid.nodes[11] and steps[3].street == "street 11-12"


def test_maneuver_right_turn(grid):
    times = [e.free_time_s * 10 for e in grid.edges]
    path = [10, 11, 6]  # east then south = right turn
    for a, b in zip(path, path[1:], strict=False):
        times[edge_between(grid, a, b).id] = 1.0
    r = shortest_path(grid, EdgeCosts.build(grid, times), 10, 6)
    assert [m.kind for m in maneuvers(grid, r)] == ["depart", "right", "arrive"]


def test_astar_heuristic_must_not_overestimate():
    # A slow direct road and a fast dog-leg that first heads away from the target. A search
    # that overestimates the remaining time settles for the direct road.
    nodes = [(43.0, 76.0), (43.0, 76.0123), (43.0045, 76.0)]
    direct = haversine_m(*nodes[0], *nodes[1])
    edges = [
        Edge(0, 0, 1, direct, 3, 50, "direct", (nodes[0], nodes[1]), -1),
        Edge(1, 0, 2, haversine_m(*nodes[0], *nodes[2]), 3, 50, "up", (nodes[0], nodes[2]), -1),
        Edge(2, 2, 1, haversine_m(*nodes[2], *nodes[1]), 3, 50, "across", (nodes[2], nodes[1]), -1),
    ]
    g = RoadGraph(nodes, edges)
    r = shortest_path(g, EdgeCosts.build(g, [100.0, 10.0, 20.0]), 0, 1)
    assert r.edges == (1, 2) and r.duration_s == 30.0


def test_slow_network_is_still_routable(grid):
    # Every road slower than 1 m/s: a crawl, not "no route".
    costs = EdgeCosts.build(grid, [e.length_m / 0.5 for e in grid.edges])
    assert costs.max_speed_mps == pytest.approx(0.5)
    r = shortest_path(grid, costs, 0, 1)
    assert r.nodes == (0, 1) and r.duration_s == pytest.approx(r.distance_m / 0.5)
