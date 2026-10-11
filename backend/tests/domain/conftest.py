from __future__ import annotations

import pytest

from app.domain.geo import haversine_m
from app.domain.graph import Edge, RoadGraph

LAT0, LON0 = 43.2400, 76.9000
DLAT, DLON = 0.0018, 0.0025  # ≈ 200 m × 200 m blocks


def make_grid(rows: int, cols: int, speed_kph: float = 50.0, road_class: int = 3,
              drop: set[tuple[int, int]] | None = None) -> RoadGraph:
    """Rectangular two-way street grid. `drop` removes undirected links (node, node)."""
    drop = drop or set()
    nodes = [(LAT0 + r * DLAT, LON0 + c * DLON) for r in range(rows) for c in range(cols)]
    edges: list[Edge] = []

    def link(a: int, b: int) -> None:
        if (a, b) in drop or (b, a) in drop:
            return
        length = haversine_m(*nodes[a], *nodes[b])
        i = len(edges)
        name = f"street {a}-{b}"
        edges.append(Edge(i, a, b, length, road_class, speed_kph, name, (nodes[a], nodes[b]), i + 1))
        edges.append(Edge(i + 1, b, a, length, road_class, speed_kph, name, (nodes[b], nodes[a]), i))

    for r in range(rows):
        for c in range(cols):
            n = r * cols + c
            if c + 1 < cols:
                link(n, n + 1)
            if r + 1 < rows:
                link(n, n + cols)
    return RoadGraph(nodes, edges)


def edge_between(graph: RoadGraph, a: int, b: int) -> Edge:
    return next(graph.edges[i] for i in graph.out[a] if graph.edges[i].v == b)


@pytest.fixture
def grid() -> RoadGraph:
    return make_grid(5, 5)
