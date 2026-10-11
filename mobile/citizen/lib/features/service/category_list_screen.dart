import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../shared/widgets.dart';
import '../../state/providers.dart';

/// Photo that illustrates a category in the list.
String categoryPhoto(ServiceType service, String categoryId) => switch ((service, categoryId)) {
  (ServiceType.ambulance, 'pediatric') => 'ambulance_kz_2',
  (ServiceType.ambulance, 'reanimation') => 'ambulance_kz_reanimation',
  (ServiceType.ambulance, _) => 'ambulance_kz_1',
  (ServiceType.police, 'patrol') => 'police_kz_1',
  (ServiceType.police, _) => 'police_kz_2',
  (ServiceType.fire, 'forest') => 'fire_kz_2',
  (ServiceType.fire, _) => 'fire_kz_1',
  (ServiceType.rescue, _) => 'rescue_kz_1',
};

/// «Скорая помощь»: category cards with photo, title, description and chevron.
/// Pops with the picked category id.
class CategoryListScreen extends ConsumerWidget {
  const CategoryListScreen({super.key, required this.service});

  final ServiceType service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final color = JardemColors.service(service);
    return Scaffold(
      appBar: JardemAppBar(title: service.title, fallbackLocation: '/map/service/${service.id}'),
      body: catalog.when(
        loading: () => const LoadingView(),
        error: (e, _) => MessageView.error(e, onRetry: () => ref.invalidate(catalogProvider)),
        data: (all) {
          final categories = all.where((s) => s.service == service).firstOrNull?.categories ?? const <Category>[];
          if (categories.isEmpty) {
            return const MessageView(icon: Icons.category_outlined, title: 'Категорий пока нет');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final c = categories[i];
              final urgent = c.priority == 1;
              return JardemCard(
                key: Key('category-${c.id}'),
                color: urgent && i == 0 ? JardemColors.serviceSoft(service) : Colors.white,
                borderColor: urgent && i == 0 ? Color.lerp(color, Colors.white, 0.6) : null,
                padding: const EdgeInsets.all(10),
                onTap: () => Navigator.of(context).pop(c.id),
                child: Row(
                  children: [
                    UnitPhoto(photo: categoryPhoto(service, c.id), service: service, width: 76, height: 60),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.title, style: JardemTheme.text(15, FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text(
                            c.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: urgent && i == 0 ? color : JardemColors.faint),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
