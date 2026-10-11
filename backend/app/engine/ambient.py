"""Background activity for the demo: simulated calls and congestion hotspots.

Without it the map is static until someone files a call. Everything generated here is
flagged synthetic and is driven by a seeded RNG, so runs are reproducible.
"""

from __future__ import annotations

import random

from app.domain.graph import ARTERIAL_MAX_CLASS
from app.domain.traffic import Hotspot, rush_intensity
from app.engine.core import Engine

# (category, weight, sample descriptions)
CALL_MIX: tuple[tuple[str, float, tuple[str, ...]], ...] = (
    ("emergency", 30, ("Боль в груди, давление 180", "Упал с высоты, перелом ноги",
                       "Сильная аллергическая реакция", "Травма головы, кровь")),
    ("reanimation", 6, ("Мужчина, около 60 лет, потерял сознание, не дышит",
                        "Женщина без сознания, судороги")),
    ("pediatric", 12, ("Высокая температура у ребёнка, 3 года", "Ребёнок упал, травма руки")),
    ("planned", 8, ("Транспортировка лежачего пациента в стационар",)),
    ("patrol", 14, ("Драка возле магазина", "Шум и угрозы от соседей", "Кража из автомобиля")),
    ("traffic", 12, ("ДТП, есть пострадавшие", "Столкновение двух автомобилей, без пострадавших")),
    ("district", 4, ("Семейный скандал, просят участкового",)),
    ("fire_engine", 7, ("Пожар в квартире", "Горит мусорный контейнер, огонь рядом с домом",
                        "Дым из подвала жилого дома")),
    ("fire_rescue", 4, ("Человек заблокирован в лифте", "ДТП, водитель зажат в машине")),
    ("search", 2, ("Пропал пожилой человек, ушёл и не вернулся",)),
    ("mountain", 1, ("Турист подвернул ногу на тропе в ущелье",)),
)
HOTSPOT_KINDS = ("jam", "jam", "jam", "accident", "roadworks")


class Ambient:
    def __init__(self, engine: Engine, *, calls_per_hour: float = 0.0, max_hotspots: int = 0,
                 seed: int = 1, max_open_calls: int = 12):
        self.engine = engine
        self.calls_per_hour = calls_per_hour
        self.max_hotspots = max_hotspots
        self.max_open_calls = max_open_calls
        self.rng = random.Random(seed)
        self._serial = 0
        self._arterials = [e for e in engine.graph.edges if e.road_class <= ARTERIAL_MAX_CLASS]
        lats = sorted(lat for lat, _ in engine.graph.nodes)
        lons = sorted(lon for _, lon in engine.graph.nodes)
        # Calls come from the built-up core: the middle 80% of the network's extent.
        n = len(lats)
        self._box = (lats[n // 10], lons[n // 10], lats[-(n // 10) - 1], lons[-(n // 10) - 1])
        self._core_nodes = [
            p for p in engine.graph.nodes
            if self._box[0] <= p[0] <= self._box[2] and self._box[1] <= p[1] <= self._box[3]
        ] or list(engine.graph.nodes)

    def tick(self, dt: float) -> None:
        self._calls(dt)
        self._hotspots()

    def _calls(self, dt: float) -> None:
        if self.calls_per_hour <= 0:
            return
        open_synthetic = sum(
            1 for i in self.engine.world.incidents.values()
            if i.synthetic and i.closed_wall is None
        )
        if open_synthetic >= self.max_open_calls:
            return
        if self.rng.random() < self.calls_per_hour * dt / 3600.0:
            self.spawn_call()

    def spawn_call(self):
        categories = [c for c, _, _ in CALL_MIX]
        weights = [w for _, w, _ in CALL_MIX]
        index = self.rng.choices(range(len(categories)), weights)[0]
        lat, lon = self.rng.choice(self._core_nodes)
        node = self.engine.graph.nearest_node(lat, lon)
        street = next((self.engine.graph.edges[e].name for e in self.engine.graph.out[node]
                       if self.engine.graph.edges[e].name), "")
        address = f"{street}, {self.rng.randint(1, 240)}" if street else ""
        return self.engine.create_incident(
            categories[index], lat, lon, description=self.rng.choice(CALL_MIX[index][2]),
            address=address, synthetic=True,
        )

    def _hotspots(self) -> None:
        if self.max_hotspots <= 0 or not self._arterials:
            return
        now = self.engine.now
        hour = self.engine.traffic.local_hour(now)
        target = round(self.max_hotspots * (0.3 + 0.7 * rush_intensity(hour)))
        ambient = [h for h in self.engine.traffic.hotspots if h.id.startswith("amb-")]
        if len(ambient) >= target:
            return
        edge = self.rng.choice(self._arterials)
        self._serial += 1
        self.engine.traffic.add_hotspot(Hotspot(
            id=f"amb-{self._serial}", lat=edge.midpoint[0], lon=edge.midpoint[1],
            radius_m=self.rng.uniform(250, 650), severity=self.rng.uniform(0.4, 0.85),
            expires_at=now + self.rng.uniform(600, 1800), kind=self.rng.choice(HOTSPOT_KINDS),
        ))
        self.engine.outbox.append({"type": "traffic.updated"})
