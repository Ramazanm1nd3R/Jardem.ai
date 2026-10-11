import pytest

from app.domain.models import (
    CATEGORIES,
    CATEGORY_BY_ID,
    INCIDENT_TRANSITIONS,
    SCARCE_CAPABILITIES,
    SERVICE_PHONES,
    UNIT_TRANSITIONS,
    IncidentStatus,
    Priority,
    Service,
    TransitionError,
    UnitStatus,
    categories_for,
    check_incident_transition,
    check_unit_transition,
    incident_status_for_units,
)
from app.domain.triage import triage

U, I = UnitStatus, IncidentStatus


def test_catalogue_is_consistent():
    assert len(CATEGORY_BY_ID) == len(CATEGORIES) == 15
    assert {s: len(categories_for(s)) for s in Service} == {
        Service.AMBULANCE: 4, Service.POLICE: 5, Service.FIRE: 3, Service.RESCUE: 3,
    }
    assert all(c.required and c.units_required >= 1 for c in CATEGORIES)
    assert CATEGORY_BY_ID["fire_engine"].units_required == 2
    assert CATEGORY_BY_ID["emergency"].units_required == 1
    assert CATEGORY_BY_ID["reanimation"].required == {"medical", "reanimation"}
    assert CATEGORY_BY_ID["planned"].priority is Priority.LOW
    assert SERVICE_PHONES == {Service.AMBULANCE: "103", Service.POLICE: "102",
                              Service.FIRE: "101", Service.RESCUE: "112"}
    used = set().union(*(c.required for c in CATEGORIES))
    assert used >= SCARCE_CAPABILITIES


def test_unit_happy_path_and_guards():
    path = [U.OFF_DUTY, U.AVAILABLE, U.ASSIGNED, U.EN_ROUTE, U.ON_SCENE, U.TRANSPORTING,
            U.RETURNING, U.AVAILABLE]
    for a, b in zip(path, path[1:], strict=False):
        check_unit_transition(a, b)
    for a, b in [(U.OFF_DUTY, U.EN_ROUTE), (U.AVAILABLE, U.ON_SCENE), (U.ON_SCENE, U.EN_ROUTE),
                 (U.ASSIGNED, U.ON_SCENE), (U.TRANSPORTING, U.ON_SCENE), (U.AVAILABLE, U.AVAILABLE),
                 (U.EN_ROUTE, U.OFF_DUTY), (U.ON_SCENE, U.OFF_DUTY)]:
        with pytest.raises(TransitionError, match=f"{a.value} to {b.value}"):
            check_unit_transition(a, b)
    # Re-optimisation paths: a unit can be pulled back or re-routed before arriving.
    check_unit_transition(U.EN_ROUTE, U.AVAILABLE)
    check_unit_transition(U.EN_ROUTE, U.ASSIGNED)
    check_unit_transition(U.RETURNING, U.ASSIGNED)
    assert set(UNIT_TRANSITIONS) == set(U)


def test_incident_transitions():
    path = [I.NEW, I.ASSIGNED, I.EN_ROUTE, I.ON_SCENE, I.RESOLVED]
    for a, b in zip(path, path[1:], strict=False):
        check_incident_transition(a, b)
    for status in (I.NEW, I.ASSIGNED, I.EN_ROUTE):
        check_incident_transition(status, I.CANCELLED)
    for a, b in [(I.ON_SCENE, I.CANCELLED), (I.RESOLVED, I.NEW), (I.CANCELLED, I.NEW),
                 (I.NEW, I.EN_ROUTE), (I.NEW, I.RESOLVED), (I.ASSIGNED, I.ON_SCENE)]:
        with pytest.raises(TransitionError, match=f"{a.value} to {b.value}"):
            check_incident_transition(a, b)
    assert INCIDENT_TRANSITIONS[I.RESOLVED] == frozenset()
    assert INCIDENT_TRANSITIONS[I.CANCELLED] == frozenset()
    check_incident_transition(I.EN_ROUTE, I.NEW)
    check_incident_transition(I.EN_ROUTE, I.ASSIGNED)


@pytest.mark.parametrize(
    ("statuses", "expected"),
    [([], I.NEW), ([U.ASSIGNED], I.ASSIGNED), ([U.ASSIGNED, U.EN_ROUTE], I.EN_ROUTE),
     ([U.EN_ROUTE, U.ON_SCENE], I.ON_SCENE), ([U.TRANSPORTING], I.ON_SCENE),
     ([U.ASSIGNED, U.ASSIGNED], I.ASSIGNED), ([U.EN_ROUTE], I.EN_ROUTE)],
)
def test_incident_status_follows_most_advanced_unit(statuses, expected):
    assert incident_status_for_units(statuses) is expected


