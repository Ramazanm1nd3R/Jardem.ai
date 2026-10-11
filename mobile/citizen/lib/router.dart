import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

import 'features/call/call_form_screen.dart';
import 'features/call/other_screen.dart';
import 'features/calls/calls_screens.dart';
import 'features/home/home_screen.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/profile/profile_pages.dart';
import 'features/profile/profile_screen.dart';
import 'features/service/category_list_screen.dart';
import 'features/service/nearest_units_screen.dart';
import 'features/service/service_screen.dart';
import 'features/tracking/tracking_screen.dart';
import 'state/session.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Screen shown for an unknown service id or path.
class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: MessageView(
      icon: Icons.explore_off_outlined,
      title: 'Страница не найдена',
      actionLabel: 'На главную',
      onAction: () => context.go('/map'),
    ),
  );
}

Widget _service(GoRouterState state, Widget Function(ServiceType) build) {
  final service = ServiceType.tryParse(state.pathParameters['service']);
  return service == null ? const _NotFound() : build(service);
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects when the session changes (sign-in, logout, expired token).
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/map',
    refreshListenable: refresh,
    errorBuilder: (_, _) => const _NotFound(),
    redirect: (context, state) {
      final signedIn = ref.read(sessionProvider) != null;
      final onWelcome = state.matchedLocation == '/welcome';
      if (!signedIn) return onWelcome ? null : '/welcome';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/map'),
      GoRoute(path: '/welcome', builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                builder: (_, _) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'service/:service',
                    builder: (_, state) => _service(
                      state,
                      (s) => ServiceScreen(
                        key: ValueKey('service-${s.id}'),
                        service: s,
                        initialCategory: state.uri.queryParameters['category'],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/calls', builder: (_, _) => const CallsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/history', builder: (_, _) => const HistoryScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())],
          ),
        ],
      ),
      GoRoute(
        path: '/service/:service/categories',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => _service(state, (s) => CategoryListScreen(service: s)),
      ),
      GoRoute(
        path: '/service/:service/units',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            _service(state, (s) => NearestUnitsScreen(service: s, category: state.uri.queryParameters['category'])),
      ),
      GoRoute(
        path: '/call/:service',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => _service(
          state,
          (s) => CallFormScreen(
            key: ValueKey('call-${s.id}'),
            service: s,
            initialCategory: state.uri.queryParameters['category'],
            initialText: state.uri.queryParameters['text'],
          ),
        ),
      ),
      GoRoute(path: '/other', parentNavigatorKey: _rootKey, builder: (_, _) => const OtherScreen()),
      GoRoute(
        path: '/tracking/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => TrackingScreen(incidentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/profile/history',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const HistoryScreen(title: 'История вызовов', fallbackLocation: '/profile'),
      ),
      GoRoute(
        path: '/profile/contacts',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const EmergencyContactsScreen(),
      ),
      GoRoute(path: '/profile/about', parentNavigatorKey: _rootKey, builder: (_, _) => const AboutScreen()),
      GoRoute(
        path: '/profile/soon/:kind',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => ComingSoonScreen(kind: state.pathParameters['kind']!),
      ),
    ],
  );
});
