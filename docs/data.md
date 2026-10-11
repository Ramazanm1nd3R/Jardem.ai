# Данные

| Что | Источник | Насколько это реально |
|---|---|---|
| Дорожный граф Алматы (25 254 узла, 32 684 сегмента, 4 228 км) | OpenStreetMap через Overpass API, © участники OSM, ODbL | Реальная геометрия, односторонние улицы, классы дорог. Скорости — из `maxspeed`, иначе типовые по классу дороги |
| Пожарные части (15) | OSM `amenity=fire_station` | Реальные объекты и адреса |
| Отделения полиции (14) | OSM `amenity=police`, выборка с названиями, равномерно по городу | Реальные объекты |
| Подстанции скорой (12) | Привязаны к больницам из OSM, равномерно по городу | **Приблизительно**: в OSM почти нет подстанций ССМП; в API помечены `approximate: true` |
| Базы спасателей (3) | Заданы вручную | **Приблизительно** |
| Экипажи, номера, составы бригад, оснащение | Генерируются `backend/app/engine/seed.py` | Вымышленные демо-данные |
| Пробки | Модель `backend/app/domain/traffic.py` | **Симуляция**: суточный профиль, очаги, перекрытия. Реальный сигнал — только скорость экипажей из приложения службы |
| Вызовы на карте | Генератор `backend/app/engine/ambient.py` и пользователи демо | Симуляция, помечены `synthetic` |
| Веса районов для оценки покрытия | Центры 8 районов, веса ≈ население | Грубая оценка |
| Фотографии | Wikimedia Commons, см. `assets/photos/ATTRIBUTION.md` | Реальные снимки из Казахстана, лицензии CC BY / CC BY-SA / CC0 |

## Пересборка

Запросы Overpass (bbox `43.15,76.76,43.37,77.04`):

```
[out:json][timeout:180];
(way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$"](43.15,76.76,43.37,77.04););
out body;>;out skel qt;
```
```
[out:json][timeout:120];
(nwr["amenity"~"^(fire_station|police|hospital)$"](43.15,76.76,43.37,77.04);
 nwr["emergency"~"^(ambulance_station|rescue_station|mountain_rescue)$"](43.15,76.76,43.37,77.04););
out center tags;
```

Сохраните ответы в `backend/data/raw/almaty_roads.json` и `almaty_pois.json`, затем `make data`.
Сборщик графа делит дороги на сегменты между перекрёстками и оставляет наибольшую сильно связную компоненту, чтобы из любой точки можно было доехать в любую.
