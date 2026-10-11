import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../logic/chat.dart';
import '../../shared/widgets.dart';
import '../../state/crew.dart';
import '../../state/messages.dart';

/// «Связь с диспетчером»: the chat is real, audio and channels are not built.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _tab = 0;
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String raw) async {
    if (_sending || outgoingText(raw) == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _sending = true);
    try {
      await ref.read(chatProvider.notifier).send(raw);
      if (raw == _input.text) _input.clear();
    } catch (e) {
      toast(messenger, 'Сообщение не отправлено. ${errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final crew = ref.watch(crewProvider);
    final messages = chat.messages;
    // This tab is the visible one (hidden shell branches have tickers off).
    if (TickerMode.valuesOf(context).enabled && _tab == 0 && chat.unread > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(chatProvider.notifier).markRead();
      });
    }
    ref.listen(chatProvider.select((c) => c.messages?.length), (_, _) => _toBottom());
    final replies = quickReplies(crew.status, crew.unit?.service ?? ServiceType.ambulance);
    return Scaffold(
      appBar: const JardemAppBar(title: 'Связь с диспетчером'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentTabs(
              labels: const ['Чат', 'Аудио', 'Каналы'],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          if (_tab != 0)
            Expanded(
              child: MessageView(
                icon: Icons.construction_rounded,
                title: 'В разработке',
                text: _tab == 1
                    ? 'Голосовая связь с диспетчером в прототипе не реализована. Используйте чат или рацию.'
                    : 'Групповые каналы экипажей в прототипе не реализованы.',
              ),
            )
          else ...[
            Expanded(
              child: messages == null
                  ? (chat.error == null
                        ? const LoadingView()
                        : MessageView.error(chat.error!, onRetry: () => ref.read(chatProvider.notifier).refresh()))
                  : messages.isEmpty
                  ? const MessageView(
                      icon: Icons.forum_outlined,
                      title: 'Сообщений пока нет',
                      text: 'Здесь появятся указания диспетчера и ваши ответы.',
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: messages.length,
                      itemBuilder: (_, i) => _Bubble(messages[i]),
                    ),
            ),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: replies.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => OutlinedButton(
                  key: Key('quick-${replies[i]}'),
                  onPressed: _sending ? null : () => _send(replies[i]),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: JardemColors.primaryDark,
                    side: const BorderSide(color: JardemColors.border, width: 1.5),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: JardemTheme.text(13, FontWeight.w700),
                  ),
                  child: Text(replies[i]),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('chat-input'),
                        controller: _input,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _send,
                        decoration: const InputDecoration(hintText: 'Написать сообщение…'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SquareIconButton(
                      key: const Key('chat-send'),
                      icon: Icons.send_rounded,
                      color: Colors.white,
                      background: JardemColors.primary,
                      tooltip: 'Отправить',
                      onPressed: _sending ? null : () => _send(_input.text),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.message);
  final Message message;

  @override
  Widget build(BuildContext context) {
    final mine = !message.fromDispatcher;
    final author = message.author.isEmpty ? (mine ? 'Экипаж' : 'Диспетчер') : message.author;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.68),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: mine ? JardemColors.primary : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
        boxShadow: mine ? null : JardemColors.cardShadow,
      ),
      child: Text(
        message.text,
        style: JardemTheme.text(14, FontWeight.w500, color: mine ? Colors.white : JardemColors.navy, height: 1.35),
      ),
    );
    return Padding(
      key: Key('msg-${message.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            const CircleAvatar(
              radius: 16,
              backgroundColor: JardemColors.primarySoft,
              child: Icon(Icons.headset_mic_rounded, size: 17, color: JardemColors.primaryDark),
            ),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 2, right: 2),
                child: Text(
                  '$author · ${formatClock(message.at)}',
                  style: JardemTheme.text(11, FontWeight.w600, color: JardemColors.muted),
                ),
              ),
              bubble,
            ],
          ),
          if (mine) ...[const SizedBox(width: 8), InitialsAvatar(author, radius: 16)],
        ],
      ),
    );
  }
}
