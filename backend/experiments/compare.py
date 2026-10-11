"""Offline comparison of dispatch strategies on identical simulated scenarios.

    uv run python -m experiments.compare            # full run, writes docs/experiments/
    uv run python -m experiments.compare --quick    # one seed, one simulated hour

Every strategy sees the same fleet, the same stream of calls (time, place, category) and
the same traffic (time of day, hotspots). Only the assignment logic differs. All data is
simulated: the numbers describe the model, not real response times in Almaty.
"""

from __future__ import annotations

import argparse
import json
import random
import statistics
import time
from dataclasses import dataclass
from pathlib import Path

from app.domain.dispatch.planner import STRATEGIES
from app.domain.graph import ARTERIAL_MAX_CLASS, RoadGraph
from app.domain.models import IncidentStatus, Priority, UnitStatus
from app.domain.traffic import Hotspot, TrafficModel
from app.engine.ambient import CALL_MIX, Ambient
from app.engine.core import Engine
from app.engine.seed import DATA_DIR, build_world

OUT_DIR = Path(__file__).resolve().parents[2] / "docs" / "experiments"
TICK_S = 5.0
# Share of calls the model expects to be reached within this time, by priority.
TARGET_S = {Priority.CRITICAL: 600, Priority.HIGH: 900, Priority.MEDIUM: 1200, Priority.LOW: 1800}


@dataclass(frozen=True)
class Scenario:
    key: str
    title: str
    start_hour: float  # local time of day the run starts at
    calls_per_hour: float
    hotspots: int
    fleet_share: float  # share of the fleet on duty


SCENARIOS = (
    Scenario("normal", "Обычная нагрузка (ночь, свободные дороги)", 2.0, 40, 0, 1.0),
    Scenario("rush", "Час пик (утро, очаги заторов)", 7.5, 60, 14, 1.0),
    Scenario("surge", "Пиковая нагрузка (час пик, 60% экипажей, всплеск вызовов)", 17.5, 150, 14, 0.6),
)


def build_calls(graph: RoadGraph, seed: int, scenario: Scenario, hours: float) -> list[tuple]:
    rng = random.Random(seed * 1000 + 17)
    nodes = Ambient(Engine(graph, build_world(graph, seed)))._core_nodes
    categories = [c for c, _, _ in CALL_MIX]
    weights = [w for _, w, _ in CALL_MIX]
    calls, t = [], 0.0
    while True:
        t += rng.expovariate(scenario.calls_per_hour / 3600.0)
        if t >= hours * 3600:
            return calls
        calls.append((t, rng.choices(categories, weights)[0], *rng.choice(nodes)))


def build_hotspots(graph: RoadGraph, seed: int, scenario: Scenario, hours: float) -> list[tuple]:
    rng = random.Random(seed * 1000 + 29)
    arterials = [e for e in graph.edges if e.road_class <= ARTERIAL_MAX_CLASS]
    events = []
    for k in range(int(scenario.hotspots * hours * 2.5)):
        edge = rng.choice(arterials)
        events.append((rng.uniform(0, hours * 3600), f"h{k}", *edge.midpoint, rng.uniform(300, 700),
                       rng.uniform(0.5, 0.9), rng.uniform(900, 2400)))
    return sorted(events)


def run(graph: RoadGraph, strategy: str, scenario: Scenario, seed: int, hours: float) -> dict:
    # Start at a fixed UTC instant so the local time of day (UTC+5) is the scenario's.
    start = ((scenario.start_hour - 5.0) % 24.0) * 3600.0
    world = build_world(graph, seed)
    rng = random.Random(seed)
    for unit in sorted(world.units.values(), key=lambda u: u.id):
        unit.controlled_by = None
        unit.status = UnitStatus.AVAILABLE if rng.random() < scenario.fleet_share else UnitStatus.OFF_DUTY
    engine = Engine(graph, world, traffic=TrafficModel(graph, seed=seed), now=start,
                    wall=lambda: 0.0, strategy=strategy)
    calls = build_calls(graph, seed, scenario, hours)
    hotspots = build_hotspots(graph, seed, scenario, hours)
    ci = hi = 0
    reassignments = 0
    wall_start = time.perf_counter()
    # Run past the last call so late incidents can still be served.
    for step in range(int((hours + 1.0) * 3600 / TICK_S)):
        elapsed = step * TICK_S
        while hi < len(hotspots) and hotspots[hi][0] <= elapsed:
            _, hid, lat, lon, radius, severity, ttl = hotspots[hi]
            engine.traffic.add_hotspot(Hotspot(hid, lat, lon, radius, severity, engine.now + ttl))
            hi += 1
        while ci < len(calls) and calls[ci][0] <= elapsed:
            _, category, lat, lon = calls[ci]
            engine.create_incident(category, lat, lon, synthetic=True)
            ci += 1
        engine.tick(TICK_S)
        reassignments += sum(1 for e in engine.drain() if e["type"] == "unit.released")
    incidents = list(world.incidents.values())
    arrived = [i for i in incidents if i.first_arrival_s is not None]
    times = sorted(i.first_arrival_s for i in arrived)
    critical = sorted(i.first_arrival_s for i in arrived if i.priority is Priority.CRITICAL)
    on_time = sum(1 for i in arrived if i.first_arrival_s <= TARGET_S[i.priority])

    def pct(values: list[float], q: float) -> float:
        return values[min(len(values) - 1, int(q * len(values)))] if values else float("nan")

    return {
        "strategy": strategy, "scenario": scenario.key, "seed": seed,
        "calls": len(incidents), "reached": len(arrived),
        "never_reached": sum(1 for i in incidents if i.first_arrival_s is None),
        "still_waiting": sum(1 for i in incidents if i.status is IncidentStatus.NEW),
        "mean_s": statistics.fmean(times) if times else float("nan"),
        "p90_s": pct(times, 0.9),
        "critical_mean_s": statistics.fmean(critical) if critical else float("nan"),
        "critical_p90_s": pct(critical, 0.9),
        "on_time_share": on_time / len(incidents) if incidents else float("nan"),
        "reroutes": reassignments,
        "compute_s": time.perf_counter() - wall_start,
    }


