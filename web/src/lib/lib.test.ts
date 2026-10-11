import { describe, expect, it } from "vitest";
import type { Unit } from "../api/types";
import { formatDistance, formatEta, plural, trafficLabel } from "./format";
import { boundsOf, haversine, insideBbox, lerpPosition } from "./geo";
import { applyMoves, filterUnits, nearestPerService, SERVICE_ORDER, SERVICE_STYLES, shortCategory } from "./services";
import { backoffMs, indexColor, TRAFFIC_COLORS, TRAFFIC_LABELS } from "./traffic";

describe("formatDistance", () => {
  it.each([
    [0, "10 м"], [4, "10 м"], [14, "10 м"], [15, "20 м"], [96, "100 м"], [99, "100 м"],
    [100, "100 м"], [124, "100 м"], [125, "150 м"], [800, "800 м"], [974, "950 м"],
    [975, "1,0 км"], [999, "1,0 км"], [1000, "1,0 км"], [1200, "1,2 км"], [1249, "1,2 км"],
    [2400, "2,4 км"], [9940, "9,9 км"], [10_000, "10 км"], [12_600, "13 км"],
  ])("%d m → %s", (m, text) => expect(formatDistance(m)).toBe(text));

  it("shows a dash for missing or invalid values", () => {
    for (const bad of [null, undefined, NaN, Infinity, -1]) expect(formatDistance(bad)).toBe("—");
  });
});

describe("formatEta", () => {
  it.each([
    [0, "1 мин"], [1, "1 мин"], [60, "1 мин"], [61, "2 мин"], [120, "2 мин"], [240, "4 мин"],
    [3540, "59 мин"], [3541, "1 ч"], [3600, "1 ч"], [3601, "1 ч 1 мин"], [4320, "1 ч 12 мин"],
    [7200, "2 ч"],
  ])("%d s → %s", (s, text) => expect(formatEta(s)).toBe(text));

  it("shows a dash for missing or invalid values", () => {
    for (const bad of [null, undefined, NaN, Infinity, -5]) expect(formatEta(bad)).toBe("—");
  });
});

describe("plural", () => {
  it.each([
    [1, "экипаж"], [2, "экипажа"], [4, "экипажа"], [5, "экипажей"], [0, "экипажей"],
    [10, "экипажей"], [11, "экипажей"], [12, "экипажей"], [14, "экипажей"], [19, "экипажей"],
    [20, "экипажей"], [21, "экипаж"], [22, "экипажа"], [25, "экипажей"], [101, "экипаж"],
    [111, "экипажей"], [112, "экипажей"], [121, "экипаж"], [-1, "экипаж"], [-3, "экипажа"],
  ])("%d → %s", (n, word) => expect(plural(n, "экипаж", "экипажа", "экипажей")).toBe(word));
});

