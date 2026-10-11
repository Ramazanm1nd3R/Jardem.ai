import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../state/session.dart';
import 'sign_in_sheet.dart';

/// Splash: logo, slogan, Almaty skyline and the «Начать» button.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    if (ref.read(sessionProvider) == null) {
      final ok = await showSignInSheet(context);
      if (ok != true || !context.mounted) return;
    }
    context.go('/map');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, box) {
          final short = box.maxHeight < 640;
          final skylineHeight = box.maxHeight * (short ? 0.36 : 0.44);
          return Stack(
            children: [
              Positioned(left: 0, right: 0, bottom: 0, height: skylineHeight, child: const _Skyline()),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      SizedBox(height: box.maxHeight * (short ? 0.05 : 0.11)),
                      JardemLogo(size: short ? 104 : 136),
                      SizedBox(height: short ? 20 : 40),
                      Text(
                        'Помощь ближе,\nчем кажется',
                        textAlign: TextAlign.center,
                        style: JardemTheme.text(20, FontWeight.w500, color: const Color(0xFF3C5A82), height: 1.3),
                      ),
                      const Spacer(),
                      PrimaryButton(
                        label: 'Начать',
                        trailingIcon: Icons.chevron_right_rounded,
                        height: 56,
                        onPressed: () => _start(context, ref),
                      ),
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
      // Soft fade from the white page into the photo, and a light veil so
      // the button stays readable.
      // Overdrawn by 2 px so no hairline of the photo shows at the top edge.
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
              colors: [Colors.white, Color(0xB3FFFFFF), Color(0x26FFFFFF), Color(0x66EAF4FF)],
              stops: [0.02, 0.3, 0.62, 1],
            ),
          ),
        ),
      ),
    ],
  );
}
