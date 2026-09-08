import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_navigation_destination.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/live/live_view_context.dart';

/// Index of the Songs tab in the desktop navigation rail.
const _songsTabIndex = 1;

/// Index of the Setlists tab in the desktop navigation rail.
const _setlistsTabIndex = 2;

class DesktopShell extends ConsumerStatefulWidget {
  static const _shellPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 16);
  static const _contentPadding = EdgeInsets.all(24);
  static const _railMinWidth = 96.0;
  static const _railExtendedWidth = 220.0;

  const DesktopShell({
    super.key,
    required this.shell,
    required this.isLiveRoute,
  });

  final StatefulNavigationShell shell;
  final bool isLiveRoute;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  @override
  void initState() {
    super.initState();
  }

  void _onDestinationSelected(WidgetRef ref, int index) {
    // Clear editor providers when leaving their respective tabs so stale
    // entities don't linger (e.g. for the play button).
    final previous = widget.shell.currentIndex;
    if (previous == _songsTabIndex && index != _songsTabIndex) {
      ref.read(activeEditorSongProvider.notifier).state = null;
    }
    if (previous == _setlistsTabIndex && index != _setlistsTabIndex) {
      ref.read(activeEditorSetlistProvider.notifier).state = null;
    }
    widget.shell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    final Widget scaffold;

    if (widget.isLiveRoute) {
      scaffold = Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: ColoredBox(
            color: AppColors.background,
            child: SizedBox.expand(child: widget.shell),
          ),
        ),
      );
    } else {
      scaffold = Scaffold(
        body: SafeArea(
          child: Padding(
            padding: DesktopShell._shellPadding,
            child: Row(
              children: [
                NavigationRail(
                  backgroundColor: AppColors.surface,
                  minWidth: DesktopShell._railMinWidth,
                  minExtendedWidth: DesktopShell._railExtendedWidth,
                  groupAlignment: -1,
                  extended: true,
                  useIndicator: true,
                  selectedIndex: widget.shell.currentIndex,
                  onDestinationSelected: (index) =>
                      _onDestinationSelected(ref, index),
                  leading: _DesktopRailHeader(
                    shell: widget.shell,
                  ),
                  destinations: [
                    for (final destination in appNavigationDestinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 24),
                Expanded(
                  child: DecoratedBox(
                    decoration:
                        const BoxDecoration(color: AppColors.background),
                    child: Padding(
                      padding: DesktopShell._contentPadding,
                      child: widget.shell,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return scaffold;
  }
}

class _DesktopRailHeader extends ConsumerWidget {
  static const _headerPadding = EdgeInsets.fromLTRB(12, 8, 12, 16);
  static const _titleSubtitleSpacing = 4.0;
  static const _playButtonSize = 40.0;
  static const _playButtonWidth = 180.0;

  const _DesktopRailHeader({required this.shell});

  final StatefulNavigationShell shell;

  /// Determines the live route based on active tab and editor state.
  ///
  /// Returns `null` when the play button should be disabled.
  String? _livePath(BuildContext context, WidgetRef ref) {
    // Use the router's current URI to check whether an editor is actually
    // open (has an :id segment). This avoids stale-provider bugs: even if
    // activeEditorSongProvider still holds a song from a previous visit,
    // the play button stays disabled when the user is on the plain list.
    final uri = GoRouter.of(context)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
    final segments = Uri.parse(uri).pathSegments;

    // Tab indices: 0 = Metronome, 1 = Songs, 2 = Setlists, 3 = Settings
    return switch (shell.currentIndex) {
      1 => () {
          // /songs/:id → segments = ['songs', '<id>']
          if (segments.length < 2) return null;
          final song = ref.watch(activeEditorSongProvider);
          if (song == null) return null;
          return '${Routes.songs}/${song.id}/live';
        }(),
      2 => () {
          // /setlists/:id → segments = ['setlists', '<id>']
          if (segments.length < 2) return null;
          final setlist = ref.watch(activeEditorSetlistProvider);
          if (setlist == null) return null;
          return '${Routes.setlists}/${setlist.id}/live';
        }(),
      _ => '${Routes.metronome}/live', // Metronome & Settings
    };
  }

  void _onPlay(BuildContext context, WidgetRef ref) {
    final path = _livePath(context, ref);
    if (path == null) return;

    // Set the correct live view context before navigation.
    final liveCtx = switch (shell.currentIndex) {
      1 => () {
          final song = ref.read(activeEditorSongProvider);
          return song != null ? SongViewContext(song: song) : null;
        }(),
      2 => () {
          final setlist = ref.read(activeEditorSetlistProvider);
          return setlist != null
              ? SetlistViewContext(setlist: setlist)
              : null;
        }(),
      _ => const MetronomeViewContext() as LiveViewContext?,
    };

    if (liveCtx == null) return;
    ref.read(liveViewContextProvider.notifier).set(liveCtx);
    context.go(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textMuted,
        );
    final isEnabled = _livePath(context, ref) != null;

    return Padding(
      padding: _headerPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TempoDeck', style: titleStyle),
          const SizedBox(height: _titleSubtitleSpacing),
          Text('Desktop', style: labelStyle),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: _playButtonWidth,
            height: _playButtonSize,
            child: FilledButton.icon(
              onPressed: isEnabled ? () => _onPlay(context, ref) : null,
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text('Play'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.surface,
                disabledForegroundColor: AppColors.textMuted,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.sm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
