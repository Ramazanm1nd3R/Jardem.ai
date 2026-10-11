"""Shortest-time routing over a RoadGraph for a given set of edge travel times."""

from __future__ import annotations

import heapq
import math
from dataclasses import dataclass

from app.domain.geo import LatLon, bearing_deg, turn_angle_deg
from app.domain.graph import RoadGraph

INF = math.inf


@dataclass(frozen=True, slots=True)
class EdgeCosts:
    """Travel time in seconds per edge id; inf marks a closed edge."""

    times: tuple[float, ...]
    version: int
    max_speed_mps: float  # fastest speed on any open edge — bounds the A* heuristic

    @classmethod
    def build(cls, graph: RoadGraph, times: list[float], version: int = 0) -> EdgeCosts:
        if len(times) != len(graph.edges):
            raise ValueError("one travel time per edge is required")
        vmax = 0.0
        for e, t in zip(graph.edges, times, strict=True):
            if t <= 0:
                raise ValueError(f"non-positive travel time on edge {e.id}")
            if t != INF:
                vmax = max(vmax, e.length_m / t)
        return cls(tuple(times), version, vmax)

    @classmethod
    def free_flow(cls, graph: RoadGraph) -> EdgeCosts:
        return cls.build(graph, [e.free_time_s for e in graph.edges])


@dataclass(frozen=True, slots=True)
class Maneuver:
    kind: str  # depart | left | right | slight_left | slight_right | uturn | arrive
    street: str
    distance_m: float  # distance travelled before this maneuver happens
    location: LatLon


@dataclass(frozen=True, slots=True)
class Route:
    nodes: tuple[int, ...]
    edges: tuple[int, ...]
    distance_m: float
    duration_s: float
    geometry: tuple[LatLon, ...]


def shortest_path(graph: RoadGraph, costs: EdgeCosts, src: int, dst: int) -> Route | None:
    """A* by travel time. Returns None when dst is unreachable."""
    if src == dst:
        return Route((src,), (), 0.0, 0.0, (graph.nodes[src],))
    vmax = costs.max_speed_mps
    if vmax <= 0:
        return None
    times = costs.times
    edges = graph.edges
    out = graph.out
    dx, dy = graph.xy[dst]
    xy = graph.xy

    best: dict[int, float] = {src: 0.0}
    came: dict[int, int] = {}
    heap: list[tuple[float, float, int]] = [(graph.heuristic_m(src, dst) / vmax, 0.0, src)]
    while heap:
        _, g, node = heapq.heappop(heap)
        if node == dst:
            break
        if g > best.get(node, INF):
            continue
        for eid in out[node]:
            t = times[eid]
            if t == INF:
                continue
            nxt = edges[eid].v
            ng = g + t
            if ng < best.get(nxt, INF):
                best[nxt] = ng
                came[nxt] = eid
                x, y = xy[nxt]
                heapq.heappush(heap, (ng + math.hypot(x - dx, y - dy) / vmax, ng, nxt))
    if dst not in came:
        return None

    edge_ids: list[int] = []
    node = dst
    while node != src:
        eid = came[node]
        edge_ids.append(eid)
        node = edges[eid].u
    edge_ids.reverse()
    return _assemble(graph, src, edge_ids, best[dst])


def _assemble(graph: RoadGraph, src: int, edge_ids: list[int], duration: float) -> Route:
    nodes = [src]
    geometry: list[LatLon] = [graph.nodes[src]]
    distance = 0.0
    for eid in edge_ids:
        e = graph.edges[eid]
        nodes.append(e.v)
        geometry.extend(e.shape[1:])
        distance += e.length_m
    return Route(tuple(nodes), tuple(edge_ids), distance, duration, tuple(geometry))


def times_to(graph: RoadGraph, costs: EdgeCosts, dst: int) -> list[float]:
    """Travel time from every node to dst (Dijkstra on the reversed graph)."""
    return _dijkstra(graph, costs, dst, reverse=True)


def times_from(graph: RoadGraph, costs: EdgeCosts, src: int) -> list[float]:
    """Travel time from src to every node."""
    return _dijkstra(graph, costs, src, reverse=False)


def _dijkstra(graph: RoadGraph, costs: EdgeCosts, origin: int, *, reverse: bool) -> list[float]:
    times = costs.times
    edges = graph.edges
    adjacency = graph.inc if reverse else graph.out
    dist = [INF] * len(graph.nodes)
    dist[origin] = 0.0
    heap: list[tuple[float, int]] = [(0.0, origin)]
    while heap:
        d, node = heapq.heappop(heap)
        if d > dist[node]:
            continue
        for eid in adjacency[node]:
            t = times[eid]
            if t == INF:
                continue
            e = edges[eid]
            nxt = e.u if reverse else e.v
            nd = d + t
            if nd < dist[nxt]:
                dist[nxt] = nd
                heapq.heappush(heap, (nd, nxt))
    return dist


SLIGHT_TURN_DEG = 25.0
TURN_DEG = 60.0
UTURN_DEG = 160.0


def classify_turn(angle: float) -> str | None:
    """Maneuver kind for a signed turn angle, or None when the road continues straight."""
    magnitude = abs(angle)
    if magnitude < SLIGHT_TURN_DEG:
        return None
    if magnitude >= UTURN_DEG:
        return "uturn"
    side = "right" if angle > 0 else "left"
    return side if magnitude >= TURN_DEG else f"slight_{side}"


def maneuvers(graph: RoadGraph, route: Route) -> list[Maneuver]:
    """Turn-by-turn instructions: a maneuver is emitted where the heading changes."""
    if not route.edges:
        return []
    first = graph.edges[route.edges[0]]
    result = [Maneuver("depart", first.name, 0.0, first.shape[0])]
    travelled = 0.0
    for prev_id, next_id in zip(route.edges, route.edges[1:], strict=False):
        prev, nxt = graph.edges[prev_id], graph.edges[next_id]
        travelled += prev.length_m
        angle = turn_angle_deg(
            bearing_deg(*prev.shape[-2], *prev.shape[-1]),
            bearing_deg(*nxt.shape[0], *nxt.shape[1]),
        )
        kind = classify_turn(angle)
        if kind is not None:
            result.append(Maneuver(kind, nxt.name, travelled, nxt.shape[0]))
    last = graph.edges[route.edges[-1]]
    result.append(Maneuver("arrive", last.name, route.distance_m, last.shape[-1]))
    return result
