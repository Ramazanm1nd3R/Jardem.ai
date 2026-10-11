from __future__ import annotations

import asyncio
import contextlib
import time
from dataclasses import asdict
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, WebSocket
from pydantic import BaseModel, Field
from starlette.websockets import WebSocketDisconnect

from app.api import serializers as ser
from app.domain.dispatch.planner import STRATEGIES
from app.domain.geo import haversine_m
from app.domain.models import (
    ACTIVE_INCIDENT,
    CATEGORY_BY_ID,
    DISPATCHABLE,
    SERVICE_PHONES,
    Service,
    TransitionError,
    UnitStatus,
)
from app.domain.routing import maneuvers
from app.domain.traffic import Hotspot, congestion_level
from app.domain.triage import triage
from app.engine.core import EngineError
from app.engine.seed import DEMO_UNIT_ID
from app.runtime import Runtime
from app.security import Principal, citizen_id, make_token, read_token

router = APIRouter(prefix="/api/v1")

Lat = Annotated[float, Query(ge=-90, le=90)]
Lon = Annotated[float, Query(ge=-180, le=180)]
ALMATY_CENTER = {"lat": 43.2445, "lon": 76.9457}


def rt(request: Request) -> Runtime:
    return request.app.state.runtime


Rt = Annotated[Runtime, Depends(rt)]


def principal(request: Request, authorization: Annotated[str | None, Header()] = None,
              ) -> Principal | None:
    if not authorization or not authorization.lower().startswith("bearer "):
        return None
    return read_token(authorization[7:], request.app.state.runtime.settings.jwt_secret)


def require(*roles: str):
    def dependency(who: Annotated[Principal | None, Depends(principal)]) -> Principal:
        if who is None:
            raise HTTPException(401, "authentication required")
        if who.role not in roles:
            raise HTTPException(403, "not allowed for this role")
        return who
    return dependency


Citizen = Annotated[Principal, Depends(require("citizen"))]
Responder = Annotated[Principal, Depends(require("responder"))]
Dispatcher = Annotated[Principal, Depends(require("dispatcher"))]
Staff = Annotated[Principal, Depends(require("responder", "dispatcher"))]


def guard(fn, *args, **kwargs):
    """Run an engine call, mapping domain errors to HTTP 4xx."""
    try:
        return fn(*args, **kwargs)
    except TransitionError as exc:
        raise HTTPException(409, str(exc)) from None
    except EngineError as exc:
        status = 404 if str(exc).startswith("unknown") else 409
        raise HTTPException(status, str(exc)) from None


# --- public ----------------------------------------------------------------------


@router.get("/health")
async def health(r: Rt) -> dict:
    return {"status": "ok", "uptime_s": round(time.time() - r.started_at),
            "database": r.db is not None, "redis": bool(r.settings.redis_url),
            "units": len(r.engine.world.units), "graph_nodes": len(r.engine.graph.nodes)}


@router.get("/meta")
async def meta(r: Rt) -> dict:
    lats = [p[0] for p in r.engine.graph.nodes]
    lons = [p[1] for p in r.engine.graph.nodes]
    return {
        "city": "Алматы", "center": ALMATY_CENTER,
        "bbox": [min(lats), min(lons), max(lats), max(lons)],
        "demo": True,
        "disclaimer": "Демонстрационная платформа. Экипажи и вызовы смоделированы. "
                      "В реальной экстренной ситуации звоните 112.",
        "emergency_phone": "112", "phones": {s.value: p for s, p in SERVICE_PHONES.items()},
        "strategy": r.engine.strategy, "strategies": list(STRATEGIES),
        "auto_dispatch": r.engine.auto_dispatch, "sim_speed": r.sim_speed,
        "app_url": r.settings.public_app_url,
    }


@router.get("/catalog")
async def get_catalog() -> list[dict]:
    return ser.catalog()


