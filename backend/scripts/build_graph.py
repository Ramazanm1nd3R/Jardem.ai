"""Build the compact Almaty road graph from a raw Overpass (OSM) extract.

Usage:
    python scripts/build_graph.py data/raw/almaty_roads.json app/data/almaty_graph.json.gz

The raw extract is produced by the Overpass query documented in docs/data.md.
Output format (gzipped JSON):
    nodes: [[lat, lon], ...]
    names: [str, ...]
    edges: [[u, v, length_m, class_idx, speed_kph, name_idx, bidirectional, [lat, lon, ...]], ...]
The geometry list holds only the intermediate shape points (endpoints are the nodes).
"""

from __future__ import annotations

import gzip
import json
import math
import sys
from collections import defaultdict

ROAD_CLASSES = [
    "motorway",
    "trunk",
    "primary",
    "secondary",
    "tertiary",
    "unclassified",
    "residential",
    "living_street",
]
# Free-flow speeds (km/h) for an urban network; used when OSM has no usable maxspeed.
DEFAULT_SPEED = {
    "motorway": 90,
    "trunk": 70,
    "primary": 60,
    "secondary": 50,
    "tertiary": 40,
    "unclassified": 30,
    "residential": 25,
    "living_street": 10,
}
LINK_SPEED = 40
EARTH_RADIUS_M = 6_371_008.8


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def parse_speed(tags: dict, cls: str, is_link: bool) -> int:
    default = LINK_SPEED if is_link else DEFAULT_SPEED[cls]
    raw = tags.get("maxspeed", "")
    try:
        value = int(float(raw.split()[0]))
    except (ValueError, IndexError):
        return default
    if not 5 <= value <= 130:
        return default
    # Posted limits overstate urban free-flow on minor streets; never exceed class default by >20.
    return min(value, default + 20)


def oneway_direction(tags: dict, cls: str) -> int:
    """1 = forward only, -1 = backward only, 0 = both directions."""
    ow = tags.get("oneway", "")
    if ow in ("yes", "true", "1"):
        return 1
    if ow in ("-1", "reverse"):
        return -1
    if ow in ("no", "false", "0"):
        return 0
    if cls == "motorway" or tags.get("junction") in ("roundabout", "circular"):
        return 1
    return 0


def largest_scc(n: int, adj: list[list[int]]) -> set[int]:
    """Iterative Tarjan; returns the node set of the largest strongly connected component."""
    index = [-1] * n
    low = [0] * n
    on_stack = [False] * n
    stack: list[int] = []
    best: list[int] = []
    counter = 0
    for root in range(n):
        if index[root] != -1:
            continue
        work = [(root, 0)]
        while work:
            v, i = work[-1]
            if i == 0:
                index[v] = low[v] = counter
                counter += 1
                stack.append(v)
                on_stack[v] = True
            advanced = False
            neighbours = adj[v]
            while i < len(neighbours):
                w = neighbours[i]
                i += 1
                if index[w] == -1:
                    work[-1] = (v, i)
                    work.append((w, 0))
                    advanced = True
                    break
                if on_stack[w]:
                    low[v] = min(low[v], index[w])
            if advanced:
                continue
            work.pop()
            if work:
                parent = work[-1][0]
                low[parent] = min(low[parent], low[v])
            if low[v] == index[v]:
                comp = []
                while True:
                    w = stack.pop()
                    on_stack[w] = False
                    comp.append(w)
                    if w == v:
                        break
                if len(comp) > len(best):
                    best = comp
    return set(best)


