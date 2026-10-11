"""Engine state -> JSON for clients. Geometries are GeoJSON-ordered [lon, lat]."""

from __future__ import annotations

from datetime import UTC, datetime

from app.domain.models import (
    CATEGORY_BY_ID,
    DISPATCHABLE,
    SERVICE_PHONES,
    SERVICE_TITLES,
    Service,
    UnitStatus,
    categories_for,
)
from app.engine.core import Engine
from app.engine.world import Department, Incident, Message, Unit

UNIT_STATUS_LABEL = {
    UnitStatus.OFF_DUTY: "Не на смене",
    UnitStatus.AVAILABLE: "Свободен",
    UnitStatus.ASSIGNED: "Назначен",
    UnitStatus.EN_ROUTE: "В пути",
    UnitStatus.ON_SCENE: "На месте",
    UnitStatus.TRANSPORTING: "Транспортировка",
    UnitStatus.RETURNING: "Возвращается",
}
PHOTO_BY_KIND = {
    (Service.AMBULANCE, "linear"): "ambulance_kz_1",
    (Service.AMBULANCE, "pediatric"): "ambulance_kz_2",
    (Service.AMBULANCE, "reanimation"): "ambulance_kz_reanimation",
    (Service.POLICE, "patrol"): "police_kz_1",
    (Service.FIRE, "engine"): "fire_kz_1",
    (Service.FIRE, "forest"): "fire_kz_2",
}
PHOTO_BY_SERVICE = {Service.AMBULANCE: "ambulance_kz_1", Service.POLICE: "police_kz_2",
                    Service.FIRE: "fire_kz_1", Service.RESCUE: "rescue_kz_1"}
MANEUVER_TEXT = {"depart": "Начните движение", "left": "Поверните налево",
                 "right": "Поверните направо", "slight_left": "Держитесь левее",
                 "slight_right": "Держитесь правее", "uturn": "Развернитесь",
                 "arrive": "Вы на месте"}


def iso(wall: float | None) -> str | None:
    return None if wall is None else datetime.fromtimestamp(wall, UTC).isoformat()


def line(points) -> list[list[float]]:
    return [[round(lon, 5), round(lat, 5)] for lat, lon in points]


def catalog() -> list[dict]:
    return [
        {"id": s.value, "title": SERVICE_TITLES[s], "phone": SERVICE_PHONES[s],
         "categories": [
             {"id": c.id, "title": c.title, "description": c.description,
              "priority": int(c.priority), "units_required": c.units_required}
             for c in categories_for(s)]}
        for s in Service
    ]


def department(d: Department, distance_m: float | None = None, units: int = 0,
               free: int = 0) -> dict:
    return {"id": d.id, "service": d.service.value, "name": d.name, "address": d.address,
            "lat": d.lat, "lon": d.lon, "approximate": d.approximate,
            "distance_m": None if distance_m is None else round(distance_m),
            "units": units, "units_free": free}


def unit_brief(u: Unit) -> dict:
    return {"id": u.id, "service": u.service.value, "kind": u.kind, "status": u.status.value,
            "lat": round(u.lat, 6), "lon": round(u.lon, 6), "heading": round(u.heading)}


def unit_public(u: Unit, distance_m: float | None = None, eta_s: float | None = None) -> dict:
    return {
        **unit_brief(u), "name": u.name, "callsign": u.callsign,
        "department_id": u.department_id, "status_label": UNIT_STATUS_LABEL[u.status],
        "free": u.status in DISPATCHABLE, "plate": u.plate, "vehicle": u.vehicle,
        "photo": PHOTO_BY_KIND.get((u.service, u.kind), PHOTO_BY_SERVICE[u.service]),
        "capabilities": sorted(u.capabilities),
        "distance_m": None if distance_m is None else round(distance_m),
        "eta_s": None if eta_s is None else round(eta_s),
    }


def unit_on_incident(engine: Engine, u: Unit) -> dict:
    eta = engine.unit_eta_s(u)
    route = u.route
    return {
        **unit_public(u, eta_s=eta),
        "distance_m": None if route is None else round(route.distance_m - route.travelled_m),
        "route": line(engine.remaining_geometry(u)),
        "lead": next((c.name for c in u.crew if c.lead), ""),
    }


def incident_public(engine: Engine, i: Incident, *, private: bool = False) -> dict:
    cat = CATEGORY_BY_ID[i.category]
    units = [unit_on_incident(engine, u) for u in engine.world.units_of(i)]
    etas = [u["eta_s"] for u in units if u["eta_s"] is not None]
    data = {
        "id": i.id, "number": i.number, "service": i.service.value, "category": i.category,
        "category_title": cat.title, "service_title": SERVICE_TITLES[i.service],
        "priority": int(i.priority), "status": i.status.value, "lat": i.lat, "lon": i.lon,
        "address": i.address, "created_at": iso(i.created_wall), "closed_at": iso(i.closed_wall),
        "timeline": [{"status": t.status, "at": iso(t.at)} for t in i.timeline],
        "units": units, "units_required": i.units_required,
        "eta_s": min(etas) if etas else None,
        "first_arrival_s": None if i.first_arrival_s is None else round(i.first_arrival_s),
        "synthetic": i.synthetic,
    }
    if private:
        data.update(description=i.description, caller_name=i.caller_name,
                    caller_phone=i.caller_phone, extra_info=i.extra_info, triage=i.triage)
    return data


def maneuver_list(u: Unit) -> list[dict]:
    route = u.route
    if route is None:
        return []
    return [
        {"kind": m.kind, "text": MANEUVER_TEXT[m.kind], "street": m.street,
         "in_m": round(m.distance_m - route.travelled_m), "lat": m.location[0],
         "lon": m.location[1]}
        for m in route.maneuvers if m.distance_m >= route.travelled_m or m.kind == "arrive"
    ]


def responder_unit(engine: Engine, u: Unit) -> dict:
    dept = engine.world.departments.get(u.department_id)
    return {
        **unit_public(u),
        "department": dept.name if dept else "", "fuel_pct": u.fuel_pct,
        "crew": [{"id": c.id, "name": c.name, "role": c.role, "phone": c.phone,
                  "lead": c.lead, "online": True} for c in u.crew],
        "equipment": u.equipment,
        "shift_started_at": iso(u.shift_started_at),
        "status_since_s": round(engine.now - u.status_since),
        "incident_id": u.incident_id,
    }


def message(m: Message) -> dict:
    return {"id": m.id, "unit_id": m.unit_id, "sender": m.sender, "author": m.author,
            "text": m.text, "at": iso(m.at)}