@router.get("/departments")
async def departments(r: Rt, service: Service | None = None, lat: Lat | None = None,
                      lon: Lon | None = None, limit: int = Query(100, ge=1, le=200)) -> list[dict]:
    world = r.engine.world
    counts: dict[str, list[int]] = {}
    for u in world.units.values():
        c = counts.setdefault(u.department_id, [0, 0])
        c[0] += u.status is not UnitStatus.OFF_DUTY
        c[1] += u.status in DISPATCHABLE
    if lat is not None and lon is not None:
        if r.db is not None:
            near = await r.db.departments_near(lat, lon, service.value if service else None, limit)
        else:
            pool = [d for d in world.departments.values() if service in (None, d.service)]
            near = sorted(((d.id, haversine_m(lat, lon, d.lat, d.lon)) for d in pool),
                          key=lambda x: x[1])[:limit]
        return [ser.department(world.departments[i], m, *counts.get(i, [0, 0])) for i, m in near]
    rows = [d for d in world.departments.values() if service in (None, d.service)]
    return [ser.department(d, None, *counts.get(d.id, [0, 0])) for d in rows[:limit]]


@router.get("/units")
async def units(r: Rt, service: Service | None = None, category: str | None = None,
                lat: Lat | None = None, lon: Lon | None = None,
                limit: int = Query(200, ge=1, le=500)) -> list[dict]:
    if category is not None and category not in CATEGORY_BY_ID:
        raise HTTPException(404, f"unknown category: {category}")
    if lat is not None and lon is not None:
        rows = r.engine.nearby_units(lat, lon, service=service, category=category, limit=limit)
        return [ser.unit_public(u, d, eta) for u, d, eta in rows]
    required = CATEGORY_BY_ID[category].required if category else frozenset()
    if category:
        service = CATEGORY_BY_ID[category].service
    return [ser.unit_public(u) for u in r.engine.world.units.values()
            if u.status is not UnitStatus.OFF_DUTY and service in (None, u.service)
            and required <= u.capabilities][:limit]


@router.get("/units/{unit_id}")
async def unit_detail(r: Rt, unit_id: str, lat: Lat | None = None, lon: Lon | None = None) -> dict:
    unit = r.engine.world.units.get(unit_id)
    if unit is None:
        raise HTTPException(404, "unknown unit")
    data = ser.unit_public(unit)
    dept = r.engine.world.departments.get(unit.department_id)
    data["department"] = ser.department(dept) if dept else None
    if lat is not None and lon is not None:
        found = r.engine.eta.route((unit.lat, unit.lon), (lat, lon), r.engine.now)
        if found is not None:
            route, _ = found
            data.update(distance_m=round(route.distance_m), eta_s=round(route.duration_s),
                        route=ser.line(route.geometry))
    return data


@router.get("/route")
async def route(r: Rt, from_lat: Lat, from_lon: Lon, to_lat: Lat, to_lon: Lon,
                profile: Literal["emergency", "car"] = "emergency") -> dict:
    engine = r.engine
    found = engine.eta.route((from_lat, from_lon), (to_lat, to_lon), engine.now, profile)
    if found is None:
        raise HTTPException(404, "no route between these points")
    path, _ = found
    factors = engine.traffic.snapshot(engine.now).factors
    # Consecutive edges with the same congestion level merge into one coloured section.
    sections: list[dict] = []
    for eid in path.edges:
        edge = engine.graph.edges[eid]
        level = congestion_level(factors[eid]).value
        if sections and sections[-1]["level"] == level:
            sections[-1]["geometry"].extend(ser.line(edge.shape[1:]))
        else:
            sections.append({"level": level, "geometry": ser.line(edge.shape)})
    free = sum(engine.graph.edges[e].free_time_s for e in path.edges)
    return {
        "distance_m": round(path.distance_m), "duration_s": round(path.duration_s),
        "free_flow_s": round(free), "profile": profile, "geometry": ser.line(path.geometry),
        "sections": sections,
        "maneuvers": [{"kind": m.kind, "text": ser.MANEUVER_TEXT[m.kind], "street": m.street,
                       "at_m": round(m.distance_m), "lat": m.location[0], "lon": m.location[1]}
                      for m in maneuvers(engine.graph, path)],
    }


