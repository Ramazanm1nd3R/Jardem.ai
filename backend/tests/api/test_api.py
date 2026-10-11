import asyncio

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

HOME = {"lat": 43.2445, "lon": 76.9457}


@pytest.fixture
def client(almaty):
    settings = Settings(database_url="", redis_url="", jwt_secret="test-secret", demo_pin="4321")
    app = create_app(settings, graph=almaty, run_loop=False)
    with TestClient(app) as c:
        c.runtime = app.state.runtime
        yield c


def advance(client, seconds, step=2.0):
    runtime = client.runtime
    for _ in range(int(seconds / step)):
        runtime.engine.tick(step)
    asyncio.run(runtime.flush())


def citizen(client, phone="+7 777 123 45 67"):
    r = client.post("/api/v1/auth/citizen", json={"phone": phone, "name": "Айдос"})
    assert r.status_code == 200
    return {"Authorization": f"Bearer {r.json()['token']}"}


def responder(client, login="smp7", pin="4321"):
    r = client.post("/api/v1/auth/responder", json={"login": login, "pin": pin})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def test_health_meta_catalog(client):
    health = client.get("/api/v1/health").json()
    assert health["status"] == "ok" and health["units"] == 121 and not health["database"]
    meta = client.get("/api/v1/meta").json()
    assert meta["demo"] is True and "112" in meta["disclaimer"]
    assert meta["phones"] == {"ambulance": "103", "police": "102", "fire": "101", "rescue": "112"}
    assert meta["bbox"][0] < HOME["lat"] < meta["bbox"][2]
    catalog = client.get("/api/v1/catalog").json()
    assert [s["id"] for s in catalog] == ["ambulance", "police", "fire", "rescue"]
    assert [c["title"] for c in catalog[0]["categories"]] == [
        "Экстренная помощь", "Плановая помощь", "Детская скорая", "Реанимация"]


def test_departments_listing_and_nearest(client):
    everything = client.get("/api/v1/departments").json()
    assert len(everything) == 44
    fire = client.get("/api/v1/departments", params={"service": "fire"}).json()
    assert len(fire) == 15 and all(d["service"] == "fire" and d["units"] >= 2 for d in fire)
    near = client.get("/api/v1/departments", params={**HOME, "limit": 5}).json()
    assert len(near) == 5
    assert [d["distance_m"] for d in near] == sorted(d["distance_m"] for d in near)
    assert near[0]["distance_m"] < 1500
    assert client.get("/api/v1/departments", params={"service": "pizza"}).status_code == 422


def test_units_near_point_with_eta(client):
    rows = client.get("/api/v1/units", params={**HOME, "service": "ambulance", "limit": 3}).json()
    assert len(rows) == 3
    assert all(u["service"] == "ambulance" and u["free"] for u in rows)
    assert rows[0]["eta_s"] <= rows[1]["eta_s"] <= rows[2]["eta_s"]
    assert rows[0]["distance_m"] > 0 and rows[0]["photo"].startswith("ambulance_kz")
    pediatric = client.get("/api/v1/units", params={**HOME, "category": "pediatric"}).json()
    assert pediatric and all("pediatric" in u["capabilities"] for u in pediatric)
    assert client.get("/api/v1/units", params={"category": "pizza"}).status_code == 404
    # The demo crew is off duty until it signs in, so it is not offered to citizens.
    assert "ambulance-7-1" not in {u["id"] for u in client.get("/api/v1/units").json()}
    one = client.get(f"/api/v1/units/{rows[0]['id']}", params=HOME).json()
    assert one["eta_s"] > 0 and len(one["route"]) >= 2 and one["department"]["name"]
    assert client.get("/api/v1/units/ghost").status_code == 404


