import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/i_export_engine.dart';
import '../../core/domain/song.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_theme.dart';
import '../../core/widgets/td_animated_background.dart';
import '../../core/widgets/td_button.dart';
import '../../core/widgets/td_dialog.dart';
import '../../core/widgets/td_empty_state.dart';
import '../../core/widgets/td_list_tile.dart';
import '../../core/widgets/td_staggered_list_item.dart';
import '../../core/widgets/td_text_field.dart';
import '../export/export_sheet.dart';
import '../live/live_view_context.dart';
import 'songs_list_provider.dart';
import 'songs_screen_controller.dart';

class SongsScreen extends ConsumerWidget {
  static const _embeddedHeaderPadding = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.lg,
    AppSpacing.lg,
    AppSpacing.sm,
  );

  const SongsScreen({
    super.key,
    this.selectedSongId,
    this.showScaffold = true,
    this.onSongTap,
  });

  final String? selectedSongId;
  final bool showScaffold;
  final void Function(BuildContext context, Song song)? onSongTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(songsListProvider);
    final controller = ref.read(songsScreenControllerProvider);

    final content = songs.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (e, _) => Center(
        child: Text('Error: $e', style: AppTextTheme.bodySecondary),
      ),
      data: (songs) => songs.isEmpty
          ? TDEmptyState(
              icon: Icons.music_note_outlined,
              title: 'No songs yet',
              subtitle: 'Create your first song to get started.',
              actionLabel: 'New Song',
              onAction: () => _promptCreate(context, controller),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return TDStaggeredListItem(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: TDListTile(
                      title: song.title,
                      subtitle:
                          '${song.startBpm} BPM \u00B7 ${song.beatsPerBar}/${song.beatUnit}',
                      isSelected: song.id == selectedSongId,
                      trailing: PopupMenuButton<_SongAction>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: AppColors.textSecondary,
                        ),
                        onSelected: (action) {
                          switch (action) {
                            case _SongAction.export:
                              showExportSheet(
                                context: context,
                                source: SongExportSource(song.id),
                                title: song.title,
                              );
                            case _SongAction.rename:
                              _promptRename(context, song, controller);
                            case _SongAction.delete:
                              _confirmDelete(context, ref, song, controller);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _SongAction.export,
                            child: Text('Export'),
                          ),
                          PopupMenuItem(
                            value: _SongAction.rename,
                            child: Text('Rename'),
                          ),
                          PopupMenuItem(
                            value: _SongAction.delete,
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                      onTap: () => _handleSongTap(context, song),
                    ),
                  ),
                );
              },
            ),
    );

    if (!showScaffold) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: _embeddedHeaderPadding,
            child: Row(
              children: [
                const Expanded(
                  child: Text('Songs', style: AppTextTheme.heading2),
                ),
                TDButton(
                  label: 'New Song',
                  icon: Icons.add,
                  onPressed: () => _promptCreate(context, controller),
                ),
              ],
            ),
          ),
          Expanded(child: content),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Songs', style: AppTextTheme.heading2),
        backgroundColor: Colors.transparent,
      ),
      body: TDAnimatedBackground(child: content),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () => _promptCreate(context, controller),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _handleSongTap(BuildContext context, Song song) {
    final onSongTap = this.onSongTap;
    if (onSongTap != null) {
      onSongTap(context, song);
      return;
    }

    context.go('${Routes.songs}/${song.id}');
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

Future<void> _promptCreate(
  BuildContext context,
  SongsScreenController controller,
) async {
  final title = await _showSongNameDialog(context, title: 'New Song');
  if (title == null || !context.mounted) return;
  await controller.createSong(title);
}

Future<void> _promptRename(
  BuildContext context,
  Song song,
  SongsScreenController controller,
) async {
  final title = await _showSongNameDialog(
    context,
    title: 'Rename Song',
    initialValue: song.title,
  );
  if (title == null || !context.mounted) return;
  await controller.renameSong(song, title);
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Song song,
  SongsScreenController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: tdDialogShape,
      title: const Text('Delete Song', style: AppTextTheme.heading3),
      content: Text(
        'Delete "${song.title}"? This cannot be undone.',
        style: AppTextTheme.body,
      ),
      actions: [
        TDButton(
          label: 'Cancel',
          variant: TDButtonVariant.secondary,
          onPressed: () => Navigator.pop(context, false),
        ),
        TDButton(
          label: 'Delete',
          variant: TDButtonVariant.destructive,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await controller.deleteSong(song.id);

  // Clear the active editor song if the deleted song was being edited,
  // so the desktop play button does not reference a stale entity.
  final activeSong = ref.read(activeEditorSongProvider);
  if (activeSong?.id == song.id) {
    ref.read(activeEditorSongProvider.notifier).state = null;
  }
}

Future<String?> _showSongNameDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _SongNameDialog(
      title: title,
      initialValue: initialValue,
    ),
  );
}

class _SongNameDialog extends StatefulWidget {
  const _SongNameDialog({required this.title, this.initialValue = ''});

  final String title;
  final String initialValue;

  @override
  State<_SongNameDialog> createState() => _SongNameDialogState();
}

class _SongNameDialogState extends State<_SongNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.pop(context, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: tdDialogShape,
      title: Text(widget.title, style: AppTextTheme.heading3),
      content: TDTextField(
        controller: _controller,
        autofocus: true,
        hint: 'Song name',
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TDButton(
          label: 'Cancel',
          variant: TDButtonVariant.secondary,
          onPressed: () => Navigator.pop(context),
        ),
        TDButton(
          label: 'Save',
          onPressed: _submit,
        ),
      ],
    );
  }
}

enum _SongAction { export, rename, delete }
