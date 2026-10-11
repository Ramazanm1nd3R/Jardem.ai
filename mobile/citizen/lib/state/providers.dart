import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Overridden in `main()` with the loaded instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final apiConfigProvider = Provider<ApiConfig>((ref) => ApiConfig.resolve());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(baseUrl: ref.watch(apiConfigProvider).baseUrl);
  ref.onDispose(client.close);
  return client;
});

final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final client = RealtimeClient(ref.watch(apiConfigProvider).wsUrl)..connect();
  ref.onDispose(client.dispose);
  return client;
});

/// Realtime notifications; tests override this with their own stream.
final realtimeEventsProvider = Provider<Stream<RealtimeEvent>>((ref) => ref.watch(realtimeClientProvider).events);

/// Platform facts and the disclaimer; falls back to built-in defaults offline.
final metaProvider = FutureProvider<Meta>((ref) async {
  try {
    return await ref.watch(apiClientProvider).meta();
  } on ApiException {
    // Retry on next read, but never block the UI on /meta.
    Timer(const Duration(seconds: 10), ref.invalidateSelf);
    return const Meta();
  }
});

final catalogProvider = FutureProvider<List<ServiceInfo>>((ref) => ref.watch(apiClientProvider).catalog());

/// Opens the phone dialler. Returns false when the platform cannot do it.
typedef Dialer = Future<bool> Function(String number);

final dialerProvider = Provider<Dialer>(
  (ref) => (number) async {
    try {
      return await launchUrl(telUri(number));
    } catch (_) {
      return false;
    }
  },
);
