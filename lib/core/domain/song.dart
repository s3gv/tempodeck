import 'accent_level.dart';
import 'audio_cue.dart';
import 'linked_audio_file.dart';
import 'subdivision.dart';

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.startBpm,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.countInBars,
    required this.endBar,
    this.tempoChanges = const [],
    this.loops = const [],
    this.songEvents = const [],
    this.beatPatterns = const [],
    this.linkedAudio,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final int startBpm;
  final int beatsPerBar;
  final int beatUnit;
  final int countInBars;
  final int endBar;
  final List<SongTempoChange> tempoChanges;
  final List<SongLoop> loops;
  final List<SongEvent> songEvents;
  final List<SongBarBeatPattern> beatPatterns;
  final LinkedAudioFile? linkedAudio;

  Song copyWith({
    String? title,
    int? startBpm,
    int? beatsPerBar,
    int? beatUnit,
    int? countInBars,
    int? endBar,
    List<SongTempoChange>? tempoChanges,
    List<SongLoop>? loops,
    List<SongEvent>? songEvents,
    List<SongBarBeatPattern>? beatPatterns,
    LinkedAudioFile? linkedAudio,
    bool clearLinkedAudio = false,
  }) {
    return Song(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      startBpm: startBpm ?? this.startBpm,
      beatsPerBar: beatsPerBar ?? this.beatsPerBar,
      beatUnit: beatUnit ?? this.beatUnit,
      countInBars: countInBars ?? this.countInBars,
      endBar: endBar ?? this.endBar,
      tempoChanges: tempoChanges ?? this.tempoChanges,
      loops: loops ?? this.loops,
      songEvents: songEvents ?? this.songEvents,
      beatPatterns: beatPatterns ?? this.beatPatterns,
      linkedAudio: clearLinkedAudio ? null : (linkedAudio ?? this.linkedAudio),
    );
  }
}

class SongTempoChange {
  const SongTempoChange({
    required this.id,
    required this.barIndex,
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
  });

  final String id;
  final int barIndex;
  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
}

class SongLoop {
  const SongLoop({
    required this.id,
    required this.startBar,
    required this.endBar,
    required this.repeatCount,
    this.alternativeEndings = const [],
  });

  final String id;
  final int startBar;
  final int endBar;
  final int repeatCount;
  final List<SongLoopAlternativeEnding> alternativeEndings;
}

class SongLoopAlternativeEnding {
  const SongLoopAlternativeEnding({
    required this.id,
    required this.repeatPass,
    required this.lengthBars,
    this.tempoChanges = const [],
    this.songEvents = const [],
    this.beatPatterns = const [],
  });

  final String id;
  final int repeatPass;
  final int lengthBars;
  final List<SongTempoChange> tempoChanges;
  final List<SongEvent> songEvents;
  final List<SongBarBeatPattern> beatPatterns;
}

class SongEvent {
  const SongEvent({
    required this.id,
    required this.barIndex,
    required this.label,
    this.audioCue,
    this.audioCueBarsBefore = 0,
  });

  final String id;
  final int barIndex;
  final String label;
  final AudioCue? audioCue;
  final int audioCueBarsBefore;
}

class SongBarBeatPattern {
  const SongBarBeatPattern({
    required this.id,
    required this.barIndex,
    required this.accents,
    required this.subdivision,
    this.repeatPass,
  });

  final String id;
  final int barIndex;
  final List<AccentLevel> accents;
  final Subdivision subdivision;
  final int? repeatPass;
}
