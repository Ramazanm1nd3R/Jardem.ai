import type { FeatureCollection, LineString } from "geojson";

export type ServiceId = "ambulance" | "police" | "fire" | "rescue";
export type UnitStatus =
  | "off_duty" | "available" | "assigned" | "en_route" | "on_scene" | "transporting" | "returning";
export type TrafficLevel = "free" | "slow" | "jam" | "heavy" | "closed";
export type Position = [lon: number, lat: number];

export interface Category {
  id: string;
  title: string;
  description: string;
  priority: number;
  units_required: number;
}

export interface ServiceInfo {
  id: ServiceId;
  title: string;
  phone: string;
  categories: Category[];
}

export interface UnitBrief {
  id: string;
  service: ServiceId;
  kind: string;
  status: UnitStatus;
  lat: number;
  lon: number;
  heading: number;
}

export interface Unit extends UnitBrief {
  name: string;
  callsign: string;
  department_id: string;
  status_label: string;
  free: boolean;
  plate: string;
  vehicle: string;
  photo: string;
  capabilities: string[];
  distance_m: number | null;
  eta_s: number | null;
  route?: Position[];
}

export interface Meta {
  city: string;
  center: { lat: number; lon: number };
  bbox: [number, number, number, number];
  disclaimer: string;
  phones: Record<ServiceId, string>;
  strategy: string;
  sim_speed: number;
  app_url: string;
}

export interface Traffic {
  simulated: boolean;
  index: number;
  local_hour: number;
  hotspots: { id: string; lat: number; lon: number; radius_m: number; severity: number; kind: string }[];
  closures: { id: string; lat: number; lon: number; reason: string }[];
  segments: FeatureCollection<LineString, { level: TrafficLevel; speed_kph: number; name: string }>;
}

export interface Stats {
  services: Record<ServiceId, { active_incidents: number; units: number; units_free: number }>;
  active_incidents: number;
  departments: number;
  mean_arrival_s: number | null;
  served: number;
  traffic_index: number;
  strategy: string;
}

export interface Candidate extends Unit {
  coverage_loss_s: number;
  overqualified: number;
  cost: number;
}

export interface Comparison {
  picks: Record<"nearest" | "min_eta" | "jardem", string[]>;
  candidates: Candidate[];
}

export type RealtimeEvent =
  | { type: "hello" }
  | { type: "units.moved"; units: UnitBrief[] }
  | { type: "unit.updated"; unit: UnitBrief; incident_id: string | null }
  | { type: "incident.updated"; incident_id: string; status: string; service: ServiceId }
  | { type: "message.created"; unit_id: string }
  | { type: "traffic.updated" };
