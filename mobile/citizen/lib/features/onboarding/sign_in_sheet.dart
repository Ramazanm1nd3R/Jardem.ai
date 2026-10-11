import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../shared/widgets.dart';
import '../../state/session.dart';

/// Shows the phone + name sheet; resolves to true once signed in.
Future<bool?> showSignInSheet(BuildContext context) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => const SignInSheet(),
);

class SignInSheet extends ConsumerStatefulWidget {
  const SignInSheet({super.key});

  @override
  ConsumerState<SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<SignInSheet> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController(text: '+7 ');
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).signIn(phone: _phone.text, name: _name.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Давайте знакомиться', style: JardemTheme.text(20, FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Номер нужен, чтобы экипаж мог с вами связаться. В демо-версии код из SMS не требуется.',
                style: JardemTheme.text(13, FontWeight.w500, color: JardemColors.muted, height: 1.35),
              ),
              const FieldLabel('Телефон'),
              TextFormField(
                key: const Key('signin-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: '+7 777 123 45 67',
                  prefixIcon: Icon(Icons.phone_rounded, size: 20, color: JardemColors.faint),
                ),
                validator: (v) => isValidKzPhone(v) ? null : 'Введите номер в формате +7 XXX XXX XX XX',
              ),
              const FieldLabel('Как к вам обращаться'),
              TextFormField(
                key: const Key('signin-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.givenName],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: 'Имя',
                  prefixIcon: Icon(Icons.person_rounded, size: 20, color: JardemColors.faint),
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Укажите имя' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.danger)),
              ],
              const SizedBox(height: 18),
              PrimaryButton(label: 'Продолжить', loading: _busy, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