@router.get("/traffic")
async def traffic(r: Rt, bbox: str | None = None, include_free: bool = False) -> dict:
    box = None
    if bbox:
        try:
            box = tuple(float(x) for x in bbox.split(","))
            assert len(box) == 4
        except (ValueError, AssertionError):
            raise HTTPException(422, "bbox must be min_lat,min_lon,max_lat,max_lon") from None
    engine = r.engine
    model = engine.traffic
    return {
        "simulated": True,
        "index": model.city_index(engine.now),
        "local_hour": round(model.local_hour(engine.now), 2),
        "hotspots": [{"id": h.id, "lat": h.lat, "lon": h.lon, "radius_m": round(h.radius_m),
                      "severity": round(h.severity, 2), "kind": h.kind} for h in model.hotspots],
        "closures": [{"id": c.id, "lat": c.lat, "lon": c.lon, "reason": c.reason}
                     for c in model.closures],
        "segments": {
            "type": "FeatureCollection",
            "features": [
                {"type": "Feature",
                 "properties": {"level": s["level"], "speed_kph": s["speed_kph"],
                                "name": s["name"]},
                 "geometry": {"type": "LineString", "coordinates": s["geometry"]}}
                for s in model.segments(engine.now, box, include_free)],
        },
    }


class TriageIn(BaseModel):
    text: str = Field(max_length=2000)


@router.post("/triage")
async def triage_text(body: TriageIn) -> dict:
    result = triage(body.text)
    data = asdict(result)
    data["priority"] = None if result.priority is None else int(result.priority)
    data["service"] = None if result.service is None else result.service.value
    data["category_title"] = (CATEGORY_BY_ID[result.category].title if result.category else None)
    return data


class CompareIn(BaseModel):
    category: str
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


@router.post("/dispatch/compare")
async def compare(r: Rt, body: CompareIn) -> dict:
    result = guard(r.engine.compare, body.category, body.lat, body.lon)
    world = r.engine.world
    return {
        "picks": result["picks"],
        "candidates": [
            {**ser.unit_public(world.units[c.unit_id], c.distance_m, c.eta_s),
             "coverage_loss_s": round(c.coverage_loss_s), "overqualified": c.overqualified,
             "cost": round(c.cost)}
            for c in result["candidates"][:8]],
    }


@router.get("/stats")
async def stats(r: Rt) -> dict:
    world = r.engine.world
    services = {s.value: {"active_incidents": 0, "units": 0, "units_free": 0} for s in Service}
    for i in world.incidents.values():
        if i.status in ACTIVE_INCIDENT:
            services[i.service.value]["active_incidents"] += 1
    for u in world.units.values():
        if u.status is UnitStatus.OFF_DUTY:
            continue
        services[u.service.value]["units"] += 1
        services[u.service.value]["units_free"] += u.status in DISPATCHABLE
    arrivals = [i.first_arrival_s for i in world.incidents.values() if i.first_arrival_s]
    return {
        "services": services,
        "active_incidents": sum(s["active_incidents"] for s in services.values()),
        "departments": len(world.departments),
        "mean_arrival_s": round(sum(arrivals) / len(arrivals)) if arrivals else None,
        "served": len(arrivals),
        "traffic_index": r.engine.traffic.city_index(r.engine.now),
        "strategy": r.engine.strategy,
    }


# --- auth ------------------------------------------------------------------------


class CitizenLogin(BaseModel):
    phone: str = Field(min_length=5, max_length=24)
    name: str = Field(default="", max_length=80)


class StaffLogin(BaseModel):
    login: str = Field(min_length=1, max_length=40)
    pin: str = Field(min_length=1, max_length=16)


