import 'accent_level.dart';
import 'audio_cue.dart';
import 'subdivision.dart';

class SongBeatmap {
  SongBeatmap({
    required List<SongBeatmapEntry> entries,
  }) : entries = List.unmodifiable(entries) {
    for (var index = 0; index < this.entries.length; index += 1) {
      final entry = this.entries[index];
      final expectedPlaybackBarIndex = index + 1;
      if (entry.playbackBarIndex != expectedPlaybackBarIndex) {
        throw ArgumentError(
          'Beatmap entries must be sequential from 1..n. '
          'Expected playback bar $expectedPlaybackBarIndex, got '
          '${entry.playbackBarIndex}.',
        );
      }
    }
  }

  final List<SongBeatmapEntry> entries;

  int get totalPlaybackBars => entries.length;

  int get countInBarCount =>
      entries.where((entry) => entry.barKind == SongBeatmapBarKind.countIn).length;

  SongBeatmapEntry get firstSongEntry => entries.firstWhere(
        (entry) => entry.barKind != SongBeatmapBarKind.countIn,
        orElse: () => throw StateError('Beatmap has no song entries.'),
      );

  /// Returns a new beatmap with all count-in entries removed and playback bar
  /// indices re-numbered from 1. Used in setlist playback where the song's own
  /// count-in is replaced by transition step count-ins.
  SongBeatmap withoutCountIn() {
    if (countInBarCount == 0) {
      return this;
    }

    var reindexed = 1;
    final songEntries = <SongBeatmapEntry>[];
    for (final entry in entries) {
      if (entry.barKind == SongBeatmapBarKind.countIn) {
        continue;
      }
      songEntries.add(
        SongBeatmapEntry(
          playbackBarIndex: reindexed,
          barLabel: entry.barLabel,
          barKind: entry.barKind,
          repeatPass: entry.repeatPass,
          notationBarIndex: entry.notationBarIndex,
          loopId: entry.loopId,
          alternativeEndingId: entry.alternativeEndingId,
          alternativeEndingBarIndex: entry.alternativeEndingBarIndex,
          bpm: entry.bpm,
          beatsPerBar: entry.beatsPerBar,
          beatUnit: entry.beatUnit,
          subdivision: entry.subdivision,
          accentPattern: entry.accentPattern,
          events: entry.events,
          audioCueTriggers: entry.audioCueTriggers,
        ),
      );
      reindexed += 1;
    }

    return SongBeatmap(entries: songEntries);
  }

  SongBeatmapEntry entryForPlaybackBar(int playbackBarIndex) {
    if (playbackBarIndex < 1 || playbackBarIndex > entries.length) {
      throw StateError(
        'Beatmap entry not found for playback bar $playbackBarIndex.',
      );
    }
    return entries[playbackBarIndex - 1];
  }
}

enum SongBeatmapBarKind {
  countIn,
  notation,
  alternativeEnding,
}

enum SongBeatmapEventKind {
  tempoChange,
  loopStart,
  loopEnd,
  songMarker,
}

class SongBeatmapAudioCueTrigger {
  const SongBeatmapAudioCueTrigger({
    required this.sourceEventId,
    required this.sourceBarLabel,
    required this.label,
    required this.audioCue,
  });

  final String sourceEventId;
  final String sourceBarLabel;
  final String label;
  final AudioCue audioCue;
}

class SongBeatmapEvent {
  const SongBeatmapEvent({
    required this.id,
    required this.kind,
    required this.label,
    this.barLabel,
    this.bpm,
    this.beatsPerBar,
    this.beatUnit,
    this.loopStartBar,
    this.loopEndBar,
    this.loopIteration,
    this.loopTotalIterations,
    this.sourceBarIndex,
  });

  final String id;
  final SongBeatmapEventKind kind;
  final String label;
  final String? barLabel;
  final int? bpm;
  final int? beatsPerBar;
  final int? beatUnit;
  final int? loopStartBar;
  final int? loopEndBar;
  final int? loopIteration;
  final int? loopTotalIterations;
  final int? sourceBarIndex;
}

class SongBeatmapEntry {
  const SongBeatmapEntry({
    required this.playbackBarIndex,
    required this.barLabel,
    required this.barKind,
    required this.repeatPass,
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.subdivision,
    required this.accentPattern,
    required this.events,
    required this.audioCueTriggers,
    this.notationBarIndex,
    this.loopId,
    this.alternativeEndingId,
    this.alternativeEndingBarIndex,
  });

  final int playbackBarIndex;
  final String barLabel;
  final SongBeatmapBarKind barKind;
  final int repeatPass;
  final int? notationBarIndex;
  final String? loopId;
  final String? alternativeEndingId;
  final int? alternativeEndingBarIndex;
  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
  final Subdivision subdivision;
  final List<AccentLevel> accentPattern;
  final List<SongBeatmapEvent> events;
  final List<SongBeatmapAudioCueTrigger> audioCueTriggers;

  int get displayBarIndex => notationBarIndex ?? playbackBarIndex;
}
