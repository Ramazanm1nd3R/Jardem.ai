import itertools
import math
import random

import pytest

from app.domain.dispatch.planner import (
    PRIORITY_WEIGHT,
    Assignment,
    DemandPoint,
    DispatchParams,
    IncidentView,
    Plan,
    UnitView,
    coverage_losses,
    is_eligible,
    make_plan,
    overqualification,
    plan_greedy,
    plan_jardem,
    rank_candidates,
)
from app.domain.geo import haversine_m
from app.domain.models import Priority, Service, UnitStatus

A, P = Service.AMBULANCE, Service.POLICE
MED = frozenset({"medical"})


class TableOracle:
    """ETA and cover times from explicit tables; anything missing is unreachable."""

    def __init__(self, eta=None, cover=None):
        self.eta = eta or {}
        self.cover = cover or {}

    def eta_s(self, unit, incident):
        return self.eta.get((unit.id, incident.id), math.inf)

    def cover_s(self, unit, demand_index):
        return self.cover.get((unit.id, demand_index), math.inf)


def unit(id_, caps=MED, status=UnitStatus.AVAILABLE, service=A, lat=43.24, lon=76.90,
         incident_id=None, reassignments=0):
    return UnitView(id_, service, frozenset(caps), status, lat, lon, incident_id, reassignments)


def incident(id_, priority=Priority.HIGH, required=MED, service=A, lat=43.24, lon=76.90,
             created_at=0.0, units_required=1):
    return IncidentView(id_, service, frozenset(required), priority, lat, lon, created_at,
                        units_required)


NO_COVER = DispatchParams(coverage_weight=0.0)
DEMAND = (DemandPoint(43.24, 76.90, 1.0),)


def pairs(plan: Plan):
    return sorted((a.incident_id, a.unit_id) for a in plan.assignments)


def test_eligibility():
    inc = incident("i", required={"medical", "pediatric"})
    assert is_eligible(unit("u", {"medical", "pediatric", "reanimation"}), inc)
    assert not is_eligible(unit("u", {"medical"}), inc)
    assert not is_eligible(unit("u", {"medical", "pediatric"}, service=P), inc)
    assert is_eligible(unit("u", {"medical", "pediatric"}), inc)


def test_overqualification_counts_unused_scarce_capabilities():
    plain = incident("i")
    assert overqualification(unit("u"), plain) == 0
    assert overqualification(unit("u", {"medical", "reanimation"}), plain) == 1
    assert overqualification(unit("u", {"medical", "reanimation", "pediatric"}), plain) == 2
    needs = incident("i", required={"medical", "reanimation"})
    assert overqualification(unit("u", {"medical", "reanimation"}), needs) == 0


def test_coverage_losses_hand_point_to_runner_up():
    units = [unit("a"), unit("b"), unit("c"), unit("busy", status=UnitStatus.ON_SCENE),
             unit("p", {"patrol"}, service=P)]
    demand = (DemandPoint(0, 0, 3.0), DemandPoint(0, 0, 1.0))
    oracle = TableOracle(cover={
        ("a", 0): 100, ("b", 0): 300, ("c", 0): 900,
        ("a", 1): 500, ("b", 1): 200, ("c", 1): 260,
        ("busy", 0): 1, ("busy", 1): 1,
        ("p", 0): 50, ("p", 1): 5000,
    })
    losses = coverage_losses(units, demand, oracle, cap_s=1200.0)
    assert set(losses) == {"a", "b", "c", "p"}
    assert losses["a"] == pytest.approx(3 * (300 - 100) / 4)
    assert losses["b"] == pytest.approx(1 * (260 - 200) / 4)
    assert losses["c"] == 0.0
    # The lone police unit: losing it leaves point 0 uncovered (cap); point 1 was already
    # beyond the cap, so nothing is lost there.
    assert losses["p"] == pytest.approx(3 * (1200 - 50) / 4)