def mmss(seconds: float) -> str:
    return "—" if seconds != seconds else f"{int(seconds // 60)}:{int(seconds % 60):02d}"


def report(rows: list[dict], seeds: list[int], hours: float) -> str:
    lines = [
        "# Сравнение стратегий диспетчеризации",
        "",
        f"Симуляция на дорожном графе Алматы (OpenStreetMap). {len(seeds)} прогон(а) на сценарий "
        f"(seed {', '.join(map(str, seeds))}), {hours:g} ч потока вызовов + 1 ч на дообслуживание. "
        "Все стратегии получают одинаковый парк, одинаковый поток вызовов и одинаковые пробки.",
        "",
        "**Данные смоделированы.** Цифры описывают поведение модели и не являются измерениями "
        "реального времени прибытия экстренных служб.",
        "",
        "Время — от создания вызова до прибытия первого экипажа (включая 30 с на выезд), мм:сс. "
        "«В норматив» — доля всех вызовов, до которых доехали за целевое время модели "
        "(критические 10 мин, высокие 15, средние 20, низкие 30).",
    ]
    for scenario in SCENARIOS:
        subset = [r for r in rows if r["scenario"] == scenario.key]
        if not subset:
            continue
        lines += ["", f"## {scenario.title}", "",
                  f"{scenario.calls_per_hour:g} вызовов/ч · очагов заторов: {scenario.hotspots} · "
                  f"экипажей на линии: {scenario.fleet_share:.0%}", "",
                  "| Стратегия | Среднее | P90 | Критические: среднее | Критические: P90 | В норматив | Не доехали | Перенаправлений |",
                  "|---|---|---|---|---|---|---|---|"]
        for strategy in STRATEGIES:
            s = [r for r in subset if r["strategy"] == strategy]
            avg = lambda key: statistics.fmean(r[key] for r in s)  # noqa: E731
            lines.append(
                f"| {strategy} | {mmss(avg('mean_s'))} | {mmss(avg('p90_s'))} | "
                f"{mmss(avg('critical_mean_s'))} | {mmss(avg('critical_p90_s'))} | "
                f"{avg('on_time_share'):.1%} | {avg('never_reached'):.1f} | {avg('reroutes'):.1f} |")
        base = statistics.fmean(r["critical_mean_s"] for r in subset if r["strategy"] == "nearest")
        ours = statistics.fmean(r["critical_mean_s"] for r in subset if r["strategy"] == "jardem")
        lines += ["", f"Критические вызовы, jardem относительно nearest: {(ours - base) / base:+.1%} "
                      "к среднему времени прибытия."]
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--no-write", action="store_true")
    args = parser.parse_args()
    seeds = [1] if args.quick else [1, 2, 3]
    hours = 1.0 if args.quick else 2.0
    graph = RoadGraph.from_file(DATA_DIR / "almaty_graph.json.gz")
    rows = []
    for scenario in SCENARIOS:
        for seed in seeds:
            for strategy in STRATEGIES:
                row = run(graph, strategy, scenario, seed, hours)
                rows.append(row)
                print(f"{scenario.key:7} seed={seed} {strategy:8} calls={row['calls']:4} "
                      f"mean={mmss(row['mean_s'])} crit={mmss(row['critical_mean_s'])} "
                      f"on_time={row['on_time_share']:.1%} unreached={row['never_reached']} "
                      f"({row['compute_s']:.0f}s)", flush=True)
    text = report(rows, seeds, hours)
    if not args.no_write:
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        suffix = "_quick" if args.quick else ""
        (OUT_DIR / f"results{suffix}.md").write_text(text, "utf-8")
        (OUT_DIR / f"results{suffix}.json").write_text(json.dumps(rows, indent=1), "utf-8")
    print("\n" + text)


if __name__ == "__main__":
    main()
