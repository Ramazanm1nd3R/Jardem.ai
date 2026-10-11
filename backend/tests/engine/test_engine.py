import pytest

from app.domain.dispatch.planner import DemandPoint, DispatchParams
from app.domain.models import IncidentStatus, Priority, Service, TransitionError, UnitStatus
from app.domain.traffic import TrafficModel
from app.engine.core import TURNOUT_S, Engine, EngineError
from app.engine.seed import DEMO_UNIT_ID, build_world, department_number
from app.engine.world import Unit, World
from tests.domain.conftest import edge_between, make_grid

NIGHT = 22 * 3600.0  # 03:00 local: free flow, so travel times are predictable
MED = frozenset({"medical"})


def add_unit(world, graph, id_, node, caps=MED, service=Service.AMBULANCE,
             status=UnitStatus.AVAILABLE, controlled_by=None):
    lat, lon = graph.nodes[node]
    world.units[id_] = Unit(id=id_, department_id="d", service=service, kind="k", name=id_,
                            callsign=id_, capabilities=frozenset(caps), status=status, lat=lat,
                            lon=lon, base=(lat, lon), controlled_by=controlled_by)
    return world.units[id_]


@pytest.fixture
def setup():
    graph = make_grid(5, 5)
    world = World()
    demand = (DemandPoint(*graph.nodes[12], 1.0),)
    engine = Engine(graph, world, traffic=TrafficModel(graph), now=NIGHT, wall=lambda: 1000.0,
                    demand=demand, params=DispatchParams(coverage_weight=0.0))
    return graph, world, engine


def run(engine, seconds, step=1.0):
    for _ in range(int(seconds / step)):
        engine.tick(step)


def test_full_incident_lifecycle(setup):
    graph, world, engine = setup
    near = add_unit(world, graph, "near", 2)
    add_unit(world, graph, "far", 24)
    inc = engine.create_incident("emergency", *graph.nodes[0], description="упал, перелом")
    assert inc.number == 45821 and inc.id == "inc-45821"
    assert inc.status is IncidentStatus.ASSIGNED and inc.unit_ids == ["near"]
    assert near.status is UnitStatus.ASSIGNED and near.incident_id == inc.id
    assert world.units["far"].status is UnitStatus.AVAILABLE
    eta = engine.unit_eta_s(near)
    assert eta == pytest.approx(near.route.distance_m / (50 / 3.6 * 1.15), rel=0.02)
    assert engine.remaining_geometry(near)[0] == (near.lat, near.lon)
    assert engine.remaining_geometry(near)[-1] == graph.nodes[0]

    run(engine, TURNOUT_S - 1)
    assert near.status is UnitStatus.ASSIGNED and (near.lat, near.lon) == graph.nodes[2]
    run(engine, 2)
    assert near.status is UnitStatus.EN_ROUTE and inc.status is IncidentStatus.EN_ROUTE
    run(engine, eta / 2)
    assert engine.unit_eta_s(near) == pytest.approx(eta / 2, abs=3)
    assert graph.nodes[0][1] < near.lon < graph.nodes[2][1]
    assert near.heading == pytest.approx(270, abs=1)
    run(engine, eta / 2 + 2)
    assert near.status is UnitStatus.ON_SCENE and inc.status is IncidentStatus.ON_SCENE
    assert (near.lat, near.lon) == pytest.approx(graph.nodes[0])
    assert inc.first_arrival_s == pytest.approx(TURNOUT_S + eta, abs=3)
    assert inc.served_by == ["near"] and engine.unit_eta_s(near) == 0.0

    run(engine, engine.on_scene_duration_s(inc) + 2)
    assert inc.status is IncidentStatus.RESOLVED and inc.unit_ids == []
    assert inc.closed_wall == 1000.0
    assert [t.status for t in inc.timeline] == ["new", "assigned", "en_route", "on_scene",
                                                "resolved"]
    assert near.status is UnitStatus.RETURNING and near.incident_id is None
    run(engine, eta + 5)
    assert near.status is UnitStatus.AVAILABLE and near.route is None
    assert (near.lat, near.lon) == graph.nodes[2]
    kinds = {e["type"] for e in engine.drain()}
    assert {"incident.created", "incident.updated", "unit.assigned", "unit.updated",
            "unit.moved"} <= kinds
    assert engine.drain() == []


