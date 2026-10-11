# Jardem.ai API (v1)

Base URL inside the cluster: `http://localhost:8080/api/v1` (gateway → backend).
Interactive schema: `/api/docs`, machine-readable: `/api/openapi.json`.

Conventions
- JSON, UTF-8. Points are `lat` / `lon` fields; line geometries are GeoJSON-ordered `[lon, lat]` pairs.
- Times are ISO-8601 UTC strings; durations are seconds (`*_s`), distances metres (`*_m`).
- Auth: `Authorization: Bearer <token>` from one of the `/auth/*` endpoints. Errors: `{"detail": "..."}` with 401 / 403 / 404 / 409 (invalid state transition) / 422 / 429.
- Everything is a demo simulation: `/meta` returns the disclaimer that must be shown, and the real emergency numbers (112, 103, 102, 101).

## Public (no auth)
| Method | Path | Notes |
|---|---|---|
| GET | `/health` | liveness, whether DB/Redis are attached |
| GET | `/meta` | city, `center`, `bbox`, `disclaimer`, `phones`, `strategy`, `sim_speed`, `app_url` |
| GET | `/catalog` | 4 services, each with `categories[] {id,title,description,priority,units_required}` |
| GET | `/departments?service=&lat=&lon=&limit=` | with `lat/lon`: nearest first, `distance_m` (PostGIS KNN) |
| GET | `/units?service=&category=&lat=&lon=&limit=` | on-duty units; with `lat/lon`: free units first, then by `eta_s`; each has `distance_m`, `eta_s`, `free`, `status`, `status_label`, `name`, `callsign`, `photo`, `plate`, `vehicle` |
| GET | `/units/{id}?lat=&lon=` | one unit; with a point adds `route`, `eta_s`, `distance_m` |
| GET | `/route?from_lat&from_lon&to_lat&to_lon&profile=emergency\|car` | `geometry`, `sections[] {level, geometry}` (traffic-coloured), `maneuvers[]`, `duration_s`, `free_flow_s` |
| GET | `/traffic?bbox=minLat,minLon,maxLat,maxLon&include_free=` | `index` 0–10, `hotspots[]`, `closures[]`, `segments` (GeoJSON FeatureCollection, `properties.level` ∈ free/slow/jam/heavy/closed) |
| POST | `/triage` `{text}` | suggested `service`, `category`, `priority`, flags, `missing[]` |
| POST | `/dispatch/compare` `{category,lat,lon}` | what each strategy would send: `picks {nearest,min_eta,jardem}` + ranked `candidates[]` with cost breakdown |
| GET | `/stats` | per-service active incidents / units / free units, `traffic_index`, mean arrival |
| WS | `/ws` | change notifications, see below |

## Auth (demo-grade)
- `POST /auth/citizen {phone, name?}` → `{token, user}` (no SMS code in the prototype).
- `POST /auth/responder {login, pin}` → binds the session to a unit. `login` is a unit id (e.g. `fire-9-1`) or `smp7` for the demo crew «СМП №7»; PIN = `JARDEM_DEMO_PIN` (default `1234`).
- `POST /auth/dispatcher {login:"dispatcher", pin}`.
- `GET /auth/me`. `POST /auth/logout` — for a crew session returns the unit to the simulator (the demo crew stays human-driven).

## Citizen
- `POST /incidents {category, lat, lon, address?, description?, phone?}` → 201 incident. The description is triaged; stated danger to life raises priority to critical. 422 outside Almaty, 429 with 3 open calls.
- `GET /incidents` → `{active[], history[]}`.
- `GET /incidents/{id}` → incident: `status` (new → assigned → en_route → on_scene → resolved | cancelled), `timeline[] {status, at}`, `eta_s`, `units[]` (each with live `lat/lon/heading`, `eta_s`, `distance_m`, `route`, `name`, `callsign`, `plate`, `photo`).
- `POST /incidents/{id}/cancel` (409 once a crew is on scene).

## Responder
- `GET /responder/me` → `{unit, assignment, counters, unread}`. `unit` has `crew[]`, `equipment[]`, `fuel_pct`, `shift_started_at`, `status`. `assignment` is the incident plus `my {eta_s, distance_m, route, maneuvers[] {kind,text,street,in_m}}`.
- `POST /responder/shift {on_duty}`.
- `POST /responder/action {action}`: `accept` (assigned→en_route), `arrive` (→on_scene), `transport` (→transporting), `complete` (→returning; closes the incident when the last crew leaves).
- `POST /responder/location {lat, lon, speed_mps?}` — real GPS fix; overrides simulated motion for 15 s and feeds the traffic model as a probe.
- `GET|POST /responder/messages` — chat with dispatch. `GET /responder/history`.
- `POST /traffic/closures {lat, lon, reason?, minutes?}`, `DELETE /traffic/closures/{id}` — report / lift a road closure (responder or dispatcher).

## Dispatcher
- `GET /dispatch/overview`, `POST /dispatch/assign {incident_id, unit_id}`, `POST /dispatch/messages {unit_id, text}`.
- `POST /dispatch/settings {strategy?, auto_dispatch?, sim_speed?, calls_per_hour?, hotspots?}`.
- `POST /traffic/hotspots {lat, lon, radius_m?, severity?, minutes?, kind?}`.

## WebSocket `/ws`
Server → client JSON messages; clients re-fetch details over REST.
- `{"type":"hello"}`
- `{"type":"units.moved","units":[{id,service,kind,status,lat,lon,heading}]}` — about once per tick for moving units
- `{"type":"unit.updated","unit":{...},"incident_id"}`
- `{"type":"incident.updated","incident_id","status","service","unit_ids"}`
- `{"type":"message.created","unit_id"}`
- `{"type":"traffic.updated"}`
