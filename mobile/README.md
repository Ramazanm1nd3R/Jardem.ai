# Jardem.ai — mobile

Flutter side of the Jardem.ai emergency-services aggregator (Almaty, demo/simulation).

```
mobile/
  packages/jardem_core/   shared Dart package: models, API client, realtime, theme, widgets, utils
  citizen/                citizen app (Android · iOS · web)
  responder/              crew app (Android · iOS · web)
```

Flutter 3.41 / Dart 3.11. No code generation — `flutter pub get` is the only setup step.

## jardem_core

| Folder | What is inside |
|---|---|
| `lib/src/models` | Immutable, null-tolerant models with `fromJson` for every payload in `docs/api.md` (catalog, units, incidents, routes, traffic, triage, session, responder state, messages, stats, meta) and the wire enums with Russian labels. |
| `lib/src/api` | `ApiClient` (over `package:http`, injectable `http.Client`, bearer token, `ApiException(status, detail)`), covering public, citizen, responder and dispatcher endpoints. `ApiConfig.resolve()` picks the base URL. |
| `lib/src/realtime` | `RealtimeClient` — WebSocket feed with auto-reconnect (1 s, 2 s, 4 s … 30 s) and a typed broadcast `Stream<RealtimeEvent>`. |
| `lib/src/theme` | `JardemTheme.light()`, `JardemColors`, bundled Manrope (variable font, OFL). |
| `lib/src/widgets` | `JardemLogo`, `ServiceBadge`, `StatusChip`, `UnitCard`, buttons, state views, `JardemMap` (flutter_map: animated unit markers, my location, dashed / traffic-coloured routes, traffic segments, hotspots, closures). |
| `lib/src/utils` | Pure logic: Russian distance / ETA formatting, +7 phone handling, incident → stepper mapping, geometry, traffic levels, reconnect backoff, URL resolution. This folder is mutation-tested. |

### API base URL

1. `--dart-define=JARDEM_API=http://host:8080/api/v1` if given;
2. on web: the page's own origin + `/api/v1`;
3. Android emulator: `http://10.0.2.2:8080/api/v1`; everything else: `http://localhost:8080/api/v1`.

The WebSocket URL is derived from it (`ws(s)://…/api/v1/ws`). On a real phone pass your computer's LAN address
with `JARDEM_API`.

### Map tiles

The mock-ups use CARTO Voyager, but CARTO now answers key-less requests with an «API KEY REQUIRED» watermark
tile, so the default tile source is the key-less OpenStreetMap standard layer, softened with a colour filter.
To use CARTO (or any other raster source) pass:

```
--dart-define=JARDEM_TILE_URL='https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png?api_key=YOUR_KEY'
--dart-define=JARDEM_TILE_ATTRIBUTION='© OpenStreetMap contributors, © CARTO'
```

The attribution string is shown on every map and in «О приложении».

## Citizen app

```
citizen/lib/
  main.dart, app.dart, router.dart
  state/      Riverpod providers: session, location, live units, traffic, incidents / tracking
  shared/     app bar, chips, phone-width frame, dialler helper
  features/   onboarding · home · service · call · tracking · calls · profile
```

State management: flutter_riverpod. Routing: go_router (bottom navigation is a `StatefulShellRoute`).

### Run

The backend must be running (`docker compose up` in the repo root → `http://localhost:8080`).

```sh
cd mobile/citizen
flutter pub get

# web (dev server); the API is on another origin, so name it explicitly
flutter run -d chrome --dart-define=JARDEM_API=http://localhost:8080/api/v1

# Android emulator (uses http://10.0.2.2:8080 automatically) / iOS simulator (uses localhost)
flutter run

# a real phone on the same Wi-Fi
flutter run --dart-define=JARDEM_API=http://192.168.1.10:8080/api/v1
```

### Build for the cluster gateway

The nginx gateway serves `mobile/citizen/build/web` at `http://localhost:8080/app/citizen/`:

```sh
cd mobile/citizen
flutter build web --release --base-href /app/citizen/ --no-web-resources-cdn
```