def test_route_and_traffic(client):
    params = {"from_lat": 43.2567, "from_lon": 76.9286, "to_lat": 43.2220, "to_lon": 76.8510}
    emergency = client.get("/api/v1/route", params=params).json()
    car = client.get("/api/v1/route", params={**params, "profile": "car"}).json()
    assert 7000 < emergency["distance_m"] < 16000
    assert emergency["duration_s"] < car["duration_s"]
    assert emergency["maneuvers"][0]["kind"] == "depart"
    assert emergency["maneuvers"][-1]["kind"] == "arrive"
    assert sum(len(s["geometry"]) for s in emergency["sections"]) >= len(emergency["geometry"])
    assert {s["level"] for s in car["sections"]} <= {"free", "slow", "jam", "heavy"}
    assert client.get("/api/v1/route", params={**params, "profile": "bike"}).status_code == 422

    token = client.post("/api/v1/auth/dispatcher", json={"login": "dispatcher", "pin": "4321"})
    disp = {"Authorization": f"Bearer {token.json()['token']}"}
    made = client.post("/api/v1/traffic/hotspots", headers=disp,
                       json={"lat": 43.2400, "lon": 76.9000, "radius_m": 900, "severity": 0.9})
    assert made.status_code == 201
    traffic = client.get("/api/v1/traffic").json()
    assert traffic["simulated"] is True and len(traffic["hotspots"]) == 1
    features = traffic["segments"]["features"]
    assert features and {f["properties"]["level"] for f in features} & {"jam", "heavy"}
    boxed = client.get("/api/v1/traffic", params={"bbox": "43.0,76.0,43.01,76.01"}).json()
    assert boxed["segments"]["features"] == []
    assert client.get("/api/v1/traffic", params={"bbox": "1,2,3"}).status_code == 422
    assert client.post("/api/v1/traffic/hotspots", json={"lat": 43.24, "lon": 76.9}).status_code == 401


def test_triage_endpoint(client):
    data = client.post("/api/v1/triage", json={"text": "Горит квартира, внутри люди"}).json()
    assert (data["service"], data["category"], data["priority"]) == ("fire", "fire_engine", 1)
    assert data["category_title"] == "Пожарные части" and data["people_inside"] is True
    empty = client.post("/api/v1/triage", json={"text": "привет"}).json()
    assert empty["service"] is None and "what_happened" in empty["missing"]


def test_compare_endpoint(client):
    data = client.post("/api/v1/dispatch/compare", json={"category": "emergency", **HOME}).json()
    assert set(data["picks"]) == {"nearest", "min_eta", "jardem"}
    assert all(len(v) == 1 for v in data["picks"].values())
    assert data["candidates"][0]["cost"] <= data["candidates"][1]["cost"]
    assert client.post("/api/v1/dispatch/compare",
                       json={"category": "pizza", **HOME}).status_code == 404


def test_auth_rules(client):
    assert client.post("/api/v1/auth/citizen", json={"phone": "12345"}).status_code == 422
    assert client.post("/api/v1/auth/responder", json={"login": "smp7", "pin": "0"}).status_code == 401
    assert client.post("/api/v1/auth/responder", json={"login": "ghost", "pin": "4321"}).status_code == 401
    assert client.post("/api/v1/auth/dispatcher", json={"login": "x", "pin": "4321"}).status_code == 401
    assert client.get("/api/v1/incidents").status_code == 401
    assert client.get("/api/v1/incidents", headers={"Authorization": "Bearer junk"}).status_code == 401
    assert client.get("/api/v1/responder/me", headers=citizen(client)).status_code == 403
    me = client.get("/api/v1/auth/me", headers=citizen(client)).json()
    assert me["role"] == "citizen" and me["name"] == "Айдос" and me["id"].startswith("cit-")
    same = client.get("/api/v1/auth/me", headers=citizen(client, "8 (777) 123-45-67")).json()
    other = client.get("/api/v1/auth/me", headers=citizen(client, "+7 777 123 45 67")).json()
    assert other["id"] == me["id"] and same["id"] != me["id"]


def test_citizen_call_end_to_end(client):
    auth = citizen(client)
    made = client.post("/api/v1/incidents", headers=auth, json={
        "category": "emergency", **HOME, "address": "ул. Назарбаева, 125",
        "description": "Мужчина потерял сознание, не дышит"})
    assert made.status_code == 201, made.text
    inc = made.json()
    assert inc["status"] == "assigned" and inc["priority"] == 1 and inc["number"] == 45821
    assert len(inc["units"]) == 1 and inc["eta_s"] > 0 and len(inc["units"][0]["route"]) > 2
    assert inc["triage"]["life_threat"] is True and inc["caller_name"] == "Айдос"
    first_eta = inc["eta_s"]

    stranger = citizen(client, "+7 701 000 00 00")
    assert client.get(f"/api/v1/incidents/{inc['id']}", headers=stranger).status_code == 403
    assert client.get("/api/v1/incidents/inc-1", headers=auth).status_code == 404

    advance(client, 60)
    moving = client.get(f"/api/v1/incidents/{inc['id']}", headers=auth).json()
    assert moving["status"] == "en_route" and moving["eta_s"] < first_eta
    advance(client, first_eta + 30)
    there = client.get(f"/api/v1/incidents/{inc['id']}", headers=auth).json()
    assert there["status"] == "on_scene" and there["first_arrival_s"] > 0
    assert [t["status"] for t in there["timeline"]] == ["new", "assigned", "en_route", "on_scene"]
    assert client.post(f"/api/v1/incidents/{inc['id']}/cancel", headers=auth).status_code == 409
    advance(client, 900)
    mine = client.get("/api/v1/incidents", headers=auth).json()
    assert mine["active"] == [] and [h["status"] for h in mine["history"]] == ["resolved"]
    stats = client.get("/api/v1/stats").json()
    assert stats["served"] == 1 and stats["active_incidents"] == 0


