import '../../core/domain/interval_settings.dart';
import '../../core/validation/preset_write_validator.dart';

class MetronomeIntervalPreviewItem {
  const MetronomeIntervalPreviewItem({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
}

class MetronomeIntervalPreviewBuilder {
  static const int previewItemCount = 5;

  const MetronomeIntervalPreviewBuilder();

  List<MetronomeIntervalPreviewItem> build({
    required int bpm,
    required IntervalSettings intervalSettings,
  }) {
    final items = <MetronomeIntervalPreviewItem>[];
    final interval = intervalSettings.interval;

    for (var intervalIndex = 1;
        intervalIndex <= previewItemCount;
        intervalIndex++) {
      final elapsed = interval * intervalIndex;
      final maxDuration = intervalSettings.maxDuration;
      if (maxDuration != null && elapsed > maxDuration) {
        items.add(
          MetronomeIntervalPreviewItem(
            title: 'Stop playback',
            subtitle: 'After ${_formatDuration(maxDuration)}',
          ),
        );
        break;
      }

      final nextBpm = intervalSettings.bpmStepEnabled
          ? (bpm + (intervalSettings.bpmStep * intervalIndex)).clamp(
              PresetWriteValidator.minimumBpm,
              PresetWriteValidator.maximumBpm,
            )
          : bpm;
      final bpmDescription = intervalSettings.bpmStepEnabled
          ? 'Change to $nextBpm BPM'
          : 'Keep $bpm BPM';

      items.add(
        MetronomeIntervalPreviewItem(
          title: 'Interval $intervalIndex',
          subtitle: 'After ${_formatDuration(elapsed)} • $bpmDescription',
        ),
      );

      if (maxDuration != null && elapsed == maxDuration) {
        items.add(
          MetronomeIntervalPreviewItem(
            title: 'Stop playback',
            subtitle: 'After ${_formatDuration(maxDuration)}',
          ),
        );
        break;
      }
    }

    return List<MetronomeIntervalPreviewItem>.unmodifiable(items);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % Duration.secondsPerMinute;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