`--no-web-resources-cdn` bundles CanvasKit so the app does not depend on Google's CDN. If the page is stale or
404s after a build (the build recreates the directory the gateway bind-mounts), run `docker compose restart gateway`
from the repo root.

### Things worth knowing

* **It is a simulation.** The `/meta` disclaimer is shown on the home map (dismissible) and on the call form;
  a red 112 button is always on the home screen. Phone buttons open the real dialler (`tel:` 112 / 103 / 102 / 101).
* **Location.** `geolocator` is asked once on the home screen. If permission is denied, the fix is unavailable or
  it lies outside `/meta.bbox`, the app uses the demo point 43.2445, 76.9457 «ул. Назарбаева, 125, Алматы» and
  labels it «Демо-адрес». Long-press the home map to move the pin. There is no reverse geocoding: for a GPS or
  manual point the user types the address in the call form.
* **Photos / video** picked in the call form stay on the device; the demo backend has no upload endpoint.
* **Chat with the crew** is not available in the demo — «Написать» says so.
* Android: `INTERNET` + location permissions and `usesCleartextTraffic` (development API over HTTP) are set in
  `android/app/src/main/AndroidManifest.xml`. iOS: usage strings and local-network ATS exception are in
  `ios/Runner/Info.plist`.

## Responder app

The crew's side: sign in with the unit login + PIN (demo: `smp7` / `1234`; any unit id such as `fire-9-1` works with
the same PIN), go on shift, receive a call, navigate with the traffic-coloured route and confirm every step.

```
responder/lib/
  main.dart, app.dart, router.dart
  logic/      pure decision logic (mutation-tested): status state machine and button labels per service,
              shift timeline, next maneuver + arrow, arrival clock, history grouping, quick replies,
              unread counter, GPS fix acceptance, realtime event relevance, closures, call facts
  state/      Riverpod: session, crew (`/responder/me` + realtime + 5 s poll), chat, map (traffic, peers,
              live `/route`), GPS sharing, closures
  shared/     phone-width frame, app bar, tabs, chips, the step button(s), the incoming-call card
  features/   login · home · navigation · call · crew · shift · chat · history · closure · profile
```

### Run / build

```sh
cd mobile/responder
flutter pub get
flutter run -d chrome --dart-define=JARDEM_API=http://localhost:8080/api/v1     # web dev server
flutter run                                                                      # emulator / simulator

# for the gateway: http://localhost:8080/app/responder/
flutter build web --release --base-href /app/responder/ --no-web-resources-cdn
```

To get a call for the demo crew: go on shift in the app, then create an incident close to the unit as a citizen
(the optimiser picks the best crew, so the point has to be nearer to «СМП №7» than to the other free ambulances):

```sh
API=http://localhost:8080/api/v1
RT=$(curl -s -X POST $API/auth/responder -H 'content-type: application/json' -d '{"login":"smp7","pin":"1234"}' | jq -r .token)
CT=$(curl -s -X POST $API/auth/citizen -H 'content-type: application/json' -d '{"phone":"+7 701 000 11 22","name":"Тест"}' | jq -r .token)
read LAT LON < <(curl -s $API/responder/me -H "authorization: Bearer $RT" | jq -r '.unit | "\(.lat - 0.009) \(.lon - 0.011)"')
curl -s -X POST $API/incidents -H "authorization: Bearer $CT" -H 'content-type: application/json' \
  -d "{\"category\":\"emergency\",\"lat\":$LAT,\"lon\":$LON,\"description\":\"Мужчина, около 60 лет, потерял сознание\"}" | jq '.units[].id'
```

### Things worth knowing

* **One button per state.** `logic/steps.dart` maps the unit status to the next action: off duty → «Выйти на смену»,
  free → «Завершить смену», assigned → «Принять вызов», en route → «Подтвердить прибытие», on scene → «Пациент
  загружен» (ambulance only) + «Завершить вызов», transporting → «Завершить вызов». Other services have no
  transport step and no «patient» wording. A 409 from the server is explained in a snackbar and the state is re-fetched.
* **The server never changes the crew's status by itself.** After «Принять вызов» the simulator moves the vehicle
  along the route (3× real time); the crew confirms arrival, loading and completion.