def test_coverage_losses_edge_cases():
    oracle = TableOracle(cover={("a", 0): 100, ("b", 0): 100})
    assert coverage_losses([unit("a"), unit("b")], (DemandPoint(0, 0, 0.0),), oracle, 600) == {
        "a": 0.0, "b": 0.0}
    assert coverage_losses([unit("a")], (), oracle, 600) == {"a": 0.0}
    tie = coverage_losses([unit("a"), unit("b")], (DemandPoint(0, 0, 2.0),), oracle, 600)
    assert tie == {"a": 0.0, "b": 0.0}
    returning = coverage_losses([unit("a", status=UnitStatus.RETURNING)],
                                (DemandPoint(0, 0, 2.0),), oracle, 600)
    assert returning == {"a": pytest.approx(500.0)}
    assert coverage_losses([unit("a", status=UnitStatus.OFF_DUTY)], DEMAND, oracle, 600) == {}


def test_nearest_ignores_traffic_min_eta_does_not():
    near = unit("near", lat=43.241, lon=76.90)
    far = unit("far", lat=43.28, lon=76.90)
    inc = incident("i")
    oracle = TableOracle(eta={("near", "i"): 720, ("far", "i"): 420})
    by_distance = plan_greedy([near, far], [inc], oracle, by="distance")
    by_eta = plan_greedy([near, far], [inc], oracle, by="eta")
    assert by_distance.strategy == "nearest" and by_eta.strategy == "min_eta"
    assert by_distance.assignments == (
        Assignment("i", "near", 720, pytest.approx(haversine_m(43.241, 76.90, 43.24, 76.90))),)
    assert by_eta.assignments == (Assignment("i", "far", 420, 420),)
    assert plan_jardem([near, far], [inc], oracle, DEMAND, NO_COVER).units_for("i") == ["far"]
    with pytest.raises(ValueError):
        plan_greedy([near], [inc], oracle, by="vibes")


def test_greedy_serves_by_priority_then_age_and_reports_unfilled():
    u = unit("u")
    low = incident("low", Priority.LOW, created_at=0)
    crit_new = incident("crit_new", Priority.CRITICAL, created_at=50)
    crit_old = incident("crit_old", Priority.CRITICAL, created_at=10)
    oracle = TableOracle(eta={("u", "low"): 10, ("u", "crit_new"): 900, ("u", "crit_old"): 950})
    plan = plan_greedy([u], [low, crit_new, crit_old], oracle, by="eta")
    assert pairs(plan) == [("crit_old", "u")]
    assert plan.unfilled == ("crit_new", "low")


def test_greedy_skips_ineligible_unreachable_and_busy_units():
    units = [unit("wrong_caps", {"patrol"}), unit("police", service=P),
             unit("busy", status=UnitStatus.ON_SCENE, incident_id="other"),
             unit("off", status=UnitStatus.OFF_DUTY), unit("unreachable"), unit("ok"),
             unit("back", status=UnitStatus.RETURNING)]
    eta = {(u.id, "i"): 60 for u in units if u.id != "unreachable"}
    eta[("ok", "i")] = 500
    eta[("back", "i")] = 400
    plan = plan_greedy(units, [incident("i", units_required=3)], TableOracle(eta=eta), by="eta")
    assert pairs(plan) == [("i", "back"), ("i", "ok")]
    assert plan.unfilled == ("i",)


def test_greedy_ties_break_on_unit_id():
    units = [unit("b"), unit("a")]
    oracle = TableOracle(eta={("a", "i"): 100, ("b", "i"): 100})
    assert plan_greedy(units, [incident("i")], oracle, by="eta").units_for("i") == ["a"]


def test_greedy_keeps_existing_commitments():
    going = unit("going", status=UnitStatus.EN_ROUTE, incident_id="i")
    free = unit("free")
    oracle = TableOracle(eta={("going", "i"): 300, ("free", "i"): 10})
    one = plan_greedy([going, free], [incident("i")], oracle, by="eta")
    assert one.assignments == (Assignment("i", "going", 300, 0.0, kept=True),)
    two = plan_greedy([going, free], [incident("i", units_required=2)], oracle, by="eta")
    assert pairs(two) == [("i", "free"), ("i", "going")]
    assert two.unfilled == ()


