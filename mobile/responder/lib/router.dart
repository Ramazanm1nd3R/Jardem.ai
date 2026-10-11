import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import 'features/call/call_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/closure/closure_screen.dart';
import 'features/crew/crew_screen.dart';
import 'features/history/history_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/home_shell.dart';
import 'features/login/login_screen.dart';
import 'features/navigation/navigation_screen.dart';
import 'features/profile/about_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/shift/shift_screen.dart';
import 'state/session.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: MessageView(
      icon: Icons.explore_off_outlined,
      title: 'Страница не найдена',
      actionLabel: 'На главную',
      onAction: () => context.go('/home'),
    ),
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects when the session changes (sign-in, logout, expired token).
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    refreshListenable: refresh,
    errorBuilder: (_, _) => const _NotFound(),
    redirect: (context, state) {
      final signedIn = ref.read(sessionProvider) != null;
      final onLogin = state.matchedLocation == '/login';
      if (!signedIn) return onLogin ? null : '/login';
      return onLogin ? '/home' : null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/map', builder: (_, _) => const NavigationScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/calls', builder: (_, _) => const HistoryScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/messages', builder: (_, _) => const ChatScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())],
          ),
        ],
      ),
      GoRoute(path: '/call', parentNavigatorKey: _rootKey, builder: (_, _) => const CallScreen()),
      GoRoute(
        path: '/crew',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => CrewScreen(initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0),
      ),
      GoRoute(path: '/shift', parentNavigatorKey: _rootKey, builder: (_, _) => const ShiftScreen()),
      GoRoute(path: '/closure', parentNavigatorKey: _rootKey, builder: (_, _) => const ClosureScreen()),
      GoRoute(path: '/about', parentNavigatorKey: _rootKey, builder: (_, _) => const AboutScreen()),
    ],
  );
});
