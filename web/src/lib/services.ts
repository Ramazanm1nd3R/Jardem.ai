import type { ServiceId, Unit } from "../api/types";

export interface ServiceStyle {
  id: ServiceId;
  short: string;
  color: string;
  soft: string;
}

export const SERVICE_STYLES: Record<ServiceId, ServiceStyle> = {
  ambulance: { id: "ambulance", short: "Скорая", color: "#F03E3E", soft: "#FFECEC" },
  police: { id: "police", short: "Полиция", color: "#1E6FE0", soft: "#E8F1FE" },
  fire: { id: "fire", short: "Пожарные", color: "#F5821F", soft: "#FFF1E4" },
  rescue: { id: "rescue", short: "Спасатели", color: "#12B886", soft: "#E3F8F1" },
};

export const SERVICE_ORDER: ServiceId[] = ["ambulance", "police", "fire", "rescue"];

/** The nearest free unit of each service, in display order — the "Ближайшие подразделения" row. */
export function nearestPerService(units: Unit[]): Unit[] {
  const best = new Map<ServiceId, Unit>();
  for (const unit of units) {
    if (!unit.free || unit.eta_s == null) continue;
    const current = best.get(unit.service);
    if (!current || unit.eta_s < (current.eta_s ?? Infinity)) best.set(unit.service, unit);
  }
  return SERVICE_ORDER.flatMap((s) => (best.has(s) ? [best.get(s)!] : []));
}

/** Units to draw for the active filter ("all" shows everything on duty). */
export function filterUnits<T extends { service: ServiceId; status: string }>(
  units: T[],
  filter: ServiceId | "all",
): T[] {
  return units.filter((u) => u.status !== "off_duty" && (filter === "all" || u.service === filter));
}

/** Apply a batch of position updates to the unit list without re-fetching it. */
export function applyMoves<T extends { id: string }>(units: T[], moves: (Partial<T> & { id: string })[]): T[] {
  if (moves.length === 0) return units;
  const byId = new Map(moves.map((m) => [m.id, m]));
  let changed = false;
  const next = units.map((u) => {
    const move = byId.get(u.id);
    if (!move) return u;
    changed = true;
    return { ...u, ...move };
  });
  return changed ? next : units;
}

/** Chip label for a category: ambulance titles drop the repeated noun ("Экстренная помощь" → "Экстренная"). */
export function shortCategory(service: ServiceId, title: string): string {
  return service === "ambulance" ? title.split(" ")[0] : title;
}