def _session(r: Runtime, who: Principal) -> dict:
    return {"token": make_token(who, r.settings.jwt_secret),
            "user": {"id": who.sub, "role": who.role, "name": who.name, "phone": who.phone,
                     "unit_id": who.unit_id}}


@router.post("/auth/citizen")
async def auth_citizen(r: Rt, body: CitizenLogin) -> dict:
    digits = [ch for ch in body.phone if ch.isdigit()]
    if len(digits) < 10:
        raise HTTPException(422, "phone number is too short")
    return _session(r, Principal("citizen", citizen_id(body.phone), body.name.strip(),
                                 body.phone.strip()))


@router.post("/auth/responder")
async def auth_responder(r: Rt, body: StaffLogin) -> dict:
    if body.pin != r.settings.demo_pin:
        raise HTTPException(401, "wrong login or PIN")
    login = body.login.strip().lower()
    unit_id = DEMO_UNIT_ID if login in ("smp7", "demo") else login
    unit = r.engine.world.units.get(unit_id)
    if unit is None:
        raise HTTPException(401, "wrong login or PIN")
    lead = next((c for c in unit.crew if c.lead), None)
    who = Principal("responder", unit.controlled_by or f"resp-{unit.id}",
                    lead.name if lead else unit.callsign, lead.phone if lead else "", unit.id)
    unit.controlled_by = who.sub
    return _session(r, who)


@router.post("/auth/logout")
async def auth_logout(r: Rt, who: Annotated[Principal, Depends(require("citizen", "responder",
                                                                       "dispatcher"))]) -> dict:
    """End a crew session: a simulated unit goes back to the simulator and onto the line.

    Without this a unit someone signed in as would wait for manual confirmations forever.
    The demo crew «СМП №7» is always human-driven and simply stays as it is.
    """
    unit = r.engine.world.units.get(who.unit_id or "")
    if who.role == "responder" and unit is not None and unit.id != DEMO_UNIT_ID:
        unit.controlled_by = None
        if unit.status is UnitStatus.OFF_DUTY:
            guard(r.engine.set_shift, unit.id, True)
        await r.flush()
    return {"ok": True}


@router.post("/auth/dispatcher")
async def auth_dispatcher(r: Rt, body: StaffLogin) -> dict:
    if body.login.strip().lower() != "dispatcher" or body.pin != r.settings.demo_pin:
        raise HTTPException(401, "wrong login or PIN")
    return _session(r, Principal("dispatcher", "disp-1", "Диспетчер"))


@router.get("/auth/me")
async def me(who: Annotated[Principal, Depends(require("citizen", "responder", "dispatcher"))],
             ) -> dict:
    return {"id": who.sub, "role": who.role, "name": who.name, "phone": who.phone,
            "unit_id": who.unit_id}


# --- citizen ---------------------------------------------------------------------


class IncidentIn(BaseModel):
    category: str
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    address: str = Field(default="", max_length=200)
    description: str = Field(default="", max_length=2000)
    phone: str = Field(default="", max_length=24)


def _in_service_area(r: Runtime, lat: float, lon: float) -> bool:
    node = r.engine.graph.nearest_node(lat, lon)
    return haversine_m(lat, lon, *r.engine.graph.nodes[node]) <= 1500


@router.post("/incidents", status_code=201)
async def create_incident(r: Rt, who: Citizen, body: IncidentIn) -> dict:
    if not _in_service_area(r, body.lat, body.lon):
        raise HTTPException(422, "the location is outside the Almaty service area")
    mine_open = [i for i in r.engine.world.incidents.values()
                 if i.citizen_id == who.sub and i.status in ACTIVE_INCIDENT]
    if len(mine_open) >= 3:
        raise HTTPException(429, "too many open calls for this account")
    incident = guard(r.engine.create_incident, body.category, body.lat, body.lon,
                     description=body.description, address=body.address, citizen_id=who.sub,
                     caller_name=who.name, caller_phone=body.phone or who.phone)
    await r.flush()
    return ser.incident_public(r.engine, incident, private=True)


