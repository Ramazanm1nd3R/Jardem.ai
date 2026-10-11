import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';

const String kSessionKey = 'jardem.citizen.session';

/// Reads a persisted session; null when absent or corrupted.
Session? readStoredSession(SharedPreferences prefs) {
  final raw = prefs.getString(kSessionKey);
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final session = Session.fromJson(decoded.cast<String, dynamic>());
    return session.isValid ? session : null;
  } on FormatException {
    return null;
  }
}

/// The signed-in citizen (null when signed out), persisted across launches.
class SessionController extends StateNotifier<Session?> {
  SessionController(this._api, this._prefs) : super(readStoredSession(_prefs)) {
    _api.token = state?.token;
    if (state != null) _validate();
  }

  final ApiClient _api;
  final SharedPreferences _prefs;

  /// Drops a stored token the server no longer accepts.
  Future<void> _validate() async {
    try {
      await _api.me();
    } on ApiException catch (e) {
      if (e.isUnauthorized && mounted) await signOut();
    }
  }

  /// `POST /auth/citizen`; throws [ApiException] on failure.
  Future<void> signIn({required String phone, required String name}) async {
    final session = await _api.loginCitizen(phone: formatKzPhone(phone), name: name.trim());
    await _prefs.setString(kSessionKey, jsonEncode(session.toJson()));
    if (mounted) state = session;
  }

  Future<void> signOut() async {
    _api.token = null;
    await _prefs.remove(kSessionKey);
    if (mounted) state = null;
  }
}

final sessionProvider = StateNotifierProvider<SessionController, Session?>(
  (ref) => SessionController(ref.watch(apiClientProvider), ref.watch(sharedPreferencesProvider)),
);
