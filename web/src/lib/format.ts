/** Human-readable distances and durations in Russian, as shown across the product. */

export function formatDistance(metres: number | null | undefined): string {
  if (metres == null || !Number.isFinite(metres) || metres < 0) return "—";
  if (metres < 1000) {
    const rounded = metres < 100 ? Math.round(metres / 10) * 10 : Math.round(metres / 50) * 50;
    if (rounded < 1000) return `${Math.max(rounded, 10)} м`;
  }
  const km = metres / 1000;
  const text = km < 10 ? km.toFixed(1).replace(".", ",") : String(Math.round(km));
  return `${text} км`;
}

export function formatEta(seconds: number | null | undefined): string {
  if (seconds == null || !Number.isFinite(seconds) || seconds < 0) return "—";
  const minutes = Math.ceil(seconds / 60);
  if (minutes <= 1) return "1 мин";
  if (minutes < 60) return `${minutes} мин`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest === 0 ? `${hours} ч` : `${hours} ч ${rest} мин`;
}

/** Russian plural form: plural(3, "экипаж", "экипажа", "экипажей") → "экипажа". */
export function plural(n: number, one: string, few: string, many: string): string {
  const abs = Math.abs(n) % 100;
  const last = abs % 10;
  if (abs > 10 && abs < 20) return many;
  if (last === 1) return one;
  if (last >= 2 && last <= 4) return few;
  return many;
}

export function trafficLabel(index: number): string {
  if (index <= 2) return "Дороги свободны";
  if (index <= 4) return "Местами затруднения";
  if (index <= 6) return "Плотное движение";
  if (index <= 8) return "Серьёзные пробки";
  return "Город стоит";
}
