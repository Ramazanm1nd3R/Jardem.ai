"""Core vocabulary: services, statuses, priorities and the service catalogue."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum, StrEnum


class Service(StrEnum):
    AMBULANCE = "ambulance"
    POLICE = "police"
    FIRE = "fire"
    RESCUE = "rescue"


class UnitStatus(StrEnum):
    OFF_DUTY = "off_duty"
    AVAILABLE = "available"
    ASSIGNED = "assigned"  # dispatched, crew has not confirmed yet
    EN_ROUTE = "en_route"
    ON_SCENE = "on_scene"
    TRANSPORTING = "transporting"
    RETURNING = "returning"


class IncidentStatus(StrEnum):
    NEW = "new"  # accepted by the platform, no unit yet
    ASSIGNED = "assigned"
    EN_ROUTE = "en_route"
    ON_SCENE = "on_scene"
    RESOLVED = "resolved"
    CANCELLED = "cancelled"


class Priority(IntEnum):
    CRITICAL = 1
    HIGH = 2
    MEDIUM = 3
    LOW = 4


# Units that can be given a new assignment.
DISPATCHABLE = frozenset({UnitStatus.AVAILABLE, UnitStatus.RETURNING})
# Units committed to an incident but not yet working it — still movable by re-optimisation.
REASSIGNABLE = frozenset({UnitStatus.ASSIGNED, UnitStatus.EN_ROUTE})
ACTIVE_INCIDENT = frozenset(
    {IncidentStatus.NEW, IncidentStatus.ASSIGNED, IncidentStatus.EN_ROUTE, IncidentStatus.ON_SCENE}
)

UNIT_TRANSITIONS: dict[UnitStatus, frozenset[UnitStatus]] = {
    UnitStatus.OFF_DUTY: frozenset({UnitStatus.AVAILABLE}),
    UnitStatus.AVAILABLE: frozenset({UnitStatus.ASSIGNED, UnitStatus.OFF_DUTY}),
    UnitStatus.ASSIGNED: frozenset({UnitStatus.EN_ROUTE, UnitStatus.AVAILABLE}),
    UnitStatus.EN_ROUTE: frozenset({UnitStatus.ON_SCENE, UnitStatus.AVAILABLE, UnitStatus.ASSIGNED}),
    UnitStatus.ON_SCENE: frozenset(
        {UnitStatus.TRANSPORTING, UnitStatus.RETURNING, UnitStatus.AVAILABLE}
    ),
    UnitStatus.TRANSPORTING: frozenset({UnitStatus.RETURNING, UnitStatus.AVAILABLE}),
    UnitStatus.RETURNING: frozenset(
        {UnitStatus.AVAILABLE, UnitStatus.ASSIGNED, UnitStatus.OFF_DUTY}
    ),
}

INCIDENT_TRANSITIONS: dict[IncidentStatus, frozenset[IncidentStatus]] = {
    IncidentStatus.NEW: frozenset({IncidentStatus.ASSIGNED, IncidentStatus.CANCELLED}),
    IncidentStatus.ASSIGNED: frozenset(
        {IncidentStatus.EN_ROUTE, IncidentStatus.NEW, IncidentStatus.CANCELLED}
    ),
    IncidentStatus.EN_ROUTE: frozenset(
        {IncidentStatus.ON_SCENE, IncidentStatus.ASSIGNED, IncidentStatus.NEW,
         IncidentStatus.CANCELLED}
    ),
    IncidentStatus.ON_SCENE: frozenset({IncidentStatus.RESOLVED}),
    IncidentStatus.RESOLVED: frozenset(),
    IncidentStatus.CANCELLED: frozenset(),
}


class TransitionError(ValueError):
    pass


def check_unit_transition(current: UnitStatus, target: UnitStatus) -> None:
    if target not in UNIT_TRANSITIONS[current]:
        raise TransitionError(f"unit cannot go from {current.value} to {target.value}")


def check_incident_transition(current: IncidentStatus, target: IncidentStatus) -> None:
    if target not in INCIDENT_TRANSITIONS[current]:
        raise TransitionError(f"incident cannot go from {current.value} to {target.value}")


def incident_status_for_units(statuses: list[UnitStatus]) -> IncidentStatus:
    """Incident status implied by the statuses of the units working it.

    The incident follows its most advanced unit: one crew on scene means help has arrived.
    """
    if not statuses:
        return IncidentStatus.NEW
    if any(s in (UnitStatus.ON_SCENE, UnitStatus.TRANSPORTING) for s in statuses):
        return IncidentStatus.ON_SCENE
    if any(s is UnitStatus.EN_ROUTE for s in statuses):
        return IncidentStatus.EN_ROUTE
    return IncidentStatus.ASSIGNED


@dataclass(frozen=True, slots=True)
class Category:
    """A kind of call within a service, as offered to the citizen."""

    id: str
    service: Service
    title: str
    description: str
    required: frozenset[str]  # capabilities a unit must have
    priority: Priority
    units_required: int = 1


def _cat(id_: str, service: Service, title: str, description: str, required: set[str],
         priority: Priority, units_required: int = 1) -> Category:
    return Category(id_, service, title, description, frozenset(required), priority,
                    units_required)


CATEGORIES: tuple[Category, ...] = (
    _cat("emergency", Service.AMBULANCE, "Экстренная помощь",
         "Критические состояния, угроза жизни", {"medical"}, Priority.CRITICAL),
    _cat("planned", Service.AMBULANCE, "Плановая помощь",
         "Консультации, транспортировка", {"medical"}, Priority.LOW),
    _cat("pediatric", Service.AMBULANCE, "Детская скорая",
         "Помощь детям и подросткам", {"medical", "pediatric"}, Priority.HIGH),
    _cat("reanimation", Service.AMBULANCE, "Реанимация",
         "Тяжёлые состояния, реанимационные бригады", {"medical", "reanimation"},
         Priority.CRITICAL),
    _cat("patrol", Service.POLICE, "Патруль",
         "Нарушение порядка, угроза безопасности", {"patrol"}, Priority.HIGH),
    _cat("district", Service.POLICE, "Участковые",
         "Бытовые конфликты, обращения по месту жительства", {"district"}, Priority.LOW),
    _cat("traffic", Service.POLICE, "ДПС",
         "ДТП и нарушения на дороге", {"traffic"}, Priority.MEDIUM),
    _cat("moto", Service.POLICE, "Мотобат",
         "Мобильные экипажи для плотного трафика", {"patrol", "moto"}, Priority.HIGH),
    _cat("special", Service.POLICE, "ОМОН",
         "Вооружённые инциденты, массовые беспорядки", {"special"}, Priority.CRITICAL),
    _cat("fire_engine", Service.FIRE, "Пожарные части",
         "Пожар в здании, транспорте, на улице", {"fire_suppression"}, Priority.CRITICAL, 2),
    _cat("fire_rescue", Service.FIRE, "Спасательные",
         "Деблокирование, эвакуация, ДТП с зажатыми", {"technical_rescue"}, Priority.HIGH),
    _cat("forest", Service.FIRE, "Лесные",
         "Возгорания в предгорьях и лесопарках", {"fire_suppression", "wildfire"},
         Priority.HIGH),
    _cat("mountain", Service.RESCUE, "Горные спасатели",
         "Происшествия в горах и ущельях", {"mountain_rescue"}, Priority.HIGH),
    _cat("search", Service.RESCUE, "Поисково-спасательные",
         "Поиск пропавших, спасение на воде", {"search_rescue"}, Priority.HIGH),
    _cat("disaster", Service.RESCUE, "ЧС и стихийные бедствия",
         "Сели, землетрясения, обрушения", {"search_rescue", "disaster"}, Priority.CRITICAL),
)
CATEGORY_BY_ID: dict[str, Category] = {c.id: c for c in CATEGORIES}

SERVICE_TITLES: dict[Service, str] = {
    Service.AMBULANCE: "Скорая помощь",
    Service.POLICE: "Полиция",
    Service.FIRE: "Пожарные",
    Service.RESCUE: "Спасатели",
}
# Direct emergency numbers in Kazakhstan; 112 is the unified one.
SERVICE_PHONES: dict[Service, str] = {
    Service.AMBULANCE: "103",
    Service.POLICE: "102",
    Service.FIRE: "101",
    Service.RESCUE: "112",
}

# Capabilities that are scarce: a unit carrying one that the call does not need is
# "overqualified", and the optimiser prefers to keep it free.
SCARCE_CAPABILITIES = frozenset(
    {"reanimation", "pediatric", "special", "moto", "wildfire", "disaster", "technical_rescue"}
)


def categories_for(service: Service) -> list[Category]:
    return [c for c in CATEGORIES if c.service is service]
