import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../logic/chat.dart';
import '../../shared/incoming_call.dart';
import '../../shared/widgets.dart';
import '../../state/gps.dart';
import '../../state/messages.dart';

/// Bottom navigation: Главная · Карта · Вызовы · Сообщения · Профиль, with the
/// incoming-call card floating above it on every tab.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.home_rounded, 'Главная'),
    (Icons.map_outlined, 'Карта'),
    (Icons.format_list_bulleted_rounded, 'Вызовы'),
    (Icons.chat_bubble_outline_rounded, 'Сообщения'),
    (Icons.person_outline_rounded, 'Профиль'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the GPS sharer alive for as long as the crew is signed in.
    ref.watch(gpsProvider.select((g) => g.sharing));
    final unread = badgeText(ref.watch(chatProvider.select((c) => c.unread)));
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: shell),
          const Positioned(left: 0, right: 0, bottom: 0, child: IncomingCallOverlay()),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: JardemColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: _NavItem(
                      key: Key('nav-$i'),
                      icon: _items[i].$1,
                      label: _items[i].$2,
                      badge: i == 3 && shell.currentIndex != 3 ? unread : '',
                      selected: shell.currentIndex == i,
                      onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = '',
  });

  final IconData icon;
  final String label;
  final String badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? JardemColors.primary : JardemColors.faint;
    return Semantics(
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 24),
                if (badge.isNotEmpty) Positioned(right: -9, top: -4, child: CountBadge(badge)),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: JardemTheme.text(10.5, selected ? FontWeight.w700 : FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
