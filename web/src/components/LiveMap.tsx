import * as maplibregl from "maplibre-gl";
import type { GeoJSONSource, Map as MlMap, Marker } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import workerUrl from "maplibre-gl/dist/maplibre-gl-worker.mjs?url";
import { useEffect, useRef, useState } from "react";
import type { Position, ServiceId, Traffic, Unit } from "../api/types";
import { formatDistance, formatEta, trafficLabel } from "../lib/format";
import { boundsOf } from "../lib/geo";
import { SERVICE_ORDER, SERVICE_STYLES } from "../lib/services";
import { indexColor, TRAFFIC_COLORS, TRAFFIC_LABELS } from "../lib/traffic";
import { Chevron, Layers, Locate, Minus, Plus, Search, ServiceIcon } from "./Icons";

// MapLibre 6 ships its worker as a separate module; the bundler has to emit it as a file.
maplibregl.setWorkerUrl(workerUrl);

const STYLE_URL = "https://tiles.openfreemap.org/styles/positron";

const PIN_SVG: Record<ServiceId, string> = {
  ambulance: '<path d="M9.500 3h5v6.500H21v5h-6.500V21h-5v-6.500H3v-5h6.500z"/>',
  police: '<path d="M12 2l8 3v6.200c0 5-3.300 8.700-8 10.800-4.700-2.100-8-5.800-8-10.800V5l8-3zm0 3.200L7 7.100v4.100c0 3.300 1.900 5.800 5 7.500 3.100-1.700 5-4.200 5-7.500V7.100l-5-1.900z"/>',
  fire: '<path d="M13 2c.6 4 5.500 6.200 5.500 12A6.500 6.500 0 0 1 12 20.500 6.500 6.500 0 0 1 5.500 14c0-2.900 1.500-4.800 3-6.700.5 2 1.400 3 2.700 3.200C11 7.500 11.300 4.500 13 2z"/>',
  rescue: '<path fill-rule="evenodd" d="M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18zm0 5.500a3.500 3.500 0 1 0 0 7 3.500 3.500 0 0 0 0-7z"/>',
};

function pinElement(unit: Unit): HTMLDivElement {
  const el = document.createElement("div");
  el.className = `pin pin--${unit.service}`;
  el.innerHTML = `<svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor" aria-hidden="true">${PIN_SVG[unit.service]}</svg>`;
  el.title = unit.name;
  return el;
}

export interface LiveMapProps {
  units: Unit[];
  traffic: Traffic | null;
  point: { lat: number; lon: number; demo: boolean };
  onPoint: (lat: number, lon: number) => void;
  service: ServiceId;
  onService: (service: ServiceId) => void;
  highlight: Unit | null;
  route: Position[] | null;
  onLocate: () => void;
}

