/// API / WebSocket URL resolution (pure; platform facts are passed in).
library;

const String kApiPath = '/api/v1';

/// Picks the REST base URL (no trailing slash).
///
/// 1. [override] (`--dart-define=JARDEM_API=…`) when non-empty;
/// 2. on web: the page's own origin + `/api/v1`;
/// 3. Android (emulator): `http://10.0.2.2:8080/api/v1`;
/// 4. otherwise `http://localhost:8080/api/v1`.
String resolveApiBase({String override = '', required bool isWeb, required bool isAndroid, Uri? pageUri}) {
  final explicit = override.trim();
  if (explicit.isNotEmpty) return _stripTrailingSlashes(explicit);
  if (isWeb && pageUri != null && pageUri.hasScheme && pageUri.host.isNotEmpty) {
    return '${pageUri.origin}$kApiPath';
  }
  return isAndroid ? 'http://10.0.2.2:8080$kApiPath' : 'http://localhost:8080$kApiPath';
}

/// `http://h/api/v1` → `ws://h/api/v1/ws`, `https://…` → `wss://…`.
String wsUrlFor(String apiBase) {
  final base = Uri.parse(_stripTrailingSlashes(apiBase));
  final scheme = base.scheme == 'https' || base.scheme == 'wss' ? 'wss' : 'ws';
  return base.replace(scheme: scheme, path: '${base.path}/ws').toString();
}

String _stripTrailingSlashes(String s) {
  var out = s;
  while (out.endsWith('/')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

/// Bundled asset path of a unit photo basename (`ambulance_kz_1`), or null.
String? photoAsset(String? basename, {bool thumb = true}) {
  final name = (basename ?? '').trim();
  if (name.isEmpty) return null;
  return 'assets/images/$name${thumb ? '_thumb' : ''}.jpg';
}