def test_unknown_inputs(setup):
    graph, world, engine = setup
    with pytest.raises(EngineError):
        engine.create_incident("pizza", 43.24, 76.9)
    with pytest.raises(EngineError):
        engine.cancel_incident("nope")
    with pytest.raises(EngineError):
        engine.unit_action("nope", "accept")
    with pytest.raises(EngineError):
        engine.compare("pizza", 43.24, 76.9)
    with pytest.raises(EngineError):
        Engine(graph, world, strategy="vibes")
    add_unit(world, graph, "u", 0)
    with pytest.raises(EngineError, match="no active assignment"):
        engine.unit_action("u", "accept")


def test_no_unit_then_unit_comes_on_duty(setup):
    graph, world, engine = setup
    u = add_unit(world, graph, "u", 6, status=UnitStatus.OFF_DUTY)
    inc = engine.create_incident("emergency", *graph.nodes[0])
    assert inc.status is IncidentStatus.NEW and engine.last_plan.unfilled == (inc.id,)
    engine.set_shift("u", True)
    assert u.shift_started_at == 1000.0
    assert inc.status is IncidentStatus.ASSIGNED and inc.unit_ids == ["u"]
    with pytest.raises(EngineError, match="finish the active call"):
        engine.set_shift("u", False)


def test_shift_toggle(setup):
    graph, world, engine = setup
    u = add_unit(world, graph, "u", 6)
    engine.set_shift("u", False)
    assert u.status is UnitStatus.OFF_DUTY and u.shift_started_at is None
    engine.set_shift("u", False)
    engine.set_shift("u", True)
    engine.set_shift("u", True)
    assert u.status is UnitStatus.AVAILABLE


def test_capability_matching_and_text_escalation(setup):
    graph, world, engine = setup
    add_unit(world, graph, "plain", 1)
    rean = add_unit(world, graph, "rean", 24, {"medical", "reanimation"})
    inc = engine.create_incident("reanimation", *graph.nodes[0])
    assert inc.unit_ids == ["rean"] and rean.status is UnitStatus.ASSIGNED
    planned = engine.create_incident("planned", *graph.nodes[3],
                                     description="Дедушка не дышит, без сознания")
    assert planned.priority is Priority.CRITICAL and planned.triage["life_threat"] is True
    calm = engine.create_incident("planned", *graph.nodes[3], description="нужна справка")
    assert calm.priority is Priority.LOW
    forced = engine.create_incident("planned", *graph.nodes[3], description="не дышит",
                                    priority=Priority.MEDIUM)
    assert forced.priority is Priority.MEDIUM
    assert engine.create_incident("planned", *graph.nodes[3]).triage is None


def test_human_crew_drives_the_status(setup):
    graph, world, engine = setup
    u = add_unit(world, graph, "u", 4, controlled_by="resp-1")
    inc = engine.create_incident("emergency", *graph.nodes[0])
    run(engine, TURNOUT_S * 3)
    assert u.status is UnitStatus.ASSIGNED and (u.lat, u.lon) == graph.nodes[4]
    with pytest.raises(TransitionError):
        engine.unit_action("u", "arrive")
    engine.unit_action("u", "accept")
    assert inc.status is IncidentStatus.EN_ROUTE
    run(engine, 600)
    # Reached the address but the crew has not confirmed yet.
    assert u.status is UnitStatus.EN_ROUTE and (u.lat, u.lon) == pytest.approx(graph.nodes[0])
    engine.unit_action("u", "arrive")
    assert inc.status is IncidentStatus.ON_SCENE
    run(engine, 5000)
    assert u.status is UnitStatus.ON_SCENE
    engine.unit_action("u", "transport")
    assert u.status is UnitStatus.TRANSPORTING and inc.status is IncidentStatus.ON_SCENE
    with pytest.raises(EngineError, match="unknown action"):
        engine.unit_action("u", "dance")
    engine.unit_action("u", "complete")
    assert inc.status is IncidentStatus.RESOLVED and u.status is UnitStatus.RETURNING
    with pytest.raises(EngineError):
        engine.unit_action("u", "complete")


