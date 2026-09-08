import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/song_playback_timeline_mapper.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/subdivision.dart';

void main() {
  group('SongPlaybackTimelineMapper.calculateSongDuration', () {
    const mapper = SongPlaybackTimelineMapper();

    test('sums bar durations across tempo changes', () {
      final song = _buildSong(
        endBar: 3,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 3,
            bpm: 60,
            beatsPerBar: 3,
            beatUnit: 4,
          ),
        ],
      );

      final duration = mapper.calculateSongDuration(song);

      expect(duration, const Duration(seconds: 7));
    });

    test('accounts for beatUnit in duration calculation', () {
      // 120 bpm, 4 beats, beatUnit=8 → beat = 0.25s, bar = 1s.
      // 2 bars = 2s.
      final song = Song(
        id: 'song-1',
        title: 'Test',
        createdAt: DateTime(2024),
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 8,
        countInBars: 0,
        endBar: 2,
      );

      final duration = mapper.calculateSongDuration(song);

      // (60/120) * (4/8) = 0.25s per beat, 4 beats = 1s per bar, 2 bars = 2s.
      expect(duration, const Duration(seconds: 2));
    });
  });

  group('SongPlaybackTimelineMapper.mapElapsed', () {
    const mapper = SongPlaybackTimelineMapper();

    test('starts at the first bar, beat, and pulse', () {
      final position = mapper.mapElapsed(_buildSong(), Duration.zero);

      expect(position.barIndex, 1);
      expect(position.beatIndex, 1);
      expect(position.pulseIndex, 1);
      expect(position.isSongComplete, isFalse);
    });

    test('maps elapsed time across beat and bar boundaries', () {
      final song = _buildSong(endBar: 4);

      final position = mapper.mapElapsed(song, const Duration(milliseconds: 2500));

      expect(position.barIndex, 2);
      expect(position.beatIndex, 2);
      expect(position.pulseIndex, 1);
      expect(position.elapsedInBar, const Duration(milliseconds: 500));
      expect(position.elapsedInBeat, Duration.zero);
    });

    test('respects per-bar subdivision when calculating pulse position', () {
      final song = _buildSong(
        beatPatterns: const [
          SongBarBeatPattern(
            id: 'pattern-1',
            barIndex: 2,
            accents: [],
            subdivision: Subdivision.four,
          ),
        ],
      );

      final position = mapper.mapElapsed(song, const Duration(milliseconds: 2375));

      expect(position.barIndex, 2);
      expect(position.beatIndex, 1);
      expect(position.pulseIndex, 4);
      expect(position.subdivision, 4);
      expect(position.elapsedInPulse, Duration.zero);
    });

    test('uses updated tempo and meter after a tempo change', () {
      final song = _buildSong(
        endBar: 4,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 3,
            bpm: 60,
            beatsPerBar: 3,
            beatUnit: 8,
          ),
        ],
      );

      // Bars 1-2: 120bpm, 4/4 → 0.5s/beat, 2s/bar → 4s total.
      // Bar 3: 60bpm, 3/8 → (60/60)*(4/8) = 0.5s/beat.
      // At 4100ms: bar 3, 100ms elapsed → beat 1, pulse 1.
      final position = mapper.mapElapsed(song, const Duration(milliseconds: 4100));

      expect(position.barIndex, 3);
      expect(position.beatIndex, 1);
      expect(position.pulseIndex, 1);
      expect(position.bpm, 60);
      expect(position.beatsPerBar, 3);
      expect(position.beatUnit, 8);
    });

    test('clamps to the completed song position at the end', () {
      final song = _buildSong(endBar: 2);

      final position = mapper.mapElapsed(song, const Duration(seconds: 4));

      expect(position.barIndex, 2);
      expect(position.beatIndex, 4);
      expect(position.pulseIndex, 1);
      expect(position.isSongComplete, isTrue);
      expect(position.elapsed, position.songDuration);
    });

    test('throws for negative elapsed time', () {
      expect(
        () => mapper.mapElapsed(_buildSong(), const Duration(milliseconds: -1)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

Song _buildSong({
  int endBar = 2,
  List<SongTempoChange> tempoChanges = const [],
  List<SongBarBeatPattern> beatPatterns = const [],
}) {
  return Song(
    id: 'song-1',
    title: 'Timeline Test',
    createdAt: DateTime(2026, 3, 9),
    startBpm: 120,
    beatsPerBar: 4,
    beatUnit: 4,
    countInBars: 1,
    endBar: endBar,
    tempoChanges: tempoChanges,
    beatPatterns: beatPatterns,
  );
}