export function LiveMap({ units, traffic, point, onPoint, service, onService, highlight, route, onLocate }: LiveMapProps) {
  const container = useRef<HTMLDivElement>(null);
  const mapRef = useRef<MlMap | null>(null);
  const markers = useRef(new Map<string, Marker>());
  const meMarker = useRef<Marker | null>(null);
  const cardMarker = useRef<Marker | null>(null);
  const cardEl = useRef<HTMLDivElement | null>(null);
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);
  const [showTraffic, setShowTraffic] = useState(true);
  const [query, setQuery] = useState("");
  const onPointRef = useRef(onPoint);
  onPointRef.current = onPoint;

  useEffect(() => {
    if (!container.current) return;
    let map: MlMap;
    try {
      map = new maplibregl.Map({
        container: container.current,
        style: STYLE_URL,
        center: [point.lon, point.lat],
        zoom: 12.6,
        attributionControl: { compact: true },
        cooperativeGestures: true,
      });
    } catch {
      setFailed(true);
      return;
    }
    mapRef.current = map;
    map.on("load", () => {
      map.addSource("traffic", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
      map.addLayer({
        id: "traffic",
        type: "line",
        source: "traffic",
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-width": ["interpolate", ["linear"], ["zoom"], 10, 1.5, 14, 4, 17, 8],
          "line-opacity": 0.85,
          "line-color": [
            "match", ["get", "level"],
            "slow", TRAFFIC_COLORS.slow, "jam", TRAFFIC_COLORS.jam, "heavy", TRAFFIC_COLORS.heavy,
            "closed", TRAFFIC_COLORS.closed, TRAFFIC_COLORS.free,
          ],
        },
      });
      map.addSource("route", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
      map.addLayer({
        id: "route",
        type: "line",
        source: "route",
        layout: { "line-cap": "round", "line-join": "round" },
        paint: { "line-width": 3.5, "line-color": "#F03E3E", "line-dasharray": [0.2, 2] },
      });
      setReady(true);
    });
    map.on("click", (event) => onPointRef.current(event.lngLat.lat, event.lngLat.lng));
    map.on("error", () => undefined);
    const known = markers.current;
    return () => {
      known.clear();
      map.remove();
      mapRef.current = null;
    };
    // The map is created once; later position changes are applied by the effects below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Unit markers: create, move, restyle, remove.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready) return;
    const seen = new Set<string>();
    for (const unit of units) {
      if (unit.status === "off_duty") continue;
      seen.add(unit.id);
      const existing = markers.current.get(unit.id);
      const marker = existing
        ? existing.setLngLat([unit.lon, unit.lat])
        : new maplibregl.Marker({ element: pinElement(unit) }).setLngLat([unit.lon, unit.lat]).addTo(map);
      if (!existing) markers.current.set(unit.id, marker);
      const el = marker.getElement();
      el.classList.toggle("pin--dim", unit.service !== service);
      el.classList.toggle("pin--busy", !["available", "returning"].includes(unit.status));
      el.classList.toggle("pin--active", unit.id === highlight?.id);
    }
    for (const [id, marker] of markers.current) {
      if (!seen.has(id)) {
        marker.remove();
        markers.current.delete(id);
      }
    }
  }, [units, service, highlight?.id, ready]);

  // "Me" marker.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready) return;
    if (!meMarker.current) {
      const el = document.createElement("div");
      el.className = "me";
      meMarker.current = new maplibregl.Marker({ element: el }).setLngLat([point.lon, point.lat]).addTo(map);
    } else {
      meMarker.current.setLngLat([point.lon, point.lat]);
    }
  }, [point.lat, point.lon, ready]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready || !traffic) return;
    (map.getSource("traffic") as GeoJSONSource).setData(traffic.segments);
  }, [traffic, ready]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready) return;
    map.setLayoutProperty("traffic", "visibility", showTraffic ? "visible" : "none");
  }, [showTraffic, ready]);

  // Route and the highlighted unit's card.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready) return;
    const source = map.getSource("route") as GeoJSONSource;
    source.setData({
      type: "FeatureCollection",
      features: route && route.length > 1
        ? [{ type: "Feature", properties: {}, geometry: { type: "LineString", coordinates: route } }]
        : [],
    });
    map.setPaintProperty("route", "line-color", SERVICE_STYLES[service].color);
  }, [route, service, ready]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready) return;
    if (!highlight) {
      cardMarker.current?.remove();
      cardMarker.current = null;
      return;
    }
    if (!cardEl.current) {
      cardEl.current = document.createElement("div");
      cardEl.current.className = "map-card";
    }
    cardEl.current.innerHTML = "";
    const img = document.createElement("img");
    img.src = `/images/${highlight.photo}_thumb.jpg`;
    img.alt = "";
    const text = document.createElement("div");
    const title = document.createElement("b");
    title.textContent = highlight.name;
    const sub = document.createElement("span");
    sub.textContent = SERVICE_STYLES[highlight.service].short;
    const metrics = document.createElement("em");
    metrics.textContent = `${formatDistance(highlight.distance_m)} • ${formatEta(highlight.eta_s)}`;
    text.append(title, sub, metrics);
    cardEl.current.append(img, text);
    if (!cardMarker.current) {
      cardMarker.current = new maplibregl.Marker({ element: cardEl.current, anchor: "left", offset: [26, 0] })
        .setLngLat([highlight.lon, highlight.lat])
        .addTo(map);
    } else {
      cardMarker.current.setLngLat([highlight.lon, highlight.lat]);
    }
  }, [highlight, ready]);

  // Frame the user and the highlighted unit when the selection changes.
  const framed = useRef("");
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready || !highlight) return;
    const key = `${highlight.id}:${point.lat}:${point.lon}`;
    if (framed.current === key) return;
    framed.current = key;
    const bounds = boundsOf([[point.lon, point.lat], [highlight.lon, highlight.lat], ...(route ?? [])]);
    if (bounds) map.fitBounds(bounds, { padding: { top: 100, bottom: 140, left: 110, right: 230 }, maxZoom: 14.5, duration: 700 });
  }, [highlight, point.lat, point.lon, route, ready]);

  const search = (event: React.FormEvent) => {
    event.preventDefault();
    const needle = query.trim().toLowerCase();
    if (!needle) return;
    const hit = units.find((u) => u.name.toLowerCase().includes(needle) || u.callsign.toLowerCase().includes(needle));
    if (hit) {
      onService(hit.service);
      mapRef.current?.flyTo({ center: [hit.lon, hit.lat], zoom: 14.5 });
    }
  };

  return (
    <div className="livemap">
      <div ref={container} className="livemap__canvas" aria-label="Карта экстренных служб Алматы" />
      {failed && <div className="livemap__fallback">Карта недоступна в этом браузере (нужен WebGL).</div>}
      <div className="livemap__top">
        <form className="livemap__search" onSubmit={search} role="search">
          <Search />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Алматы, Казахстан"
            aria-label="Поиск подразделения" list="unit-names" />
          <datalist id="unit-names">
            {[...new Set(units.map((u) => u.name))].slice(0, 80).map((name) => <option key={name} value={name} />)}
          </datalist>
        </form>
        <div className="livemap__chips" role="tablist" aria-label="Служба">
          {SERVICE_ORDER.map((id) => (
            <button key={id} role="tab" aria-selected={id === service} onClick={() => onService(id)}
              className={`chip chip--${id}${id === service ? " chip--on" : ""}`}>
              <span className="chip__icon"><ServiceIcon service={id} size={14} /></span>
              {SERVICE_STYLES[id].short}
            </button>
          ))}
        </div>
      </div>
      <div className="livemap__controls">
        <button onClick={onLocate} title="Моё местоположение" aria-label="Моё местоположение"><Locate /></button>
        <button onClick={() => mapRef.current?.zoomIn()} title="Приблизить" aria-label="Приблизить"><Plus /></button>
        <button onClick={() => mapRef.current?.zoomOut()} title="Отдалить" aria-label="Отдалить"><Minus /></button>
        <button onClick={() => setShowTraffic((v) => !v)} title="Пробки" aria-label="Слой пробок"
          aria-pressed={showTraffic} className={showTraffic ? "is-on" : ""}><Layers /></button>
      </div>
      {traffic && showTraffic && (
        <div className="livemap__traffic" title="Смоделированная дорожная обстановка">
          <span className="livemap__index" style={{ background: indexColor(traffic.index) }}>{traffic.index}</span>
          <span>
            <b>{trafficLabel(traffic.index)}</b>
            <i>
              {(["slow", "jam", "heavy", "closed"] as const).map((level) => (
                <span key={level}><u style={{ background: TRAFFIC_COLORS[level] }} />{TRAFFIC_LABELS[level]}</span>
              ))}
            </i>
          </span>
        </div>
      )}
      <div className="livemap__hint">
        <Chevron size={12} /> Нажмите на карту, чтобы выбрать точку{point.demo ? " · сейчас демо-адрес" : ""}
      </div>
    </div>
  );
}
