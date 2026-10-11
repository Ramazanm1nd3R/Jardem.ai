# jardem_core

Shared code of the Jardem.ai apps (citizen, responder): models, `ApiClient`, `RealtimeClient`, theme, widgets and
pure utilities. See [`../../README.md`](../../README.md) for the overview, configuration and test commands.

```dart
import 'package:jardem_core/jardem_core.dart';

final config = ApiConfig.resolve();
final api = ApiClient(baseUrl: config.baseUrl);
final realtime = RealtimeClient(config.wsUrl)..connect();

final session = await api.loginResponder(login: 'smp7', pin: '1234'); // token is stored on the client
final me = await api.responderMe();
realtime.events.listen((event) { /* UnitsMoved, IncidentUpdated, MessageCreated … → re-fetch */ });
```
