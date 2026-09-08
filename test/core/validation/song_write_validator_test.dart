import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/subdivision.dart';
import 'package:tempodeck/core/validation/song_write_validator.dart';

void main() {
  const validator = SongWriteValidator();

  test('accepts a valid song aggregate', () {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      tempoChanges: const [
        SongTempoChange(
          id: 'tempo-1',
          barIndex: 8,
          bpm: 132,
          beatsPerBar: 7,
          beatUnit: 8,
        ),
      ],
      loops: const [
        SongLoop(
          id: 'loop-1',
          startBar: 10,
          endBar: 12,
          repeatCount: 2,
        ),
      ],
      songEvents: const [
        SongEvent(
          id: 'event-1',
          barIndex: 16,
          label: 'Verse',
          audioCueBarsBefore: 2,
        ),
      ],
      beatPatterns: const [
        SongBarBeatPattern(
          id: 'pattern-1',
          barIndex: 20,
          accents: [],
          subdivision: Subdivision.four,
          repeatPass: 1,
        ),
      ],
    );

    expect(() => validator.validate(song), returnsNormally);
  });

  test('rejects an empty title', () {
    final song = Song(
      id: 'song-1',
      title: '   ',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
    );

    expect(
      () => validator.validate(song),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects bpm outside the supported range', () {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 10,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
    );

    expect(
      () => validator.validate(song),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects unsupported beat units', () {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 3,
      countInBars: 2,
      endBar: 32,
    );

    expect(
      () => validator.validate(song),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects tempo changes outside the song range', () {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      tempoChanges: const [
        SongTempoChange(
          id: 'tempo-1',
          barIndex: 40,
          bpm: 132,
          beatsPerBar: 4,
          beatUnit: 4,
        ),
      ],
    );

    expect(
      () => validator.validate(song),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects loops with inverted bar ranges', () {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      loops: const [
        SongLoop(
          id: 'loop-1',
          startBar: 12,
          endBar: 10,
          repeatCount: 2,
        ),
      ],
    );

    expect(
      () => validator.validate(song),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects overlapping loops', () {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      loops: const [
        SongLoop(
          id: 'loop-1',
          startBar: 8,
          endBar: 12,
          repeatCount: 2,
        ),
        SongLoop(
          id: 'loop-2',
          startBar: 12,
          endBar: 16,
          repeatCount: 2,
        ),
      ],
    );

    expect(
      () => validator.validate(song),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects duplicate alternative-ending repeat passes within a loop', () {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      loops: const [
        SongLoop(
          id: 'loop-1',
          startBar: 8,
          endBar: 12,
          repeatCount: 2,
          alternativeEndings: [
            SongLoopAlternativeEnding(
              id: 'ending-1',
              repeatPass: 2,
              lengthBars: 2,
            ),
            SongLoopAlternativeEnding(
              id: 'ending-2',
              repeatPass: 2,
              lengthBars: 1,
            ),
          ],
        ),
      ],
    );

    expect(
      () => validator.validate(song),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects invalid top-level meter and end-bar values', () {
    final invalidBeatsPerBarSong = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 0,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
    );
    final invalidEndBarSong = Song(
      id: 'song-2',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 0,
    );

    expect(
      () => validator.validate(invalidBeatsPerBarSong),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validator.validate(invalidEndBarSong),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects invalid tempo change field values', () {
    final invalidTempoChangeBpmSong = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      tempoChanges: const [
        SongTempoChange(
          id: 'tempo-1',
          barIndex: 8,
          bpm: 10,
          beatsPerBar: 4,
          beatUnit: 4,
        ),
      ],
    );
    final invalidTempoChangeBeatUnitSong = Song(
      id: 'song-2',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      tempoChanges: const [
        SongTempoChange(
          id: 'tempo-1',
          barIndex: 8,
          bpm: 132,
          beatsPerBar: 4,
          beatUnit: 3,
        ),
      ],
    );

    expect(
      () => validator.validate(invalidTempoChangeBpmSong),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validator.validate(invalidTempoChangeBeatUnitSong),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects invalid loop child fields', () {
    final invalidLoopRangeSong = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      loops: const [
        SongLoop(
          id: 'loop-1',
          startBar: 0,
          endBar: 12,
          repeatCount: 2,
        ),
      ],
    );
    final invalidLoopRepeatCountSong = Song(
      id: 'song-2',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      loops: const [
        SongLoop(
          id: 'loop-1',
          startBar: 10,
          endBar: 12,
          repeatCount: 0,
        ),
      ],
    );

    expect(
      () => validator.validate(invalidLoopRangeSong),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validator.validate(invalidLoopRepeatCountSong),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects invalid song event fields', () {
    final invalidEventBarSong = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      songEvents: const [
        SongEvent(
          id: 'event-1',
          barIndex: 40,
          label: 'Verse',
        ),
      ],
    );
    final invalidEventCueLeadSong = Song(
      id: 'song-2',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      songEvents: const [
        SongEvent(
          id: 'event-1',
          barIndex: 16,
          label: 'Verse',
          audioCueBarsBefore: -1,
        ),
      ],
    );

    expect(
      () => validator.validate(invalidEventBarSong),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validator.validate(invalidEventCueLeadSong),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects invalid song event audio cues', () {
    final invalidVoiceCueSong = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      songEvents: const [
        SongEvent(
          id: 'event-1',
          barIndex: 8,
          label: 'Cue',
          audioCue: AudioCue(
            type: AudioCueType.voice,
            voiceText: '   ',
          ),
        ),
      ],
    );
    final invalidCustomFileCueSong = Song(
      id: 'song-2',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      songEvents: const [
        SongEvent(
          id: 'event-1',
          barIndex: 8,
          label: 'Cue',
          audioCue: AudioCue(
            type: AudioCueType.customFile,
            customFilePath: '',
          ),
        ),
      ],
    );
    final invalidVolumeCueSong = Song(
      id: 'song-3',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      songEvents: const [
        SongEvent(
          id: 'event-1',
          barIndex: 8,
          label: 'Cue',
          audioCue: AudioCue(
            type: AudioCueType.highPulse,
            volumePercent: 120,
          ),
        ),
      ],
    );

    expect(
      () => validator.validate(invalidVoiceCueSong),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validator.validate(invalidCustomFileCueSong),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validator.validate(invalidVolumeCueSong),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects invalid beat pattern fields', () {
    final invalidBeatPatternBarSong = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      beatPatterns: const [
        SongBarBeatPattern(
          id: 'pattern-1',
          barIndex: 40,
          accents: [],
          subdivision: Subdivision.four,
        ),
      ],
    );
    final invalidBeatPatternRepeatPassSong = Song(
      id: 'song-2',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      beatPatterns: const [
        SongBarBeatPattern(
          id: 'pattern-1',
          barIndex: 20,
          accents: [],
          subdivision: Subdivision.four,
          repeatPass: 0,
        ),
      ],
    );

    expect(
      () => validator.validate(invalidBeatPatternBarSong),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validator.validate(invalidBeatPatternRepeatPassSong),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects beat patterns that exceed beats per bar at that bar', () {
    final invalidBeatPatternAccentsSong = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      beatPatterns: const [
        SongBarBeatPattern(
          id: 'pattern-1',
          barIndex: 1,
          accents: [
            AccentLevel.high,
            AccentLevel.normal,
            AccentLevel.normal,
            AccentLevel.normal,
            AccentLevel.normal,
          ],
          subdivision: Subdivision.four,
        ),
      ],
    );

    expect(
      () => validator.validate(invalidBeatPatternAccentsSong),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects beat patterns that exceed beats per bar from a tempo change', () {
    final invalidBeatPatternAccentsSong = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      tempoChanges: const [
        SongTempoChange(
          id: 'tempo-1',
          barIndex: 8,
          bpm: 128,
          beatsPerBar: 3,
          beatUnit: 4,
        ),
      ],
      beatPatterns: const [
        SongBarBeatPattern(
          id: 'pattern-1',
          barIndex: 8,
          accents: [
            AccentLevel.high,
            AccentLevel.normal,
            AccentLevel.normal,
            AccentLevel.normal,
          ],
          subdivision: Subdivision.one,
        ),
      ],
    );

    expect(
      () => validator.validate(invalidBeatPatternAccentsSong),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects invalid linked audio fields', () {
    final invalidOffsetSong = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      linkedAudio: const LinkedAudioFile(
        filePath: '/tmp/track.mp3',
        displayName: 'Track',
        offsetMilliseconds: -1,
      ),
    );
    final invalidVolumeSong = Song(
      id: 'song-2',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      linkedAudio: const LinkedAudioFile(
        filePath: '/tmp/track.mp3',
        displayName: 'Track',
        volumePercent: 101,
      ),
    );

    expect(
      () => validator.validate(invalidOffsetSong),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validator.validate(invalidVolumeSong),
      throwsA(isA<ArgumentError>()),
    );
  });
}