* **Navigation.** The line is `/route` from the vehicle's current position to the call (re-requested every 10 s and
  on `traffic.updated`), falling back to `assignment.my.route`. The banner shows the first maneuver that is not
  `depart`. «Открыть в навигаторе» opens `geo:` (Android), Apple Maps (iOS) or Google Maps directions (web).
* **«Передавать геопозицию»** (Профиль, Смена и статус) is OFF by default: the server then simulates the movement.
  When ON and the crew is on shift, a `geolocator` fix is posted to `/responder/location` every 5 s — only if it lies
  inside the `/meta` bbox of Almaty. Fixes are read while the app is in the foreground; the background-location
  entries in the manifests are what a production build with a foreground service would need.
* **Unread counter** is local: dispatcher messages newer than the last time the chat tab was open (stored per unit).
* **Closures.** `/traffic` does not say who reported a closure, so «Снять» is offered only for closures reported
  from this device (ids kept in shared preferences).
* **Signing in takes a unit under manual control.** `POST /auth/responder` marks the unit as driven by a person:
  from then on the simulator no longer accepts / arrives / completes for it, and there is no endpoint that hands it
  back (only a backend restart does). Sign in as a simulated unit (`fire-9-1`, `police-10-1`, …) only if you are
  going to drive it; otherwise take it off shift before leaving so that no call waits for it.
* Not in the API, therefore not in the app: adding crew members, audio / channels (honest «В разработке» tabs).
  The time of «Пациент загружен» is kept in memory only (the incident timeline does not record it).
* Android: `INTERNET`, fine / coarse / background location, foreground-service permissions, cleartext for the dev
  host, `tel:` / `geo:` queries. iOS: when-in-use and always location strings, `location` background mode,
  `tel` / maps query schemes, local-network ATS exception.

## Tests

```sh
cd mobile/packages/jardem_core && flutter analyze && flutter test
cd mobile/citizen              && flutter analyze && flutter test
cd mobile/responder            && flutter analyze && flutter test
```

* `jardem_core/test/utils` — unit tests of every pure function;
* `jardem_core/test/models` — model parsing against JSON captured from the live API (`test/fixtures`);
* `jardem_core/test/api`, `test/realtime` — `ApiClient` with `MockClient`, `RealtimeClient` with a fake channel;
* `jardem_core/test/widgets` — shared widgets and `JardemMap`;
* `citizen/test` — widget tests of the flows with a fake `ApiClient` (onboarding, home, service, call form,
  tracking, tabs) and unit tests of the state layer.
* `responder/test/logic` — unit tests of every pure function in `responder/lib/logic`;
* `responder/test` — widget tests with a fake `ApiClient` that implements the crew state machine (login ok / 401,
  home, incoming call → accept → arrive → transport → complete, a fire crew without the transport step, 409,
  navigation, chat, closures, history, profile, GPS sharing) and unit tests of the state layer.

### Mutation testing (pure logic in `jardem_core/lib/src/utils` and `responder/lib/logic`)

```sh
dart pub global activate mutation_test
cd mobile/packages/jardem_core
dart pub global run mutation_test mutation_test.xml     # ≈ 15–20 min, report in mutation-test-report/
```

The responder's decision logic is tested the same way (same rule set, `flutter test test/logic` per mutant):

```sh
cd mobile/responder
dart pub global run mutation_test mutation_test.xml     # ≈ 12 min, 200+ mutants
```

`mutation_test.xml` mutates only `lib/src/utils/**.dart` with the built-in rules plus a few extra ones
(strict-comparison flips, boolean literals, rounding mode, emptiness checks, integer constants) and runs
`flutter test test/utils` for every mutant. The tool edits source files in place while it runs — do not edit
or run other tests in the package at the same time.

## Credits

* Map data © OpenStreetMap contributors (ODbL).
* Photos: Wikimedia Commons, see `packages/jardem_core/assets/images/ATTRIBUTION.md` (also listed in-app under
  Профиль → О приложении).
* Font: Manrope, SIL Open Font License 1.1 (`packages/jardem_core/assets/fonts/OFL.txt`).
