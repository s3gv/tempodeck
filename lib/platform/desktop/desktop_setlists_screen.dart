import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/td_empty_state.dart';
import '../../features/live/live_view_context.dart';
import '../../features/setlists/setlist_editor_screen.dart';
import '../../features/setlists/setlists_screen.dart';
import 'desktop_panel_layout.dart';

class DesktopSetlistsScreen extends ConsumerWidget {
  const DesktopSetlistsScreen({
    super.key,
    this.selectedSetlistId,
  });

  final String? selectedSetlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Clear the active editor setlist when no setlist is selected (user
    // navigated back to the list or the previously selected setlist was deleted).
    if (selectedSetlistId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeEditorSetlistProvider.notifier).state = null;
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
            child: SetlistsScreen(
              selectedSetlistId: selectedSetlistId,
              showScaffold: false,
              onSetlistTap: (context, setlist) =>
                  context.go('${Routes.setlists}/${setlist.id}'),
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
            child: selectedSetlistId == null
                ? const _DesktopSetlistPlaceholder()
                : SetlistEditorScreen(
                    setlistId: selectedSetlistId!,
                    showScaffold: false,
                  ),
          ),
        ),
      ],
    );
  }
}

class _DesktopSetlistPlaceholder extends StatelessWidget {
  const _DesktopSetlistPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const TDEmptyState(
      icon: Icons.queue_music_outlined,
      title: 'Select a setlist to edit',
    );
  }
}
