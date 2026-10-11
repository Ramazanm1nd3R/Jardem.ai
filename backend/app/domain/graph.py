"""Directed road graph with a spatial grid index."""

from __future__ import annotations

import gzip
import json
import math
from dataclasses import dataclass
from pathlib import Path

from app.domain.geo import EARTH_RADIUS_M, LatLon, haversine_m

ROAD_CLASSES = (
    "motorway",
    "trunk",
    "primary",
    "secondary",
    "tertiary",
    "unclassified",
    "residential",
    "living_street",
)
# Classes drawn on the traffic layer and treated as arterials by the traffic model.
ARTERIAL_MAX_CLASS = 4

GRID_CELL_DEG = 0.004


@dataclass(frozen=True, slots=True)
class Edge:
    id: int
    u: int
    v: int
    length_m: float
    road_class: int
    speed_kph: float
    name: str
    shape: tuple[LatLon, ...]  # full geometry including both end nodes
    twin: int  # id of the opposite-direction edge of the same road, or -1

    @property
    def free_time_s(self) -> float:
        return self.length_m / (self.speed_kph / 3.6)

    @property
    def midpoint(self) -> LatLon:
        a, b = self.shape[(len(self.shape) - 1) // 2], self.shape[len(self.shape) // 2]
        return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)


class RoadGraph:
    def __init__(self, nodes: list[LatLon], edges: list[Edge]):
        if not nodes:
            raise ValueError("graph has no nodes")
        self.nodes = nodes
        self.edges = edges
        self.out: list[list[int]] = [[] for _ in nodes]
        self.inc: list[list[int]] = [[] for _ in nodes]
        for e in edges:
            self.out[e.u].append(e.id)
            self.inc[e.v].append(e.id)

        # Planar projection used only as an admissible A* heuristic: scaling longitude by
        # the cosine of the latitude farthest from the equator never overestimates distance.
        max_abs_lat = max(abs(lat) for lat, _ in nodes)
        self._kx = EARTH_RADIUS_M * math.radians(1.0) * math.cos(math.radians(max_abs_lat))
        self._ky = EARTH_RADIUS_M * math.radians(1.0)
        self.xy: list[tuple[float, float]] = [(lon * self._kx, lat * self._ky) for lat, lon in nodes]

        self._grid: dict[tuple[int, int], list[int]] = {}
        for i, (lat, lon) in enumerate(nodes):
            self._grid.setdefault(self._cell(lat, lon), []).append(i)

    @staticmethod
    def _cell(lat: float, lon: float) -> tuple[int, int]:
        return (math.floor(lat / GRID_CELL_DEG), math.floor(lon / GRID_CELL_DEG))

    def nearest_node(self, lat: float, lon: float) -> int:
        """Closest graph node to the point (exact, expanding ring search)."""
        cy, cx = self._cell(lat, lon)
        best, best_d = -1, math.inf
        ring = 0
        # One cell is at least ~320 m wide at Almaty's latitude; once a candidate is found
        # the search needs one more ring to rule out closer nodes in neighbouring cells.
        max_ring = 4096
        stop_at = max_ring
        while ring <= stop_at:
            for y in range(cy - ring, cy + ring + 1):
                on_edge_row = y in (cy - ring, cy + ring)
                xs = range(cx - ring, cx + ring + 1) if on_edge_row else (cx - ring, cx + ring)
                for x in xs:
                    for i in self._grid.get((y, x), ()):
                        nlat, nlon = self.nodes[i]
                        d = haversine_m(lat, lon, nlat, nlon)
                        if d < best_d:
                            best, best_d = i, d
            if best >= 0 and stop_at == max_ring:
                cell_m = GRID_CELL_DEG * self._kx
                stop_at = ring + math.ceil(best_d / cell_m)
            ring += 1
        return best

    def heuristic_m(self, a: int, b: int) -> float:
        ax, ay = self.xy[a]
        bx, by = self.xy[b]
        return math.hypot(ax - bx, ay - by)

    def edges_near(self, lat: float, lon: float, radius_m: float) -> list[int]:
        """Edges whose midpoint lies within radius_m of the point."""
        return [
            e.id for e in self.edges if haversine_m(lat, lon, *e.midpoint) <= radius_m
        ]

    @classmethod
    def from_dict(cls, data: dict) -> RoadGraph:
        nodes: list[LatLon] = [(float(lat), float(lon)) for lat, lon in data["nodes"]]
        names = data["names"]
        edges: list[Edge] = []
        for u, v, length, cls_idx, speed, name_idx, bidir, flat in data["edges"]:
            inner = [(flat[i], flat[i + 1]) for i in range(0, len(flat), 2)]
            shape = (nodes[u], *inner, nodes[v])
            fwd = len(edges)
            edges.append(
                Edge(fwd, u, v, float(length), cls_idx, float(speed), names[name_idx], shape,
                     fwd + 1 if bidir else -1)
            )
            if bidir:
                edges.append(
                    Edge(fwd + 1, v, u, float(length), cls_idx, float(speed), names[name_idx],
                         shape[::-1], fwd)
                )
        return cls(nodes, edges)

    @classmethod
    def from_file(cls, path: str | Path) -> RoadGraph:
        with gzip.open(path, "rt", encoding="utf-8") as fh:
            return cls.from_dict(json.load(fh))