def test_jardem_beats_greedy_when_incidents_compete():
    # Greedy gives the first incident its fastest unit (a) and leaves the second a 20-minute
    # wait; the global plan swaps them for a far better total.
    units = [unit("a"), unit("b")]
    i1, i2 = incident("i1", created_at=0), incident("i2", created_at=1)
    oracle = TableOracle(eta={("a", "i1"): 120, ("b", "i1"): 180,
                              ("a", "i2"): 150, ("b", "i2"): 1200})
    greedy = plan_greedy(units, [i1, i2], oracle, by="eta")
    assert pairs(greedy) == [("i1", "a"), ("i2", "b")]
    smart = plan_jardem(units, [i1, i2], oracle, DEMAND, NO_COVER)
    assert pairs(smart) == [("i1", "b"), ("i2", "a")]
    assert sum(a.eta_s for a in smart.assignments) == 330
    assert smart.unfilled == () and smart.released == ()
    w = PRIORITY_WEIGHT[Priority.HIGH]
    assert sorted(a.cost for a in smart.assignments) == [150 * w, 180 * w]
    assert not any(a.kept for a in smart.assignments)


def test_jardem_gives_scarce_unit_to_the_critical_incident():
    units = [unit("only")]
    low = incident("low", Priority.LOW, created_at=0)
    crit = incident("crit", Priority.CRITICAL, created_at=5)
    oracle = TableOracle(eta={("only", "low"): 60, ("only", "crit"): 600})
    plan = plan_jardem(units, [low, crit], oracle, DEMAND, NO_COVER)
    assert pairs(plan) == [("crit", "only")]
    assert plan.unfilled == ("low",)


def test_jardem_spares_specialised_unit_for_routine_call():
    params = DispatchParams(coverage_weight=0.0, overqualification_penalty_s=120.0)
    rean = unit("rean", {"medical", "reanimation"})
    plain = unit("plain")
    low = incident("low", Priority.LOW)
    oracle = TableOracle(eta={("rean", "low"): 200, ("plain", "low"): 300})
    assert plan_jardem([rean, plain], [low], oracle, DEMAND, params).units_for("low") == ["plain"]
    # ...but not at any price: once the plain unit is more than the penalty slower, send rean.
    oracle.eta[("plain", "low")] = 321
    assert plan_jardem([rean, plain], [low], oracle, DEMAND, params).units_for("low") == ["rean"]
    # A critical call weighs seconds 4x, so the same 100 s gap now favours the faster unit.
    crit = incident("low", Priority.CRITICAL)
    oracle.eta[("plain", "low")] = 300
    assert plan_jardem([rean, plain], [crit], oracle, DEMAND, params).units_for("low") == ["rean"]


def test_jardem_protects_area_coverage():
    # "last" is the only unit covering the far district; "spare" has a neighbour. They are
    # nearly equidistant from the incident, so the plan keeps "last" at home.
    last, spare, neighbour = unit("last"), unit("spare"), unit("neighbour")
    inc = incident("i", Priority.MEDIUM)
    demand = (DemandPoint(0, 0, 1.0), DemandPoint(0, 0, 1.0))
    oracle = TableOracle(
        eta={("last", "i"): 300, ("spare", "i"): 360, ("neighbour", "i"): 5000},
        cover={("last", 0): 120, ("spare", 1): 100, ("neighbour", 1): 140,
               ("spare", 0): 2000, ("neighbour", 0): 2000, ("last", 1): 2000},
    )
    units = [last, spare, neighbour]
    params = DispatchParams(coverage_weight=0.6)
    assert plan_jardem(units, [inc], oracle, demand, params).units_for("i") == ["spare"]
    assert plan_jardem(units, [inc], oracle, demand, NO_COVER).units_for("i") == ["last"]
    ranked = rank_candidates(inc, units, oracle, demand, params)
    assert [c.unit_id for c in ranked] == ["spare", "last", "neighbour"]
    assert ranked[1].coverage_loss_s == pytest.approx((1200 - 120) / 2)
    assert ranked[0].coverage_loss_s == pytest.approx((140 - 100) / 2)
    assert ranked[0].cost == pytest.approx(1.5 * 360 + 0.6 * 20)
    assert ranked[1].cost == pytest.approx(1.5 * 300 + 0.6 * 540)


