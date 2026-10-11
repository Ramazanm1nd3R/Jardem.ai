"""Async shell around the engine: the tick loop, event fan-out and persistence."""

from __future__ import annotations

import asyncio
import contextlib
import logging
import time

from app.api.serializers import unit_brief
from app.config import Settings
from app.domain.graph import RoadGraph
from app.engine.ambient import Ambient
from app.engine.core import Engine
from app.engine.seed import DATA_DIR, build_world
from app.infra.bus import LocalBus, RedisBus
from app.infra.persistence import Persistence

log = logging.getLogger("jardem.runtime")
TRACK_EVERY_S = 15.0
MAX_CLOSED_IN_MEMORY = 300


class Runtime:
    def __init__(self, settings: Settings, graph: RoadGraph | None = None):
        self.settings = settings
        graph = graph or RoadGraph.from_file(DATA_DIR / "almaty_graph.json.gz")
        world = build_world(graph, seed=settings.seed)
        self.engine = Engine(graph, world, now=time.time(), strategy=settings.strategy,
                             auto_dispatch=settings.auto_dispatch)
        self.ambient = Ambient(self.engine, calls_per_hour=settings.ambient_calls_per_hour,
                               max_hotspots=settings.ambient_hotspots, seed=settings.seed)
        self.sim_speed = settings.sim_speed
        self.bus: LocalBus = RedisBus(settings.redis_url) if settings.redis_url else LocalBus()
        self.db: Persistence | None = (
            Persistence(settings.database_url) if settings.database_url else None)
        self._task: asyncio.Task | None = None
        self._last_track = 0.0
        self.started_at = time.time()

    async def start(self, run_loop: bool = True) -> None:
        await self.bus.start()
        if self.db is not None:
            await self.db.start(self.engine.world)
        if run_loop:
            self._task = asyncio.create_task(self._loop())

    async def stop(self) -> None:
        if self._task is not None:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
        await self.bus.stop()
        if self.db is not None:
            await self.db.stop()

    async def _loop(self) -> None:
        last = time.monotonic()
        while True:
            await asyncio.sleep(self.settings.tick_s)
            current = time.monotonic()
            dt, last = (current - last) * self.sim_speed, current
            try:
                self.engine.tick(dt)
                self.ambient.tick(dt)
                await self.flush()
            except asyncio.CancelledError:
                raise
            except Exception:
                log.exception("engine tick failed")

    async def flush(self) -> None:
        """Publish and persist everything the engine did since the last flush."""
        events = self.engine.drain()
        if not events:
            return
        world = self.engine.world
        moved: set[str] = set()
        changed_units: set[str] = set()
        incidents: set[str] = set()
        out: list[dict] = []
        for e in events:
            kind = e["type"]
            if kind == "unit.moved":
                moved.update(e["units"])
            elif kind.startswith("unit."):
                changed_units.add(e["unit_id"])
                if kind == "unit.assigned":
                    self._greet_crew(e["unit_id"], e["incident_id"])
                    incidents.add(e["incident_id"])
            elif kind.startswith("incident."):
                incidents.add(e["incident_id"])
            elif kind == "message.created":
                out.append({"type": "message.created", "unit_id": e["unit_id"]})
            elif kind == "traffic.updated":
                if not any(o["type"] == "traffic.updated" for o in out):
                    out.append({"type": "traffic.updated"})
            elif kind == "dispatch.proposed":
                out.append(e)
        # _greet_crew may have produced message events; pick them up now.
        for e in self.engine.drain():
            if e["type"] == "message.created":
                out.append({"type": "message.created", "unit_id": e["unit_id"]})
        if moved:
            out.append({"type": "units.moved",
                        "units": [unit_brief(world.units[u]) for u in sorted(moved)]})
        for unit_id in sorted(changed_units):
            unit = world.units[unit_id]
            out.append({"type": "unit.updated", "unit": unit_brief(unit),
                        "incident_id": unit.incident_id})
        for incident_id in sorted(incidents):
            inc = world.incidents[incident_id]
            out.append({"type": "incident.updated", "incident_id": inc.id,
                        "status": inc.status.value, "service": inc.service.value,
                        "unit_ids": list(inc.unit_ids)})
        for message in out:
            await self.bus.publish(message)
        if self.db is not None:
            await self._persist(events, incidents, changed_units, moved)
        self._prune()

    def _greet_crew(self, unit_id: str, incident_id: str) -> None:
        unit = self.engine.world.units[unit_id]
        if unit.controlled_by is None:
            return
        number = self.engine.world.incidents[incident_id].number
        self.engine.post_message(unit_id, "dispatcher", "Диспетчер",
                                 f"{unit.callsign}, подтвердите приём вызова #{number}.")

    async def _persist(self, events: list[dict], incidents: set[str], changed: set[str],
                       moved: set[str]) -> None:
        assert self.db is not None
        world = self.engine.world
        try:
            for incident_id in incidents:
                await self.db.save_incident(world.incidents[incident_id])
            track = time.monotonic() - self._last_track >= TRACK_EVERY_S
            ids = changed | moved if track else changed
            if track:
                self._last_track = time.monotonic()
            await self.db.save_unit_states(
                [(u, world.units[u].status.value, world.units[u].lat, world.units[u].lon)
                 for u in ids], track)
            await self.db.log_events([e for e in events if e["type"] != "unit.moved"])
        except Exception:
            log.exception("persistence failed")

    def _prune(self) -> None:
        """Keep memory bounded: drop the oldest closed synthetic incidents."""
        world = self.engine.world
        closed = [i for i in world.incidents.values() if i.closed_wall is not None and i.synthetic]
        if len(closed) > MAX_CLOSED_IN_MEMORY:
            closed.sort(key=lambda i: i.closed_wall or 0.0)
            for incident in closed[: len(closed) - MAX_CLOSED_IN_MEMORY]:
                del world.incidents[incident.id]