def _own(r: Runtime, who: Principal, incident_id: str):
    incident = r.engine.world.incidents.get(incident_id)
    if incident is None:
        raise HTTPException(404, "unknown incident")
    allowed = (who.role == "dispatcher" or incident.citizen_id == who.sub
               or (who.unit_id is not None and who.unit_id in incident.unit_ids + incident.served_by))
    if not allowed:
        raise HTTPException(403, "not your incident")
    return incident


AnyUser = Annotated[Principal, Depends(require("citizen", "responder", "dispatcher"))]


@router.get("/incidents")
async def my_incidents(r: Rt, who: Citizen) -> dict:
    mine = sorted((i for i in r.engine.world.incidents.values() if i.citizen_id == who.sub),
                  key=lambda i: i.created_wall, reverse=True)
    active = [ser.incident_public(r.engine, i, private=True) for i in mine
              if i.status in ACTIVE_INCIDENT]
    history = [ser.incident_public(r.engine, i, private=True) for i in mine
               if i.status not in ACTIVE_INCIDENT]
    if r.db is not None:
        known = {h["id"] for h in history}
        for row in await r.db.history(citizen_id=who.sub):
            if row["id"] not in known:
                history.append(_history_row(row))
    return {"active": active, "history": history}


def _history_row(row: dict) -> dict:
    cat = CATEGORY_BY_ID.get(row["category"])
    return {
        "id": row["id"], "number": row["number"], "service": row["service"],
        "category": row["category"], "category_title": cat.title if cat else row["category"],
        "priority": row["priority"], "status": row["status"], "address": row["address"],
        "description": row["description"], "lat": row["lat"], "lon": row["lon"],
        "created_at": row["created_at"].isoformat(),
        "closed_at": row["closed_at"].isoformat() if row["closed_at"] else None,
        "first_arrival_s": None if row["first_arrival_s"] is None else round(row["first_arrival_s"]),
        "units": [], "timeline": [],
    }


@router.get("/incidents/{incident_id}")
async def incident_detail(r: Rt, who: AnyUser, incident_id: str) -> dict:
    return ser.incident_public(r.engine, _own(r, who, incident_id), private=True)


@router.post("/incidents/{incident_id}/cancel")
async def cancel_incident(r: Rt, who: AnyUser, incident_id: str) -> dict:
    incident = _own(r, who, incident_id)
    if who.role == "responder":
        raise HTTPException(403, "crews cannot cancel a call")
    guard(r.engine.cancel_incident, incident.id)
    await r.flush()
    return ser.incident_public(r.engine, incident, private=True)


# --- responder -------------------------------------------------------------------


def _my_unit(r: Runtime, who: Principal):
    unit = r.engine.world.units.get(who.unit_id or "")
    if unit is None:
        raise HTTPException(404, "no unit bound to this account")
    return unit


def _responder_state(r: Runtime, who: Principal) -> dict:
    unit = _my_unit(r, who)
    engine = r.engine
    incident = engine.world.incidents.get(unit.incident_id or "")
    assignment = None
    if incident is not None:
        assignment = ser.incident_public(engine, incident, private=True)
        eta = engine.unit_eta_s(unit)
        assignment["my"] = {
            "eta_s": None if eta is None else round(eta),
            "distance_m": (None if unit.route is None
                           else round(unit.route.distance_m - unit.route.travelled_m)),
            "route": ser.line(engine.remaining_geometry(unit)),
            "maneuvers": ser.maneuver_list(unit),
        }
    world = engine.world
    same_service = [i for i in world.incidents.values()
                    if i.service is unit.service and i.status in ACTIVE_INCIDENT]
    return {
        "unit": ser.responder_unit(engine, unit),
        "assignment": assignment,
        "counters": {
            "active": len(same_service),
            "en_route": sum(1 for i in same_service if i.status.value == "en_route"),
            "on_scene": sum(1 for i in same_service if i.status.value == "on_scene"),
        },
        "unread": sum(1 for m in world.messages
                      if m.unit_id == unit.id and m.sender == "dispatcher"),
    }


