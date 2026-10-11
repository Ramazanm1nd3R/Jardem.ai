import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/backoff.dart';
import 'realtime_event.dart';

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

/// WebSocket change feed with automatic reconnect (exponential backoff).
///
/// Events are notifications only — re-fetch details over REST.
class RealtimeClient {
  RealtimeClient(String url, {ChannelFactory? channelFactory, Duration Function(int attempt)? backoff})
    : _uri = Uri.parse(url),
      _factory = channelFactory ?? WebSocketChannel.connect,
      _backoff = backoff ?? reconnectDelay;

  final Uri _uri;
  final ChannelFactory _factory;
  final Duration Function(int attempt) _backoff;

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  bool _running = false;
  bool _isConnected = false;

  /// Broadcast stream of typed events.
  Stream<RealtimeEvent> get events => _events.stream;

  /// Emits whenever the connection goes up or down.
  Stream<bool> get connection => _connected.stream;

  bool get isConnected => _isConnected;

  /// Starts (or restarts) the connection loop. Safe to call repeatedly.
  void connect() {
    if (_running) return;
    _running = true;
    _open();
  }

  void _open() {
    if (!_running) return;
    try {
      final channel = _factory(_uri);
      _channel = channel;
      channel.ready
          .then((_) {
            if (_channel != channel) return;
            _attempt = 0;
            _setConnected(true);
          })
          .catchError((Object _) {
            if (_channel == channel) _scheduleReconnect();
          });
      _sub = channel.stream.listen(
        _onData,
        onError: (Object _) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return;
    }
    final event = RealtimeEvent.fromJson(decoded);
    if (event != null && !_events.isClosed) _events.add(event);
  }

  void _scheduleReconnect() {
    _setConnected(false);
    _sub?.cancel();
    _sub = null;
    _channel = null;
    if (!_running || _retry != null) return;
    _retry = Timer(_backoff(_attempt++), () {
      _retry = null;
      _open();
    });
  }

  void _setConnected(bool value) {
    if (_isConnected == value) return;
    _isConnected = value;
    if (!_connected.isClosed) _connected.add(value);
  }

  /// Stops reconnecting and closes the socket; [connect] may be called again.
  Future<void> disconnect() async {
    _running = false;
    _retry?.cancel();
    _retry = null;
    await _sub?.cancel();
    _sub = null;
    final channel = _channel;
    _channel = null;
    _setConnected(false);
    // Not awaited: closing a socket that never connected may not complete.
    unawaited(channel?.sink.close().catchError((Object _) {}));
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _connected.close();
  }
}
