import 'package:flutter_test/flutter_test.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:latlong2/latlong.dart';

import '../fixtures.dart';

void main() {
  group('enums', () {
    test('ServiceType round-trips ids and has the real phone numbers', () {
      for (final s in ServiceType.values) {
        expect(ServiceType.tryParse(s.id), s);
      }
      expect(ServiceType.ambulance.phone, '103');
      expect(ServiceType.police.phone, '102');
      expect(ServiceType.fire.phone, '101');
      expect(ServiceType.rescue.phone, '112');
      expect(ServiceType.ambulance.title, 'Скорая помощь');
      expect(ServiceType.ambulance.callLabel, 'Вызвать скорую');
      expect(ServiceType.ambulance.formTitle, 'Вызов скорой помощи');
      expect(ServiceType.tryParse('army'), isNull);
      expect(ServiceType.parse('army'), ServiceType.rescue);
      expect(ServiceType.parse(null), ServiceType.rescue);
    });

    test('UnitStatus labels match the backend', () {
      expect(UnitStatus.parse('available').label, 'Свободен');
      expect(UnitStatus.parse('off_duty').label, 'Не на смене');
      expect(UnitStatus.parse('assigned').label, 'Назначен');
      expect(UnitStatus.parse('en_route').label, 'В пути');
      expect(UnitStatus.parse('on_scene').label, 'На месте');
      expect(UnitStatus.parse('transporting').label, 'Транспортировка');
      expect(UnitStatus.parse('returning').label, 'Возвращается');
      expect(UnitStatus.parse('???'), UnitStatus.unknown);
      expect(UnitStatus.available.isFree, isTrue);
      expect(UnitStatus.values.where((s) => s.isFree), [UnitStatus.available]);
      expect(UnitStatus.available.chipLabel, 'Свободен');
      expect(UnitStatus.enRoute.chipLabel, 'Занят');
      expect(UnitStatus.returning.chipLabel, 'Занят');
      expect(UnitStatus.offDuty.chipLabel, 'Не на смене');
    });

    test('IncidentStatus lifecycle flags', () {
      expect(IncidentStatus.parse('new'), IncidentStatus.created);
      expect(IncidentStatus.parse('en_route'), IncidentStatus.enRoute);
      expect(IncidentStatus.parse('on_scene'), IncidentStatus.onScene);
      expect(IncidentStatus.parse('bogus'), IncidentStatus.unknown);
      expect(IncidentStatus.values.where((s) => s.isActive), [
        IncidentStatus.created,
        IncidentStatus.assigned,
        IncidentStatus.enRoute,
        IncidentStatus.onScene,
      ]);
      expect(IncidentStatus.values.where((s) => s.isClosed), [IncidentStatus.resolved, IncidentStatus.cancelled]);
      expect(IncidentStatus.values.where((s) => s.canCancel), [
        IncidentStatus.created,
        IncidentStatus.assigned,
        IncidentStatus.enRoute,
      ]);
    });

    test('ResponderAction ids', () {
      expect(ResponderAction.values.map((a) => a.id), ['accept', 'arrive', 'transport', 'complete']);
    });
  });

  group('live fixtures', () {
    test('/meta', () {
      final meta = Meta.fromJson(fixtureMap('meta'));
      expect(meta.city, 'Алматы');
      expect(meta.center, const LatLng(43.2445, 76.9457));
      expect(meta.bbox, const GeoBounds(43.118165, 76.738513, 43.397272, 77.07995));
      expect(meta.demo, isTrue);
      expect(meta.disclaimer, contains('звоните 112'));
      expect(meta.emergencyPhone, '112');
      expect(meta.phones, {'ambulance': '103', 'police': '102', 'fire': '101', 'rescue': '112'});
      expect(meta.phoneOf(ServiceType.fire), '101');
      expect(meta.strategy, 'jardem');
      expect(meta.strategies, ['nearest', 'min_eta', 'jardem']);
      expect(meta.autoDispatch, isTrue);
      expect(meta.simSpeed, 3.0);
      expect(meta.appUrl, endsWith('/app/citizen/'));
    });

    test('/health and /stats', () {
      final health = Health.fromJson(fixtureMap('health'));
      expect(health.ok, isTrue);
      expect(health.database, isTrue);
      expect(health.redis, isTrue);
      expect(health.units, greaterThan(0));

      final stats = Stats.fromJson(fixtureMap('stats'));
      expect(stats.services.keys, ServiceType.values);
      expect(stats.services[ServiceType.ambulance]!.units, 35);
      expect(stats.services[ServiceType.ambulance]!.unitsFree, 30);
      expect(stats.services[ServiceType.ambulance]!.activeIncidents, 5);
      expect(stats.activeIncidents, 10);
      expect(stats.departments, 44);
      expect(stats.meanArrivalS, 239);
      expect(stats.trafficIndex, 2);
      expect(stats.strategy, 'jardem');
    });

    test('/catalog', () {
      final catalog = ServiceInfo.listFromJson(fixture('catalog'));
      expect(catalog.map((s) => s.service), ServiceType.values);
      final ambulance = catalog.first;
      expect(ambulance.id, 'ambulance');
      expect(ambulance.title, 'Скорая помощь');
      expect(ambulance.phone, '103');
      expect(ambulance.categories.map((c) => c.id), ['emergency', 'planned', 'pediatric', 'reanimation']);
      final emergency = ambulance.category('emergency')!;
      expect(emergency.title, 'Экстренная помощь');
      expect(emergency.shortTitle, 'Экстренная');
      expect(emergency.description, 'Критические состояния, угроза жизни');
      expect(emergency.priority, 1);
      expect(emergency.unitsRequired, 1);
      expect(ambulance.category('pediatric')!.shortTitle, 'Детская скорая');
      expect(ambulance.category('nope'), isNull);
      expect(catalog[2].category('fire_engine')!.unitsRequired, 2);
      expect(serviceOfCategory(catalog, 'patrol')!.service, ServiceType.police);
      expect(serviceOfCategory(catalog, 'mountain')!.service, ServiceType.rescue);
      expect(serviceOfCategory(catalog, 'nope'), isNull);
      expect(serviceOfCategory(catalog, null), isNull);
    });

    test('/units', () {
      final units = Unit.listFromJson(fixture('units'));
      expect(units, hasLength(3));
      final u = units.first;
      expect(u.id, 'ambulance-1-2');
      expect(u.service, ServiceType.ambulance);
      expect(u.kind, 'linear');
      expect(u.status, UnitStatus.available);
      expect(u.statusLabel, 'Свободен');
      expect(u.free, isTrue);
      expect(u.onDuty, isTrue);
      expect(u.position, const LatLng(43.233232, 76.938217));
      expect(u.name, 'Подстанция №1');
      expect(u.callsign, 'СМП №1');
      expect(u.departmentId, 'ambulance-1');
      expect(u.plate, '527 TK 02');
      expect(u.vehicle, 'JAC Sunray');
      expect(u.photo, 'ambulance_kz_1');
      expect(u.capabilities, ['medical']);
      expect(u.distanceM, 1392);
      expect(u.etaS, 151);
      expect(u.route, isEmpty);
      expect(u.department, isNull);
      expect(u.crew, isEmpty);
    });

    test('/units/{id}?lat&lon adds route and department object', () {
      final u = Unit.fromJson(fixtureMap('unit_detail'));
      expect(u.route.length, greaterThan(10));
      expect(u.route.first, const LatLng(43.23323, 76.93822));
      expect(u.distanceM, 1833);
      expect(u.etaS, 141);
      expect(u.department!.name, 'Подстанция №1');
      expect(u.department!.approximate, isTrue);
      expect(u.departmentName, 'Подстанция №1');
      // The route is real road geometry, so it is at least as long as the crow flies.
      expect(polylineLengthM(u.route), greaterThan(haversineM(u.route.first, u.route.last)));
      expect(polylineLengthM(u.route), closeTo(1833, 120));
    });

    test('/departments', () {
      final list = (fixture('departments') as List).map((d) => Department.fromJson((d as Map).cast())).toList();
      expect(list, hasLength(2));
      expect(list.first.id, 'fire-2');
      expect(list.first.service, ServiceType.fire);
      expect(list.first.name, 'Пожарная часть №5');
      expect(list.first.distanceM, 624);
      expect(list.first.units, 2);
      expect(list.first.unitsFree, 2);
      expect(list.first.position, const LatLng(43.247957, 76.951755));
      expect(list.first.approximate, isFalse);
    });

    test('/route', () {
      final r = RouteResult.fromJson(fixtureMap('route'));
      expect(r.distanceM, 3049);
      expect(r.durationS, 224);
      expect(r.freeFlowS, 242);
      expect(r.profile, 'emergency');
      expect(r.geometry.length, greaterThan(50));
      expect(r.geometry.first, const LatLng(43.26096, 76.9302));
      expect(r.sections, isNotEmpty);
      expect(r.sections.first.level, TrafficLevel.free);
      expect(r.sections.first.geometry, isNotEmpty);
      expect(r.maneuvers.first.kind, 'depart');
      expect(r.maneuvers.first.text, 'Начните движение');
      expect(r.maneuvers.first.street, 'проспект Жибек Жолы');
      expect(r.maneuvers.first.atM, 0);
      expect(r.maneuvers[1].kind, 'right');
      expect(r.maneuvers[1].atM, 139);
      expect(r.maneuvers[1].lat, closeTo(43.261028, 1e-9));
      expect(r.maneuvers[1].inM, isNull);
    });

    test('/traffic', () {
      final t = TrafficData.fromJson(fixtureMap('traffic'));
      expect(t.simulated, isTrue);
      expect(t.index, 2);
      expect(t.localHour, closeTo(13.44, 1e-9));
      expect(t.hotspots, isNotEmpty);
      expect(t.hotspots.first.id, 'amb-1');
      expect(t.hotspots.first.kind, 'jam');
      expect(t.hotspots.first.label, 'Затор');
      expect(t.hotspots[1].kind, 'accident');
      expect(t.hotspots[1].label, 'ДТП');
      expect(t.hotspots.first.radiusM, 408);
      expect(t.hotspots.first.severity, 0.42);
      expect(t.closures, isEmpty);
      expect(t.segments.length, greaterThan(100));
      final s = t.segments.first;
      expect(s.level, TrafficLevel.jam);
      expect(s.speedKph, 19.8);
      expect(s.name, 'улица Жансугурова');
      expect(s.points.first, const LatLng(43.29039, 76.93701));
      final byLevel = t.byLevel;
      expect(byLevel.values.fold<int>(0, (n, l) => n + l.length), t.segments.length);
      expect(byLevel.keys, isNot(contains(TrafficLevel.free)));
      for (final e in byLevel.entries) {
        expect(e.value.every((s) => s.level == e.key), isTrue);
      }
    });

    test('/triage', () {
      final t = TriageResult.fromJson(fixtureMap('triage'));
      expect(t.service, ServiceType.fire);
      expect(t.category, 'fire_engine');
      expect(t.categoryTitle, 'Пожарные части');
      expect(t.priority, 1);
      expect(t.confidence, 0.75);
      expect(t.lifeThreat, isFalse);
      expect(t.uncertain, isFalse);
      expect(t.matched, ['горит', 'дым']);
      expect(t.missing, ['address', 'people_inside']);
      expect(t.missing.map(missingLabel), ['адрес', 'есть ли люди внутри']);
      expect(t.victims, isNull);
      expect(t.hasSuggestion, isTrue);
    });

    test('/auth/citizen session round-trips through toJson', () {
      final s = Session.fromJson(fixtureMap('session'));
      expect(s.token, 'test-token-citizen');
      expect(s.user.id, startsWith('cit-'));
      expect(s.user.role, 'citizen');
      expect(s.user.name, 'Айдос');
      expect(s.user.phone, '+7 777 123 45 67');
      expect(s.user.unitId, isNull);
      expect(s.isValid, isTrue);
      final again = Session.fromJson(s.toJson());
      expect(again.token, s.token);
      expect(again.user.name, s.user.name);
      expect(again.user.phone, s.user.phone);
      expect(User.fromJson(fixtureMap('me')).id, s.user.id);
    });

    test('responder session binds a unit', () {
      final s = Session.fromJson(fixtureMap('rsession'));
      expect(s.user.role, 'responder');
      expect(s.user.unitId, 'ambulance-7-1');
      expect(Session.fromJson(s.toJson()).user.unitId, 'ambulance-7-1');
    });

    test('POST /incidents response', () {
      final i = Incident.fromJson(fixtureMap('incident_created'));
      expect(i.id, 'inc-45831');
      expect(i.number, 45831);
      expect(i.service, ServiceType.ambulance);
      expect(i.category, 'emergency');
      expect(i.categoryTitle, 'Экстренная помощь');
      expect(i.serviceTitle, 'Скорая помощь');
      expect(i.priority, 1);
      expect(i.status, IncidentStatus.assigned);
      expect(i.position, const LatLng(43.2445, 76.9457));
      expect(i.address, 'ул. Назарбаева, 125, Алматы');
      expect(i.createdAt, DateTime.utc(2026, 10, 11, 8, 19, 56, 651, 49));
      expect(i.closedAt, isNull);
      expect(i.timeline.map((t) => t.status), ['new', 'assigned']);
      expect(i.reachedAt(IncidentStatus.created), i.createdAt);
      expect(i.reachedAt(IncidentStatus.onScene), isNull);
      expect(i.unitsRequired, 1);
      expect(i.etaS, 141);
      expect(i.firstArrivalS, isNull);
      expect(i.description, 'человек потерял сознание');
      expect(i.callerName, 'Айдос');
      expect(i.callerPhone, '+7 777 123 45 67');
      expect(i.triage!.category, 'reanimation');
      expect(i.triage!.lifeThreat, isTrue);
      expect(i.my, isNull);

      final u = i.primaryUnit!;
      expect(u.id, 'ambulance-1-2');
      expect(u.status, UnitStatus.assigned);
      expect(u.statusLabel, 'Назначен');
      expect(u.free, isFalse);
      expect(u.lead, 'Азамат Иванов');
      expect(u.route.length, greaterThan(10));
      expect(u.etaS, 141);
      expect(u.distanceM, 1833);
    });

    test('GET /incidents: active and history', () {
      final list = IncidentList.fromJson(fixtureMap('incidents'));
      expect(list.active.map((i) => i.id), ['inc-45831', 'inc-45821']);
      expect(list.history, isEmpty);
      final onScene = list.active[1];
      expect(onScene.status, IncidentStatus.onScene);
      expect(onScene.firstArrivalS, 173);
      expect(onScene.etaS, 0);
      expect(onScene.primaryUnit!.route, isEmpty);
      expect(onScene.primaryUnit!.distanceM, isNull);
      expect(onScene.reachedAt(IncidentStatus.onScene), isNotNull);
      expect(
        timeToArrivalS(createdAt: onScene.createdAt, arrivedAt: onScene.reachedAt(IncidentStatus.onScene)),
        greaterThan(0),
      );

      final later = IncidentList.fromJson(fixtureMap('incidents_history'));
      expect(later.active, isEmpty);
      expect(later.history.map((i) => i.status).toSet(), {IncidentStatus.resolved});
      expect(later.history.first.units, isEmpty);
      expect(later.history.first.primaryUnit, isNull);
      expect(later.history.first.firstArrivalS, 75);
      expect(later.history.first.closedAt, isNotNull);
    });

    test('resolved incident', () {
      final i = Incident.fromJson(fixtureMap('incident_resolved'));
      expect(i.status, IncidentStatus.resolved);
      expect(i.status.isClosed, isTrue);
      expect(i.timeline.last.status, 'resolved');
      expect(i.timeline.last.at, isNotNull);
      expect(citizenStepper(i.status), everyElement(StepPhase.done));
    });

    test('/responder/me', () {
      final me = ResponderState.fromJson(fixtureMap('responder_me'));
      expect(me.unit.id, 'ambulance-7-1');
      expect(me.unit.status, UnitStatus.offDuty);
      expect(me.unit.onDuty, isFalse);
      expect(me.unit.statusLabel, 'Не на смене');
      expect(me.unit.callsign, 'СМП №7');
      expect(me.unit.plate, '402 AR 02');
      expect(me.unit.vehicle, 'Mercedes Sprinter');
      // Here `department` is a plain string, not an object.
      expect(me.unit.department, isNull);
      expect(me.unit.departmentName, 'Подстанция №7');
      expect(me.unit.fuelPct, 92);
      expect(me.unit.crew, hasLength(3));
      expect(me.unit.crew.first.name, 'Алексей Иванов');
      expect(me.unit.crew.first.role, 'Водитель · Старший бригады');
      expect(me.unit.crew.first.lead, isTrue);
      expect(me.unit.crew.first.online, isTrue);
      expect(me.unit.crew[1].lead, isFalse);
      expect(me.unit.equipment.length, greaterThan(3));
      expect(me.unit.equipment.first.name, 'Дефибриллятор');
      expect(me.unit.equipment.first.detail, 'ZOLL AED Plus');
      expect(me.unit.equipment.first.ok, isTrue);
      expect(me.unit.shiftStartedAt, isNull);
      expect(me.unit.incidentId, isNull);
      expect(me.assignment, isNull);
      expect(me.counters.active, 5);
      expect(me.counters.enRoute, 2);
      expect(me.counters.onScene, 2);
      expect(me.unread, 0);
    });

    test('empty message and history lists', () {
      expect(Message.listFromJson(fixture('messages')), isEmpty);
      expect(Incident.listFromJson(fixture('rhistory')), isEmpty);
    });
  });

  group('hand-written payloads', () {
    test('assignment with `my` leg', () {
      final me = ResponderState.fromJson({
        'unit': {
          'id': 'u1',
          'service': 'ambulance',
          'status': 'en_route',
          'shift_started_at': '2026-10-11T03:00:00+00:00',
        },
        'assignment': {
          'id': 'inc-1',
          'service': 'ambulance',
          'status': 'en_route',
          'my': {
            'eta_s': 240,
            'distance_m': 1200,
            'route': [
              [76.9, 43.2],
              [76.91, 43.21],
            ],
            'maneuvers': [
              {'kind': 'right', 'text': 'Поверните направо', 'street': 'ул. Сатпаева', 'in_m': 800},
            ],
          },
        },
        'counters': {'active': 3, 'en_route': 1, 'on_scene': 0},
        'unread': 2,
      });
      expect(me.unit.status, UnitStatus.enRoute);
      expect(me.unit.shiftStartedAt, DateTime.utc(2026, 10, 11, 3));
      final my = me.assignment!.my!;
      expect(my.etaS, 240);
      expect(my.distanceM, 1200);
      expect(my.route, const [LatLng(43.2, 76.9), LatLng(43.21, 76.91)]);
      expect(my.maneuvers.single.kind, 'right');
      expect(my.maneuvers.single.street, 'ул. Сатпаева');
      expect(my.maneuvers.single.inM, 800);
      expect(my.maneuvers.single.atM, isNull);
      expect(me.unread, 2);
    });

    test('message', () {
      final m = Message.fromJson({
        'id': 'm1',
        'unit_id': 'u1',
        'sender': 'dispatcher',
        'author': 'Диспетчер',
        'text': 'Подтвердите приём',
        'at': '2026-10-11T08:00:00+00:00',
      });
      expect(m.fromDispatcher, isTrue);
      expect(m.text, 'Подтвердите приём');
      expect(m.at, DateTime.utc(2026, 10, 11, 8));
      expect(Message.fromJson({'id': 'm2', 'sender': 'unit'}).fromDispatcher, isFalse);
    });

    test('closure and hotspot', () {
      final c = RoadClosure.fromJson({'id': 'c1', 'lat': 43.2, 'lon': 76.9, 'reason': 'ДТП'});
      expect(c.position, const LatLng(43.2, 76.9));
      expect(c.reason, 'ДТП');
      expect(TrafficHotspot.fromJson({'id': 'h', 'lat': 1, 'lon': 2, 'kind': 'roadworks'}).label, 'Дорожные работы');
      final t = TrafficData.fromJson({
        'closures': [
          {'id': 'c1', 'lat': 43.2, 'lon': 76.9},
        ],
      });
      expect(t.closures.single.id, 'c1');
    });

    test('dispatch comparison', () {
      final d = DispatchComparison.fromJson({
        'picks': {
          'nearest': ['a'],
          'min_eta': ['b'],
          'jardem': ['a', 'c'],
        },
        'candidates': [
          {'id': 'a', 'cost': 605},
        ],
      });
      expect(d.picks['jardem'], ['a', 'c']);
      expect(d.candidates.single['cost'], 605);
    });

    test('incident picks the crew with the smallest ETA', () {
      final i = Incident.fromJson({
        'id': 'i',
        'service': 'fire',
        'units': [
          {'id': 'slow', 'service': 'fire', 'eta_s': 300},
          {'id': 'unknown', 'service': 'fire'},
          {'id': 'fast', 'service': 'fire', 'eta_s': 120},
        ],
      });
      expect(i.primaryUnit!.id, 'fast');
      expect(i.serviceTitle, 'Пожарные');
    });

    test('Unit.moved applies a realtime position', () {
      final u = Unit.fromJson(fixtureMap('unit_detail'));
      final moved = u.moved(
        const UnitPosition(
          id: 'ambulance-1-2',
          service: ServiceType.ambulance,
          status: UnitStatus.enRoute,
          lat: 43.24,
          lon: 76.94,
          heading: 90,
        ),
      );
      expect(moved.position, const LatLng(43.24, 76.94));
      expect(moved.heading, 90);
      expect(moved.status, UnitStatus.enRoute);
      expect(moved.statusLabel, 'В пути');
      expect(moved.free, isFalse);
      // Everything else is preserved.
      expect(moved.name, u.name);
      expect(moved.plate, u.plate);
      expect(moved.photo, u.photo);
      expect(moved.route, u.route);
      expect(moved.etaS, u.etaS);
      expect(moved.department, same(u.department));
    });
  });

  group('tolerance to missing / wrong data', () {
    test('empty objects never throw', () {
      expect(Meta.fromJson({}).bbox, kAlmatyBounds);
      expect(Meta.fromJson({}).center, kDemoPoint);
      expect(Meta.fromJson({}).disclaimer, kDefaultDisclaimer);
      expect(Meta.fromJson({}).phoneOf(ServiceType.police), '102');
      expect(Unit.fromJson({}).status, UnitStatus.unknown);
      expect(Unit.fromJson({}).statusLabel, 'Неизвестно');
      expect(Unit.fromJson({'status': 'available'}).free, isTrue);
      expect(Incident.fromJson({}).status, IncidentStatus.unknown);
      expect(Incident.fromJson({}).primaryUnit, isNull);
      expect(Incident.fromJson({}).timeline, isEmpty);
      expect(IncidentList.fromJson({}).active, isEmpty);
      expect(TrafficData.fromJson({}).segments, isEmpty);
      expect(TrafficData.fromJson({}).index, 0);
      expect(RouteResult.fromJson({}).geometry, isEmpty);
      expect(TriageResult.fromJson({}).hasSuggestion, isFalse);
      expect(Stats.fromJson({}).services, isEmpty);
      expect(Session.fromJson({}).isValid, isFalse);
      expect(ResponderState.fromJson({}).assignment, isNull);
      expect(ServiceInfo.listFromJson(null), isEmpty);
      expect(ServiceInfo.listFromJson('nope'), isEmpty);
      expect(Category.fromJson({}).priority, 3);
      expect(Health.fromJson({}).ok, isFalse);
    });

    test('wrong types fall back to defaults', () {
      final u = Unit.fromJson({
        'id': 7,
        'service': 'police',
        'lat': '43.25',
        'lon': null,
        'eta_s': '90',
        'distance_m': 1200.6,
        'free': 'yes',
        'route': 'none',
        'capabilities': {'a': 1},
        'crew': [1, 2, null],
        'heading': 'north',
      });
      expect(u.id, '7');
      expect(u.lat, 43.25);
      expect(u.lon, 0);
      expect(u.etaS, 90);
      expect(u.distanceM, 1201);
      expect(u.free, isFalse);
      expect(u.route, isEmpty);
      expect(u.capabilities, isEmpty);
      expect(u.crew, isEmpty);
      expect(u.heading, 0);
    });

    test('uncertain triage has no suggestion', () {
      final t = TriageResult.fromJson({'service': 'police', 'category': 'patrol', 'uncertain': true});
      expect(t.hasSuggestion, isFalse);
      expect(TriageResult.fromJson({'service': 'police'}).hasSuggestion, isFalse);
      expect(TriageResult.fromJson({'service': 'police', 'category': 'patrol'}).hasSuggestion, isTrue);
    });

    test('bad dates and unknown stats keys are skipped', () {
      expect(Incident.fromJson({'created_at': 'yesterday'}).createdAt, isNull);
      expect(
        Stats.fromJson({
          'services': {
            'army': {},
            'fire': {'units': 2},
          },
        }).services.keys,
        [ServiceType.fire],
      );
      expect(
        Meta.fromJson({
          'bbox': [1, 2, 3],
        }).bbox,
        kAlmatyBounds,
      );
      expect(
        Meta.fromJson({
          'center': {'lat': 43.3},
        }).center,
        kDemoPoint,
      );
    });
  });

  test('photo credits cover every bundled photo', () {
    expect(kPhotoCredits, hasLength(9));
    expect(kPhotoCredits.map((c) => c.file), contains('almaty_skyline_1'));
    for (final c in kPhotoCredits) {
      expect(c.author, isNotEmpty);
      expect(c.license, startsWith('CC'));
      expect(c.source, startsWith('https://commons.wikimedia.org/wiki/File:'));
    }
  });
}
