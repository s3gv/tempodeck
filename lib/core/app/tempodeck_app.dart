import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_variant_provider.dart';
import '../providers/service_providers.dart';
import '../router/app_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/audio_lifecycle_observer.dart';
import '../widgets/td_splash_screen.dart';

/// Root application widget shared by mobile and desktop entry points.
///
/// Reads [appVariantProvider] from the enclosing [ProviderScope], so the
/// calling `main()` only needs to set the correct [AppVariant] override.
class TempoDeckApp extends ConsumerStatefulWidget {
  const TempoDeckApp({super.key});

  @override
  ConsumerState<TempoDeckApp> createState() => _TempoDeckAppState();
}

class _TempoDeckAppState extends ConsumerState<TempoDeckApp> {
  final _rootNavigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final audioInit = ref.watch(audioInitProvider);
    final router = buildRouter(
      ref.watch(appVariantProvider),
      navigatorKey: _rootNavigatorKey,
    );
    final isStartupReady = switch (audioInit) {
      AsyncLoading() => false,
      _ => true,
    };

    final child = switch (audioInit) {
      AsyncError(:final error) => AudioInitFailedApp(error: error),
      _ => AudioLifecycleObserver(
          audioEngine: ref.read(audioEngineProvider),
          playbackSession: ref.read(audioPlaybackSessionProvider),
          foregroundService: ref.read(foregroundPlaybackServiceProvider),
          onExternalStop: () => ref
              .read(externalAudioStopCounterProvider.notifier)
              .update((count) => count + 1),
          child: MaterialApp.router(
            title: 'TempoDeck',
            theme: AppTheme.dark,
            routerConfig: router,
            debugShowCheckedModeBanner: false,
          ),
        ),
    };

    return TDSplashScreen(
      isReady: isStartupReady,
      child: child,
    );
  }
}

/// Shown when audio engine initialization fails.
///
/// Displayed as the [TDSplashScreen] target after the cross-fade completes,
/// blocking access to the normal app shell until the user restarts.
class AudioInitFailedApp extends StatelessWidget {
  const AudioInitFailedApp({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: _AudioInitFailedPage(error: error),
    );
  }
}

class _AudioInitFailedPage extends StatelessWidget {
  const _AudioInitFailedPage({required this.error});

  static const _iconSize = 56.0;
  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.backgroundDeep,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.volume_off_rounded,
                  color: AppColors.error,
                  size: _iconSize,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Audio Unavailable',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'TempoDeck could not start the audio engine.\n'
                  'Please restart the app.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  error.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
