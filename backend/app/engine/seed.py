"""Demo world: real department locations with a simulated fleet and crews.

Vehicles, plates, crews and accounts are fictional demo data. Department locations come
from app/data/almaty_departments.json (see docs/data.md for which are approximate).
"""

from __future__ import annotations

import json
import random
from dataclasses import dataclass
from pathlib import Path

from app.domain.graph import RoadGraph
from app.domain.models import Service, UnitStatus
from app.engine.world import CrewMember, Department, Unit, World

DATA_DIR = Path(__file__).resolve().parents[1] / "data"


@dataclass(frozen=True, slots=True)
class UnitTemplate:
    kind: str
    title: str  # citizen-facing prefix; the department number is appended
    callsign: str
    capabilities: frozenset[str]
    vehicle: str
    crew_roles: tuple[str, ...]


def _t(kind, title, callsign, caps, vehicle, roles) -> UnitTemplate:
    return UnitTemplate(kind, title, callsign, frozenset(caps), vehicle, tuple(roles))


AMBULANCE_LINE = _t("linear", "Подстанция", "СМП", {"medical"}, "JAC Sunray",
                    ("Водитель", "Фельдшер", "Врач"))
AMBULANCE_PEDIATRIC = _t("pediatric", "Детская бригада", "СМП-Д", {"medical", "pediatric"},
                         "Mercedes Sprinter", ("Водитель", "Фельдшер", "Врач-педиатр"))
AMBULANCE_REANIMATION = _t("reanimation", "Реанимация", "СМП-Р", {"medical", "reanimation"},
                           "Mercedes Sprinter", ("Водитель", "Фельдшер", "Врач-реаниматолог"))
POLICE_PATROL = _t("patrol", "Патрульный экипаж", "Патруль", {"patrol"}, "Chevrolet Equinox",
                   ("Водитель", "Инспектор"))
POLICE_DISTRICT = _t("district", "Участковый", "УПП", {"district", "patrol"},
                     "Chevrolet Cobalt", ("Участковый инспектор",))
POLICE_TRAFFIC = _t("traffic", "Экипаж ДПС", "ДПС", {"traffic", "patrol"}, "Skoda Octavia",
                    ("Водитель", "Инспектор ДПС"))
POLICE_MOTO = _t("moto", "Мотобат", "Мотобат", {"patrol", "moto", "traffic"}, "BMW R1250 RT",
                 ("Инспектор",))
POLICE_SPECIAL = _t("special", "Спецотряд", "СОБР", {"special", "patrol"}, "Toyota Land Cruiser",
                    ("Водитель", "Командир группы", "Боец"))
FIRE_ENGINE = _t("engine", "Пожарная часть", "ПЧ", {"fire_suppression"}, "КамАЗ АЦ-5,0-40",
                 ("Водитель", "Командир отделения", "Пожарный", "Пожарный"))
FIRE_RESCUE = _t("rescue", "Спасательный расчёт", "АСА", {"fire_suppression", "technical_rescue"},
                 "Iveco Magirus", ("Водитель", "Командир расчёта", "Спасатель"))
FIRE_FOREST = _t("forest", "Лесной расчёт", "ПЧ-Л", {"fire_suppression", "wildfire"},
                 "Урал АЦ-6,0", ("Водитель", "Командир отделения", "Пожарный"))
RESCUE_MOUNTAIN = _t("mountain", "Горные спасатели", "ГСО", {"mountain_rescue", "search_rescue"},
                     "UAZ Patriot", ("Водитель", "Спасатель", "Спасатель"))
RESCUE_SEARCH = _t("search", "Поисково-спасательная группа", "ПСО",
                   {"search_rescue", "disaster"}, "UAZ Patriot",
                   ("Водитель", "Спасатель", "Кинолог"))

FIRST_NAMES_M = ("Алексей", "Сергей", "Данияр", "Ерлан", "Тимур", "Азамат", "Руслан", "Нурлан",
                 "Бауыржан", "Дмитрий", "Арман", "Канат")
FIRST_NAMES_F = ("Мария", "Айгерим", "Динара", "Асель", "Елена", "Жанна", "Мадина", "Ольга")
LAST_NAMES = ("Иванов", "Ким", "Ахметов", "Сулейменов", "Нурланов", "Петров", "Касымов",
              "Жумабаев", "Абенов", "Ли", "Омаров", "Сериков")
LAST_NAMES_F = ("Петрова", "Ахметова", "Ким", "Сулейменова", "Касымова", "Ли", "Омарова")

EQUIPMENT: dict[Service, tuple[tuple[str, str], ...]] = {
    Service.AMBULANCE: (("Дефибриллятор", "ZOLL AED Plus"), ("Монитор пациента", "Mindray BeneVision"),
                        ("Кислородный баллон", "2 шт. (полный)"), ("ИВЛ портативный", "Weinmann Medumat"),
                        ("Укладка врача", "укомплектована"), ("Носилки-каталка", "Ferno")),
    Service.POLICE: (("Радиостанция", "Motorola DP4800"), ("Видеорегистратор", "нагрудный"),
                     ("Аптечка", "укомплектована"), ("Алкотестер", "Drager 6820")),
    Service.FIRE: (("Дыхательные аппараты", "4 шт."), ("Рукава напорные", "12 шт."),
                   ("Гидравлический инструмент", "Holmatro"), ("Тепловизор", "FLIR K55"),
                   ("Запас воды", "5,0 м³"), ("Пенообразователь", "300 л")),
    Service.RESCUE: (("Альпинистское снаряжение", "комплект"), ("Носилки спасательные", "акья"),
                     ("Спутниковый телефон", "Iridium"), ("Аптечка", "укомплектована"),
                     ("Квадрокоптер", "DJI Mavic 3T")),
}

