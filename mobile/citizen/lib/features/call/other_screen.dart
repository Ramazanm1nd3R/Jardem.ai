import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../shared/dial.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';

/// «Другое»: free text → triage → suggested service → call form.
class OtherScreen extends ConsumerStatefulWidget {
  const OtherScreen({super.key});

  @override
  ConsumerState<OtherScreen> createState() => _OtherScreenState();
}

class _OtherScreenState extends ConsumerState<OtherScreen> {
  final _text = TextEditingController();
  bool _busy = false;
  TriageResult? _result;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _analyse() async {
    final text = _text.text.trim();
    if (text.length < 4) {
      setState(() => _error = 'Опишите ситуацию хотя бы парой слов.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref.read(apiClientProvider).triage(text);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continue(ServiceType service, String? category) => context.push(
    Uri(path: '/call/${service.id}', queryParameters: {'category': ?category, 'text': _text.text.trim()}).toString(),
  );

  @override
  Widget build(BuildContext context) {
    final meta = ref.watch(metaProvider).valueOrNull ?? const Meta();
    final result = _result;
    return Scaffold(
      appBar: const JardemAppBar(title: 'Другое', fallbackLocation: '/map'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text('Опишите, что случилось', style: JardemTheme.text(18, FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Мы подскажем, какая служба нужна, и подготовим вызов.',
              style: JardemTheme.text(13, FontWeight.w500, color: JardemColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('other-text'),
              controller: _text,
              minLines: 4,
              maxLines: 7,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Например: в подъезде сильный запах дыма, на 3 этаже',
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.danger)),
            ],
            const SizedBox(height: 14),
            PrimaryButton(
              key: const Key('other-analyse'),
              label: 'Подобрать службу',
              icon: Icons.auto_awesome_rounded,
              loading: _busy,
              onPressed: _analyse,
            ),
            if (result != null) ...[
              const SizedBox(height: 16),
              if (result.hasSuggestion)
                _Suggestion(result: result, onContinue: () => _continue(result.service!, result.category))
              else
                const MessageView(
                  icon: Icons.help_outline_rounded,
                  title: 'Не удалось определить службу',
                  text: 'Выберите службу вручную или позвоните 112.',
                  compact: true,
                ),
              const SizedBox(height: 14),
              Text(
                result.hasSuggestion ? 'Или выберите другую службу' : 'Выберите службу',
                style: JardemTheme.text(13, FontWeight.w700, color: JardemColors.muted),
              ),
              const SizedBox(height: 8),
              for (final s in ServiceType.values)
                if (s != result.service || !result.hasSuggestion)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: JardemCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      onTap: () => _continue(s, null),
                      child: Row(
                        children: [
                          ServiceBadge(s, size: 30),
                          const SizedBox(width: 12),
                          Expanded(child: Text(s.title, style: JardemTheme.text(14, FontWeight.w700))),
                          const Icon(Icons.chevron_right_rounded, color: JardemColors.faint),
                        ],
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    kDefaultDisclaimer,
                    style: JardemTheme.text(11.5, FontWeight.w600, color: JardemColors.muted, height: 1.3),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => dial(context, ref, meta.emergencyPhone),
                  icon: const Icon(Icons.phone_rounded, size: 16),
                  label: Text(meta.emergencyPhone),
                  style: TextButton.styleFrom(foregroundColor: JardemColors.danger),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.result, required this.onContinue});

  final TriageResult result;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final service = result.service!;
    final missing = result.missing.map(missingLabel).toList();
    return JardemCard(
      key: const Key('other-suggestion'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ServiceBadge(service, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Рекомендуем', style: JardemTheme.text(12, FontWeight.w600, color: JardemColors.muted)),
                    Text(service.title, style: JardemTheme.text(17, FontWeight.w800)),
                    if (result.categoryTitle != null)
                      Text(
                        result.categoryTitle!,
                        style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.muted),
                      ),
                  ],
                ),
              ),
              StatusChip(priorityLabel(result.priority), tone: result.priority == 1 ? ChipTone.danger : ChipTone.info),
            ],
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'В форме вызова уточните: ${missing.join(', ')}',
              style: JardemTheme.text(12, FontWeight.w500, color: JardemColors.muted, height: 1.3),
            ),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            key: const Key('other-continue'),
            label: 'Продолжить',
            trailingIcon: Icons.chevron_right_rounded,
            color: JardemColors.service(service),
            height: 48,
            radius: 14,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}
