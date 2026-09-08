import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/i_export_engine.dart';
import '../../core/domain/song.dart';
import '../../core/domain/setlist.dart';
import '../../core/providers/repository_providers.dart';
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
import 'setlists_list_provider.dart';
import 'setlists_screen_controller.dart';

class SetlistsScreen extends ConsumerWidget {
  static const _embeddedHeaderPadding = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.lg,
    AppSpacing.lg,
    AppSpacing.sm,
  );

  const SetlistsScreen({
    super.key,
    this.selectedSetlistId,
    this.showScaffold = true,
    this.onSetlistTap,
  });

  final String? selectedSetlistId;
  final bool showScaffold;
  final void Function(BuildContext context, Setlist setlist)? onSetlistTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setlists = ref.watch(setlistsListProvider);
    final controller = ref.read(setlistsScreenControllerProvider);

    final content = setlists.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (error, _) => Center(
        child: Text('Error: $error', style: AppTextTheme.bodySecondary),
      ),
      data: (setlists) => setlists.isEmpty
          ? TDEmptyState(
              icon: Icons.queue_music_outlined,
              title: 'No setlists yet',
              subtitle: 'Create your first setlist to get started.',
              actionLabel: 'New Setlist',
              onAction: () => _promptCreate(context, controller),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              itemCount: setlists.length,
              itemBuilder: (context, index) {
                final setlist = setlists[index];
                final itemCount = setlist.items.length;
                final songLabel = itemCount == 1 ? 'song' : 'songs';

                return TDStaggeredListItem(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: TDListTile(
                      title: setlist.title,
                      subtitle: '$itemCount $songLabel',
                      isSelected: setlist.id == selectedSetlistId,
                      trailing: PopupMenuButton<_SetlistAction>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: AppColors.textSecondary,
                        ),
                        onSelected: (action) {
                          switch (action) {
                            case _SetlistAction.export:
                              showExportSheet(
                                context: context,
                                source: SetlistExportSource(setlist.id),
                                title: setlist.title,
                              );
                            case _SetlistAction.addSong:
                              _promptAddSong(
                                context, ref, setlist, controller,
                              );
                            case _SetlistAction.rename:
                              _promptRename(context, setlist, controller);
                            case _SetlistAction.delete:
                              _confirmDelete(
                                context, ref, setlist, controller,
                              );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _SetlistAction.export,
                            child: Text('Export'),
                          ),
                          PopupMenuItem(
                            value: _SetlistAction.addSong,
                            child: Text('Add song'),
                          ),
                          PopupMenuItem(
                            value: _SetlistAction.rename,
                            child: Text('Rename'),
                          ),
                          PopupMenuItem(
                            value: _SetlistAction.delete,
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                      onTap: () => _handleSetlistTap(context, setlist),
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
                  child: Text('Setlists', style: AppTextTheme.heading2),
                ),
                TDButton(
                  label: 'New Setlist',
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
        title: const Text('Setlists', style: AppTextTheme.heading2),
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

  void _handleSetlistTap(BuildContext context, Setlist setlist) {
    final onSetlistTap = this.onSetlistTap;
    if (onSetlistTap != null) {
      onSetlistTap(context, setlist);
      return;
    }

    context.go('${Routes.setlists}/${setlist.id}');
  }
}

Future<void> _promptAddSong(
  BuildContext context,
  WidgetRef ref,
  Setlist setlist,
  SetlistsScreenController controller,
) async {
  final selectedSong = await showDialog<Song>(
    context: context,
    builder: (context) => _SongBrowserDialog(
      songsStream: ref.read(songRepositoryProvider).watchAllSongs(),
    ),
  );
  if (selectedSong == null || !context.mounted) {
    return;
  }

  await controller.addSongToSetlist(setlist, selectedSong);
}

Future<void> _promptCreate(
  BuildContext context,
  SetlistsScreenController controller,
) async {
  final title = await _showSetlistNameDialog(context, title: 'New Setlist');
  if (title == null || !context.mounted) {
    return;
  }

  await controller.createSetlist(title);
}

Future<void> _promptRename(
  BuildContext context,
  Setlist setlist,
  SetlistsScreenController controller,
) async {
  final title = await _showSetlistNameDialog(
    context,
    title: 'Rename Setlist',
    initialValue: setlist.title,
  );
  if (title == null || !context.mounted) {
    return;
  }

  await controller.renameSetlist(setlist, title);
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Setlist setlist,
  SetlistsScreenController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: tdDialogShape,
      title: const Text('Delete Setlist', style: AppTextTheme.heading3),
      content: Text(
        'Delete "${setlist.title}"? This cannot be undone.',
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
  if (confirmed != true || !context.mounted) {
    return;
  }

  await controller.deleteSetlist(setlist.id);

  // Clear the active editor setlist if the deleted setlist was being edited,
  // so the desktop play button does not reference a stale entity.
  final activeSetlist = ref.read(activeEditorSetlistProvider);
  if (activeSetlist?.id == setlist.id) {
    ref.read(activeEditorSetlistProvider.notifier).state = null;
  }
}

Future<String?> _showSetlistNameDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _SetlistNameDialog(
      title: title,
      initialValue: initialValue,
    ),
  );
}

class _SetlistNameDialog extends StatefulWidget {
  const _SetlistNameDialog({
    required this.title,
    this.initialValue = '',
  });

  final String title;
  final String initialValue;

  @override
  State<_SetlistNameDialog> createState() => _SetlistNameDialogState();
}

class _SetlistNameDialogState extends State<_SetlistNameDialog> {
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
    if (trimmed.isEmpty) {
      return;
    }

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
        hint: 'Setlist name',
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

enum _SetlistAction { export, addSong, rename, delete }

class _SongBrowserDialog extends StatelessWidget {
  static const _dialogWidth = 420.0;
  static const _dialogStateHeight = 120.0;

  const _SongBrowserDialog({required this.songsStream});

  final Stream<List<Song>> songsStream;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: tdDialogShape,
      title: const Text('Add song', style: AppTextTheme.heading3),
      content: SizedBox(
        width: _dialogWidth,
        child: StreamBuilder<List<Song>>(
          stream: songsStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                height: _dialogStateHeight,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              );
            }

            final songs = snapshot.data!;
            if (songs.isEmpty) {
              return const SizedBox(
                height: _dialogStateHeight,
                child: Center(
                  child: Text(
                    'No songs available',
                    style: AppTextTheme.bodySecondary,
                  ),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return TDListTile(
                  title: song.title,
                  subtitle:
                      '${song.startBpm} BPM \u00B7 ${song.beatsPerBar}/${song.beatUnit}',
                  onTap: () => Navigator.pop(context, song),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TDButton(
          label: 'Cancel',
          variant: TDButtonVariant.secondary,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
