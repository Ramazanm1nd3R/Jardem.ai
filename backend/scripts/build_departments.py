"""Build the department catalogue from the raw OSM POI extract.

Usage: python scripts/build_departments.py data/raw/almaty_pois.json app/data/almaty_departments.json

Fire stations and police departments are real OSM objects. OSM has almost no ambulance
substations for Almaty, so substations are anchored to well-spread hospitals and flagged
`approximate`; rescue bases are likewise approximate. See docs/data.md.
"""

from __future__ import annotations

import json
import math
import re
import sys


def dist(a, b):
    kx = 111_320 * math.cos(math.radians(43.25))
    return math.hypot((a[0] - b[0]) * 110_540, (a[1] - b[1]) * kx)


def spread(points, k, first=(43.238, 76.945)):
    """Farthest-point sampling: k points covering the city as evenly as possible."""
    chosen = [min(points, key=lambda p: dist(p["pos"], first))]
    while len(chosen) < min(k, len(points)):
        chosen.append(max(points, key=lambda p: min(dist(p["pos"], c["pos"]) for c in chosen)))
    return chosen


def main(raw_path: str, out_path: str) -> None:
    raw = json.load(open(raw_path, encoding="utf-8"))
    pois = []
    for el in raw["elements"]:
        tags = el.get("tags", {})
        kind = tags.get("amenity") or tags.get("emergency")
        lat = el.get("lat") or el.get("center", {}).get("lat")
        lon = el.get("lon") or el.get("center", {}).get("lon")
        if lat is None or not (43.17 <= lat <= 43.36 and 76.79 <= lon <= 77.03):
            continue
        name = tags.get("name:ru") or tags.get("name") or ""
        street = tags.get("addr:street", "")
        house = tags.get("addr:housenumber", "")
        address = f"{street}, {house}".strip(", ") if street else ""
        pois.append({"kind": kind, "name": name, "pos": (lat, lon), "address": address,
                     "osm": f"{el['type']}/{el['id']}"})

    out = []

    def add(service, name, p, approximate=False):
        out.append({
            "id": f"{service}-{len([d for d in out if d['service'] == service]) + 1}",
            "service": service, "name": name, "address": p.get("address", ""),
            "lat": round(p["pos"][0], 6), "lon": round(p["pos"][1], 6),
            "approximate": approximate, "source": p.get("osm", "approximate"),
        })

    fire = sorted((p for p in pois if p["kind"] == "fire_station"), key=lambda p: p["osm"])
    for p in fire:
        num = re.search(r"\d+", p["name"])
        special = "СПЧ" in p["name"]
        post = "пост" in p["name"].lower()
        label = ("Пожарный пост" if post else "Специализированная пожарная часть" if special
                 else "Пожарная часть")
        add("fire", f"{label} №{num.group(0)}" if num else label, p)

    police = [p for p in pois if p["kind"] == "police" and re.search(
        r"РУВД|УВД|управление полиции|участков|полиция бөлім", p["name"], re.I)]
    for p in spread(police, 14):
        name = p["name"]
        if name.isupper():
            name = "Управление полиции Медеуского района" if "МЕДЕУ" in name else name.capitalize()
        add("police", name[0].upper() + name[1:], p)

    hospitals = [p for p in pois if p["kind"] == "hospital" and p["name"]]
    for i, p in enumerate(spread(hospitals, 12), start=1):
        add("ambulance", f"Подстанция №{i}", p,
            approximate=True)

    for name, pos in [("Служба спасения города Алматы", (43.2567, 76.9286)),
                      ("Горноспасательный пост «Медеу»", (43.1935, 77.0075)),
                      ("Поисково-спасательный отряд «Север»", (43.3180, 76.9320))]:
        add("rescue", name, {"pos": pos, "address": ""}, approximate=True)

    json.dump({"departments": out}, open(out_path, "w", encoding="utf-8"), ensure_ascii=False,
              indent=1)
    for d in out:
        print(d["id"], "|", d["name"], "|", d["address"], "|", d["lat"], d["lon"])


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