@router.get("/responder/me")
async def responder_me(r: Rt, who: Responder) -> dict:
    return _responder_state(r, who)


class ShiftIn(BaseModel):
    on_duty: bool


@router.post("/responder/shift")
async def responder_shift(r: Rt, who: Responder, body: ShiftIn) -> dict:
    guard(r.engine.set_shift, _my_unit(r, who).id, body.on_duty)
    await r.flush()
    return _responder_state(r, who)


class ActionIn(BaseModel):
    action: Literal["accept", "arrive", "transport", "complete"]


@router.post("/responder/action")
async def responder_action(r: Rt, who: Responder, body: ActionIn) -> dict:
    guard(r.engine.unit_action, _my_unit(r, who).id, body.action)
    await r.flush()
    return _responder_state(r, who)


class LocationIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    speed_mps: float | None = Field(default=None, ge=0, le=70)


@router.post("/responder/location")
async def responder_location(r: Rt, who: Responder, body: LocationIn) -> dict:
    unit = guard(r.engine.update_location, _my_unit(r, who).id, body.lat, body.lon, body.speed_mps)
    await r.flush()
    return ser.unit_brief(unit)


@router.get("/responder/messages")
async def responder_messages(r: Rt, who: Responder) -> list[dict]:
    unit = _my_unit(r, who)
    return [ser.message(m) for m in r.engine.world.messages if m.unit_id == unit.id][-100:]


class MessageIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)


@router.post("/responder/messages", status_code=201)
async def responder_send(r: Rt, who: Responder, body: MessageIn) -> dict:
    unit = _my_unit(r, who)
    message = r.engine.post_message(unit.id, "unit", who.name or unit.callsign, body.text)
    await r.flush()
    return ser.message(message)


@router.get("/responder/history")
async def responder_history(r: Rt, who: Responder) -> list[dict]:
    unit = _my_unit(r, who)
    rows = [ser.incident_public(r.engine, i, private=True)
            for i in r.engine.world.incidents.values()
            if unit.id in i.served_by and i.status not in ACTIVE_INCIDENT]
    if r.db is not None:
        known = {h["id"] for h in rows}
        rows.extend(_history_row(row) for row in await r.db.history(unit_id=unit.id)
                    if row["id"] not in known)
    rows.sort(key=lambda h: h["created_at"], reverse=True)
    return rows


class ClosureIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    reason: str = Field(default="", max_length=120)
    minutes: int = Field(default=30, ge=1, le=240)


@router.post("/traffic/closures", status_code=201)
async def report_closure(r: Rt, who: Staff, body: ClosureIn) -> dict:
    engine = r.engine
    closure_id = f"cl-{int(engine.now * 1000) % 10**9}"
    closure = engine.traffic.close_road(closure_id, body.lat, body.lon, 25.0,
                                        engine.now + body.minutes * 60, body.reason)
    engine.outbox.append({"type": "traffic.updated"})
    await r.flush()
    return {"id": closure.id, "edges": len(closure.edge_ids), "reported_by": who.sub}


@router.delete("/traffic/closures/{closure_id}")
async def reopen(r: Rt, who: Staff, closure_id: str) -> dict:
    if not r.engine.traffic.reopen_road(closure_id):
        raise HTTPException(404, "unknown closure")
    r.engine.outbox.append({"type": "traffic.updated"})
    await r.flush()
    return {"ok": True}


# --- dispatcher ------------------------------------------------------------------


class HotspotIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    radius_m: float = Field(default=400, gt=20, le=3000)
    severity: float = Field(default=0.7, gt=0, le=1)
    minutes: int = Field(default=20, ge=1, le=240)
    kind: Literal["jam", "accident", "roadworks"] = "jam"


