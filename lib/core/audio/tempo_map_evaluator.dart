import '../domain/song.dart';

class TempoMapState {
  const TempoMapState({
    required this.barIndex,
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
  });

  /// The bar at which this tempo state became active.
  /// Not the bar that was queried.
  final int barIndex;
  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
}

class TempoMapSegment {
  const TempoMapSegment({
    required this.startBarIndex,
    required this.endBarIndex,
    required this.state,
  });

  final int startBarIndex;
  final int endBarIndex;
  final TempoMapState state;
}

class TempoMapEvaluator {
  const TempoMapEvaluator();

  TempoMapState resolveAtBar(Song song, int barIndex) {
    _validateSong(song);
    _validateRequestedBar(song.endBar, barIndex);

    final checkpoints = _buildCheckpoints(song);
    var activeState = checkpoints.first;

    for (final checkpoint in checkpoints) {
      if (checkpoint.barIndex > barIndex) {
        break;
      }

      activeState = checkpoint;
    }

    return activeState;
  }

  List<TempoMapSegment> buildSegments(Song song) {
    _validateSong(song);

    final checkpoints = _buildCheckpoints(song);

    final segments = <TempoMapSegment>[];
    for (var index = 0; index < checkpoints.length; index++) {
      final checkpoint = checkpoints[index];
      final nextCheckpoint = index + 1 < checkpoints.length ? checkpoints[index + 1] : null;
      final endBarIndex = nextCheckpoint == null ? song.endBar : nextCheckpoint.barIndex - 1;

      segments.add(
        TempoMapSegment(
          startBarIndex: checkpoint.barIndex,
          endBarIndex: endBarIndex,
          state: checkpoint,
        ),
      );
    }

    return segments;
  }

  List<TempoMapState> _buildCheckpoints(Song song) {
    final checkpointsByBar = <int, TempoMapState>{
      1: TempoMapState(
        barIndex: 1,
        bpm: song.startBpm,
        beatsPerBar: song.beatsPerBar,
        beatUnit: song.beatUnit,
      ),
    };

    for (final change in _sortedTempoChanges(song)) {
      checkpointsByBar[change.barIndex] = TempoMapState(
        barIndex: change.barIndex,
        bpm: change.bpm,
        beatsPerBar: change.beatsPerBar,
        beatUnit: change.beatUnit,
      );
    }

    // Values are returned in insertion order (LinkedHashMap guarantee).
    // This requires _sortedTempoChanges to return ascending barIndex order.
    return checkpointsByBar.values.toList(growable: false);
  }

  List<SongTempoChange> _sortedTempoChanges(Song song) {
    final indexedChanges = song.tempoChanges.indexed.toList()
      ..sort(
        (left, right) {
          final barComparison = left.$2.barIndex.compareTo(right.$2.barIndex);
          if (barComparison != 0) {
            return barComparison;
          }

          // If two changes share a bar, the later list entry wins.
          return left.$1.compareTo(right.$1);
        },
      );

    return indexedChanges.map((entry) => entry.$2).toList(growable: false);
  }

  void _validateSong(Song song) {
    if (song.endBar < 1) {
      throw ArgumentError.value(song.endBar, 'song.endBar', 'must be at least 1');
    }

    for (final change in song.tempoChanges) {
      if (change.barIndex < 1 || change.barIndex > song.endBar) {
        throw ArgumentError.value(
          change.barIndex,
          'change.barIndex',
          'must be between 1 and ${song.endBar}',
        );
      }
    }
  }

  void _validateRequestedBar(int endBar, int barIndex) {
    if (barIndex < 1 || barIndex > endBar) {
      throw ArgumentError.value(
        barIndex,
        'barIndex',
        'must be between 1 and $endBar',
      );
    }
  }
}
