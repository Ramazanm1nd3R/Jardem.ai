import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// Opens the dialler for [number]; tells the user the number if that fails.
Future<void> dial(BuildContext context, WidgetRef ref, String number) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await ref.read(dialerProvider)(number);
  if (!ok) {
    messenger?.showSnackBar(SnackBar(content: Text('Не удалось открыть звонок. Наберите $number вручную.')));
  }
}
