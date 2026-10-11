import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import 'router.dart';
import 'shared/phone_frame.dart';

class JardemCitizenApp extends ConsumerWidget {
  const JardemCitizenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Jardem.ai',
    debugShowCheckedModeBanner: false,
    theme: JardemTheme.light(),
    locale: const Locale('ru'),
    routerConfig: ref.watch(routerProvider),
    builder: (context, child) => PhoneFrame(child: child ?? const SizedBox.shrink()),
  );
}
