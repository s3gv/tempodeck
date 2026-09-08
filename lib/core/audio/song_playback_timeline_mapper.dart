import '../domain/song.dart';
import '../domain/song_beatmap.dart';
import '../domain/subdivision.dart';
import 'beat_duration.dart' as beat_duration_util;
import 'tempo_map_evaluator.dart';

class SongTimelinePosition {
  const SongTimelinePosition({
    required this.elapsed,
    required this.songDuration,
    required this.barIndex,
    required this.beatIndex,
    required this.pulseIndex,
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.subdivision,
    required this.elapsedInBar,
    required this.elapsedInBeat,
    required this.elapsedInPulse,
    required this.isSongComplete,
  });

  final Duration elapsed;
  final Duration songDuration;
  final int barIndex;
  final int beatIndex;
  final int pulseIndex;
  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
  final int subdivision;
  final Duration elapsedInBar;
  final Duration elapsedInBeat;
  final Duration elapsedInPulse;
  final bool isSongComplete;
}

class SongPlaybackTimelineMapper {
  const SongPlaybackTimelineMapper({
    TempoMapEvaluator tempoMapEvaluator = const TempoMapEvaluator(),
  }) : _tempoMapEvaluator = tempoMapEvaluator;

  final TempoMapEvaluator _tempoMapEvaluator;

  SongTimelinePosition mapElapsed(Song song, Duration elapsed) {
    _validateElapsed(elapsed);

    final totalDuration = calculateSongDuration(song);
    if (elapsed >= totalDuration) {
      return _buildCompletedPosition(song, totalDuration);
    }

    var remaining = elapsed;
    for (var barIndex = 1; barIndex <= song.endBar; barIndex++) {
      final tempoState = _tempoMapEvaluator.resolveAtBar(song, barIndex);
      final subdivision = _resolveSubdivision(song, barIndex);
      final bd = beat_duration_util.beatDuration(bpm: tempoState.bpm, beatUnit: tempoState.beatUnit);
      final pulseDuration = _calculatePulseDuration(bd, subdivision);
      final barDuration = _multiplyDuration(bd, tempoState.beatsPerBar);

      if (remaining < barDuration) {
        final beatOffset = remaining.inMicroseconds ~/ bd.inMicroseconds;
        final elapsedInBeat = remaining - _multiplyDuration(bd, beatOffset);
        final pulseOffset = elapsedInBeat.inMicroseconds ~/ pulseDuration.inMicroseconds;
        final elapsedInPulse = elapsedInBeat - _multiplyDuration(pulseDuration, pulseOffset);

        return SongTimelinePosition(
          elapsed: elapsed,
          songDuration: totalDuration,
          barIndex: barIndex,
          beatIndex: beatOffset + 1,
          pulseIndex: pulseOffset + 1,
          bpm: tempoState.bpm,
          beatsPerBar: tempoState.beatsPerBar,
          beatUnit: tempoState.beatUnit,
          subdivision: subdivision,
          elapsedInBar: remaining,
          elapsedInBeat: elapsedInBeat,
          elapsedInPulse: elapsedInPulse,
          isSongComplete: false,
        );
      }

      remaining -= barDuration;
    }

    return _buildCompletedPosition(song, totalDuration);
  }

  Duration calculateSongDuration(Song song) {
    return calculateElapsedAtBar(song, song.endBar + 1);
  }

  /// Returns the total playback duration of a [SongBeatmap], including all
  /// expanded loops, alternative endings, and count-in bars.
  Duration calculateBeatmapDuration(SongBeatmap beatmap) {
    return calculateBeatmapElapsedAtPlaybackBar(
      beatmap,
      beatmap.totalPlaybackBars + 1,
    );
  }

  /// Returns the cumulative duration from the start of playback bar 1 to the
  /// start of [playbackBarIndex] within a [SongBeatmap].
  Duration calculateBeatmapElapsedAtPlaybackBar(
    SongBeatmap beatmap,
    int playbackBarIndex,
  ) {
    var total = Duration.zero;
    for (var i = 1;
        i < playbackBarIndex && i <= beatmap.totalPlaybackBars;
        i++) {
      final entry = beatmap.entryForPlaybackBar(i);
      final bd = beat_duration_util.beatDuration(bpm: entry.bpm, beatUnit: entry.beatUnit);
      total += _multiplyDuration(bd, entry.beatsPerBar);
    }
    return total;
  }

  /// Returns the cumulative duration from the start of bar 1 to the start
  /// of [barIndex]. For example, `calculateElapsedAtBar(song, 1)` returns
  /// [Duration.zero] and `calculateElapsedAtBar(song, song.endBar + 1)`
  /// returns the total song duration.
  Duration calculateElapsedAtBar(Song song, int barIndex) {
    var totalDuration = Duration.zero;

    for (var bar = 1; bar < barIndex && bar <= song.endBar; bar++) {
      final tempoState = _tempoMapEvaluator.resolveAtBar(song, bar);
      final bd = beat_duration_util.beatDuration(bpm: tempoState.bpm, beatUnit: tempoState.beatUnit);
      totalDuration += _multiplyDuration(bd, tempoState.beatsPerBar);
    }

    return totalDuration;
  }

  SongTimelinePosition _buildCompletedPosition(Song song, Duration totalDuration) {
    final finalTempoState = _tempoMapEvaluator.resolveAtBar(song, song.endBar);
    final finalSubdivision = _resolveSubdivision(song, song.endBar);
    final finalBeatDuration = beat_duration_util.beatDuration(bpm: finalTempoState.bpm, beatUnit: finalTempoState.beatUnit);
    final finalPulseDuration = _calculatePulseDuration(finalBeatDuration, finalSubdivision);
    final finalBarDuration = _multiplyDuration(finalBeatDuration, finalTempoState.beatsPerBar);

    return SongTimelinePosition(
      elapsed: totalDuration,
      songDuration: totalDuration,
      barIndex: song.endBar,
      beatIndex: finalTempoState.beatsPerBar,
      pulseIndex: finalSubdivision,
      bpm: finalTempoState.bpm,
      beatsPerBar: finalTempoState.beatsPerBar,
      beatUnit: finalTempoState.beatUnit,
      subdivision: finalSubdivision,
      elapsedInBar: finalBarDuration,
      elapsedInBeat: finalBeatDuration,
      elapsedInPulse: finalPulseDuration,
      isSongComplete: true,
    );
  }

  int _resolveSubdivision(Song song, int barIndex) {
    SongBarBeatPattern? resolvedPattern;

    for (final pattern in song.beatPatterns) {
      // repeatPass-specific patterns are applied by the loop engine.
      if (pattern.barIndex != barIndex || pattern.repeatPass != null) {
        continue;
      }

      resolvedPattern = pattern;
    }

    return (resolvedPattern?.subdivision ?? Subdivision.one).pulseCount;
  }

  Duration _calculatePulseDuration(Duration beatDuration, int subdivision) {
    final microsecondsPerPulse = (beatDuration.inMicroseconds / subdivision).round();
    return Duration(microseconds: microsecondsPerPulse);
  }

  Duration _multiplyDuration(Duration duration, int factor) {
    return Duration(microseconds: duration.inMicroseconds * factor);
  }

  void _validateElapsed(Duration elapsed) {
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'must not be negative');
    }
  }
}