def test_complete_requires_being_on_scene(setup):
    graph, world, engine = setup
    add_unit(world, graph, "u", 4, controlled_by="r")
    engine.create_incident("emergency", *graph.nodes[0])
    with pytest.raises(EngineError, match="not on scene"):
        engine.unit_action("u", "complete")


def test_cancel_releases_unit_and_sends_it_home(setup):
    graph, world, engine = setup
    u = add_unit(world, graph, "u", 4)
    inc = engine.create_incident("emergency", *graph.nodes[0])
    run(engine, TURNOUT_S + 20)
    assert u.status is UnitStatus.EN_ROUTE and (u.lat, u.lon) != graph.nodes[4]
    engine.cancel_incident(inc.id)
    assert inc.status is IncidentStatus.CANCELLED and inc.unit_ids == []
    assert u.status is UnitStatus.AVAILABLE and u.incident_id is None
    assert u.route.target == "base"
    run(engine, 120)
    assert (u.lat, u.lon) == graph.nodes[4] and u.route is None
    with pytest.raises(TransitionError):
        engine.cancel_incident(inc.id)


def test_fire_gets_two_engines_and_closes_when_both_finish(setup):
    graph, world, engine = setup
    caps = {"fire_suppression"}
    a = add_unit(world, graph, "a", 1, caps, Service.FIRE)
    b = add_unit(world, graph, "b", 20, caps, Service.FIRE)
    add_unit(world, graph, "amb", 0)
    inc = engine.create_incident("fire_engine", *graph.nodes[0])
    assert sorted(inc.unit_ids) == ["a", "b"] and inc.units_required == 2
    run(engine, TURNOUT_S + 30)
    assert a.status is UnitStatus.ON_SCENE and b.status is UnitStatus.EN_ROUTE
    assert inc.status is IncidentStatus.ON_SCENE
    run(engine, engine.on_scene_duration_s(inc) + 5)
    # The first engine has finished; the incident stays open for the second, and no
    # replacement is dispatched for the one that already served.
    assert a.status in (UnitStatus.RETURNING, UnitStatus.AVAILABLE)
    assert inc.status is IncidentStatus.ON_SCENE and inc.unit_ids == ["b"]
    run(engine, engine.on_scene_duration_s(inc) + 60)
    assert inc.status is IncidentStatus.RESOLVED and sorted(inc.served_by) == ["a", "b"]
    assert a.incident_id is None and b.incident_id is None


def test_road_closure_mid_route_forces_detour(setup):
    graph, world, engine = setup
    u = add_unit(world, graph, "u", 4)
    inc = engine.create_incident("emergency", *graph.nodes[0])
    direct_eta = engine.unit_eta_s(u)
    run(engine, TURNOUT_S + 2)
    ahead = edge_between(graph, 2, 1)
    engine.traffic.close_road("c", *ahead.midpoint, 10.0, expires_at=engine.now + 1e6)
    assert engine.unit_eta_s(u) is None  # the planned path is blocked until re-routed
    run(engine, 25)
    assert ahead.id not in u.route.edges
    assert any(e["type"] == "unit.rerouted" for e in engine.outbox)
    run(engine, 200)
    assert u.status is UnitStatus.ON_SCENE
    assert inc.first_arrival_s > direct_eta + TURNOUT_S + 10


def test_closure_directly_ahead_stops_and_reroutes(setup):
    graph, world, engine = setup
    u = add_unit(world, graph, "u", 4)
    engine.create_incident("emergency", *graph.nodes[0])
    engine.traffic.close_road("c", *edge_between(graph, 4, 3).midpoint, 10.0, engine.now + 1e6)
    run(engine, TURNOUT_S + 5)
    assert edge_between(graph, 4, 3).id not in u.route.edges
    run(engine, 300)
    assert u.status is UnitStatus.ON_SCENE


