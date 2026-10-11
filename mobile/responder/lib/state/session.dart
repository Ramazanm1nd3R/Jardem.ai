import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';

const String kSessionKey = 'jardem.responder.session';

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

/// The signed-in crew lead (null when signed out), persisted across launches.
class SessionController extends StateNotifier<Session?> {
  SessionController(this._api, this._prefs) : super(readStoredSession(_prefs)) {
    _api.token = state?.token;
  }

  final ApiClient _api;
  final SharedPreferences _prefs;

  /// `POST /auth/responder`; throws [ApiException] (401: wrong login or PIN).
  Future<void> signIn({required String login, required String pin}) async {
    final session = await _api.loginResponder(login: login.trim(), pin: pin.trim());
    await _prefs.setString(kSessionKey, jsonEncode(session.toJson()));
    if (mounted) state = session;
  }

  /// Forgets the saved session («Сменить пользователя», logout, expired token).
  Future<void> signOut() async {
    if (_api.token != null) {
      try {
        // Lets the server return a simulated unit to autopilot; signing out locally must not depend on it.
        await _api.logout();
      } on Object {
        // offline or expired token: nothing to release
      }
    }
    _api.token = null;
    await _prefs.remove(kSessionKey);
    if (mounted) state = null;
  }
}

final sessionProvider = StateNotifierProvider<SessionController, Session?>(
  (ref) => SessionController(ref.watch(apiClientProvider), ref.watch(sharedPreferencesProvider)),
);

/// Message for a failed sign-in: 401 means wrong credentials here.
String signInError(Object error) =>
    error is ApiException && error.isUnauthorized ? 'Неверный логин или PIN-код.' : errorMessage(error);
