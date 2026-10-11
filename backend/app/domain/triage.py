"""Rule-based triage of a free-text call description (Russian and Kazakh).

Extracts a suggested service, category and priority plus the facts that drove the
suggestion. It is decision support: the output is a suggestion with its evidence, and
anything not stated in the text is listed under `missing` rather than guessed.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from app.domain.models import CATEGORY_BY_ID, Priority, Service


@dataclass(frozen=True, slots=True)
class Rule:
    category: str
    weight: int
    stems: tuple[str, ...]


# Stems are matched at word starts, so "пожар" also matches "пожара", "пожарные".
RULES: tuple[Rule, ...] = (
    Rule("reanimation", 5, ("не дыш", "без сознан", "потерял сознан", "потеряла сознан",
                            "остановка сердц", "клиническ", "есінен тан", "тыныс алмай",
                            "не реагир", "судорог", "инсульт", "инфаркт")),
    Rule("emergency", 3, ("кров", "перелом", "травм", "боль в груд", "задыха", "ожог",
                          "отравл", "упал", "упала", "плохо", "сердц", "давлен", "аллерги",
                          "қан", "жарақат", "ауырып")),
    Rule("pediatric", 4, ("ребен", "ребён", "младен", "малыш", "дети", "детей", "бала",
                          "сәби", "грудничк")),
    Rule("planned", 2, ("транспортиров", "перевез", "консультац", "плановая", "справк")),
    Rule("fire_engine", 5, ("пожар", "горит", "дым", "огонь", "пламя", "возгоран",
                            "өрт", "түтін", "жанып", "запах газа", "взрыв")),
    Rule("forest", 5, ("лес горит", "трава горит", "горит трава", "горит лес",
                       "лесной пожар", "сухостой")),
    Rule("fire_rescue", 4, ("зажат", "заблокирован", "застрял", "лифт", "обрушен",
                            "деблокир", "қысылып")),
    Rule("traffic", 4, ("дтп", "авари", "столкнов", "сбил", "наезд", "жол апат", "көлік соқ")),
    Rule("patrol", 3, ("драк", "напад", "угрожа", "грабеж", "грабёж", "кража", "украл",
                       "взлом", "хулиган", "пьян", "төбелес", "ұрлық", "шум")),
    Rule("special", 6, ("оружи", "стреля", "выстрел", "заложник", "нож", "қару", "атыс")),
    Rule("district", 2, ("сосед", "участков", "семейн", "скандал")),
    Rule("mountain", 5, ("горах", "в горы", "ущель", "лавин", "альпинист", "скал",
                         "шымбулак", "медеу", "турист заблуд")),
    Rule("search", 4, ("пропал", "пропала", "потерялся", "потерялась", "заблуд", "тонет", "утонул",
                       "провалился под лед", "жоғал", "суға")),
    Rule("disaster", 6, ("сель", "землетряс", "наводнен", "оползень", "обвал", "жер сілкін",
                         "тасқын")),
)

LIFE_THREAT_STEMS = ("не дыш", "без сознан", "потерял сознан", "потеряла сознан", "кровотеч",
                     "остановка сердц", "люди внутри", "кто-то внутри", "человек внутри",
                     "заложник", "тонет", "есінен тан", "тыныс алмай", "зажат")
PEOPLE_INSIDE_STEMS = ("внутри", "в квартире люди", "не могут выйти", "ішінде")
UNCERTAIN_STEMS = ("кажется", "вроде", "возможно", "наверное", "похоже", "сияқты")

ADDRESS_RE = re.compile(
    r"(?:ул\.?|улица|пр\.?|проспект|мкр\.?|микрорайон|көшесі|даңғылы)\s*[\w\-\. ]{2,40}?\d+"
    r"|[А-ЯЁӘҒҚҢӨҰҮҺІ][\w\-]+(?:\s[А-ЯЁӘҒҚҢӨҰҮҺІ][\w\-]+)?,?\s\d{1,4}[а-я]?\b",
    re.UNICODE,
)
COUNT_RE = re.compile(r"(\d+)\s*(?:человек|пострадав|ранен|адам)", re.UNICODE)
AGE_RE = re.compile(r"(\d{1,3})\s*(?:лет|год|года|жас)", re.UNICODE)


@dataclass(frozen=True, slots=True)
class TriageResult:
    service: Service | None
    category: str | None
    priority: Priority | None
    confidence: float  # 0..1
    life_threat: bool
    people_inside: bool
    victims: int | None
    age: int | None
    address: str | None
    uncertain: bool  # the caller hedged ("кажется", "вроде")
    matched: tuple[str, ...]  # stems found, as evidence
    missing: tuple[str, ...]  # facts a dispatcher still needs
    also: tuple[str, ...]  # other categories with evidence (multi-service incidents)


def _has(text: str, stem: str) -> bool:
    return re.search(r"(?<!\w)" + re.escape(stem), text) is not None


def triage(text: str) -> TriageResult:
    norm = " ".join(text.lower().replace("ё", "е").split())
    scores: dict[str, int] = {}
    matched: list[str] = []
    for rule in RULES:
        hits = [s for s in rule.stems if _has(norm, s.replace("ё", "е"))]
        if hits:
            scores[rule.category] = rule.weight + len(hits) - 1
            matched.extend(hits)

    age_match = AGE_RE.search(norm)
    age = int(age_match.group(1)) if age_match else None
    count_match = COUNT_RE.search(norm)
    victims = int(count_match.group(1)) if count_match else None
    address_match = ADDRESS_RE.search(text)
    address = address_match.group(0).strip() if address_match else None
    life_threat = any(_has(norm, s) for s in LIFE_THREAT_STEMS)
    people_inside = any(_has(norm, s) for s in PEOPLE_INSIDE_STEMS)
    uncertain = any(_has(norm, s) for s in UNCERTAIN_STEMS)

    # A child patient turns any medical call into a paediatric one.
    medical = {"reanimation", "emergency", "planned"}
    if (age is not None and age < 15) and medical & scores.keys():
        scores["pediatric"] = scores.get("pediatric", 4) + 1
    others = scores.keys() - {"pediatric"}
    if "pediatric" in scores and others and not medical & others:
        # "ребёнок" next to a fire or a fight is not, by itself, a paediatric ambulance call.
        del scores["pediatric"]

    missing: list[str] = []
    if address is None:
        missing.append("address")
    if not scores:
        missing.append("what_happened")
        return TriageResult(None, None, None, 0.0, life_threat, people_inside, victims, age,
                            address, uncertain, (), tuple(missing), ())

    ranked = sorted(scores.items(), key=lambda kv: (-kv[1], kv[0]))
    best, best_score = ranked[0]
    category = CATEGORY_BY_ID[best]
    priority = category.priority
    if life_threat or people_inside:
        priority = Priority.CRITICAL
    if victims is None and category.service is Service.AMBULANCE:
        missing.append("patient_condition" if not life_threat else "victims_count")
    if category.service is Service.FIRE and not people_inside:
        missing.append("people_inside")

    runner_up = ranked[1][1] if len(ranked) > 1 else 0
    confidence = best_score / (best_score + runner_up + 2)
    if uncertain:
        confidence *= 0.8
    also = tuple(c for c, _ in ranked[1:] if CATEGORY_BY_ID[c].service is not category.service)
    return TriageResult(category.service, best, priority, round(confidence, 2), life_threat,
                        people_inside, victims, age, address, uncertain, tuple(matched),
                        tuple(missing), also)
