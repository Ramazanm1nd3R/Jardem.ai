import { useCallback, useEffect, useRef, useState } from "react";
import { api, socketUrl } from "../api/client";
import type { Meta, RealtimeEvent, ServiceInfo, Stats, Traffic, Unit } from "../api/types";
import { applyMoves } from "../lib/services";
import { backoffMs } from "../lib/traffic";

export interface LiveState {
  meta: Meta | null;
  catalog: ServiceInfo[];
  units: Unit[];
  stats: Stats | null;
  traffic: Traffic | null;
  online: boolean;
  error: string | null;
  point: { lat: number; lon: number; demo: boolean };
  setPoint: (lat: number, lon: number) => void;
}

const DEMO_POINT = { lat: 43.2445, lon: 76.9457 };
const REFRESH_MS = 20_000;

/** Live platform state: initial REST load, WebSocket deltas, periodic re-sync. */
export function useLive(): LiveState {
  const [meta, setMeta] = useState<Meta | null>(null);
  const [catalog, setCatalog] = useState<ServiceInfo[]>([]);
  const [units, setUnits] = useState<Unit[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [traffic, setTraffic] = useState<Traffic | null>(null);
  const [online, setOnline] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [point, setPointState] = useState({ ...DEMO_POINT, demo: true });
  const pointRef = useRef(point);
  pointRef.current = point;

  const loadUnits = useCallback(async () => {
    const { lat, lon } = pointRef.current;
    setUnits(await api.unitsNear(lat, lon));
  }, []);

  const refresh = useCallback(async () => {
    try {
      const [s, t] = await Promise.all([api.stats(), api.traffic(), loadUnits()]);
      setStats(s);
      setTraffic(t);
      setError(null);
    } catch {
      setError("Нет связи с сервером Jardem.ai. Данные на карте могут быть неактуальны.");
    }
  }, [loadUnits]);

  useEffect(() => {
    api.meta().then(setMeta).catch(() => undefined);
    api.catalog().then(setCatalog).catch(() => undefined);
    void refresh();
    const timer = setInterval(() => void refresh(), REFRESH_MS);
    return () => clearInterval(timer);
  }, [refresh]);

  useEffect(() => {
    let socket: WebSocket | null = null;
    let attempt = 0;
    let retry: ReturnType<typeof setTimeout> | undefined;
    let closed = false;

    const connect = () => {
      socket = new WebSocket(socketUrl());
      socket.onopen = () => {
        attempt = 0;
        setOnline(true);
      };
      socket.onmessage = (message) => {
        const event = JSON.parse(message.data) as RealtimeEvent;
        if (event.type === "units.moved") setUnits((current) => applyMoves(current, event.units));
        else if (event.type === "unit.updated") setUnits((current) => applyMoves(current, [event.unit]));
        else if (event.type === "traffic.updated") api.traffic().then(setTraffic).catch(() => undefined);
      };
      socket.onclose = () => {
        setOnline(false);
        if (!closed) retry = setTimeout(connect, backoffMs(attempt++));
      };
    };
    connect();
    return () => {
      closed = true;
      clearTimeout(retry);
      socket?.close();
    };
  }, []);

  const setPoint = useCallback(
    (lat: number, lon: number) => {
      setPointState({ lat, lon, demo: false });
      pointRef.current = { lat, lon, demo: false };
      void loadUnits().catch(() => undefined);
    },
    [loadUnits],
  );

  return { meta, catalog, units, stats, traffic, online, error, point, setPoint };
}