def test_critical_incident_diverts_unit_from_low_priority_call(setup):
    graph, world, engine = setup
    u = add_unit(world, graph, "u", 12)
    low = engine.create_incident("planned", *graph.nodes[10])
    run(engine, TURNOUT_S + 3)
    assert u.status is UnitStatus.EN_ROUTE and u.incident_id == low.id
    crit = engine.create_incident("emergency", *graph.nodes[14])
    assert u.incident_id == crit.id and u.reassignments == 1
    assert u.status is UnitStatus.EN_ROUTE  # already rolling: no second turnout
    assert low.status is IncidentStatus.NEW and low.unit_ids == []
    assert crit.status is IncidentStatus.EN_ROUTE
    assert [t.status for t in low.timeline] == ["new", "assigned", "en_route", "assigned", "new"]
    assert [t.status for t in crit.timeline] == ["new", "assigned", "en_route"]
    run(engine, 2000)
    # After the critical call the unit is free again and picks up the waiting one.
    assert crit.status is IncidentStatus.RESOLVED and low.status is IncidentStatus.RESOLVED
    assert u.reassignments == 0


def test_baseline_strategy_never_reassigns(setup):
    graph, world, engine = setup
    engine.strategy = "min_eta"
    u = add_unit(world, graph, "u", 12)
    low = engine.create_incident("planned", *graph.nodes[10])
    run(engine, TURNOUT_S + 3)
    crit = engine.create_incident("emergency", *graph.nodes[14])
    assert u.incident_id == low.id and crit.status is IncidentStatus.NEW


def test_manual_dispatch_mode(setup):
    graph, world, engine = setup
    engine.auto_dispatch = False
    u = add_unit(world, graph, "u", 3)
    cop = add_unit(world, graph, "cop", 3, {"patrol"}, Service.POLICE)
    inc = engine.create_incident("emergency", *graph.nodes[0])
    assert inc.status is IncidentStatus.NEW and u.status is UnitStatus.AVAILABLE
    assert engine.proposals == {inc.id: ["u"]}
    with pytest.raises(EngineError, match="cannot serve"):
        engine.assign(inc.id, "cop")
    engine.assign(inc.id, "u")
    assert inc.status is IncidentStatus.ASSIGNED and engine.proposals == {}
    with pytest.raises(EngineError, match="not available"):
        engine.assign(inc.id, "u")
    assert cop.status is UnitStatus.AVAILABLE
    engine.cancel_incident(inc.id)
    with pytest.raises(EngineError, match="closed"):
        engine.assign(inc.id, "u")


def test_nearby_units_sorted_by_eta_free_first(setup):
    graph, world, engine = setup
    add_unit(world, graph, "close", 1)
    add_unit(world, graph, "mid", 3)
    add_unit(world, graph, "off", 0, status=UnitStatus.OFF_DUTY)
    add_unit(world, graph, "cop", 0, {"patrol"}, Service.POLICE)
    add_unit(world, graph, "busy", 0, status=UnitStatus.ON_SCENE)
    add_unit(world, graph, "ped", 2, {"medical", "pediatric"})
    rows = engine.nearby_units(*graph.nodes[0], service=Service.AMBULANCE)
    assert [r[0].id for r in rows] == ["close", "ped", "mid", "busy"]
    assert rows[0][1] == pytest.approx(203, abs=3) and rows[0][2] == pytest.approx(12.7, abs=0.5)
    assert rows[3][1:] == (0.0, 0.0)
    assert [r[0].id for r in engine.nearby_units(*graph.nodes[0], category="pediatric")] == ["ped"]
    assert len(engine.nearby_units(*graph.nodes[0])) == 5
    assert len(engine.nearby_units(*graph.nodes[0], limit=2)) == 2
    assert [r[0].id for r in engine.nearby_units(*graph.nodes[0], category="patrol")] == ["cop"]