describe("trafficLabel / indexColor", () => {
  it("maps the 0–10 index to wording", () => {
    expect([0, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(trafficLabel)).toEqual([
      "Дороги свободны", "Дороги свободны", "Местами затруднения", "Местами затруднения",
      "Плотное движение", "Плотное движение", "Серьёзные пробки", "Серьёзные пробки",
      "Город стоит", "Город стоит",
    ]);
  });

  it("maps the index to a colour", () => {
    expect([0, 3, 4, 6, 7, 8, 9].map(indexColor)).toEqual([
      TRAFFIC_COLORS.free, TRAFFIC_COLORS.free, TRAFFIC_COLORS.slow, TRAFFIC_COLORS.slow,
      TRAFFIC_COLORS.jam, TRAFFIC_COLORS.jam, TRAFFIC_COLORS.heavy,
    ]);
  });

  it("has a colour and a label for every level", () => {
    expect(Object.keys(TRAFFIC_COLORS)).toEqual(["free", "slow", "jam", "heavy", "closed"]);
    expect(Object.keys(TRAFFIC_LABELS)).toEqual(Object.keys(TRAFFIC_COLORS));
    expect(new Set(Object.values(TRAFFIC_COLORS)).size).toBe(5);
    for (const color of Object.values(TRAFFIC_COLORS)) expect(color).toMatch(/^#[0-9A-F]{6}$/);
    expect(new Set(Object.values(TRAFFIC_LABELS)).size).toBe(5);
    for (const label of Object.values(TRAFFIC_LABELS)) expect(label.length).toBeGreaterThan(4);
    expect(TRAFFIC_LABELS.closed).toBe("Перекрыто");
    expect(TRAFFIC_LABELS.free).toBe("Свободно");
  });
});

describe("backoffMs", () => {
  it("doubles from one second and caps at fifteen", () => {
    expect([0, 1, 2, 3, 4, 5, 20].map(backoffMs)).toEqual([1000, 2000, 4000, 8000, 15000, 15000, 15000]);
    expect(backoffMs(-3)).toBe(1000);
  });
});

describe("geo", () => {
  it("haversine matches known distances", () => {
    expect(haversine(43, 76.9, 44, 76.9)).toBeCloseTo(111_195, -2);
    expect(haversine(43, 76, 43, 77)).toBeCloseTo(111_195 * Math.cos((43 * Math.PI) / 180), -2);
    expect(haversine(43.2, 76.9, 43.2, 76.9)).toBe(0);
    expect(haversine(0, 0, 0, 180)).toBeCloseTo(Math.PI * 6_371_008.8, 0);
    expect(haversine(43.2, 76.9, 43.3, 77.0)).toBeCloseTo(haversine(43.3, 77.0, 43.2, 76.9), 6);
  });

  it("boundsOf returns west/south/east/north", () => {
    expect(boundsOf([])).toBeNull();
    expect(boundsOf([[76.9, 43.2]])).toEqual([[76.9, 43.2], [76.9, 43.2]]);
    expect(boundsOf([[76.9, 43.3], [76.8, 43.2], [77.0, 43.25]])).toEqual([[76.8, 43.2], [77.0, 43.3]]);
  });

  it("insideBbox is inclusive on every edge", () => {
    const box: [number, number, number, number] = [43.1, 76.7, 43.4, 77.1];
    expect(insideBbox(43.2, 76.9, box)).toBe(true);
    expect(insideBbox(43.1, 76.7, box)).toBe(true);
    expect(insideBbox(43.4, 77.1, box)).toBe(true);
    expect(insideBbox(43.09, 76.9, box)).toBe(false);
    expect(insideBbox(43.41, 76.9, box)).toBe(false);
    expect(insideBbox(43.2, 76.69, box)).toBe(false);
    expect(insideBbox(43.2, 77.11, box)).toBe(false);
  });

  it("lerpPosition interpolates and clamps", () => {
    expect(lerpPosition([0, 10], [10, 30], 0.25)).toEqual([2.5, 15]);
    expect(lerpPosition([4, 10], [8, 30], 0.5)).toEqual([6, 20]);
    expect(lerpPosition([0, 10], [10, 30], 0)).toEqual([0, 10]);
    expect(lerpPosition([0, 10], [10, 30], 1)).toEqual([10, 30]);
    expect(lerpPosition([0, 10], [10, 30], -2)).toEqual([0, 10]);
    expect(lerpPosition([0, 10], [10, 30], 7)).toEqual([10, 30]);
  });
});

const unit = (id: string, service: Unit["service"], eta: number | null, free = true, status = "available"): Unit =>
  ({ id, service, eta_s: eta, free, status, lat: 43.2, lon: 76.9 }) as Unit;

describe("services", () => {
  it("defines a distinct style per service in display order", () => {
    expect(SERVICE_ORDER).toEqual(["ambulance", "police", "fire", "rescue"]);
    expect(SERVICE_ORDER.map((s) => SERVICE_STYLES[s].id)).toEqual(SERVICE_ORDER);
    expect(SERVICE_ORDER.map((s) => SERVICE_STYLES[s].short)).toEqual(["Скорая", "Полиция", "Пожарные", "Спасатели"]);
    expect(new Set(SERVICE_ORDER.map((s) => SERVICE_STYLES[s].color)).size).toBe(4);
    expect(new Set(SERVICE_ORDER.map((s) => SERVICE_STYLES[s].soft)).size).toBe(4);
    for (const s of SERVICE_ORDER) {
      expect(SERVICE_STYLES[s].color).toMatch(/^#[0-9A-F]{6}$/);
      expect(SERVICE_STYLES[s].soft).toMatch(/^#[0-9A-F]{6}$/);
    }
  });

  it("shortCategory trims ambulance titles only", () => {
    expect(shortCategory("ambulance", "Экстренная помощь")).toBe("Экстренная");
    expect(shortCategory("ambulance", "Реанимация")).toBe("Реанимация");
    expect(shortCategory("fire", "Пожарные части")).toBe("Пожарные части");
    expect(shortCategory("rescue", "ЧС и стихийные бедствия")).toBe("ЧС и стихийные бедствия");
  });

  it("nearestPerService picks the fastest free unit of each service", () => {
    const picked = nearestPerService([
      unit("f-slow", "fire", 500), unit("a-busy", "ambulance", 10, false), unit("a-2", "ambulance", 300),
      unit("a-1", "ambulance", 240), unit("f-fast", "fire", 360), unit("p-unknown", "police", null),
      unit("a-3", "ambulance", 240),
    ]);
    expect(picked.map((u) => u.id)).toEqual(["a-1", "f-fast"]);
    expect(nearestPerService([])).toEqual([]);
  });

  it("filterUnits hides off-duty crews and applies the service filter", () => {
    const all = [unit("a", "ambulance", 1), unit("p", "police", 1), unit("off", "ambulance", 1, false, "off_duty")];
    expect(filterUnits(all, "all").map((u) => u.id)).toEqual(["a", "p"]);
    expect(filterUnits(all, "ambulance").map((u) => u.id)).toEqual(["a"]);
    expect(filterUnits(all, "fire")).toEqual([]);
  });

  it("applyMoves merges updates and keeps identity when nothing matches", () => {
    const all = [unit("a", "ambulance", 1), unit("p", "police", 1)];
    expect(applyMoves(all, [])).toBe(all);
    expect(applyMoves(all, [{ id: "ghost", lat: 1 }])).toBe(all);
    const moved = applyMoves(all, [{ id: "p", lat: 43.3, status: "en_route" }]);
    expect(moved).not.toBe(all);
    expect(moved[0]).toBe(all[0]);
    expect(moved[1]).toMatchObject({ id: "p", lat: 43.3, lon: 76.9, status: "en_route", service: "police" });
    expect(all[1].lat).toBe(43.2);
  });
});