def test_jardem_fills_multiple_slots_with_distinct_units():
    units = [unit(n, {"fire_suppression"}, service=Service.FIRE) for n in "abc"]
    fire = incident("f", Priority.CRITICAL, {"fire_suppression"}, Service.FIRE, units_required=2)
    oracle = TableOracle(eta={("a", "f"): 500, ("b", "f"): 100, ("c", "f"): 200})
    plan = plan_jardem(units, [fire], oracle, DEMAND, NO_COVER)
    assert sorted(plan.units_for("f")) == ["b", "c"]
    short = plan_jardem(units[:1], [fire], oracle, DEMAND, NO_COVER)
    assert short.units_for("f") == ["a"] and short.unfilled == ("f",)


def test_jardem_leaves_slot_empty_rather_than_use_ineligible_or_unreachable():
    units = [unit("cop", {"patrol"}, service=P), unit("nocaps", set()), unit("island")]
    plan = plan_jardem(units, [incident("i")], TableOracle(eta={("cop", "i"): 1, ("nocaps", "i"): 1}),
                       DEMAND, NO_COVER)
    assert plan.assignments == () and plan.unfilled == ("i",)
    assert plan_jardem(units, [], TableOracle(), DEMAND) == Plan("jardem", ())
    assert plan_jardem([], [incident("i")], TableOracle(), DEMAND).unfilled == ("i",)


def test_unassigned_penalty_bounds_how_far_a_unit_is_sent():
    params = DispatchParams(coverage_weight=0.0, unassigned_penalty_s=1000.0)
    oracle = TableOracle(eta={("u", "i"): 999})
    assert plan_jardem([unit("u")], [incident("i")], oracle, DEMAND, params).units_for("i") == ["u"]
    oracle.eta[("u", "i")] = 1001
    assert plan_jardem([unit("u")], [incident("i")], oracle, DEMAND, params).unfilled == ("i",)


def test_reoptimisation_needs_a_real_gain_to_reroute():
    params = DispatchParams(coverage_weight=0.0, stickiness_s=90.0, stickiness_ratio=0.25)
    going = unit("going", status=UnitStatus.EN_ROUTE, incident_id="i")
    fresh = unit("fresh")
    inc = incident("i")
    # 80 s faster is under the 90 s threshold (ratio gives 0.25 * 300 = 75): keep.
    oracle = TableOracle(eta={("going", "i"): 300, ("fresh", "i"): 220})
    keep = plan_jardem([going, fresh], [inc], oracle, DEMAND, params)
    assert keep.assignments == (Assignment("i", "going", 300, pytest.approx(2.5 * 210), kept=True),)
    assert keep.released == ()
    # 100 s faster clears it: swap, and the old unit is released.
    oracle.eta[("fresh", "i")] = 200
    swap = plan_jardem([going, fresh], [inc], oracle, DEMAND, params)
    assert pairs(swap) == [("i", "fresh")] and swap.released == ("going",)
    assert not swap.assignments[0].kept
    # On a long run the threshold scales with the ETA: 0.25 * 1000 = 250 s.
    oracle.eta.update({("going", "i"): 1000, ("fresh", "i"): 760})
    assert plan_jardem([going, fresh], [inc], oracle, DEMAND, params).units_for("i") == ["going"]
    oracle.eta[("fresh", "i")] = 740
    assert plan_jardem([going, fresh], [inc], oracle, DEMAND, params).units_for("i") == ["fresh"]


def test_reoptimisation_diverts_unit_to_more_urgent_incident():
    going = unit("going", status=UnitStatus.EN_ROUTE, incident_id="low")
    low = incident("low", Priority.LOW, created_at=0)
    crit = incident("crit", Priority.CRITICAL, created_at=100)
    oracle = TableOracle(eta={("going", "low"): 200, ("going", "crit"): 150})
    plan = plan_jardem([going], [low, crit], oracle, DEMAND, NO_COVER)
    assert pairs(plan) == [("crit", "going")]
    assert plan.unfilled == ("low",) and plan.released == ("going",)
    assert plan.assignments[0].kept is False


