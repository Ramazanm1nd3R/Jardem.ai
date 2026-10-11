/// A non-2xx response or a transport failure.
class ApiException implements Exception {
  const ApiException(this.status, this.detail);

  /// Transport-level failure (no HTTP status).
  const ApiException.network([this.detail = 'network error']) : status = 0;

  /// HTTP status code; 0 when the request never got a response.
  final int status;

  /// Server-provided `detail` (English, for logs) or a transport error text.
  final String detail;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isNotFound => status == 404;
  bool get isConflict => status == 409;
  bool get isUnprocessable => status == 422;
  bool get isRateLimited => status == 429;

  /// Russian message suitable for showing to a user.
  String get userMessage => switch (status) {
    0 => 'Нет соединения с сервером. Проверьте интернет и попробуйте ещё раз.',
    401 => 'Сессия истекла. Войдите заново.',
    403 => 'Недостаточно прав для этого действия.',
    404 => 'Не найдено.',
    409 => 'Действие сейчас недоступно.',
    422 => 'Проверьте введённые данные.',
    429 => 'Слишком много запросов. Попробуйте позже.',
    _ => 'Ошибка сервера ($status). Попробуйте ещё раз.',
  };

  @override
  String toString() => 'ApiException($status, $detail)';
}
