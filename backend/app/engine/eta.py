"""Travel-time service: snaps points to the road graph and caches shortest-path trees."""

from __future__ import annotations

import math
from collections import OrderedDict
from collections.abc import Sequence

from app.domain.dispatch.planner import DemandPoint, IncidentView, UnitView
from app.domain.geo import LatLon, haversine_m
from app.domain.graph import RoadGraph
from app.domain.routing import EdgeCosts, Route, shortest_path, times_to
from app.domain.traffic import TrafficModel

# Speed assumed between an off-road point and the nearest graph node (yards, driveways).
ACCESS_SPEED_MPS = 5.0
TREE_CACHE_SIZE = 512


class EtaService:
    def __init__(self, graph: RoadGraph, traffic: TrafficModel):
        self.graph = graph
        self.traffic = traffic
        self._nodes: dict[tuple[int, int], int] = {}
        self._trees: OrderedDict[tuple[int, int], list[float]] = OrderedDict()

    def node_of(self, lat: float, lon: float) -> int:
        key = (round(lat * 1e5), round(lon * 1e5))
        node = self._nodes.get(key)
        if node is None:
            node = self.graph.nearest_node(lat, lon)
            if len(self._nodes) > 50_000:
                self._nodes.clear()
            self._nodes[key] = node
        return node

    def access_s(self, lat: float, lon: float, node: int) -> float:
        return haversine_m(lat, lon, *self.graph.nodes[node]) / ACCESS_SPEED_MPS

    def tree_to(self, node: int, costs: EdgeCosts) -> list[float]:
        """Travel time from every node to `node`, cached per traffic state."""
        key = (node, costs.version)
        tree = self._trees.get(key)
        if tree is None:
            tree = times_to(self.graph, costs, node)
            self._trees[key] = tree
            if len(self._trees) > TREE_CACHE_SIZE:
                self._trees.popitem(last=False)
        else:
            self._trees.move_to_end(key)
        return tree

    def eta_s(self, origin: LatLon, destination: LatLon, now: float,
              profile: str = "emergency") -> float:
        costs = self.traffic.edge_costs(now, profile)
        a, b = self.node_of(*origin), self.node_of(*destination)
        drive = self.tree_to(b, costs)[a]
        if drive == math.inf:
            return math.inf
        return drive + self.access_s(*origin, a) + self.access_s(*destination, b)

    def route(self, origin: LatLon, destination: LatLon, now: float,
              profile: str = "emergency") -> tuple[Route, EdgeCosts] | None:
        costs = self.traffic.edge_costs(now, profile)
        found = shortest_path(self.graph, costs, self.node_of(*origin), self.node_of(*destination))
        return (found, costs) if found is not None else None


class EngineOracle:
    """Planner oracle backed by the road graph at one instant."""

    def __init__(self, eta: EtaService, demand: Sequence[DemandPoint], now: float):
        self._eta = eta
        self._now = now
        self._costs = eta.traffic.edge_costs(now, "emergency")
        self._demand_nodes = [eta.node_of(d.lat, d.lon) for d in demand]

    def eta_s(self, unit: UnitView, incident: IncidentView) -> float:
        return self._eta.eta_s((unit.lat, unit.lon), (incident.lat, incident.lon), self._now)

    def cover_s(self, unit: UnitView, demand_index: int) -> float:
        tree = self._eta.tree_to(self._demand_nodes[demand_index], self._costs)
        return tree[self._eta.node_of(unit.lat, unit.lon)]