def test_locked_units_are_never_moved():
    params = DispatchParams(coverage_weight=0.0, max_reassignments=1)
    crit = incident("crit", Priority.CRITICAL, created_at=100)
    low = incident("low", Priority.LOW)
    oracle = TableOracle(eta={("u", "low"): 200, ("u", "crit"): 10})
    for locked in (unit("u", status=UnitStatus.EN_ROUTE, incident_id="low", reassignments=1),
                   unit("u", status=UnitStatus.ON_SCENE, incident_id="low"),
                   unit("u", status=UnitStatus.TRANSPORTING, incident_id="low")):
        plan = plan_jardem([locked], [low, crit], oracle, DEMAND, params)
        assert plan.assignments == (Assignment("low", "u", 200, 0.0, kept=True),)
        assert plan.unfilled == ("crit",) and plan.released == ()
    movable = unit("u", status=UnitStatus.ASSIGNED, incident_id="low", reassignments=0)
    assert pairs(plan_jardem([movable], [low, crit], oracle, DEMAND, params)) == [("crit", "u")]


def test_unit_committed_outside_the_round_is_left_alone():
    elsewhere = unit("u", status=UnitStatus.EN_ROUTE, incident_id="not-in-round")
    oracle = TableOracle(eta={("u", "i"): 5})
    plan = plan_jardem([elsewhere], [incident("i")], oracle, DEMAND, NO_COVER)
    assert plan.assignments == () and plan.unfilled == ("i",) and plan.released == ()


def test_on_scene_unit_fills_a_slot():
    there = unit("there", {"fire_suppression"}, UnitStatus.ON_SCENE, Service.FIRE, incident_id="f")
    free = [unit(n, {"fire_suppression"}, service=Service.FIRE) for n in "ab"]
    fire = incident("f", Priority.CRITICAL, {"fire_suppression"}, Service.FIRE, units_required=2)
    oracle = TableOracle(eta={("a", "f"): 300, ("b", "f"): 200, ("there", "f"): 0})
    plan = plan_jardem([there, *free], [fire], oracle, DEMAND, NO_COVER)
    assert pairs(plan) == [("f", "b"), ("f", "there")]


def test_make_plan_dispatches_by_name():
    units, incs = [unit("u")], [incident("i")]
    oracle = TableOracle(eta={("u", "i"): 60})
    assert [make_plan(s, units, incs, oracle, DEMAND).strategy
            for s in ("nearest", "min_eta", "jardem")] == ["nearest", "min_eta", "jardem"]
    with pytest.raises(ValueError):
        make_plan("random", units, incs, oracle, DEMAND)


def test_rank_candidates_filters_and_orders():
    units = [unit("slow"), unit("fast"), unit("busy", status=UnitStatus.EN_ROUTE),
             unit("cop", service=P), unit("island"), unit("rean", {"medical", "reanimation"})]
    oracle = TableOracle(eta={("slow", "i"): 400, ("fast", "i"): 100, ("busy", "i"): 1,
                              ("cop", "i"): 1, ("rean", "i"): 100})
    ranked = rank_candidates(incident("i", lat=43.25), units, oracle, (), NO_COVER)
    assert [c.unit_id for c in ranked] == ["fast", "rean", "slow"]
    assert ranked[0].distance_m == pytest.approx(haversine_m(43.24, 76.90, 43.25, 76.90))
    assert (ranked[1].overqualified, ranked[1].cost) == (1, pytest.approx(2.5 * 100 + 120))
    assert ranked[0].eta_s == 100 and ranked[0].coverage_loss_s == 0.0


