"""PostgreSQL/PostGIS persistence: catalogue, incident records, audit trail, tracks.

The engine keeps live state in memory; this layer makes it durable and queryable. Incident
history survives restarts. Incidents still open when the process stopped are closed as
cancelled on the next start, because their in-flight routes are not restored.
"""

from __future__ import annotations

import json
import logging
from datetime import UTC, datetime

import asyncpg

from app.engine.world import Incident, World

log = logging.getLogger("jardem.db")

SCHEMA = """
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE TABLE IF NOT EXISTS departments (
    id text PRIMARY KEY, service text NOT NULL, name text NOT NULL, address text NOT NULL,
    approximate boolean NOT NULL, geom geography(Point, 4326) NOT NULL);
CREATE INDEX IF NOT EXISTS departments_geom ON departments USING gist (geom);
CREATE TABLE IF NOT EXISTS units (
    id text PRIMARY KEY, department_id text NOT NULL REFERENCES departments(id),
    service text NOT NULL, kind text NOT NULL, name text NOT NULL, callsign text NOT NULL,
    capabilities text[] NOT NULL, plate text NOT NULL, vehicle text NOT NULL,
    status text NOT NULL, geom geography(Point, 4326) NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS incidents (
    id text PRIMARY KEY, number integer NOT NULL UNIQUE, service text NOT NULL,
    category text NOT NULL, priority smallint NOT NULL, status text NOT NULL,
    address text NOT NULL, description text NOT NULL, citizen_id text,
    synthetic boolean NOT NULL, geom geography(Point, 4326) NOT NULL,
    created_at timestamptz NOT NULL, closed_at timestamptz, first_arrival_s real,
    served_by text[] NOT NULL DEFAULT '{}', timeline jsonb NOT NULL DEFAULT '[]');
CREATE INDEX IF NOT EXISTS incidents_citizen ON incidents (citizen_id, created_at DESC);
CREATE INDEX IF NOT EXISTS incidents_open ON incidents (status) WHERE closed_at IS NULL;
CREATE TABLE IF NOT EXISTS events (
    id bigserial PRIMARY KEY, at timestamptz NOT NULL DEFAULT now(), type text NOT NULL,
    payload jsonb NOT NULL);
CREATE TABLE IF NOT EXISTS unit_tracks (
    unit_id text NOT NULL, at timestamptz NOT NULL DEFAULT now(), status text NOT NULL,
    geom geography(Point, 4326) NOT NULL);
CREATE INDEX IF NOT EXISTS unit_tracks_unit ON unit_tracks (unit_id, at DESC);
"""

_POINT = "ST_SetSRID(ST_MakePoint({lon}, {lat}), 4326)::geography"


def _ts(wall: float | None) -> datetime | None:
    return None if wall is None else datetime.fromtimestamp(wall, UTC)


