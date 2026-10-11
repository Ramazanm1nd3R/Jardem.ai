import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../state/session.dart';

/// «Профиль»: who is signed in and the settings menu.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const _menu = [
    (Icons.location_on_outlined, 'Мои адреса', '/profile/soon/addresses'),
    (Icons.history_rounded, 'История вызовов', '/profile/history'),
    (Icons.forum_outlined, 'Способы связи', '/profile/soon/contact'),
    (Icons.contact_emergency_outlined, 'Экстренные контакты', '/profile/contacts'),
    (Icons.notifications_none_rounded, 'Уведомления', '/profile/soon/notifications'),
    (Icons.info_outline_rounded, 'О приложении', '/profile/about'),
  ];

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из профиля?'),
        content: const Text('Чтобы снова вызывать службы, нужно будет указать номер телефона.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Остаться')),
          TextButton(
            key: const Key('logout-confirm'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: JardemColors.danger),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(sessionProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)?.user;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: JardemColors.primarySoft,
                  child: Text(
                    initials(user?.name),
                    style: JardemTheme.text(20, FontWeight.w800, color: JardemColors.primaryDark),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (user?.name ?? '').isEmpty ? 'Гость' : user!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JardemTheme.text(18, FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatKzPhone(user?.phone),
                        style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'О приложении',
                  icon: const Icon(Icons.settings_outlined, color: JardemColors.navy),
                  onPressed: () => context.push('/profile/about'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            JardemCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < _menu.length; i++) ...[
                    if (i > 0) const Divider(indent: 52),
                    ListTile(
                      key: Key('menu-$i'),
                      dense: true,
                      minLeadingWidth: 24,
                      leading: Icon(_menu[i].$1, color: JardemColors.navy, size: 22),
                      title: Text(_menu[i].$2, style: JardemTheme.text(14.5, FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: JardemColors.faint),
                      onTap: () => context.push(_menu[i].$3),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SecondaryButton(
              key: const Key('logout'),
              label: 'Выйти',
              icon: Icons.logout_rounded,
              color: JardemColors.danger,
              onPressed: () => _logout(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
