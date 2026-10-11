/// Reconnect schedule for the realtime channel.
library;

/// Delay before reconnect [attempt] (0-based): 1 s, 2 s, 4 s … capped at [max].
Duration reconnectDelay(
  int attempt, {
  Duration base = const Duration(seconds: 1),
  Duration max = const Duration(seconds: 30),
}) {
  // Past 2^20 the cap has long been reached; the clamp also avoids overflow
  // for huge attempts and treats negative ones like the first.
  final factor = 1 << attempt.clamp(0, 20);
  final ms = base.inMilliseconds * factor;
  return ms >= max.inMilliseconds ? max : Duration(milliseconds: ms);
}