class Persistence:
    def __init__(self, url: str) -> None:
        self._url = url
        self.pool: asyncpg.Pool | None = None

    async def start(self, world: World) -> None:
        self.pool = await asyncpg.create_pool(self._url, min_size=1, max_size=5)
        async with self.pool.acquire() as con:
            await con.execute(SCHEMA)
            await con.executemany(
                "INSERT INTO departments (id, service, name, address, approximate, geom) "
                f"VALUES ($1, $2, $3, $4, $5, {_POINT.format(lon='$6', lat='$7')}) "
                "ON CONFLICT (id) DO UPDATE SET service = excluded.service, "
                "name = excluded.name, address = excluded.address, "
                "approximate = excluded.approximate, geom = excluded.geom",
                [(d.id, d.service.value, d.name, d.address, d.approximate, d.lon, d.lat)
                 for d in world.departments.values()],
            )
            await con.executemany(
                "INSERT INTO units (id, department_id, service, kind, name, callsign, "
                "capabilities, plate, vehicle, status, geom) VALUES "
                f"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, {_POINT.format(lon='$11', lat='$12')}) "
                "ON CONFLICT (id) DO UPDATE SET name = excluded.name, "
                "callsign = excluded.callsign, capabilities = excluded.capabilities, "
                "plate = excluded.plate, vehicle = excluded.vehicle, status = excluded.status, "
                "geom = excluded.geom, updated_at = now()",
                [(u.id, u.department_id, u.service.value, u.kind, u.name, u.callsign,
                  sorted(u.capabilities), u.plate, u.vehicle, u.status.value, u.lon, u.lat)
                 for u in world.units.values()],
            )
            orphaned = await con.execute(
                "UPDATE incidents SET status = 'cancelled', closed_at = now(), "
                "timeline = timeline || $1::jsonb WHERE closed_at IS NULL",
                json.dumps([{"status": "cancelled", "note": "service restarted",
                             "at": datetime.now(UTC).timestamp()}]),
            )
            last = await con.fetchval("SELECT max(number) FROM incidents")
        if last is not None:
            world.next_incident_number = max(world.next_incident_number, last + 1)
        log.info("database ready (%s, next incident #%s)", orphaned, world.next_incident_number)

    async def stop(self) -> None:
        if self.pool is not None:
            await self.pool.close()

    async def save_incident(self, i: Incident) -> None:
        assert self.pool is not None
        await self.pool.execute(
            "INSERT INTO incidents (id, number, service, category, priority, status, address, "
            "description, citizen_id, synthetic, geom, created_at, closed_at, first_arrival_s, "
            "served_by, timeline) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, "
            f"{_POINT.format(lon='$11', lat='$12')}, $13, $14, $15, $16, $17::jsonb) "
            "ON CONFLICT (id) DO UPDATE SET status = excluded.status, "
            "priority = excluded.priority, closed_at = excluded.closed_at, "
            "first_arrival_s = excluded.first_arrival_s, served_by = excluded.served_by, "
            "timeline = excluded.timeline",
            i.id, i.number, i.service.value, i.category, int(i.priority), i.status.value,
            i.address, i.description, i.citizen_id, i.synthetic, i.lon, i.lat,
            _ts(i.created_wall), _ts(i.closed_wall), i.first_arrival_s, list(i.served_by),
            json.dumps([{"status": t.status, "at": t.at, "note": t.note} for t in i.timeline]),
        )

    async def save_unit_states(self, rows: list[tuple[str, str, float, float]],
                               track: bool) -> None:
        """rows: (unit_id, status, lat, lon)."""
        assert self.pool is not None
        if not rows:
            return
        async with self.pool.acquire() as con:
            await con.executemany(
                f"UPDATE units SET status = $2, geom = {_POINT.format(lon='$4', lat='$3')}, "
                "updated_at = now() WHERE id = $1", rows)
            if track:
                await con.executemany(
                    "INSERT INTO unit_tracks (unit_id, status, geom) VALUES "
                    f"($1, $2, {_POINT.format(lon='$4', lat='$3')})", rows)

    async def log_events(self, events: list[dict]) -> None:
        assert self.pool is not None
        if events:
            await self.pool.executemany(
                "INSERT INTO events (type, payload) VALUES ($1, $2::jsonb)",
                [(e["type"], json.dumps(e, ensure_ascii=False, default=str)) for e in events])

    async def history(self, *, citizen_id: str | None = None, unit_id: str | None = None,
                      limit: int = 50) -> list[dict]:
        """Closed incidents, newest first, for a citizen or for a unit that served them."""
        assert self.pool is not None
        where, arg = ("citizen_id = $1", citizen_id) if citizen_id else ("$1 = ANY(served_by)",
                                                                          unit_id)
        rows = await self.pool.fetch(
            "SELECT id, number, service, category, priority, status, address, description, "
            "ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon, created_at, closed_at, "
            f"first_arrival_s FROM incidents WHERE {where} AND closed_at IS NOT NULL "
            "ORDER BY created_at DESC LIMIT $2", arg, limit)
        return [dict(r) for r in rows]

    async def departments_near(self, lat: float, lon: float, service: str | None,
                               limit: int) -> list[tuple[str, float]]:
        """Nearest departments by great-circle distance (PostGIS KNN): (id, metres)."""
        assert self.pool is not None
        point = _POINT.format(lon="$1", lat="$2")
        rows = await self.pool.fetch(
            f"SELECT id, ST_Distance(geom, {point}) AS m FROM departments "
            f"WHERE $3::text IS NULL OR service = $3 ORDER BY geom <-> {point} LIMIT $4",
            lon, lat, service, limit)
        return [(r["id"], float(r["m"])) for r in rows]
