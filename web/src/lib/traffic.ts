import type { TrafficLevel } from "../api/types";

export const TRAFFIC_COLORS: Record<TrafficLevel, string> = {
  free: "#2FB344",
  slow: "#F2C037",
  jam: "#F08C00",
  heavy: "#E03131",
  closed: "#495057",
};

export const TRAFFIC_LABELS: Record<TrafficLevel, string> = {
  free: "Свободно",
  slow: "Замедление",
  jam: "Пробка",
  heavy: "Затор",
  closed: "Перекрыто",
};

/** Colour of the 0–10 city index badge. */
export function indexColor(index: number): string {
  if (index <= 3) return TRAFFIC_COLORS.free;
  if (index <= 6) return TRAFFIC_COLORS.slow;
  if (index <= 8) return TRAFFIC_COLORS.jam;
  return TRAFFIC_COLORS.heavy;
}

/** Reconnect delay for the realtime socket: 1 s doubling to a 15 s ceiling. */
export function backoffMs(attempt: number): number {
  return Math.min(15_000, 1000 * 2 ** Math.max(0, attempt));
}
