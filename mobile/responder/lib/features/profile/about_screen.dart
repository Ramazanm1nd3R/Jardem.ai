import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../shared/widgets.dart';
import '../../state/providers.dart';

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
            'Jardem.ai — прототип единой платформы вызова экстренных служб Алматы (дипломный проект). '
            'Приложение экипажа, версия 1.0.0.',
            textAlign: TextAlign.center,
            style: body,
          ),
          const SizedBox(height: 12),
          DemoNotice(text: '$kDemoNotice.\n${meta.disclaimer}'),
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
                showLicensePage(context: context, applicationName: 'Jardem.ai — Экипаж', applicationVersion: '1.0.0'),
            child: const Text('Лицензии открытого ПО'),
          ),
        ],
      ),
    );
  }
}