# The crew from the product mock-ups: the account the responder app signs in with by default.
DEMO_UNIT_ID = "ambulance-7-1"
DEMO_CREW = (
    CrewMember("resp-demo", "Алексей Иванов", "Водитель · Старший бригады", "+7 700 123 45 67", True),
    CrewMember("resp-demo-2", "Мария Петрова", "Фельдшер", "+7 701 555 12 12"),
    CrewMember("resp-demo-3", "Сергей Ким", "Врач", "+7 702 555 34 34"),
)


def _templates(service: Service, index: int, name: str) -> list[UnitTemplate]:
    if service is Service.AMBULANCE:
        special = AMBULANCE_PEDIATRIC if index % 2 else AMBULANCE_REANIMATION
        return [AMBULANCE_LINE, AMBULANCE_LINE, special]
    if service is Service.POLICE:
        if "РУВД" in name or "Управление" in name:
            return [POLICE_PATROL, POLICE_PATROL, POLICE_TRAFFIC, POLICE_MOTO, POLICE_SPECIAL]
        return [POLICE_PATROL, POLICE_DISTRICT] + ([POLICE_TRAFFIC] if index % 2 else [])
    if service is Service.FIRE:
        if "пост" in name:
            return [FIRE_ENGINE, FIRE_FOREST]
        if "Специализированная" in name:
            return [FIRE_ENGINE, FIRE_ENGINE, FIRE_RESCUE]
        return [FIRE_ENGINE, FIRE_ENGINE] + ([FIRE_FOREST] if index % 4 == 0 else [])
    if "Горно" in name:
        return [RESCUE_MOUNTAIN, RESCUE_MOUNTAIN]
    return [RESCUE_SEARCH, RESCUE_SEARCH, RESCUE_MOUNTAIN]


def _plate(rng: random.Random) -> str:
    letters = "".join(rng.choice("ABCDEHKMOPTX") for _ in range(2))
    return f"{rng.randint(100, 999)} {letters} 02"


def _crew(rng: random.Random, unit_id: str, roles: tuple[str, ...]) -> list[CrewMember]:
    crew = []
    for i, role in enumerate(roles):
        female = role in ("Фельдшер",) and rng.random() < 0.6
        first = rng.choice(FIRST_NAMES_F if female else FIRST_NAMES_M)
        last = rng.choice(LAST_NAMES_F if female else LAST_NAMES)
        phone = f"+7 70{rng.randint(0, 9)} {rng.randint(100, 999)} {rng.randint(10, 99)} {rng.randint(10, 99)}"
        crew.append(CrewMember(f"{unit_id}-c{i + 1}", f"{first} {last}", role, phone, lead=i == 0))
    return crew


def department_number(name: str, fallback: int) -> str:
    digits = "".join(ch if ch.isdigit() else " " for ch in name).split()
    return digits[0] if digits else str(fallback)


def build_world(graph: RoadGraph, seed: int = 7,
                departments_path: Path | None = None) -> World:
    rng = random.Random(seed)
    raw = json.loads((departments_path or DATA_DIR / "almaty_departments.json").read_text("utf-8"))
    world = World()
    for row in raw["departments"]:
        service = Service(row["service"])
        dept = Department(row["id"], service, row["name"], row["address"], row["lat"],
                          row["lon"], row["approximate"])
        world.departments[dept.id] = dept
        index = int(dept.id.rsplit("-", 1)[1])
        number = department_number(dept.name, index)
        base = graph.nodes[graph.nearest_node(dept.lat, dept.lon)]
        for k, tpl in enumerate(_templates(service, index, dept.name), start=1):
            unit_id = f"{dept.id}-{k}"
            unit = Unit(
                id=unit_id, department_id=dept.id, service=service, kind=tpl.kind,
                name=f"{tpl.title} №{number}", callsign=f"{tpl.callsign} №{number}",
                capabilities=tpl.capabilities, status=UnitStatus.AVAILABLE,
                lat=base[0], lon=base[1], base=base, plate=_plate(rng), vehicle=tpl.vehicle,
                fuel_pct=rng.randint(55, 98), crew=_crew(rng, unit_id, tpl.crew_roles),
                equipment=[{"name": n, "detail": d, "ok": True} for n, d in EQUIPMENT[service]],
            )
            world.units[unit.id] = unit

    demo = world.units.get(DEMO_UNIT_ID)
    if demo is not None:
        demo.crew = list(DEMO_CREW)
        demo.vehicle = "Mercedes Sprinter"
        demo.plate = "402 AR 02"
        demo.fuel_pct = 92
        demo.controlled_by = "resp-demo"
        demo.status = UnitStatus.OFF_DUTY  # goes on duty when the responder signs in
    return world
