import 'package:flutter/foundation.dart';

import '../utils/urls.dart';

/// Where the backend lives for this build / platform.
class ApiConfig {
  const ApiConfig(this.baseUrl);

  /// See [resolveApiBase] for the rules.
  factory ApiConfig.resolve() => ApiConfig(
    resolveApiBase(
      override: const String.fromEnvironment('JARDEM_API'),
      isWeb: kIsWeb,
      isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      pageUri: kIsWeb ? Uri.base : null,
    ),
  );

  /// e.g. `http://localhost:8080/api/v1`.
  final String baseUrl;

  String get wsUrl => wsUrlFor(baseUrl);
}
