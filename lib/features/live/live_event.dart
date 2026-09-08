import 'package:flutter/material.dart';

import '../../core/domain/setlist.dart';

/// Unified event model for the live view.
///
/// Multiple [LiveEvent]s can be active at the same bar simultaneously
/// (e.g., a loop start, a tempo change, and a song marker).
sealed class LiveEvent {
  const LiveEvent({this.displayBarLabel});

  final String? displayBarLabel;

  /// Human-readable label for display.
  String get label;

  /// Icon representing the event type.
  IconData get icon;
}

/// A tempo or time signature change at a specific bar.
class TempoChangeEvent extends LiveEvent {
  const TempoChangeEvent({
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.barIndex,
    super.displayBarLabel,
  });

  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
  final int barIndex;

  @override
  String get label => 'Tempo → $bpm BPM ($beatsPerBar/$beatUnit)';

  @override
  IconData get icon => Icons.speed;
}

/// A loop boundary (start or end) with iteration info.
class LoopEvent extends LiveEvent {
  const LoopEvent({
    required this.startBar,
    required this.endBar,
    required this.iteration,
    required this.totalIterations,
    required this.isStart,
    super.displayBarLabel,
  });

  final int startBar;
  final int endBar;
  final int iteration;
  final int totalIterations;
  final bool isStart;

  @override
  String get label {
    final boundary = isStart ? 'start' : 'end';
    return 'Loop $boundary ($iteration/$totalIterations)';
  }

  @override
  IconData get icon => Icons.replay;
}

/// A user-defined song marker (e.g., "Verse 1", "Chorus").
class SongMarkerEvent extends LiveEvent {
  const SongMarkerEvent({
    required this.eventLabel,
    required this.barIndex,
    super.displayBarLabel,
  });

  final String eventLabel;
  final int barIndex;

  @override
  String get label => eventLabel;

  @override
  IconData get icon => Icons.bookmark_outline;
}

/// An interval tempo step (metronome progressive tempo mode).
class IntervalStepEvent extends LiveEvent {
  const IntervalStepEvent({
    required this.fromBpm,
    required this.toBpm,
  });

  final int fromBpm;
  final int toBpm;

  @override
  String get label => 'Interval → $toBpm BPM';

  @override
  IconData get icon => Icons.trending_up;
}

/// A setlist transition step between songs.
class SetlistTransitionEvent extends LiveEvent {
  const SetlistTransitionEvent({
    required this.type,
    required this.value,
  });

  final SetlistTransitionStepType type;
  final int value;

  @override
  String get label => switch (type) {
        SetlistTransitionStepType.countInBars => 'Count-in: $value bars',
        SetlistTransitionStepType.pauseTimer => 'Pause: ${value}s',
        SetlistTransitionStepType.manual => 'Manual wait',
        SetlistTransitionStepType.audio => 'Audio cue',
      };

  @override
  IconData get icon => Icons.swap_horiz;
}

/// A setlist song change notification.
class SetlistSongChangeEvent extends LiveEvent {
  const SetlistSongChangeEvent({
    required this.songTitle,
  });

  final String songTitle;

  @override
  String get label => 'Up next: $songTitle';

  @override
  IconData get icon => Icons.skip_next;
}
