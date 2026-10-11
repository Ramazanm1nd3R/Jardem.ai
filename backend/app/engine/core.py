"""The dispatch engine: owns the world state and advances it.

Everything here is synchronous and driven by an explicit simulation clock (`tick`), so
whole scenarios run deterministically in tests and in the offline experiments. The API
layer wraps it with asyncio and drains `outbox` to push events to clients.
"""

from __future__ import annotations

import math
import time
from collections.abc import Callable, Sequence
from dataclasses import asdict

from app.domain.dispatch.planner import (
    STRATEGIES,
    Candidate,
    DemandPoint,
    DispatchParams,
    IncidentView,
    Plan,
    UnitView,
    make_plan,
    rank_candidates,
)
from app.domain.geo import LatLon, bearing_deg, haversine_m, point_along
from app.domain.graph import RoadGraph
from app.domain.models import (
    ACTIVE_INCIDENT,
    CATEGORY_BY_ID,
    DISPATCHABLE,
    IncidentStatus,
    Priority,
    Service,
    UnitStatus,
    check_incident_transition,
    check_unit_transition,
    incident_status_for_units,
)
from app.domain.routing import INF, maneuvers
from app.domain.traffic import TrafficModel
from app.domain.triage import triage
from app.engine.eta import EngineOracle, EtaService
from app.engine.world import Incident, Message, RouteState, TimelineEntry, Unit, World

TURNOUT_S = 30.0  # simulated crews start driving this long after being assigned
REROUTE_INTERVAL_S = 20.0
REPLAN_INTERVAL_S = 30.0
DEVICE_GPS_FRESH_S = 15.0
ON_SCENE_BASE_S: dict[Service, float] = {
    Service.AMBULANCE: 480.0,
    Service.POLICE: 600.0,
    Service.FIRE: 900.0,
    Service.RESCUE: 900.0,
}
_INCIDENT_ORDER = (IncidentStatus.NEW, IncidentStatus.ASSIGNED, IncidentStatus.EN_ROUTE,
                   IncidentStatus.ON_SCENE)

# Almaty districts: approximate centroids, weights proportional to rough population.
ALMATY_DEMAND: tuple[DemandPoint, ...] = (
    DemandPoint(43.250, 76.905, 0.22),  # Алмалинский
    DemandPoint(43.225, 76.850, 0.31),  # Ауэзовский
    DemandPoint(43.215, 76.925, 0.36),  # Бостандыкский
    DemandPoint(43.300, 76.930, 0.17),  # Жетысуский
    DemandPoint(43.245, 76.965, 0.22),  # Медеуский
    DemandPoint(43.195, 76.810, 0.17),  # Наурызбайский
    DemandPoint(43.330, 76.970, 0.25),  # Турксибский
    DemandPoint(43.290, 76.850, 0.33),  # Алатауский
)


class EngineError(ValueError):
    pass


