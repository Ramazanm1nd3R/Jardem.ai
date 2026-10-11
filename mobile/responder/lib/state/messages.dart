import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../logic/chat.dart';
import 'providers.dart';
import 'session.dart';

const String kChatReadKey = 'jardem.responder.chat_read_at';

class ChatState {
  const ChatState({this.messages, this.error, this.lastReadAt});

  /// Null until the first load.
  final List<Message>? messages;
  final Object? error;
  final DateTime? lastReadAt;

  int get unread => unreadCount(messages ?? const [], lastReadAt);
}

/// Chat with dispatch: reloads on `message.created` for this unit.
class ChatController extends StateNotifier<ChatState> {
  ChatController(this._api, Stream<RealtimeEvent> events, this._ref, {required this.unitId})
    : super(
        ChatState(
          lastReadAt: DateTime.tryParse(_ref.read(sharedPreferencesProvider).getString('$kChatReadKey.$unitId') ?? ''),
        ),
      ) {
    if (unitId.isEmpty) return;
    _sub = events.where((e) => e is MessageCreated && e.unitId == unitId).listen((_) => refresh());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
    refresh();
  }

  final ApiClient _api;
  final Ref _ref;
  final String unitId;
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _timer;

  Future<void> refresh() async {
    try {
      final messages = await _api.responderMessages();
      if (mounted) state = ChatState(messages: messages, lastReadAt: state.lastReadAt);
    } catch (e) {
      if (mounted) state = ChatState(messages: state.messages, error: e, lastReadAt: state.lastReadAt);
    }
  }

  /// `POST /responder/messages`; throws [ApiException]. Blank text is ignored.
  Future<bool> send(String raw) async {
    final text = outgoingText(raw);
    if (text == null) return false;
    final sent = await _api.sendResponderMessage(text);
    if (mounted) {
      final known = state.messages ?? const <Message>[];
      state = ChatState(messages: [...known.where((m) => m.id != sent.id), sent], lastReadAt: state.lastReadAt);
    }
    return true;
  }

  /// The chat is on screen: everything received so far counts as read.
  void markRead() {
    final messages = state.messages;
    if (messages == null || state.unread == 0) return;
    var latest = state.lastReadAt;
    for (final m in messages) {
      final at = m.at;
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    if (latest == null) return;
    _ref.read(sharedPreferencesProvider).setString('$kChatReadKey.$unitId', latest.toIso8601String());
    state = ChatState(messages: messages, error: state.error, lastReadAt: latest);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider<ChatController, ChatState>((ref) {
  final unitId = ref.watch(sessionProvider.select((s) => s?.user.unitId)) ?? '';
  return ChatController(ref.watch(apiClientProvider), ref.watch(realtimeEventsProvider), ref, unitId: unitId);
});
