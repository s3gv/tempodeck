import '../../core/domain/interval_settings.dart';
import 'live_event.dart';

/// Resolves metronome-only live events (interval BPM stepping).
///
/// Song and setlist events are resolved exclusively from the persisted
/// beatmap. This resolver must NOT be used for song or setlist playback.
class LiveMetronomeEventResolver {
  const LiveMetronomeEventResolver();

  ({List<LiveEvent> current, List<LiveEvent> next}) resolve({
    required IntervalSettings? intervalSettings,
    required int? currentBpm,
  }) {
    if (intervalSettings == null ||
        !intervalSettings.bpmStepEnabled ||
        currentBpm == null) {
      return (current: const [], next: const []);
    }

    final nextBpm = currentBpm + intervalSettings.bpmStep;
    return (
      current: const [],
      next: [
        IntervalStepEvent(fromBpm: currentBpm, toBpm: nextBpm),
      ],
    );
  }
}
