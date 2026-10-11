import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../logic/steps.dart';
import '../../shared/widgets.dart';
import '../../state/crew.dart';
import '../../state/session.dart';
import '../shift/shift_screen.dart';

/// «Профиль»: the crew lead, the unit, settings and logout.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const _menu = [
    (Icons.groups_2_outlined, 'Моя бригада', '/crew'),
    (Icons.timeline_rounded, 'Смена и статус', '/shift'),
    (Icons.block_rounded, 'Сообщить о перекрытии', '/closure'),
    (Icons.info_outline_rounded, 'О приложении', '/about'),
  ];

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из приложения?'),
        content: const Text(
          'Смена при этом не завершается. Чтобы снова получать вызовы, войдите с логином и PIN-кодом.',
        ),
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
    final unit = ref.watch(crewProvider.select((c) => c.unit));
    final name = (user?.name ?? '').isNotEmpty ? user!.name : (unit?.lead ?? 'Экипаж');
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              children: [
                InitialsAvatar(name, radius: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JardemTheme.text(18, FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      if ((user?.phone ?? '').isNotEmpty)
                        Text(
                          formatKzPhone(user?.phone),
                          style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.muted),
                        ),
                      if (unit != null)
                        Text(
                          '${crewTitle(unit.service, unit.callsign)} · ${unit.service.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const DemoNotice(),
            const SizedBox(height: 14),
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
                      title: Text(
                        i == 0 ? myCrewLabel(unit?.service) : _menu[i].$2,
                        style: JardemTheme.text(14.5, FontWeight.w600),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: JardemColors.faint),
                      onTap: () => context.push(_menu[i].$3),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            const GpsCard(),
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