def build(raw_path: str, out_path: str) -> dict:
    with open(raw_path, encoding="utf-8") as fh:
        raw = json.load(fh)

    coords: dict[int, tuple[float, float]] = {}
    ways = []
    for el in raw["elements"]:
        if el["type"] == "node":
            coords[el["id"]] = (el["lat"], el["lon"])
        elif el["type"] == "way":
            tags = el.get("tags", {})
            hw = tags.get("highway", "")
            is_link = hw.endswith("_link")
            cls = hw[:-5] if is_link else hw
            if cls not in DEFAULT_SPEED:
                continue
            if tags.get("access") in ("no", "private") or tags.get("area") == "yes":
                continue
            ways.append((el["nodes"], tags, cls, is_link))

    usage: dict[int, int] = defaultdict(int)
    for nodes, *_ in ways:
        for i, nid in enumerate(nodes):
            usage[nid] += 2 if i in (0, len(nodes) - 1) else 1

    node_index: dict[int, int] = {}
    node_list: list[tuple[float, float]] = []

    def idx(osm_id: int) -> int:
        if osm_id not in node_index:
            node_index[osm_id] = len(node_list)
            node_list.append(coords[osm_id])
        return node_index[osm_id]

    names: dict[str, int] = {"": 0}
    segments = []  # (u, v, length, cls_idx, speed, name_idx, direction, shape)
    for nodes, tags, cls, is_link in ways:
        nodes = [n for n in nodes if n in coords]
        if len(nodes) < 2:
            continue
        name = tags.get("name:ru") or tags.get("name") or ""
        name_idx = names.setdefault(name, len(names))
        speed = parse_speed(tags, cls, is_link)
        direction = oneway_direction(tags, cls)
        cls_idx = ROAD_CLASSES.index(cls)
        start = 0
        for i in range(1, len(nodes)):
            if usage[nodes[i]] > 1 or i == len(nodes) - 1:
                part = nodes[start : i + 1]
                start = i
                if part[0] == part[-1] and len(part) < 3:
                    continue
                length = sum(
                    haversine_m(*coords[a], *coords[b]) for a, b in zip(part, part[1:])
                )
                if length < 0.5:
                    continue
                shape = [c for n in part[1:-1] for c in coords[n]]
                segments.append(
                    (idx(part[0]), idx(part[-1]), length, cls_idx, speed, name_idx, direction, shape)
                )

    n = len(node_list)
    adj: list[list[int]] = [[] for _ in range(n)]
    for u, v, *_rest, direction, _shape in segments:
        if direction >= 0:
            adj[u].append(v)
        if direction <= 0:
            adj[v].append(u)
    keep = largest_scc(n, adj)

    remap: dict[int, int] = {}
    out_nodes = []
    for old in sorted(keep):
        remap[old] = len(out_nodes)
        lat, lon = node_list[old]
        out_nodes.append([round(lat, 6), round(lon, 6)])

    out_edges = []
    for u, v, length, cls_idx, speed, name_idx, direction, shape in segments:
        if u not in keep or v not in keep:
            continue
        if direction == -1:
            u, v = v, u
            pairs = [shape[i : i + 2] for i in range(0, len(shape), 2)][::-1]
            shape = [c for p in pairs for c in p]
        out_edges.append(
            [
                remap[u],
                remap[v],
                round(length, 1),
                cls_idx,
                speed,
                name_idx,
                1 if direction == 0 else 0,
                [round(c, 5) for c in shape],
            ]
        )

    name_list = [""] * len(names)
    for name, i in names.items():
        name_list[i] = name

    lats = [p[0] for p in out_nodes]
    lons = [p[1] for p in out_nodes]
    graph = {
        "meta": {
            "source": "OpenStreetMap contributors (ODbL), via Overpass API",
            "osm_base": raw.get("osm3s", {}).get("timestamp_osm_base"),
            "bbox": [min(lats), min(lons), max(lats), max(lons)],
            "road_classes": ROAD_CLASSES,
        },
        "nodes": out_nodes,
        "names": name_list,
        "edges": out_edges,
    }
    with gzip.open(out_path, "wt", encoding="utf-8", compresslevel=9) as fh:
        json.dump(graph, fh, ensure_ascii=False, separators=(",", ":"))
    return {
        "raw_ways": len(ways),
        "nodes": len(out_nodes),
        "edges": len(out_edges),
        "dropped_nodes": n - len(out_nodes),
        "km": round(sum(e[2] for e in out_edges) / 1000, 1),
    }


if __name__ == "__main__":
    print(build(sys.argv[1], sys.argv[2]))