def test_compare_shows_where_strategies_differ(setup):
    graph, world, engine = setup
    add_unit(world, graph, "near", 1)
    add_unit(world, graph, "far", 10)
    # A jam on the short approach makes the nearer unit the slower one.
    engine.traffic.report_probe(edge_between(graph, 1, 0).id, 0.5, engine.now)
    result = engine.compare("emergency", *graph.nodes[0])
    assert result["picks"] == {"nearest": ["near"], "min_eta": ["far"], "jardem": ["far"]}
    assert [c.unit_id for c in result["candidates"]] == ["far", "near"]
    assert world.incidents == {}  # a what-if, nothing is created


def test_device_gps_overrides_simulated_motion_and_feeds_traffic(setup):
    graph, world, engine = setup
    u = add_unit(world, graph, "u", 4, controlled_by="r")
    inc = engine.create_incident("emergency", *graph.nodes[0])
    engine.unit_action("u", "accept")
    lat, lon = graph.nodes[3]
    engine.update_location("u", lat, lon + 0.0001, speed_mps=2.0)
    assert (u.lat, u.lon) == (lat, lon + 0.0001)
    assert u.heading == pytest.approx(270, abs=2)
    run(engine, 10)
    assert (u.lat, u.lon) == (lat, lon + 0.0001)  # the phone, not the simulator, moves it
    slowed = [f for f in engine.traffic.snapshot(engine.now).factors if f < 0.5]
    assert len(slowed) == 1 and slowed[0] == pytest.approx(2.0 / (50 / 3.6), abs=0.02)
    assert engine.unit_eta_s(u) == pytest.approx(
        engine.eta.eta_s((u.lat, u.lon), (inc.lat, inc.lon), engine.now))
    run(engine, 30)
    assert u.lon < lon  # GPS went quiet: simulated motion takes over again


def test_messages(setup):
    graph, world, engine = setup
    add_unit(world, graph, "u", 4)
    m = engine.post_message("u", "dispatcher", "Диспетчер", "  Подтвердите приём  ")
    assert (m.id, m.text, m.at, m.sender) == ("msg-1", "Подтвердите приём", 1000.0, "dispatcher")
    assert engine.post_message("u", "unit", "Алексей", "Принял").id == "msg-2"
    with pytest.raises(EngineError):
        engine.post_message("ghost", "unit", "x", "y")


def test_tick_ignores_non_positive_dt(setup):
    _, _, engine = setup
    engine.tick(0)
    engine.tick(-5)
    assert engine.now == NIGHT


def test_department_number():
    assert department_number("Пожарная часть №12", 3) == "12"
    assert department_number("Служба спасения", 3) == "3"


@pytest.mark.slow
def test_demo_world_on_real_almaty_graph(almaty):
    world = build_world(almaty, seed=7)
    assert len(world.departments) == 44
    by_service = {s: sum(1 for u in world.units.values() if u.service is s) for s in Service}
    assert by_service[Service.AMBULANCE] == 36 and min(by_service.values()) >= 8
    demo = world.units[DEMO_UNIT_ID]
    assert demo.plate == "402 AR 02" and demo.crew[0].name == "Алексей Иванов"
    assert demo.status is UnitStatus.OFF_DUTY and demo.controlled_by == "resp-demo"
    assert build_world(almaty, seed=7).units["fire-1-1"].plate == world.units["fire-1-1"].plate

    engine = Engine(almaty, world, now=NIGHT)
    calls = [("emergency", 43.2445, 76.9457), ("fire_engine", 43.2567, 76.9286),
             ("patrol", 43.2220, 76.8510), ("mountain", 43.2000, 76.9900),
             ("pediatric", 43.3100, 76.9300)]
    incidents = [engine.create_incident(c, lat, lon) for c, lat, lon in calls]
    assert all(i.status is IncidentStatus.ASSIGNED for i in incidents)
    assert len(incidents[1].unit_ids) == 2
    for _ in range(900):
        engine.tick(4.0)
    assert all(i.status is IncidentStatus.RESOLVED for i in incidents)
    assert all(60 < i.first_arrival_s < 1500 for i in incidents)
    nearby = engine.nearby_units(43.2445, 76.9457, service=Service.AMBULANCE, limit=3)
    assert len(nearby) == 3 and nearby[0][2] <= nearby[1][2] <= nearby[2][2]
