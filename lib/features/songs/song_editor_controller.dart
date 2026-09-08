import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/domain/accent_level.dart';
import '../../core/domain/audio_cue.dart';
import '../../core/domain/linked_audio_file.dart';
import '../../core/domain/song.dart';
import '../../core/domain/subdivision.dart';
import '../../core/providers/repository_providers.dart';

final songEditorControllerProvider = Provider(
  (ref) => SongEditorController(ref),
);

class SongEditorController {
  SongEditorController(this._ref);

  final Ref _ref;
  final _uuid = const Uuid();

  Future<void> saveSongDetails({
    required Song song,
    required String title,
    required int startBpm,
    required int beatsPerBar,
    required int beatUnit,
    required int countInBars,
    required int endBar,
    required List<SongTempoChange> tempoChanges,
    required List<SongLoop> loops,
    required List<SongEvent> songEvents,
    required List<SongBarBeatPattern> beatPatterns,
    required LinkedAudioFile? linkedAudio,
  }) async {
    await _ref.read(songRepositoryProvider).saveSong(
          song.copyWith(
            title: title.trim(),
            startBpm: startBpm,
            beatsPerBar: beatsPerBar,
            beatUnit: beatUnit,
            countInBars: countInBars,
            endBar: endBar,
            tempoChanges: tempoChanges,
            loops: loops,
            songEvents: songEvents,
            beatPatterns: beatPatterns,
            linkedAudio: linkedAudio,
            clearLinkedAudio: linkedAudio == null,
          ),
        );
  }

  Future<void> regenerateBeatmap(String songId) async {
    await _ref.read(songRepositoryProvider).regenerateBeatmap(songId);
  }

  SongTempoChange createTempoChange({
    required int barIndex,
    required int bpm,
    required int beatsPerBar,
    required int beatUnit,
  }) {
    return SongTempoChange(
      id: _uuid.v4(),
      barIndex: barIndex,
      bpm: bpm,
      beatsPerBar: beatsPerBar,
      beatUnit: beatUnit,
    );
  }

  SongLoop createLoop({
    required int startBar,
    required int endBar,
    required int repeatCount,
    List<SongLoopAlternativeEnding> alternativeEndings = const [],
  }) {
    return SongLoop(
      id: _uuid.v4(),
      startBar: startBar,
      endBar: endBar,
      repeatCount: repeatCount,
      alternativeEndings: alternativeEndings,
    );
  }

  SongEvent createSongEvent({
    required int barIndex,
    required String label,
    required AudioCue? audioCue,
    required int audioCueBarsBefore,
  }) {
    return SongEvent(
      id: _uuid.v4(),
      barIndex: barIndex,
      label: label.trim(),
      audioCue: audioCue,
      audioCueBarsBefore: audioCueBarsBefore,
    );
  }

  SongBarBeatPattern createBeatPattern({
    required int barIndex,
    required List<AccentLevel> accents,
    required Subdivision subdivision,
    required int? repeatPass,
  }) {
    return SongBarBeatPattern(
      id: _uuid.v4(),
      barIndex: barIndex,
      accents: accents,
      subdivision: subdivision,
      repeatPass: repeatPass,
    );
  }
}
