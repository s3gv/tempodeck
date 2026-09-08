import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/metronome/metronome_screen.dart';
import '../../features/songs/song_editor_screen.dart';
import '../../features/songs/songs_screen.dart';
import '../../features/setlists/setlist_editor_screen.dart';
import '../../features/setlists/setlists_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/live/live_screen.dart';
import '../../platform/desktop/desktop_setlists_screen.dart';
import '../../platform/desktop/desktop_settings_screen.dart';
import '../../platform/desktop/desktop_songs_screen.dart';
import '../providers/app_variant_provider.dart';
import '../theme/app_animations.dart';
import '../../platform/mobile/mobile_shell.dart';
import '../../platform/desktop/desktop_shell.dart';
import 'routes.dart';

GoRouter buildRouter(
  AppVariant variant, {
  GlobalKey<NavigatorState>? navigatorKey,
}) =>
    GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: Routes.metronome,
      routes: [
        if (variant.isDesktop) ..._desktopRoutes() else ..._mobileRoutes(),
      ],
    );

/// Subtle slide-fade transition for sub-routes (editors, detail views).
CustomTransitionPage<void> _slideFadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppAnimations.normal,
    reverseTransitionDuration: AppAnimations.normal,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final offsetTween = Tween<Offset>(
        begin: const Offset(0.05, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: AppAnimations.smooth));
      final fadeTween = CurveTween(curve: AppAnimations.smooth);
      return SlideTransition(
        position: offsetTween.animate(animation),
        child: FadeTransition(
          opacity: fadeTween.animate(animation),
          child: child,
        ),
      );
    },
  );
}

/// Slide-up transition page for mobile live view routes.
CustomTransitionPage<void> _liveSlideUpPage(GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: const LiveScreen(),
    transitionDuration: AppAnimations.normal,
    reverseTransitionDuration: AppAnimations.normal,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).chain(CurveTween(curve: AppAnimations.smooth));
      return SlideTransition(position: tween.animate(animation), child: child);
    },
  );
}

List<RouteBase> _mobileRoutes() => [
  StatefulShellRoute.indexedStack(
    builder: (context, state, shell) => MobileShell(
      shell: shell,
      isLiveRoute: state.uri.path.endsWith('/live'),
    ),
    branches: [
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.metronome,
            builder: (_, __) => const MetronomeScreen(),
            routes: [
              GoRoute(
                path: 'live',
                pageBuilder: (_, state) => _liveSlideUpPage(state),
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.songs,
            builder: (_, __) => const SongsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (_, state) => _slideFadePage(
                  state,
                  SongEditorScreen(
                    songId: state.pathParameters['id']!,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'live',
                    pageBuilder: (_, state) => _liveSlideUpPage(state),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.setlists,
            builder: (_, __) => const SetlistsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (_, state) => _slideFadePage(
                  state,
                  SetlistEditorScreen(
                    setlistId: state.pathParameters['id']!,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'live',
                    pageBuilder: (_, state) => _liveSlideUpPage(state),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.settings,
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  ),
];

List<RouteBase> _desktopRoutes() => [
  StatefulShellRoute.indexedStack(
    builder: (context, state, shell) => DesktopShell(
      shell: shell,
      isLiveRoute: state.uri.path.endsWith('/live'),
    ),
    branches: [
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.metronome,
            builder: (_, __) => const MetronomeScreen(),
            routes: [
              GoRoute(
                path: 'live',
                pageBuilder: (_, state) => _slideFadePage(
                  state,
                  const LiveScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.songs,
            builder: (_, __) => const DesktopSongsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (_, state) => _slideFadePage(
                  state,
                  DesktopSongsScreen(
                    selectedSongId: state.pathParameters['id']!,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'live',
                    pageBuilder: (_, state) => _slideFadePage(
                      state,
                      const LiveScreen(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.setlists,
            builder: (_, __) => const DesktopSetlistsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (_, state) => _slideFadePage(
                  state,
                  DesktopSetlistsScreen(
                    selectedSetlistId: state.pathParameters['id']!,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'live',
                    pageBuilder: (_, state) => _slideFadePage(
                      state,
                      const LiveScreen(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.settings,
            builder: (_, __) => const DesktopSettingsScreen(),
          ),
        ],
      ),
    ],
  ),
];
