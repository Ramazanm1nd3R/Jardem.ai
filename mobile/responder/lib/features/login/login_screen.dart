import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../shared/widgets.dart';
import '../../state/providers.dart';
import '../../state/session.dart';

const String kLastLoginKey = 'jardem.responder.last_login';

/// «Вход»: logo, slogan, vehicles over the Almaty skyline, sign-in.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  Future<void> _signIn(BuildContext context, {bool fresh = false}) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SignInSheet(fresh: fresh),
  );

  /// «Сменить пользователя»: forget the saved session and the remembered login.
  Future<void> _switchUser(BuildContext context, WidgetRef ref) async {
    await ref.read(sessionProvider.notifier).signOut();
    await ref.read(sharedPreferencesProvider).remove(kLastLoginKey);
    if (context.mounted) await _signIn(context, fresh: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, box) {
          final short = box.maxHeight < 700;
          return Stack(
            children: [
              Positioned(left: 0, right: 0, bottom: 0, height: box.maxHeight * 0.52, child: const _Skyline()),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Column(
                    children: [
                      SizedBox(height: box.maxHeight * (short ? 0.04 : 0.09)),
                      JardemLogo(size: short ? 96 : 128),
                      SizedBox(height: short ? 14 : 28),
                      Text(
                        'Работаем\nради жизни',
                        textAlign: TextAlign.center,
                        style: JardemTheme.text(20, FontWeight.w500, color: const Color(0xFF3C5A82), height: 1.3),
                      ),
                      const Spacer(),
                      const _Vehicles(),
                      SizedBox(height: short ? 14 : 22),
                      PrimaryButton(
                        key: const Key('login-open'),
                        label: 'Войти в систему',
                        height: 56,
                        radius: 16,
                        onPressed: () => _signIn(context),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        key: const Key('login-switch'),
                        onPressed: () => _switchUser(context, ref),
                        child: const Text(
                          'Сменить пользователя',
                          style: TextStyle(decoration: TextDecoration.underline),
                        ),
                      ),
                      const DemoNotice(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Real Kazakhstan vehicles (Wikimedia Commons, credited in «О приложении»).
class _Vehicles extends StatelessWidget {
  const _Vehicles();

  static const _photos = [
    ('ambulance_kz_1', ServiceType.ambulance),
    ('fire_kz_1', ServiceType.fire),
    ('police_kz_1', ServiceType.police),
  ];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < _photos.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: JardemColors.cardShadow,
            ),
            child: AspectRatio(
              aspectRatio: 1.25,
              child: LayoutBuilder(
                builder: (context, c) => UnitPhoto(
                  photo: _photos[i].$1,
                  service: _photos[i].$2,
                  width: c.maxWidth,
                  height: c.maxHeight,
                  radius: 13,
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class _Skyline extends StatelessWidget {
  const _Skyline();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    clipBehavior: Clip.none,
    children: [
      Image.asset(
        'assets/images/almaty_skyline_1.jpg',
        package: 'jardem_core',
        fit: BoxFit.cover,
        alignment: const Alignment(0, 0.2),
        errorBuilder: (_, _, _) => const ColoredBox(color: JardemColors.background),
      ),
      // Fade from the white page into the photo and a veil under the controls.
      const Positioned(
        left: 0,
        right: 0,
        top: -2,
        bottom: 0,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Color(0xB3FFFFFF), Color(0x40FFFFFF), Color(0xB3EAF4FF)],
              stops: [0.02, 0.28, 0.55, 1],
            ),
          ),
        ),
      ),
    ],
  );
}

/// Login + PIN.
class SignInSheet extends ConsumerStatefulWidget {
  const SignInSheet({super.key, this.fresh = false});

  /// Start with an empty login instead of the remembered one.
  final bool fresh;

  @override
  ConsumerState<SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<SignInSheet> {
  final _form = GlobalKey<FormState>();
  late final _login = TextEditingController(
    text: widget.fresh ? '' : (ref.read(sharedPreferencesProvider).getString(kLastLoginKey) ?? ''),
  );
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      final login = _login.text.trim();
      await ref.read(sessionProvider.notifier).signIn(login: login, pin: _pin.text);
      await ref.read(sharedPreferencesProvider).setString(kLastLoginKey, login);
      // The router has already replaced the login screen; close the sheet if it is still there.
      if (mounted && navigator.canPop()) navigator.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = signInError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 14),
      child: Text(text, style: JardemTheme.text(13, FontWeight.w700)),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Вход для экипажа', style: JardemTheme.text(20, FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Логин — позывной экипажа, PIN выдаёт диспетчерская.',
                style: JardemTheme.text(13, FontWeight.w500, color: JardemColors.muted, height: 1.35),
              ),
              label('Логин'),
              TextFormField(
                key: const Key('login-field'),
                controller: _login,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  hintText: 'smp7',
                  prefixIcon: Icon(Icons.badge_outlined, size: 20, color: JardemColors.faint),
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Введите логин экипажа' : null,
              ),
              label('PIN-код'),
              TextFormField(
                key: const Key('pin-field'),
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: '••••',
                  prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: JardemColors.faint),
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Введите PIN-код' : null,
              ),
              const SizedBox(height: 8),
              Text('Демо: smp7 / 1234', style: JardemTheme.text(12, FontWeight.w600, color: JardemColors.muted)),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  key: const Key('login-error'),
                  style: JardemTheme.text(13, FontWeight.w600, color: JardemColors.danger),
                ),
              ],
              const SizedBox(height: 18),
              PrimaryButton(
                key: const Key('login-submit'),
                label: 'Войти',
                loading: _busy,
                radius: 16,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