@router.post("/traffic/hotspots", status_code=201)
async def add_hotspot(r: Rt, who: Dispatcher, body: HotspotIn) -> dict:
    engine = r.engine
    hotspot = Hotspot(f"hs-{int(engine.now * 1000) % 10**9}", body.lat, body.lon, body.radius_m,
                      body.severity, engine.now + body.minutes * 60, body.kind)
    engine.traffic.add_hotspot(hotspot)
    engine.outbox.append({"type": "traffic.updated"})
    await r.flush()
    return {"id": hotspot.id}


@router.get("/dispatch/overview")
async def overview(r: Rt, who: Dispatcher) -> dict:
    engine = r.engine
    active = sorted((i for i in engine.world.incidents.values() if i.status in ACTIVE_INCIDENT),
                    key=lambda i: (i.priority, i.created_at))
    return {
        "incidents": [ser.incident_public(engine, i, private=True) for i in active],
        "units": [ser.unit_public(u) for u in engine.world.units.values()],
        "proposals": engine.proposals,
        "strategy": engine.strategy, "auto_dispatch": engine.auto_dispatch,
    }


class AssignIn(BaseModel):
    incident_id: str
    unit_id: str


@router.post("/dispatch/assign")
async def dispatch_assign(r: Rt, who: Dispatcher, body: AssignIn) -> dict:
    guard(r.engine.assign, body.incident_id, body.unit_id)
    await r.flush()
    return ser.incident_public(r.engine, r.engine.world.incidents[body.incident_id], private=True)


class SettingsIn(BaseModel):
    strategy: Literal["nearest", "min_eta", "jardem"] | None = None
    auto_dispatch: bool | None = None
    sim_speed: float | None = Field(default=None, ge=0.1, le=30)
    calls_per_hour: float | None = Field(default=None, ge=0, le=600)
    hotspots: int | None = Field(default=None, ge=0, le=40)


@router.post("/dispatch/settings")
async def dispatch_settings(r: Rt, who: Dispatcher, body: SettingsIn) -> dict:
    if body.strategy is not None:
        r.engine.strategy = body.strategy
    if body.auto_dispatch is not None:
        r.engine.auto_dispatch = body.auto_dispatch
    if body.sim_speed is not None:
        r.sim_speed = body.sim_speed
    if body.calls_per_hour is not None:
        r.ambient.calls_per_hour = body.calls_per_hour
    if body.hotspots is not None:
        r.ambient.max_hotspots = body.hotspots
    return {"strategy": r.engine.strategy, "auto_dispatch": r.engine.auto_dispatch,
            "sim_speed": r.sim_speed, "calls_per_hour": r.ambient.calls_per_hour,
            "hotspots": r.ambient.max_hotspots}


class DispatchMessageIn(BaseModel):
    unit_id: str
    text: str = Field(min_length=1, max_length=500)


@router.post("/dispatch/messages", status_code=201)
async def dispatch_message(r: Rt, who: Dispatcher, body: DispatchMessageIn) -> dict:
    message = guard(r.engine.post_message, body.unit_id, "dispatcher", who.name, body.text)
    await r.flush()
    return ser.message(message)


# --- realtime --------------------------------------------------------------------


@router.websocket("/ws")
async def ws(websocket: WebSocket) -> None:
    """Light change notifications; clients re-fetch details over REST."""
    runtime: Runtime = websocket.app.state.runtime
    await websocket.accept()
    queue = runtime.bus.subscribe()

    async def pump() -> None:
        while True:
            await websocket.send_text(await queue.get())

    sender = asyncio.create_task(pump())
    try:
        await websocket.send_json({"type": "hello", "server_time": time.time()})
        while True:
            # Clients only send keep-alives; reading detects disconnects.
            await websocket.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        sender.cancel()
        with contextlib.suppress(asyncio.CancelledError, Exception):
            await sender
        runtime.bus.unsubscribe(queue)

