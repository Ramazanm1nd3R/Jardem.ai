import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../shared/dial.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';

/// «Экстренные контакты»: the real numbers with one-tap dialling.
class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(metaProvider).valueOrNull ?? const Meta();
    Widget tile(Widget badge, String title, String subtitle, String number) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: JardemCard(
        key: Key('contact-$number'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => dial(context, ref, number),
        child: Row(
          children: [
            badge,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: JardemTheme.text(15, FontWeight.w800)),
                  Text(subtitle, style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted)),
                ],
              ),
            ),
            Text(number, style: JardemTheme.text(20, FontWeight.w800, color: JardemColors.primaryDark)),
            const SizedBox(width: 8),
            const Icon(Icons.phone_rounded, color: JardemColors.primary, size: 20),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: const JardemAppBar(title: 'Экстренные контакты', fallbackLocation: '/profile'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          tile(
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: JardemColors.danger, shape: BoxShape.circle),
              child: const Icon(Icons.sos_rounded, color: Colors.white, size: 22),
            ),
            'Единый номер',
            'Любая экстренная ситуация',
            meta.emergencyPhone,
          ),
          tile(
            const ServiceBadge(ServiceType.ambulance, size: 38),
            'Скорая помощь',
            'Медицинская помощь',
            meta.phoneOf(ServiceType.ambulance),
          ),
          tile(
            const ServiceBadge(ServiceType.police, size: 38),
            'Полиция',
            'Охрана порядка',
            meta.phoneOf(ServiceType.police),
          ),
          tile(
            const ServiceBadge(ServiceType.fire, size: 38),
            'Пожарная служба',
            'Пожары и задымления',
            meta.phoneOf(ServiceType.fire),
          ),
          const SizedBox(height: 6),
          Text(
            'Это настоящие номера экстренных служб Казахстана. Звонок выполняется через телефон, а не через Jardem.ai.',
            style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// «О приложении»: what the demo is, map and photo credits, font licence.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(metaProvider).valueOrNull ?? const Meta();
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: JardemTheme.text(15, FontWeight.w800)),
    );
    final body = JardemTheme.text(13, FontWeight.w500, color: JardemColors.muted, height: 1.45);
    return Scaffold(
      appBar: const JardemAppBar(title: 'О приложении', fallbackLocation: '/profile'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Center(child: JardemLogo(size: 84)),
          const SizedBox(height: 16),
          Text(
            'Jardem.ai — прототип единой платформы вызова экстренных служб Алматы (дипломный проект). Версия 1.0.0.',
            textAlign: TextAlign.center,
            style: body,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFE2A8)),
            ),
            child: Text(
              meta.disclaimer,
              style: JardemTheme.text(13, FontWeight.w600, color: const Color(0xFF7A5210), height: 1.4),
            ),
          ),
          heading('Карта'),
          Text(
            '${JardemMap.attribution}.\nКартографические данные — OpenStreetMap, лицензия ODbL '
            '(openstreetmap.org/copyright). Пробки и перемещение экипажей смоделированы.',
            style: body,
          ),
          heading('Фотографии'),
          Text(
            'Фотографии взяты с Wikimedia Commons, уменьшены и перекодированы. '
            'Производные версии распространяются на условиях тех же лицензий.',
            style: body,
          ),
          const SizedBox(height: 8),
          for (final c in kPhotoCredits)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UnitPhoto(photo: c.file, width: 56, height: 44, radius: 8),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.subject, style: JardemTheme.text(13, FontWeight.w700)),
                        Text(
                          '© ${c.author} · ${c.license}',
                          style: JardemTheme.text(12, FontWeight.w600, color: JardemColors.muted),
                        ),
                        SelectableText(
                          c.source,
                          style: JardemTheme.text(10.5, FontWeight.w500, color: JardemColors.faint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          heading('Шрифт'),
          Text('Manrope © The Manrope Project Authors, лицензия SIL Open Font License 1.1.', style: body),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () =>
                showLicensePage(context: context, applicationName: 'Jardem.ai', applicationVersion: '1.0.0'),
            child: const Text('Лицензии открытого ПО'),
          ),
        ],
      ),
    );
  }
}

/// Honest placeholder for sections that are not part of the prototype.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final (title, text) = switch (kind) {
      'addresses' => (
        'Мои адреса',
        'Сохранённые адреса (дом, работа) появятся в следующих версиях. Сейчас адрес указывается в форме вызова.',
      ),
      'contact' => (
        'Способы связи',
        'Выбор способа связи (звонок, чат, SMS) пока не реализован. Экипаж видит ваш контактный телефон из формы вызова.',
      ),
      'notifications' => (
        'Уведомления',
        'Push-уведомления в прототипе не подключены. Статус вызова обновляется на экране отслеживания в реальном времени.',
      ),
      _ => ('Раздел', 'Этот раздел пока в разработке.'),
    };
    return Scaffold(
      appBar: JardemAppBar(title: title, fallbackLocation: '/profile'),
      body: MessageView(icon: Icons.construction_rounded, title: 'В разработке', text: text),
    );
  }
}
