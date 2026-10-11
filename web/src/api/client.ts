import type { Comparison, Meta, ServiceInfo, Stats, Traffic, Unit } from "./types";

const BASE = "/api/v1";

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(BASE + path, {
    ...init,
    headers: { "content-type": "application/json", ...init?.headers },
  });
  if (!response.ok) {
    let detail = response.statusText;
    try {
      detail = (await response.json()).detail ?? detail;
    } catch {
      // non-JSON error body: keep the status text
    }
    throw new ApiError(response.status, String(detail));
  }
  return response.json() as Promise<T>;
}

const query = (params: Record<string, string | number | undefined>) => {
  const q = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) if (value !== undefined) q.set(key, String(value));
  const text = q.toString();
  return text ? `?${text}` : "";
};

export const api = {
  meta: () => request<Meta>("/meta"),
  catalog: () => request<ServiceInfo[]>("/catalog"),
  stats: () => request<Stats>("/stats"),
  traffic: () => request<Traffic>("/traffic"),
  units: () => request<Unit[]>("/units"),
  unitsNear: (lat: number, lon: number, limit = 200) => request<Unit[]>(`/units${query({ lat, lon, limit })}`),
  unitRoute: (id: string, lat: number, lon: number) => request<Unit>(`/units/${id}${query({ lat, lon })}`),
  compare: (category: string, lat: number, lon: number) =>
    request<Comparison>("/dispatch/compare", { method: "POST", body: JSON.stringify({ category, lat, lon }) }),
};

export function socketUrl(): string {
  const scheme = location.protocol === "https:" ? "wss" : "ws";
  return `${scheme}://${location.host}${BASE}/ws`;
}
