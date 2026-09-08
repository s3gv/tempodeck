import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/audio/i_export_engine.dart';
import '../../core/providers/audio_mixer_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_theme.dart';
import '../../core/widgets/td_button.dart';
import '../../core/widgets/td_sheet.dart';
import '../../core/widgets/td_toggle.dart';
import '../metronome/metronome_screen_controller.dart';
import 'export_controller.dart';

final _logger = Logger('ExportSheet');

/// Shows the export bottom sheet for a song or setlist.
Future<void> showExportSheet({
  required BuildContext context,
  required ExportSource source,
  required String title,
}) {
  return showTDSheet(
    context: context,
    builder: (context) => _ExportSheet(source: source, title: title),
  );
}

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet({required this.source, required this.title});

  final ExportSource source;
  final String title;

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  ExportMp3Layout _layout = ExportMp3Layout.singleFile;
  Duration? _estimatedDuration;

  bool _includeClickTrack = true;
  bool _includeLinkedAudio = true;
  bool _includeAudioCues = true;
  bool _includeCountIn = true;

  bool get _isSetlist => widget.source is SetlistExportSource;

  @override
  void initState() {
    super.initState();
    // Reset any stale export state from a previous session. Deferred with
    // Future() because initState runs during the build phase and Riverpod
    // does not allow provider modifications at that point.
    Future(() => ref.read(exportControllerProvider.notifier).reset());
    _loadEstimate();
  }

  Future<void> _loadEstimate() async {
    final duration = await ref
        .read(exportControllerProvider.notifier)
        .estimateDuration(
          widget.source,
          includeCountIn: _includeCountIn,
        );
    if (mounted) {
      setState(() => _estimatedDuration = duration);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exportState = ref.watch(exportControllerProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: switch (exportState) {
        ExportIdle() => _buildPreExport(),
        ExportRunning(:final progress) => _buildExporting(progress),
        ExportComplete(:final warnings) => _buildComplete(warnings),
        ExportFailed(:final message) => _buildFailed(message),
      },
    );
  }

  Widget _buildPreExport() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Export ${widget.title}', style: AppTextTheme.heading2),
        const SizedBox(height: AppSpacing.md),
        _buildDurationEstimate(),
        const SizedBox(height: AppSpacing.md),
        _buildContentToggles(),
        if (_isSetlist) ...[
          const SizedBox(height: AppSpacing.md),
          _buildLayoutToggle(),
        ],
        const SizedBox(height: AppSpacing.lg),
        TDButton(
          label: 'Export MP3',
          icon: Icons.download,
          expand: true,
          onPressed: _startExport,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  Widget _buildContentToggles() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CONTENT', style: AppTextTheme.sectionLabel),
        const SizedBox(height: AppSpacing.xs),
        _buildToggle(
          label: 'Click Track',
          value: _includeClickTrack,
          onChanged: (value) => setState(() => _includeClickTrack = value),
        ),
        _buildToggle(
          label: 'Song Audio File',
          value: _includeLinkedAudio,
          onChanged: (value) => setState(() => _includeLinkedAudio = value),
        ),
        _buildToggle(
          label: 'Audio Cues',
          value: _includeAudioCues,
          onChanged: (value) => setState(() => _includeAudioCues = value),
        ),
        _buildToggle(
          label: 'Count In',
          value: _includeCountIn,
          onChanged: (value) {
            setState(() => _includeCountIn = value);
            _loadEstimate();
          },
        ),
      ],
    );
  }

  Widget _buildToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextTheme.label),
          TDToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildDurationEstimate() {
    if (_estimatedDuration == null) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.textMuted,
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          Text('Estimating duration...', style: AppTextTheme.label),
        ],
      );
    }

    final minutes = _estimatedDuration!.inMinutes;
    final seconds = _estimatedDuration!.inSeconds % 60;
    final durationText = '${minutes}m ${seconds}s';

    return Row(
      children: [
        const Icon(Icons.timer_outlined, size: 18, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'Duration: $durationText',
          style: AppTextTheme.label,
        ),
      ],
    );
  }

  Widget _buildLayoutToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('FILE LAYOUT', style: AppTextTheme.sectionLabel),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<ExportMp3Layout>(
          segments: const [
            ButtonSegment(
              value: ExportMp3Layout.singleFile,
              label: Text('Single File'),
            ),
            ButtonSegment(
              value: ExportMp3Layout.cutOnManual,
              label: Text('Split on Manual'),
            ),
          ],
          selected: {_layout},
          onSelectionChanged: (selected) {
            setState(() => _layout = selected.first);
          },
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.textPrimary;
              }
              return AppColors.textSecondary;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.primary.withValues(alpha: 0.3);
              }
              return Colors.transparent;
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildExporting(double progress) {
    final percent = (progress * 100).toInt();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Exporting...', style: AppTextTheme.heading2),
        const SizedBox(height: AppSpacing.md),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: AppColors.surface,
          color: AppColors.primary,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('$percent%', style: AppTextTheme.numeric),
        const SizedBox(height: AppSpacing.lg),
        TDButton(
          label: 'Cancel',
          variant: TDButtonVariant.secondary,
          expand: true,
          onPressed: () {
            ref.read(exportControllerProvider.notifier).cancelExport();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  Widget _buildComplete(List<String> warnings) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success, size: 24),
            SizedBox(width: AppSpacing.sm),
            Text('Export Complete', style: AppTextTheme.heading2),
          ],
        ),
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          ...warnings.map(_buildWarning),
        ],
        const SizedBox(height: AppSpacing.lg),
        TDButton(
          label: 'Save',
          icon: Icons.save_alt,
          expand: true,
          onPressed: _saveFiles,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  Widget _buildWarning(String warning) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child:
                Icon(Icons.warning_amber, size: 16, color: AppColors.warning),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(warning, style: AppTextTheme.labelSmall),
          ),
        ],
      ),
    );
  }

  Widget _buildFailed(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 24),
            SizedBox(width: AppSpacing.sm),
            Text('Export Failed', style: AppTextTheme.heading2),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(message, style: AppTextTheme.label),
        const SizedBox(height: AppSpacing.lg),
        TDButton(
          label: 'Try Again',
          variant: TDButtonVariant.secondary,
          expand: true,
          onPressed: () {
            ref.read(exportControllerProvider.notifier).reset();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  void _startExport() {
    final mixerState = ref.read(audioMixerControllerProvider);
    final metronomeState = ref.read(metronomeScreenControllerProvider);

    final contentOptions = ExportContentOptions(
      includeClickTrack: _includeClickTrack,
      includeLinkedAudio: _includeLinkedAudio,
      includeAudioCues: _includeAudioCues,
      includeCountIn: _includeCountIn,
      clickSoundSet: metronomeState.clickSoundSet,
      metronomeVolumePercent: mixerState.metronomeVolumePercent,
      cueVolumePercent: mixerState.cueVolumePercent,
    );

    ref.read(exportControllerProvider.notifier).startExport(
          source: widget.source,
          title: widget.title,
          layout: _layout,
          contentOptions: contentOptions,
        );
  }

  Future<void> _saveFiles() async {
    try {
      await ref.read(exportControllerProvider.notifier).saveExportedFiles();
      // Do not pop the sheet — on iOS the share_plus future resolves when
      // the share sheet dismisses, but the "Save to Files" picker may still
      // be open. The user can swipe the sheet down to close it.
    } catch (error, stackTrace) {
      _logger.severe('Save failed.', error, stackTrace);
      if (mounted) {
        ref.read(exportControllerProvider.notifier).reset();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $error')),
        );
      }
    }
  }
}