class Engine:
    def __init__(self, graph: RoadGraph, world: World, *, traffic: TrafficModel | None = None,
                 now: float = 0.0, wall: Callable[[], float] = time.time,
                 strategy: str = "jardem", params: DispatchParams | None = None,
                 demand: Sequence[DemandPoint] = ALMATY_DEMAND, auto_dispatch: bool = True):
        if strategy not in STRATEGIES:
            raise EngineError(f"unknown strategy: {strategy}")
        self.graph = graph
        self.world = world
        self.traffic = traffic or TrafficModel(graph)
        self.eta = EtaService(graph, self.traffic)
        self.now = now
        self.wall = wall
        self.strategy = strategy
        self.params = params or DispatchParams()
        self.demand = tuple(demand)
        self.auto_dispatch = auto_dispatch
        self.proposals: dict[str, list[str]] = {}
        self.outbox: list[dict] = []
        self.last_plan: Plan | None = None
        self._dirty = False
        self._last_replan = now
        self._last_reroute = now

    # --- events ----------------------------------------------------------------

    def _emit(self, kind: str, **data) -> None:
        self.outbox.append({"type": kind, **data})

    def drain(self) -> list[dict]:
        events, self.outbox = self.outbox, []
        return events

    # --- incidents -------------------------------------------------------------

    def create_incident(self, category: str, lat: float, lon: float, *, description: str = "",
                        address: str = "", citizen_id: str | None = None,
                        caller_name: str = "", caller_phone: str = "", extra_info: str = "",
                        priority: Priority | None = None, synthetic: bool = False) -> Incident:
        cat = CATEGORY_BY_ID.get(category)
        if cat is None:
            raise EngineError(f"unknown category: {category}")
        triaged = None
        chosen = priority or cat.priority
        if description.strip():
            result = triage(description)
            triaged = asdict(result)
            triaged["matched"] = list(result.matched)
            # Text can only raise urgency: stated danger to life overrides the category default.
            if priority is None and (result.life_threat or result.people_inside):
                chosen = Priority.CRITICAL
        number = self.world.next_incident_number
        self.world.next_incident_number += 1
        incident = Incident(
            id=f"inc-{number}", number=number, service=cat.service, category=cat.id,
            priority=chosen, required=cat.required, units_required=cat.units_required,
            lat=lat, lon=lon, address=address, description=description,
            status=IncidentStatus.NEW, created_at=self.now, created_wall=self.wall(),
            citizen_id=citizen_id, caller_name=caller_name, caller_phone=caller_phone,
            extra_info=extra_info, synthetic=synthetic, triage=triaged,
        )
        incident.timeline.append(TimelineEntry(IncidentStatus.NEW.value, incident.created_wall))
        self.world.incidents[incident.id] = incident
        self._emit("incident.created", incident_id=incident.id)
        self.replan()
        return incident

    def cancel_incident(self, incident_id: str) -> Incident:
        incident = self._incident(incident_id)
        check_incident_transition(incident.status, IncidentStatus.CANCELLED)
        for unit in self.world.units_of(incident):
            self._release(unit)
        self._close(incident, IncidentStatus.CANCELLED)
        self.replan()
        return incident

    def _close(self, incident: Incident, status: IncidentStatus) -> None:
        incident.status = status
        incident.closed_wall = self.wall()
        incident.timeline.append(TimelineEntry(status.value, incident.closed_wall))
        self.proposals.pop(incident.id, None)
        self._emit("incident.updated", incident_id=incident.id)

    def _incident(self, incident_id: str) -> Incident:
        try:
            return self.world.incidents[incident_id]
        except KeyError:
            raise EngineError(f"unknown incident: {incident_id}") from None

    def _unit(self, unit_id: str) -> Unit:
        try:
            return self.world.units[unit_id]
        except KeyError:
            raise EngineError(f"unknown unit: {unit_id}") from None

    def _sync_incident(self, incident: Incident) -> None:
        """Bring the incident status in line with the units working it."""
        if incident.status not in ACTIVE_INCIDENT:
            return
        target = incident_status_for_units([u.status for u in self.world.units_of(incident)])
        if incident.status is IncidentStatus.ON_SCENE:
            return  # help has arrived; later arrivals and departures do not undo that
        cur, goal = _INCIDENT_ORDER.index(incident.status), _INCIDENT_ORDER.index(target)
        step = 1 if goal > cur else -1
        while cur != goal:
            cur += step
            nxt = _INCIDENT_ORDER[cur]
            check_incident_transition(incident.status, nxt)
            incident.status = nxt
            incident.timeline.append(TimelineEntry(nxt.value, self.wall()))
            if nxt is IncidentStatus.ON_SCENE and incident.first_arrival_s is None:
                incident.first_arrival_s = self.now - incident.created_at
            self._emit("incident.updated", incident_id=incident.id)

    # --- planning --------------------------------------------------------------

    def _unit_view(self, unit: Unit) -> UnitView:
        return UnitView(unit.id, unit.service, unit.capabilities, unit.status, unit.lat, unit.lon,
                        unit.incident_id, unit.reassignments)

    def _incident_view(self, incident: Incident) -> IncidentView | None:
        departed = len([u for u in incident.served_by if u not in incident.unit_ids])
        needed = incident.units_required - departed
        if needed <= 0:
            return None
        return IncidentView(incident.id, incident.service, incident.required, incident.priority,
                            incident.lat, incident.lon, incident.created_at, needed)

    def _open_incident_views(self) -> list[IncidentView]:
        views = []
        for incident in self.world.incidents.values():
            if incident.status in ACTIVE_INCIDENT:
                view = self._incident_view(incident)
                if view is not None:
                    views.append(view)
        return views

    def oracle(self) -> EngineOracle:
        return EngineOracle(self.eta, self.demand, self.now)

    def replan(self) -> Plan:
        """Recompute who goes where and (in auto mode) carry it out."""
        self._dirty = False
        self._last_replan = self.now
        units = [self._unit_view(u) for u in self.world.units.values()]
        plan = make_plan(self.strategy, units, self._open_incident_views(), self.oracle(),
                         self.demand, self.params)
        self.last_plan = plan
        if self.auto_dispatch:
            self._apply(plan)
        else:
            self.proposals = {}
            for a in plan.assignments:
                if not a.kept:
                    self.proposals.setdefault(a.incident_id, []).append(a.unit_id)
            self._emit("dispatch.proposed", proposals=self.proposals)
        return plan

    def _apply(self, plan: Plan) -> None:
        touched: set[str] = set()
        reassigned = {a.unit_id for a in plan.assignments if not a.kept}
        for unit_id in plan.released:
            unit = self.world.units[unit_id]
            if unit.incident_id is not None:
                touched.add(unit.incident_id)
            if unit_id in reassigned:
                self._detach(unit)
                unit.reassignments += 1
            else:
                self._release(unit)
        for a in plan.assignments:
            if a.kept:
                continue
            self._assign(self.world.units[a.unit_id], self.world.incidents[a.incident_id])
            touched.add(a.incident_id)
        for incident_id in touched:
            self._sync_incident(self.world.incidents[incident_id])

    def assign(self, incident_id: str, unit_id: str) -> None:
        """Manual dispatch by an operator (also used to confirm a proposal)."""
        incident, unit = self._incident(incident_id), self._unit(unit_id)
        if incident.status not in ACTIVE_INCIDENT:
            raise EngineError("incident is closed")
        if unit.status not in DISPATCHABLE:
            raise EngineError("unit is not available")
        if unit.service is not incident.service or not incident.required <= unit.capabilities:
            raise EngineError("unit cannot serve this incident")
        self._assign(unit, incident)
        self.proposals.pop(incident_id, None)
        self._sync_incident(incident)

    def _assign(self, unit: Unit, incident: Incident) -> None:
        if unit.status in DISPATCHABLE:
            self._set_status(unit, UnitStatus.ASSIGNED)
        unit.incident_id = incident.id
        if unit.id not in incident.unit_ids:
            incident.unit_ids.append(unit.id)
        self._route(unit, (incident.lat, incident.lon), "incident")
        self._emit("unit.assigned", unit_id=unit.id, incident_id=incident.id)

    def _detach(self, unit: Unit) -> None:
        incident = self.world.incidents.get(unit.incident_id or "")
        if incident is not None and unit.id in incident.unit_ids:
            incident.unit_ids.remove(unit.id)
        unit.incident_id = None
        unit.route = None

    def _release(self, unit: Unit) -> None:
        """Take the unit off its incident and send it home, free for new work."""
        self._detach(unit)
        if unit.status is not UnitStatus.AVAILABLE:
            self._set_status(unit, UnitStatus.AVAILABLE)
        self._route(unit, unit.base, "base")
        self._emit("unit.released", unit_id=unit.id)

    def _set_status(self, unit: Unit, status: UnitStatus) -> None:
        check_unit_transition(unit.status, status)
        unit.status = status
        unit.status_since = self.now
        self._emit("unit.updated", unit_id=unit.id)

    # --- routes ----------------------------------------------------------------

    def _route(self, unit: Unit, destination: LatLon, target: str) -> bool:
        found = self.eta.route((unit.lat, unit.lon), destination, self.now)
        if found is None:
            unit.route = None
            return False
        route, costs = found
        if not route.edges:
            unit.route = None
            return True
        unit.route = RouteState(target, route.edges, route.geometry, route.distance_m,
                                tuple(maneuvers(self.graph, route)), costs.version)
        return True

    def unit_eta_s(self, unit: Unit) -> float | None:
        """Remaining drive time to the unit's current destination."""
        if unit.incident_id is None and unit.route is None:
            return None
        if self.now - unit.device_gps_at <= DEVICE_GPS_FRESH_S and unit.incident_id:
            incident = self.world.incidents[unit.incident_id]
            eta = self.eta.eta_s((unit.lat, unit.lon), (incident.lat, incident.lon), self.now)
            return None if eta == INF else eta
        route = unit.route
        if route is None:
            return 0.0 if unit.status is UnitStatus.ON_SCENE else None
        costs = self.traffic.edge_costs(self.now, "emergency")
        total = 0.0
        for i in range(route.edge_index, len(route.edges)):
            t = costs.times[route.edges[i]]
            if t == INF:
                return None
            if i == route.edge_index:
                t *= 1.0 - route.edge_offset_m / self.graph.edges[route.edges[i]].length_m
            total += t
        return total

    def remaining_geometry(self, unit: Unit) -> list[LatLon]:
        route = unit.route
        if route is None or route.finished:
            return []
        edge = self.graph.edges[route.edges[route.edge_index]]
        _, segment = point_along(edge.shape, route.edge_offset_m)
        points: list[LatLon] = [(unit.lat, unit.lon), *edge.shape[segment + 1:]]
        for eid in route.edges[route.edge_index + 1:]:
            points.extend(self.graph.edges[eid].shape[1:])
        return points

    def _advance(self, unit: Unit, dt: float) -> bool:
        """Move the unit along its route for dt seconds. Returns True if it moved."""
        route = unit.route
        if route is None or route.finished:
            return False
        costs = self.traffic.edge_costs(self.now, "emergency")
        moved = False
        while dt > 0 and not route.finished:
            edge = self.graph.edges[route.edges[route.edge_index]]
            t = costs.times[edge.id]
            if t == INF:
                # The road ahead was closed after the route was planned: stop and re-route.
                destination = route.geometry[-1]
                target = route.target
                if not self._route(unit, destination, target):
                    unit.route = route
                return moved
            speed = edge.length_m / t
            left = edge.length_m - route.edge_offset_m
            step = speed * dt
            if step >= left:
                dt -= left / speed
                route.travelled_m += left
                route.edge_index += 1
                route.edge_offset_m = 0.0
                unit.lat, unit.lon = edge.shape[-1]
            else:
                route.edge_offset_m += step
                route.travelled_m += step
                dt = 0.0
                (lat, lon), seg = point_along(edge.shape, route.edge_offset_m)
                unit.heading = bearing_deg(*edge.shape[seg], *edge.shape[seg + 1])
                unit.lat, unit.lon = lat, lon
            moved = True
        return moved

    def _reroute_stale(self) -> None:
        version = self.traffic.edge_costs(self.now, "emergency").version
        for unit in self.world.units.values():
            route = unit.route
            if route is None or route.finished or route.costs_version == version:
                continue
            before = route.edges[route.edge_index:]
            self._route(unit, route.geometry[-1], route.target)
            if unit.route is None:
                unit.route = route
            elif unit.route.edges != before:
                self._emit("unit.rerouted", unit_id=unit.id)

    # --- crew actions ----------------------------------------------------------

    def unit_action(self, unit_id: str, action: str) -> Unit:
        unit = self._unit(unit_id)
        incident = self.world.incidents.get(unit.incident_id or "")
        if incident is None:
            raise EngineError("unit has no active assignment")
        if action == "accept":
            self._set_status(unit, UnitStatus.EN_ROUTE)
            if unit.route is None:
                self._route(unit, (incident.lat, incident.lon), "incident")
        elif action == "arrive":
            self._set_status(unit, UnitStatus.ON_SCENE)
            unit.route = None
            if unit.id not in incident.served_by:
                incident.served_by.append(unit.id)
        elif action == "transport":
            self._set_status(unit, UnitStatus.TRANSPORTING)
        elif action == "complete":
            if unit.status not in (UnitStatus.ON_SCENE, UnitStatus.TRANSPORTING):
                raise EngineError("unit is not on scene")
            self._set_status(unit, UnitStatus.RETURNING)
            self._detach(unit)
            unit.reassignments = 0
            self._route(unit, unit.base, "base")
            if not incident.unit_ids:
                check_incident_transition(incident.status, IncidentStatus.RESOLVED)
                self._close(incident, IncidentStatus.RESOLVED)
            self._dirty = True
            return unit
        else:
            raise EngineError(f"unknown action: {action}")
        self._sync_incident(incident)
        return unit

    def set_shift(self, unit_id: str, on_duty: bool) -> Unit:
        unit = self._unit(unit_id)
        if on_duty:
            if unit.status is UnitStatus.OFF_DUTY:
                self._set_status(unit, UnitStatus.AVAILABLE)
                unit.shift_started_at = self.wall()
                self.replan()
        else:
            if unit.incident_id is not None:
                raise EngineError("finish the active call before ending the shift")
            if unit.status is not UnitStatus.OFF_DUTY:
                self._set_status(unit, UnitStatus.OFF_DUTY)
                unit.route = None
                unit.shift_started_at = None
        return unit

    def update_location(self, unit_id: str, lat: float, lon: float,
                        speed_mps: float | None = None) -> Unit:
        """A real GPS fix from the responder app; also feeds the traffic model."""
        unit = self._unit(unit_id)
        if haversine_m(unit.lat, unit.lon, lat, lon) > 1.0:
            unit.heading = bearing_deg(unit.lat, unit.lon, lat, lon)
        unit.lat, unit.lon = lat, lon
        unit.device_gps_at = self.now
        if speed_mps is not None and unit.status is UnitStatus.EN_ROUTE:
            node = self.eta.node_of(lat, lon)
            near = [self.graph.edges[e] for e in self.graph.out[node] + self.graph.inc[node]]
            if near and haversine_m(lat, lon, *self.graph.nodes[node]) < 60:
                edge = min(near, key=lambda e: haversine_m(lat, lon, *e.midpoint))
                self.traffic.report_probe(edge.id, speed_mps, self.now)
        self._emit("unit.moved", units=[unit.id])
        return unit

    def post_message(self, unit_id: str, sender: str, author: str, text: str) -> Message:
        self._unit(unit_id)
        message = Message(f"msg-{len(self.world.messages) + 1}", unit_id, sender, author,
                          text.strip(), self.wall())
        self.world.messages.append(message)
        self._emit("message.created", unit_id=unit_id, message_id=message.id)
        return message

    # --- queries ---------------------------------------------------------------

    def nearby_units(self, lat: float, lon: float, *, service: Service | None = None,
                     category: str | None = None, limit: int = 20,
                     ) -> list[tuple[Unit, float, float]]:
        """On-duty units by travel time to the point: (unit, distance_m, eta_s)."""
        required = CATEGORY_BY_ID[category].required if category else frozenset()
        if category:
            service = CATEGORY_BY_ID[category].service
        rows = []
        for unit in self.world.units.values():
            if unit.status is UnitStatus.OFF_DUTY:
                continue
            if service is not None and unit.service is not service:
                continue
            if not required <= unit.capabilities:
                continue
            eta = self.eta.eta_s((unit.lat, unit.lon), (lat, lon), self.now)
            if eta == math.inf:
                continue
            rows.append((unit, haversine_m(unit.lat, unit.lon, lat, lon), eta))
        rows.sort(key=lambda r: (r[0].status not in DISPATCHABLE, r[2], r[0].id))
        return rows[:limit]

    def compare(self, category: str, lat: float, lon: float) -> dict:
        """What each strategy would send to a hypothetical incident right now."""
        cat = CATEGORY_BY_ID.get(category)
        if cat is None:
            raise EngineError(f"unknown category: {category}")
        probe = IncidentView("probe", cat.service, cat.required, cat.priority, lat, lon,
                             self.now, cat.units_required)
        units = [self._unit_view(u) for u in self.world.units.values()]
        oracle = self.oracle()
        picks = {
            s: make_plan(s, units, [probe], oracle, self.demand, self.params).units_for("probe")
            for s in STRATEGIES
        }
        ranked: list[Candidate] = rank_candidates(probe, units, oracle, self.demand, self.params)
        return {"picks": picks, "candidates": ranked}

    # --- time ------------------------------------------------------------------

    def on_scene_duration_s(self, incident: Incident) -> float:
        spread = ((incident.number * 2654435761) & 0xFFFF) / 0xFFFF
        return ON_SCENE_BASE_S[incident.service] * (0.7 + 0.6 * spread)

    def tick(self, dt: float) -> None:
        if dt <= 0:
            return
        self.now += dt
        if self.traffic.expire(self.now):
            self._emit("traffic.updated")
        moved: list[str] = []
        for unit in list(self.world.units.values()):
            device_driven = self.now - unit.device_gps_at <= DEVICE_GPS_FRESH_S
            drives = unit.status in (UnitStatus.EN_ROUTE, UnitStatus.RETURNING,
                                     UnitStatus.AVAILABLE)
            if drives and not device_driven and self._advance(unit, dt):
                moved.append(unit.id)
            if unit.controlled_by is None:
                self._autopilot(unit)
            if unit.route is not None and unit.route.finished and unit.route.target == "base":
                unit.route = None
                unit.lat, unit.lon = unit.base
                if unit.status is UnitStatus.RETURNING:
                    self._set_status(unit, UnitStatus.AVAILABLE)
                    self._dirty = True
        if moved:
            self._emit("unit.moved", units=moved)
        if self.now - self._last_reroute >= REROUTE_INTERVAL_S:
            self._last_reroute = self.now
            self._reroute_stale()
        waiting = any(i.status is IncidentStatus.NEW for i in self.world.incidents.values())
        due = self.now - self._last_replan >= REPLAN_INTERVAL_S
        if self._dirty or (due and (waiting or self.strategy == "jardem")):
            if self._open_incident_views():
                self.replan()
            else:
                self._dirty = False
                self._last_replan = self.now

    def _autopilot(self, unit: Unit) -> None:
        """Simulated crew: confirms, arrives and finishes on its own."""
        if unit.incident_id is None:
            return
        incident = self.world.incidents[unit.incident_id]
        if unit.status is UnitStatus.ASSIGNED:
            if self.now - unit.status_since >= TURNOUT_S:
                self.unit_action(unit.id, "accept")
        elif unit.status is UnitStatus.EN_ROUTE:
            if unit.route is None or unit.route.finished:
                self.unit_action(unit.id, "arrive")
        elif unit.status is UnitStatus.ON_SCENE and (
                self.now - unit.status_since >= self.on_scene_duration_s(incident)):
            self.unit_action(unit.id, "complete")