def test_citizen_limits_and_cancel(client):
    auth = citizen(client)
    far = client.post("/api/v1/incidents", headers=auth,
                      json={"category": "emergency", "lat": 51.1, "lon": 71.4})
    assert far.status_code == 422
    assert client.post("/api/v1/incidents", headers=auth,
                       json={"category": "pizza", **HOME}).status_code == 404
    ids = [client.post("/api/v1/incidents", headers=auth,
                       json={"category": "patrol", **HOME}).json()["id"] for _ in range(3)]
    assert client.post("/api/v1/incidents", headers=auth,
                       json={"category": "patrol", **HOME}).status_code == 429
    cancelled = client.post(f"/api/v1/incidents/{ids[0]}/cancel", headers=auth).json()
    assert cancelled["status"] == "cancelled" and cancelled["units"] == []
    assert client.post("/api/v1/incidents", headers=auth,
                       json={"category": "patrol", **HOME}).status_code == 201


def test_responder_flow_with_realtime_events(client):
    auth = responder(client)
    state = client.get("/api/v1/responder/me", headers=auth).json()
    unit = state["unit"]
    assert unit["callsign"] == "СМП №7" and unit["status"] == "off_duty"
    assert [c["name"] for c in unit["crew"]] == ["Алексей Иванов", "Мария Петрова", "Сергей Ким"]
    assert unit["plate"] == "402 AR 02" and len(unit["equipment"]) == 6
    assert state["assignment"] is None

    with client.websocket_connect("/api/v1/ws") as ws:
        assert ws.receive_json()["type"] == "hello"
        on = client.post("/api/v1/responder/shift", headers=auth, json={"on_duty": True}).json()
        assert on["unit"]["status"] == "available" and on["unit"]["shift_started_at"]
        assert ws.receive_json() == {
            "type": "unit.updated", "incident_id": None,
            "unit": {k: on["unit"][k] for k in ("id", "service", "kind", "status", "lat", "lon",
                                                "heading")}}

        # A call right next to the crew's base goes to them.
        base = {"lat": unit["lat"], "lon": unit["lon"]}
        call = client.post("/api/v1/incidents", headers=citizen(client), json={
            "category": "emergency", **base, "description": "боль в груди"}).json()
        assert call["units"][0]["id"] == unit["id"]
        seen = [ws.receive_json() for _ in range(3)]
        assert {m["type"] for m in seen} == {"message.created", "unit.updated", "incident.updated"}

    state = client.get("/api/v1/responder/me", headers=auth).json()
    assert state["assignment"]["id"] == call["id"] and state["unit"]["status"] == "assigned"
    assert state["assignment"]["description"] == "боль в груди"
    assert state["unread"] == 1
    messages = client.get("/api/v1/responder/messages", headers=auth).json()
    assert messages[0]["text"] == "СМП №7, подтвердите приём вызова #45821."

    assert client.post("/api/v1/responder/action", headers=auth,
                       json={"action": "arrive"}).status_code == 409
    assert client.post("/api/v1/responder/shift", headers=auth,
                       json={"on_duty": False}).status_code == 409
    going = client.post("/api/v1/responder/action", headers=auth, json={"action": "accept"}).json()
    assert going["unit"]["status"] == "en_route" and going["assignment"]["status"] == "en_route"
    sent = client.post("/api/v1/responder/messages", headers=auth, json={"text": "Выезжаем"})
    assert sent.status_code == 201 and sent.json()["sender"] == "unit"
    assert sent.json()["author"] == "Алексей Иванов"

    moved = client.post("/api/v1/responder/location", headers=auth,
                        json={"lat": base["lat"] + 0.0005, "lon": base["lon"], "speed_mps": 8})
    assert moved.json()["lat"] == pytest.approx(base["lat"] + 0.0005)

    for action, status in (("arrive", "on_scene"), ("transport", "transporting"),
                           ("complete", "returning")):
        after = client.post("/api/v1/responder/action", headers=auth, json={"action": action})
        assert after.json()["unit"]["status"] == status
    assert after.json()["assignment"] is None
    history = client.get("/api/v1/responder/history", headers=auth).json()
    assert [h["id"] for h in history] == [call["id"]] and history[0]["status"] == "resolved"
    assert client.post("/api/v1/responder/action", headers=auth,
                       json={"action": "fly"}).status_code == 422


