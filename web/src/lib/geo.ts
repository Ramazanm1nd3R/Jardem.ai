import type { Position } from "../api/types";

const EARTH_RADIUS_M = 6_371_008.8;
const rad = (deg: number) => (deg * Math.PI) / 180;

export function haversine(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(Math.min(1, a)));
}

export type Bounds = [[west: number, south: number], [east: number, north: number]];

/** Bounding box of [lon, lat] positions; null for an empty list. */
export function boundsOf(points: Position[]): Bounds | null {
  if (points.length === 0) return null;
  let west = Infinity, south = Infinity, east = -Infinity, north = -Infinity;
  for (const [lon, lat] of points) {
    west = Math.min(west, lon);
    east = Math.max(east, lon);
    south = Math.min(south, lat);
    north = Math.max(north, lat);
  }
  return [[west, south], [east, north]];
}

/** bbox as the API reports it: [minLat, minLon, maxLat, maxLon]. */
export function insideBbox(lat: number, lon: number, bbox: [number, number, number, number]): boolean {
  return lat >= bbox[0] && lat <= bbox[2] && lon >= bbox[1] && lon <= bbox[3];
}

/** Linear interpolation between two positions, t in [0, 1] (clamped). */
export function lerpPosition(from: Position, to: Position, t: number): Position {
  const k = Math.min(1, Math.max(0, t));
  return [from[0] + (to[0] - from[0]) * k, from[1] + (to[1] - from[1]) * k];
}
