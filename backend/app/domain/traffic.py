"""Traffic model: per-edge speed factors from time of day, congestion hotspots,
road closures and floating-car probes reported by responder vehicles.

A speed factor is the fraction of free-flow speed currently achievable on an edge
(1.0 = free flow). The model is a simulation: it does not consume a commercial
traffic feed. Probes are the only real-world signal and override the simulated value
on the edges they cover while they are fresh.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import StrEnum

from app.domain.geo import haversine_m
from app.domain.graph import ARTERIAL_MAX_CLASS, RoadGraph
from app.domain.routing import INF, EdgeCosts

MIN_FACTOR = 0.08
SNAPSHOT_BUCKET_S = 300.0
PROBE_TTL_S = 600.0
PROBE_EMA_ALPHA = 0.5

# Emergency vehicles with lights and sirens lose only part of the speed that
# ordinary traffic loses in congestion, and may exceed the free-flow speed slightly.
EMERGENCY_CONGESTION_SHARE = 0.55
EMERGENCY_SPEED_BOOST = 1.15


class Congestion(StrEnum):
    FREE = "free"
    SLOW = "slow"
    JAM = "jam"
    HEAVY = "heavy"
    CLOSED = "closed"


def congestion_level(factor: float) -> Congestion:
    if factor <= 0:
        return Congestion.CLOSED
    if factor >= 0.75:
        return Congestion.FREE
    if factor >= 0.5:
        return Congestion.SLOW
    if factor >= 0.25:
        return Congestion.JAM
    return Congestion.HEAVY


def _bump(hour: float, centre: float, width: float) -> float:
    """Smooth 0..1 peak around `centre` (hours), wrapping around midnight."""
    delta = abs(hour - centre) % 24.0
    delta = min(delta, 24.0 - delta)
    return math.exp(-((delta / width) ** 2))


def rush_intensity(hour: float) -> float:
    """0..1 share of peak congestion at a local time of day (weekday profile)."""
    morning = _bump(hour, 8.5, 1.2)
    evening = _bump(hour, 18.5, 1.6)
    midday = 0.35 * _bump(hour, 13.0, 2.5)
    return min(1.0, max(morning, evening, midday))


# Speed lost at full rush intensity, by road class: arterials congest, side streets barely.
PEAK_LOSS_BY_CLASS = (0.45, 0.55, 0.6, 0.5, 0.35, 0.2, 0.12, 0.05)


def time_of_day_factor(road_class: int, hour: float) -> float:
    return 1.0 - PEAK_LOSS_BY_CLASS[road_class] * rush_intensity(hour)


def emergency_factor(factor: float) -> float:
    """Speed factor for a vehicle running lights and sirens, given the general factor."""
    if factor <= 0:
        return 0.0
    relieved = 1.0 - (1.0 - factor) * EMERGENCY_CONGESTION_SHARE
    return relieved * EMERGENCY_SPEED_BOOST


@dataclass(frozen=True, slots=True)
class Hotspot:
    id: str
    lat: float
    lon: float
    radius_m: float
    severity: float  # share of speed lost at the centre, 0..1
    expires_at: float
    kind: str = "jam"  # jam | accident | roadworks

    def loss_at(self, distance_m: float) -> float:
        if distance_m >= self.radius_m:
            return 0.0
        # Linear falloff: full severity at the centre, none at the edge.
        return self.severity * (1.0 - distance_m / self.radius_m)


@dataclass(frozen=True, slots=True)
class Closure:
    id: str
    lat: float
    lon: float
    edge_ids: frozenset[int]
    expires_at: float
    reason: str = ""


@dataclass(frozen=True, slots=True)
class TrafficSnapshot:
    factors: tuple[float, ...]  # per edge; 0.0 = closed
    version: int
    at: float


def edge_susceptibility(edge_id: int, seed: int) -> float:
    """Deterministic per-edge multiplier in [0.6, 1.0] on time-of-day losses."""
    h = (edge_id * 2654435761 + seed * 40503) & 0xFFFFFFFF
    h ^= h >> 16
    h = (h * 0x45D9F3B) & 0xFFFFFFFF
    h ^= h >> 16
    return 0.6 + 0.4 * (h / 0xFFFFFFFF)


class TrafficModel:
    def __init__(self, graph: RoadGraph, seed: int = 0, utc_offset_h: float = 5.0):
        self.graph = graph
        self.seed = seed
        self.utc_offset_h = utc_offset_h
        self._hotspots: dict[str, Hotspot] = {}
        self._hotspot_edges: dict[str, dict[int, float]] = {}  # hotspot id -> edge -> loss
        self._closures: dict[str, Closure] = {}
        self._probes: dict[int, tuple[float, float]] = {}  # edge -> (factor, observed_at)
        self._revision = 0
        self._version = 0
        self._cache: tuple[tuple[int, int], TrafficSnapshot] | None = None
        self._costs_cache: dict[tuple[int, str], EdgeCosts] = {}
        self._susceptibility = [edge_susceptibility(e.id, seed) for e in graph.edges]

    # --- mutations -------------------------------------------------------------

    def add_hotspot(self, hotspot: Hotspot) -> None:
        if not 0 < hotspot.severity <= 1:
            raise ValueError("severity must be in (0, 1]")
        if hotspot.radius_m <= 0:
            raise ValueError("radius must be positive")
        affected: dict[int, float] = {}
        for e in self.graph.edges:
            loss = hotspot.loss_at(haversine_m(hotspot.lat, hotspot.lon, *e.midpoint))
            if loss > 0:
                affected[e.id] = loss
        self._hotspots[hotspot.id] = hotspot
        self._hotspot_edges[hotspot.id] = affected
        self._revision += 1

    def remove_hotspot(self, hotspot_id: str) -> bool:
        if self._hotspots.pop(hotspot_id, None) is None:
            return False
        del self._hotspot_edges[hotspot_id]
        self._revision += 1
        return True

    def close_road(self, closure_id: str, lat: float, lon: float, radius_m: float,
                   expires_at: float, reason: str = "") -> Closure:
        """Close every edge whose midpoint is within radius_m; at least the nearest one."""
        edge_ids = set(self.graph.edges_near(lat, lon, radius_m))
        if not edge_ids:
            nearest = min(self.graph.edges, key=lambda e: haversine_m(lat, lon, *e.midpoint))
            edge_ids = {nearest.id}
        # Closing one carriageway of a two-way street closes the street.
        edge_ids |= {self.graph.edges[i].twin for i in edge_ids if self.graph.edges[i].twin >= 0}
        closure = Closure(closure_id, lat, lon, frozenset(edge_ids), expires_at, reason)
        self._closures[closure_id] = closure
        self._revision += 1
        return closure

    def reopen_road(self, closure_id: str) -> bool:
        if self._closures.pop(closure_id, None) is None:
            return False
        self._revision += 1
        return True

    def report_probe(self, edge_id: int, observed_speed_mps: float, now: float) -> float:
        """Blend a vehicle's observed speed into the edge estimate; returns the new factor."""
        edge = self.graph.edges[edge_id]
        observed = max(MIN_FACTOR, min(1.0, observed_speed_mps / (edge.speed_kph / 3.6)))
        previous = self._probes.get(edge_id)
        if previous is not None and now - previous[1] <= PROBE_TTL_S:
            observed = PROBE_EMA_ALPHA * observed + (1 - PROBE_EMA_ALPHA) * previous[0]
        self._probes[edge_id] = (observed, now)
        self._revision += 1
        return observed

    def expire(self, now: float) -> bool:
        """Drop expired hotspots, closures and probes. Returns True if anything changed."""
        dead_hotspots = [h.id for h in self._hotspots.values() if h.expires_at <= now]
        dead_closures = [c.id for c in self._closures.values() if c.expires_at <= now]
        dead_probes = [e for e, (_, at) in self._probes.items() if now - at > PROBE_TTL_S]
        for hid in dead_hotspots:
            self.remove_hotspot(hid)
        for cid in dead_closures:
            self.reopen_road(cid)
        for eid in dead_probes:
            del self._probes[eid]
        if dead_probes:
            self._revision += 1
        return bool(dead_hotspots or dead_closures or dead_probes)

    # --- queries ---------------------------------------------------------------

    @property
    def hotspots(self) -> list[Hotspot]:
        return list(self._hotspots.values())

    @property
    def closures(self) -> list[Closure]:
        return list(self._closures.values())

    def local_hour(self, now: float) -> float:
        return ((now / 3600.0) + self.utc_offset_h) % 24.0

    def snapshot(self, now: float) -> TrafficSnapshot:
        bucket = int(now // SNAPSHOT_BUCKET_S)
        key = (self._revision, bucket)
        if self._cache is not None and self._cache[0] == key:
            return self._cache[1]

        hour = self.local_hour(bucket * SNAPSHOT_BUCKET_S)
        by_class = [time_of_day_factor(c, hour) for c in range(len(PEAK_LOSS_BY_CLASS))]
        factors = [
            1.0 - (1.0 - by_class[e.road_class]) * self._susceptibility[e.id]
            for e in self.graph.edges
        ]
        for losses in self._hotspot_edges.values():
            for eid, loss in losses.items():
                factors[eid] *= 1.0 - loss
        for eid, (probe, at) in self._probes.items():
            age = now - at
            if age <= PROBE_TTL_S:
                weight = 1.0 - age / PROBE_TTL_S
                factors[eid] = weight * probe + (1.0 - weight) * factors[eid]
        factors = [max(MIN_FACTOR, min(1.0, f)) for f in factors]
        for closure in self._closures.values():
            for eid in closure.edge_ids:
                factors[eid] = 0.0

        # Version identifies the snapshot contents for downstream caches.
        self._version += 1
        snap = TrafficSnapshot(tuple(factors), self._version, now)
        self._cache = (key, snap)
        self._costs_cache.clear()
        return snap

    def edge_costs(self, now: float, profile: str = "emergency") -> EdgeCosts:
        """Edge travel times for a routing profile: 'emergency' or 'car'."""
        if profile not in ("emergency", "car"):
            raise ValueError(f"unknown routing profile: {profile}")
        snap = self.snapshot(now)
        cached = self._costs_cache.get((snap.version, profile))
        if cached is not None:
            return cached
        times: list[float] = []
        for e, f in zip(self.graph.edges, snap.factors, strict=True):
            if f <= 0:
                times.append(INF)
                continue
            if profile == "emergency":
                f = emergency_factor(f)
            times.append(e.free_time_s / f)
        costs = EdgeCosts.build(self.graph, times, version=snap.version * 2 + (profile == "car"))
        self._costs_cache[(snap.version, profile)] = costs
        return costs

    def segments(self, now: float, bbox: tuple[float, float, float, float] | None = None,
                 include_free: bool = False) -> list[dict]:
        """Edges to draw on the traffic layer: arterials and anything congested.

        bbox = (min_lat, min_lon, max_lat, max_lon). Each undirected road is reported once,
        with the worse of its two directions.
        """
        snap = self.snapshot(now)
        result = []
        for e in self.graph.edges:
            if 0 <= e.twin < e.id:
                continue
            factor = snap.factors[e.id]
            if e.twin >= 0:
                factor = min(factor, snap.factors[e.twin])
            level = congestion_level(factor)
            if level is Congestion.FREE and not (include_free and e.road_class <= ARTERIAL_MAX_CLASS):
                continue
            if e.road_class > ARTERIAL_MAX_CLASS + 1 and level is not Congestion.CLOSED:
                # Side streets are only drawn when closed — keeps the layer readable.
                continue
            if bbox is not None:
                lat, lon = e.midpoint
                if not (bbox[0] <= lat <= bbox[2] and bbox[1] <= lon <= bbox[3]):
                    continue
            result.append(
                {
                    "edge_id": e.id,
                    "level": level.value,
                    "factor": round(factor, 2),
                    "speed_kph": round(e.speed_kph * factor, 1),
                    "name": e.name,
                    "geometry": [[round(lon, 5), round(lat, 5)] for lat, lon in e.shape],
                }
            )
        return result

    def city_index(self, now: float) -> int:
        """0..10 congestion score over arterials, length-weighted (10 = gridlock)."""
        snap = self.snapshot(now)
        total = 0.0
        lost = 0.0
        for e in self.graph.edges:
            if e.road_class > ARTERIAL_MAX_CLASS:
                continue
            total += e.length_m
            lost += e.length_m * (1.0 - snap.factors[e.id])
        if total == 0:
            return 0
        return min(10, round(10 * lost / total / 0.7))