def test_responder_reports_closure(client):
    auth = responder(client)
    assert client.post("/api/v1/traffic/closures", headers=citizen(client),
                       json={**HOME}).status_code == 403
    made = client.post("/api/v1/traffic/closures", headers=auth,
                       json={**HOME, "reason": "ДТП, перекрыта полоса"})
    assert made.status_code == 201 and made.json()["edges"] >= 1
    traffic = client.get("/api/v1/traffic").json()
    assert traffic["closures"][0]["reason"] == "ДТП, перекрыта полоса"
    assert any(f["properties"]["level"] == "closed" for f in traffic["segments"]["features"])
    assert client.delete(f"/api/v1/traffic/closures/{made.json()['id']}", headers=auth).json() == {
        "ok": True}
    assert client.delete("/api/v1/traffic/closures/nope", headers=auth).status_code == 404
    assert client.get("/api/v1/traffic").json()["closures"] == []


def test_dispatcher_console_api(client):
    token = client.post("/api/v1/auth/dispatcher", json={"login": "dispatcher", "pin": "4321"})
    disp = {"Authorization": f"Bearer {token.json()['token']}"}
    settings = client.post("/api/v1/dispatch/settings", headers=disp,
                           json={"auto_dispatch": False, "strategy": "min_eta"}).json()
    assert settings["auto_dispatch"] is False and settings["strategy"] == "min_eta"
    call = client.post("/api/v1/incidents", headers=citizen(client),
                       json={"category": "patrol", **HOME}).json()
    assert call["status"] == "new" and call["units"] == []
    view = client.get("/api/v1/dispatch/overview", headers=disp).json()
    assert [i["id"] for i in view["incidents"]] == [call["id"]] and len(view["units"]) == 121
    proposed = view["proposals"][call["id"]]
    assert len(proposed) == 1
    done = client.post("/api/v1/dispatch/assign", headers=disp,
                       json={"incident_id": call["id"], "unit_id": proposed[0]}).json()
    assert done["status"] == "assigned" and done["units"][0]["id"] == proposed[0]
    again = client.post("/api/v1/dispatch/assign", headers=disp,
                        json={"incident_id": call["id"], "unit_id": proposed[0]})
    assert again.status_code == 409
    assert client.post("/api/v1/dispatch/assign", headers=disp,
                       json={"incident_id": "inc-0", "unit_id": proposed[0]}).status_code == 404
    msg = client.post("/api/v1/dispatch/messages", headers=disp,
                      json={"unit_id": proposed[0], "text": "Ориентировочное время прибытия?"})
    assert msg.status_code == 201 and msg.json()["sender"] == "dispatcher"
    assert client.get("/api/v1/dispatch/overview", headers=citizen(client)).status_code == 403
    assert client.post("/api/v1/dispatch/settings", headers=disp,
                       json={"strategy": "magic"}).status_code == 422


def test_logout_returns_simulated_unit_to_autopilot(client):
    auth = responder(client, "fire-9-1")
    unit = client.runtime.engine.world.units["fire-9-1"]
    assert unit.controlled_by == "resp-fire-9-1"
    client.post("/api/v1/responder/shift", headers=auth, json={"on_duty": False})
    assert unit.status.value == "off_duty"
    assert client.post("/api/v1/auth/logout", headers=auth).json() == {"ok": True}
    assert unit.controlled_by is None and unit.status.value == "available"
    demo = responder(client)
    client.post("/api/v1/auth/logout", headers=demo)
    assert client.runtime.engine.world.units["ambulance-7-1"].controlled_by == "resp-demo"
    assert client.post("/api/v1/auth/logout").status_code == 401