# --- triage ---------------------------------------------------------------


def test_fire_with_people_inside():
    r = triage("Возле дома дым, кажется, горит проводка, кто-то внутри. ул. Абая 50")
    assert (r.service, r.category, r.priority) == (Service.FIRE, "fire_engine", Priority.CRITICAL)
    assert r.people_inside and r.life_threat and r.uncertain
    assert r.address == "ул. Абая 50"
    assert set(r.matched) >= {"дым", "горит"}
    assert "people_inside" not in r.missing and "address" not in r.missing


def test_fire_without_details_lists_missing_facts():
    r = triage("пожар в подъезде")
    assert r.category == "fire_engine" and r.priority is Priority.CRITICAL
    assert not r.people_inside and not r.uncertain and not r.life_threat
    assert r.missing == ("address", "people_inside")
    assert r.address is None and r.victims is None and r.age is None


def test_unconscious_adult_is_reanimation():
    r = triage("Мужчина, около 60 лет, потерял сознание. Не дышит. Назарбаева, 125")
    assert (r.service, r.category, r.priority) == (
        Service.AMBULANCE, "reanimation", Priority.CRITICAL)
    assert r.age == 60 and r.life_threat
    assert r.address == "Назарбаева, 125"
    assert r.also == ()
    assert "victims_count" in r.missing and "patient_condition" not in r.missing


def test_child_patient_becomes_pediatric():
    r = triage("У ребёнка высокая температура и сильно болит живот, ему 4 года, плохо")
    assert (r.service, r.category, r.priority) == (Service.AMBULANCE, "pediatric", Priority.HIGH)
    assert r.age == 4
    assert "patient_condition" in r.missing
    by_age = triage("Упал с велосипеда, перелом руки, 9 лет")
    assert by_age.category == "pediatric"
    teen = triage("Упал с велосипеда, перелом руки, 15 лет")
    assert teen.category == "emergency" and teen.priority is Priority.CRITICAL


def test_child_mentioned_in_non_medical_call_is_not_pediatric():
    r = triage("Горит квартира, там ребенок")
    assert r.category == "fire_engine"
    only_child = triage("ребенок")
    assert only_child.category == "pediatric"


def test_traffic_accident_with_victims_suggests_second_service():
    r = triage("ДТП на проспекте Райымбека, 3 человека пострадали, у одного кровь")
    assert (r.service, r.category) == (Service.POLICE, "traffic")
    assert r.victims == 3
    assert r.also == ("emergency",)
    assert r.priority is Priority.MEDIUM


def test_armed_incident():
    r = triage("Мужчина с ножом угрожает прохожим")
    assert (r.service, r.category, r.priority) == (Service.POLICE, "special", Priority.CRITICAL)
    assert 0 < r.confidence < 1


def test_kazakh_text():
    r = triage("Үйде өрт, түтін шығып жатыр")
    assert r.service is Service.FIRE and set(r.matched) == {"өрт", "түтін"}
    assert triage("Адам есінен танып қалды").category == "reanimation"


def test_mountain_and_disaster():
    assert triage("Турист сорвался в ущелье возле Шымбулака").category == "mountain"
    assert triage("Сель сошёл на дорогу").priority is Priority.CRITICAL
    assert triage("Пропал человек, ушёл и не вернулся").service is Service.RESCUE


def test_unknown_text():
    r = triage("здравствуйте, подскажите пожалуйста")
    assert (r.service, r.category, r.priority, r.confidence) == (None, None, None, 0.0)
    assert r.missing == ("address", "what_happened")
    assert r.matched == () and r.also == ()
    assert triage("").missing == ("address", "what_happened")


def test_stems_match_only_at_word_start():
    assert triage("задымление").category is None  # "дым" is not at a word start
    assert triage("Дым из окна").category == "fire_engine"
    assert triage("ДЫМ   ИЗ\nОКНА").category == "fire_engine"


def test_confidence_reflects_ambiguity_and_hedging():
    sure = triage("пожар, горит дом, дым")
    hedged = triage("кажется пожар, горит дом, дым")
    mixed = triage("пожар и драка")
    assert sure.confidence == pytest.approx(7 / 9, abs=0.01)
    assert hedged.confidence == pytest.approx(sure.confidence * 0.8, abs=0.01)
    assert mixed.confidence == pytest.approx(5 / 10, abs=0.01)
    assert mixed.category == "fire_engine" and mixed.also == ("patrol",)


def test_yo_normalised():
    assert triage("ребёнок упал").category == triage("ребенок упал").category == "pediatric"
