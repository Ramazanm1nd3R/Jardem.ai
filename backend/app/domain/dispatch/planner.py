"""Dispatch planning: which unit goes to which incident.

Three strategies share one interface so they can be compared on identical scenarios:

* nearest  — greedy, closest eligible unit by straight-line distance (baseline);
* min_eta  — greedy, fastest eligible unit by traffic-aware travel time (baseline);
* jardem   — global minimum-cost assignment over all open incidents at once. The cost
             weighs travel time by incident priority and, for non-critical calls, adds
             penalties for stripping an area of its cover and for spending a scarce
             specialised unit on a routine call. Units already heading to an incident are re-planned with a switching
             cost, so a marginally better option does not flip assignments back and forth.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Protocol

from app.domain.dispatch.assignment import FORBIDDEN, solve_assignment
from app.domain.geo import haversine_m
from app.domain.models import (
    DISPATCHABLE,
    REASSIGNABLE,
    SCARCE_CAPABILITIES,
    Priority,
    Service,
    UnitStatus,
)

STRATEGIES = ("nearest", "min_eta", "jardem")

PRIORITY_WEIGHT: dict[Priority, float] = {
    Priority.CRITICAL: 4.0,
    Priority.HIGH: 2.5,
    Priority.MEDIUM: 1.5,
    Priority.LOW: 1.0,
}


@dataclass(frozen=True, slots=True)
class UnitView:
    id: str
    service: Service
    capabilities: frozenset[str]
    status: UnitStatus
    lat: float
    lon: float
    incident_id: str | None = None
    reassignments: int = 0


@dataclass(frozen=True, slots=True)
class IncidentView:
    id: str
    service: Service
    required: frozenset[str]
    priority: Priority
    lat: float
    lon: float
    created_at: float
    units_required: int = 1


@dataclass(frozen=True, slots=True)
class DemandPoint:
    """A place the service must stay able to reach, weighted by expected demand."""

    lat: float
    lon: float
    weight: float


class Oracle(Protocol):
    def eta_s(self, unit: UnitView, incident: IncidentView) -> float:
        """Travel time in seconds; math.inf when unreachable."""

    def cover_s(self, unit: UnitView, demand_index: int) -> float:
        """Travel time in seconds from the unit to demand point `demand_index`."""


@dataclass(frozen=True, slots=True)
class DispatchParams:
    coverage_weight: float = 0.6  # seconds of cost per second of lost area cover
    coverage_cap_s: float = 1200.0  # cover time beyond this counts as "uncovered"
    overqualification_penalty_s: float = 120.0  # per unused scarce capability
    unassigned_penalty_s: float = 5400.0  # cost of leaving one slot empty (× priority weight)
    stickiness_s: float = 90.0  # minimum weighted gain needed to re-route a unit
    stickiness_ratio: float = 0.25  # ...or this share of its current ETA, if larger
    max_reassignments: int = 1  # times a unit may be re-routed before it is locked


@dataclass(frozen=True, slots=True)
class Assignment:
    incident_id: str
    unit_id: str
    eta_s: float
    cost: float
    kept: bool = False  # the unit was already committed to this incident


@dataclass(frozen=True, slots=True)
class Plan:
    strategy: str
    assignments: tuple[Assignment, ...]
    unfilled: tuple[str, ...] = ()  # incident id, once per slot left without a unit
    released: tuple[str, ...] = field(default=())  # units pulled off their incident

    def units_for(self, incident_id: str) -> list[str]:
        return [a.unit_id for a in self.assignments if a.incident_id == incident_id]


@dataclass(frozen=True, slots=True)
class Candidate:
    unit_id: str
    eta_s: float
    distance_m: float
    coverage_loss_s: float
    overqualified: int
    cost: float


def reserve_penalty_s(unit: UnitView, incident: IncidentView, coverage_loss_s: float,
                      params: DispatchParams) -> float:
    """Cost of spending this particular unit: lost area cover and wasted specialisation.

    A critical incident pays nothing here — when a life is at stake the fastest unit goes,
    and the reserve is protected only on the less urgent calls.
    """
    if incident.priority is Priority.CRITICAL:
        return 0.0
    return (params.coverage_weight * coverage_loss_s
            + params.overqualification_penalty_s * overqualification(unit, incident))


def is_eligible(unit: UnitView, incident: IncidentView) -> bool:
    return unit.service is incident.service and incident.required <= unit.capabilities


def overqualification(unit: UnitView, incident: IncidentView) -> int:
    return len((unit.capabilities & SCARCE_CAPABILITIES) - incident.required)


def coverage_losses(units: Sequence[UnitView], demand: Sequence[DemandPoint], oracle: Oracle,
                    cap_s: float) -> dict[str, float]:
    """Per free unit: how much the weighted mean time-to-cover grows if it leaves.

    For each service and demand point only the fastest free unit matters — removing it
    hands the point to the runner-up (or to nobody: the cap).
    """
    losses: dict[str, float] = {}
    total_weight = sum(d.weight for d in demand)
    if total_weight <= 0:
        return {u.id: 0.0 for u in units if u.status in DISPATCHABLE}
    by_service: dict[Service, list[UnitView]] = {}
    for u in units:
        if u.status in DISPATCHABLE:
            by_service.setdefault(u.service, []).append(u)
            losses[u.id] = 0.0
    for pool in by_service.values():
        for d_index, d in enumerate(demand):
            best_id, best, second = "", cap_s, cap_s
            for u in pool:
                t = min(cap_s, oracle.cover_s(u, d_index))
                if t < best:
                    best_id, second, best = u.id, best, t
                elif t < second:
                    second = t
            if best_id:
                losses[best_id] += d.weight * (second - best) / total_weight
    return losses


def _ordered(incidents: Sequence[IncidentView]) -> list[IncidentView]:
    return sorted(incidents, key=lambda i: (i.priority, i.created_at, i.id))


def _committed(units: Sequence[UnitView]) -> dict[str, list[UnitView]]:
    """Units already bound to an incident, by incident id."""
    result: dict[str, list[UnitView]] = {}
    for u in units:
        if u.incident_id is not None and u.status not in DISPATCHABLE:
            result.setdefault(u.incident_id, []).append(u)
    return result


def plan_greedy(units: Sequence[UnitView], incidents: Sequence[IncidentView], oracle: Oracle,
                *, by: str) -> Plan:
    """Baseline: serve incidents in priority order, each taking its best free unit.

    `by` is "distance" (straight line) or "eta" (travel time). Existing commitments are
    never revisited.
    """
    if by not in ("distance", "eta"):
        raise ValueError(f"unknown greedy key: {by}")
    committed = _committed(units)
    free = {u.id: u for u in units if u.status in DISPATCHABLE}
    assignments: list[Assignment] = []
    unfilled: list[str] = []
    for inc in _ordered(incidents):
        for u in committed.get(inc.id, []):
            assignments.append(Assignment(inc.id, u.id, oracle.eta_s(u, inc), 0.0, kept=True))
        open_slots = inc.units_required - len(committed.get(inc.id, []))
        for _ in range(max(0, open_slots)):
            best: tuple[float, str, float] | None = None
            for u in free.values():
                if not is_eligible(u, inc):
                    continue
                eta = oracle.eta_s(u, inc)
                if eta == math.inf:
                    continue
                key = haversine_m(u.lat, u.lon, inc.lat, inc.lon) if by == "distance" else eta
                if best is None or (key, u.id) < (best[0], best[1]):
                    best = (key, u.id, eta)
            if best is None:
                unfilled.append(inc.id)
                continue
            del free[best[1]]
            assignments.append(Assignment(inc.id, best[1], best[2], best[0]))
    return Plan("nearest" if by == "distance" else "min_eta", tuple(assignments), tuple(unfilled))


def plan_jardem(units: Sequence[UnitView], incidents: Sequence[IncidentView], oracle: Oracle,
                demand: Sequence[DemandPoint], params: DispatchParams | None = None) -> Plan:
    params = params or DispatchParams()
    incident_by_id = {i.id: i for i in incidents}
    committed = _committed(units)
    losses = coverage_losses(units, demand, oracle, params.coverage_cap_s)

    assignments: list[Assignment] = []
    slots: list[IncidentView] = []
    candidates: list[UnitView] = []
    for inc in _ordered(incidents):
        open_slots = inc.units_required
        for u in committed.get(inc.id, []):
            movable = u.status in REASSIGNABLE and u.reassignments < params.max_reassignments
            if movable:
                candidates.append(u)
            else:
                # On scene, or already re-routed once: the pairing is fixed.
                assignments.append(Assignment(inc.id, u.id, oracle.eta_s(u, inc), 0.0, kept=True))
                open_slots -= 1
        slots.extend([inc] * max(0, open_slots))
    candidates.extend(u for u in units if u.status in DISPATCHABLE)
    # Units committed to incidents outside this planning round stay where they are.
    candidates = [u for u in candidates
                  if u.status in DISPATCHABLE or u.incident_id in incident_by_id]

    if not slots:
        return Plan("jardem", tuple(assignments))

    etas: dict[tuple[int, int], float] = {}
    matrix: list[list[float]] = []
    for r, inc in enumerate(slots):
        weight = PRIORITY_WEIGHT[inc.priority]
        row: list[float] = []
        for c, u in enumerate(candidates):
            if not is_eligible(u, inc):
                row.append(FORBIDDEN)
                continue
            eta = oracle.eta_s(u, inc)
            if eta == math.inf:
                row.append(FORBIDDEN)
                continue
            etas[(r, c)] = eta
            cost = weight * eta + reserve_penalty_s(u, inc, losses.get(u.id, 0.0), params)
            if u.status not in DISPATCHABLE and u.incident_id == inc.id:
                cost -= weight * max(params.stickiness_s, params.stickiness_ratio * eta)
            row.append(cost)
        # One private "nobody" column per slot: leaving it empty is allowed but expensive.
        for other in range(len(slots)):
            row.append(params.unassigned_penalty_s * weight if other == r else FORBIDDEN)
        matrix.append(row)

    columns = solve_assignment(matrix)
    unfilled: list[str] = []
    used: set[str] = set()
    for r, c in enumerate(columns):
        inc = slots[r]
        if c >= len(candidates) or matrix[r][c] >= FORBIDDEN:
            unfilled.append(inc.id)
            continue
        u = candidates[c]
        used.add(u.id)
        assignments.append(
            Assignment(inc.id, u.id, etas[(r, c)], matrix[r][c], kept=u.incident_id == inc.id)
        )
    released = tuple(
        u.id for u in candidates
        if u.status in REASSIGNABLE and u.id not in used
    )
    moved = tuple(
        a.unit_id for a in assignments
        if not a.kept and any(u.id == a.unit_id and u.status in REASSIGNABLE for u in candidates)
    )
    return Plan("jardem", tuple(assignments), tuple(unfilled), released + moved)


def make_plan(strategy: str, units: Sequence[UnitView], incidents: Sequence[IncidentView],
              oracle: Oracle, demand: Sequence[DemandPoint],
              params: DispatchParams | None = None) -> Plan:
    if strategy == "nearest":
        return plan_greedy(units, incidents, oracle, by="distance")
    if strategy == "min_eta":
        return plan_greedy(units, incidents, oracle, by="eta")
    if strategy == "jardem":
        return plan_jardem(units, incidents, oracle, demand, params)
    raise ValueError(f"unknown strategy: {strategy}")


def rank_candidates(incident: IncidentView, units: Sequence[UnitView], oracle: Oracle,
                    demand: Sequence[DemandPoint],
                    params: DispatchParams | None = None) -> list[Candidate]:
    """Free eligible units for one incident, best first, with the cost breakdown."""
    params = params or DispatchParams()
    losses = coverage_losses(units, demand, oracle, params.coverage_cap_s)
    weight = PRIORITY_WEIGHT[incident.priority]
    result: list[Candidate] = []
    for u in units:
        if u.status not in DISPATCHABLE or not is_eligible(u, incident):
            continue
        eta = oracle.eta_s(u, incident)
        if eta == math.inf:
            continue
        over = overqualification(u, incident)
        loss = losses.get(u.id, 0.0)
        cost = weight * eta + reserve_penalty_s(u, incident, loss, params)
        result.append(
            Candidate(u.id, eta, haversine_m(u.lat, u.lon, incident.lat, incident.lon), loss,
                      over, cost)
        )
    result.sort(key=lambda c: (c.cost, c.unit_id))
    return result
