import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/td_empty_state.dart';
import '../../features/live/live_view_context.dart';
import '../../features/songs/song_editor_screen.dart';
import '../../features/songs/songs_screen.dart';
import 'desktop_panel_layout.dart';

class DesktopSongsScreen extends ConsumerWidget {
  const DesktopSongsScreen({
    super.key,
    this.selectedSongId,
  });

  final String? selectedSongId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Clear the active editor song when no song is selected (user navigated
    // back to the list or the previously selected song was deleted).
    if (selectedSongId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeEditorSongProvider.notifier).state = null;
      });
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: DesktopPanelLayout.listFlex,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(
                DesktopPanelLayout.panelBorderRadius,
              ),
            ),
            child: SongsScreen(
              selectedSongId: selectedSongId,
              showScaffold: false,
              onSongTap: (context, song) =>
                  context.go('${Routes.songs}/${song.id}'),
            ),
          ),
        ),
        const SizedBox(width: DesktopPanelLayout.panelSpacing),
        Expanded(
          flex: DesktopPanelLayout.editorFlex,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(
                DesktopPanelLayout.panelBorderRadius,
              ),
            ),
            child: selectedSongId == null
                ? const _DesktopSongPlaceholder()
                : SongEditorScreen(
                    songId: selectedSongId!,
                    showScaffold: false,
                  ),
          ),
        ),
      ],
    );
  }
}

class _DesktopSongPlaceholder extends StatelessWidget {
  const _DesktopSongPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const TDEmptyState(
      icon: Icons.music_note_outlined,
      title: 'Select a song to edit',
    );
  }
}