def test_jardem_is_optimal_for_its_objective_on_random_scenarios():
    """With no commitments the plan must equal the brute-force minimum of the objective."""
    rng = random.Random(21)
    params = DispatchParams(coverage_weight=0.5)
    for _ in range(120):
        units = [unit(f"u{k}", rng.choice([{"medical"}, {"medical", "reanimation"},
                                           {"medical", "pediatric"}]))
                 for k in range(rng.randint(1, 4))]
        incs = [incident(f"i{k}", rng.choice(list(Priority)),
                         rng.choice([{"medical"}, {"medical", "pediatric"}]), created_at=k)
                for k in range(rng.randint(1, 4))]
        oracle = TableOracle(
            eta={(u.id, i.id): rng.uniform(30, 2500) for u in units for i in incs
                 if rng.random() > 0.1},
            cover={(u.id, d): rng.uniform(30, 1500) for u in units for d in range(2)},
        )
        demand = (DemandPoint(0, 0, 1.0), DemandPoint(0, 0, 2.0))
        losses = coverage_losses(units, demand, oracle, params.coverage_cap_s)

        def objective(choice):
            total = 0.0
            for inc, u in zip(incs, choice, strict=True):
                w = PRIORITY_WEIGHT[inc.priority]
                if u is None:
                    total += params.unassigned_penalty_s * w
                    continue
                eta = oracle.eta_s(u, inc)
                if not is_eligible(u, inc) or eta == math.inf:
                    return math.inf
                total += w * eta
                if inc.priority is not Priority.CRITICAL:
                    total += (params.coverage_weight * losses[u.id]
                              + params.overqualification_penalty_s * overqualification(u, inc))
            return total

        options = [*units, *([None] * len(incs))]
        best = min(objective(c) for c in itertools.permutations(options, len(incs)))
        plan = plan_jardem(units, incs, oracle, demand, params)
        chosen = {a.incident_id: a.unit_id for a in plan.assignments}
        by_id = {u.id: u for u in units}
        got = objective([by_id.get(chosen.get(i.id)) for i in incs])
        assert got == pytest.approx(best)
        assert sorted(plan.unfilled) == sorted(i.id for i in incs if i.id not in chosen)
        assert len(set(chosen.values())) == len(chosen)


def test_coverage_loss_accumulates_over_demand_points():
    oracle = TableOracle(cover={("a", 0): 100, ("b", 0): 400, ("a", 1): 200, ("b", 1): 260})
    demand = (DemandPoint(0, 0, 0.25), DemandPoint(0, 0, 0.25))
    losses = coverage_losses([unit("a"), unit("b")], demand, oracle, 1200)
    assert losses == {"a": pytest.approx((0.25 * 300 + 0.25 * 60) / 0.5), "b": 0.0}


def test_greedy_reports_every_unfilled_slot():
    plan = plan_greedy([], [incident("i", units_required=2), incident("j")], TableOracle(),
                       by="eta")
    assert plan.unfilled == ("i", "i", "j") and plan.assignments == ()


def test_rank_candidates_uses_default_parameters():
    ranked = rank_candidates(incident("i"), [unit("rean", {"medical", "reanimation"})],
                             TableOracle(eta={("rean", "i"): 100}, cover={("rean", 0): 300}), DEMAND)
    default = DispatchParams()
    assert ranked[0].coverage_loss_s == pytest.approx(default.coverage_cap_s - 300)
    assert ranked[0].cost == pytest.approx(
        2.5 * 100 + default.overqualification_penalty_s + default.coverage_weight * 900)
    plan = plan_jardem([unit("u")], [incident("i")], TableOracle(eta={("u", "i"): 50}), DEMAND)
    assert plan.assignments[0].cost == pytest.approx(2.5 * 50)


def test_critical_incident_gets_the_fastest_unit_regardless_of_reserve():
    # The reanimation crew that is also the district's only cover is 1 s faster: for a
    # critical call it goes; for a merely high-priority one the plain crew is sent instead.
    rean = unit("rean", {"medical", "reanimation"})
    plain = unit("plain")
    oracle = TableOracle(eta={("rean", "i"): 299, ("plain", "i"): 300},
                         cover={("rean", 0): 60, ("plain", 0): 5000})
    params = DispatchParams()
    critical = incident("i", Priority.CRITICAL)
    high = incident("i", Priority.HIGH)
    assert plan_jardem([rean, plain], [critical], oracle, DEMAND, params).units_for("i") == ["rean"]
    assert plan_jardem([rean, plain], [high], oracle, DEMAND, params).units_for("i") == ["plain"]
    ranked = rank_candidates(critical, [rean, plain], oracle, DEMAND, params)
    assert [(c.unit_id, c.cost) for c in ranked] == [("rean", 4 * 299), ("plain", 4 * 300)]
    assert ranked[0].overqualified == 1 and ranked[0].coverage_loss_s == pytest.approx(1140)
