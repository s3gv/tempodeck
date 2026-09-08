import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/tempo_map_evaluator.dart';
import 'package:tempodeck/core/domain/song.dart';

void main() {
  group('TempoMapEvaluator.resolveAtBar', () {
    const evaluator = TempoMapEvaluator();

    test('returns the song start tempo before the first change', () {
      final song = _buildSong(
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-2',
            barIndex: 5,
            bpm: 140,
            beatsPerBar: 3,
            beatUnit: 4,
          ),
        ],
      );

      final state = evaluator.resolveAtBar(song, 4);

      expect(state.barIndex, 1);
      expect(state.bpm, 120);
      expect(state.beatsPerBar, 4);
      expect(state.beatUnit, 4);
    });

    test('applies the latest tempo change at or before the requested bar', () {
      final song = _buildSong(
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-2',
            barIndex: 8,
            bpm: 96,
            beatsPerBar: 7,
            beatUnit: 8,
          ),
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 3,
            bpm: 132,
            beatsPerBar: 3,
            beatUnit: 4,
          ),
        ],
      );

      final state = evaluator.resolveAtBar(song, 9);

      expect(state.barIndex, 8);
      expect(state.bpm, 96);
      expect(state.beatsPerBar, 7);
      expect(state.beatUnit, 8);
    });

    test('uses the last duplicate change for the same bar deterministically', () {
      final song = _buildSong(
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 6,
            bpm: 126,
            beatsPerBar: 5,
            beatUnit: 4,
          ),
          SongTempoChange(
            id: 'tempo-2',
            barIndex: 6,
            bpm: 144,
            beatsPerBar: 6,
            beatUnit: 8,
          ),
        ],
      );

      final state = evaluator.resolveAtBar(song, 6);

      expect(state.barIndex, 6);
      expect(state.bpm, 144);
      expect(state.beatsPerBar, 6);
      expect(state.beatUnit, 8);
    });

    test('throws when requesting a bar outside the song range', () {
      final song = _buildSong();

      expect(
        () => evaluator.resolveAtBar(song, 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => evaluator.resolveAtBar(song, 17),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TempoMapEvaluator.buildSegments', () {
    const evaluator = TempoMapEvaluator();

    test('builds contiguous segments from the song start to the end bar', () {
      final song = _buildSong(
        endBar: 12,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 4,
            bpm: 132,
            beatsPerBar: 3,
            beatUnit: 4,
          ),
          SongTempoChange(
            id: 'tempo-2',
            barIndex: 9,
            bpm: 108,
            beatsPerBar: 6,
            beatUnit: 8,
          ),
        ],
      );

      final segments = evaluator.buildSegments(song);

      expect(segments.length, 3);

      expect(segments[0].startBarIndex, 1);
      expect(segments[0].endBarIndex, 3);
      expect(segments[0].state.bpm, 120);

      expect(segments[1].startBarIndex, 4);
      expect(segments[1].endBarIndex, 8);
      expect(segments[1].state.beatsPerBar, 3);

      expect(segments[2].startBarIndex, 9);
      expect(segments[2].endBarIndex, 12);
      expect(segments[2].state.beatUnit, 8);
    });

    test('treats a bar-1 tempo change as the active initial segment', () {
      final song = _buildSong(
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 1,
            bpm: 150,
            beatsPerBar: 7,
            beatUnit: 8,
          ),
        ],
      );

      final segments = evaluator.buildSegments(song);

      expect(segments.length, 1);
      expect(segments.single.startBarIndex, 1);
      expect(segments.single.endBarIndex, 16);
      expect(segments.single.state.bpm, 150);
      expect(segments.single.state.beatsPerBar, 7);
      expect(segments.single.state.beatUnit, 8);
    });

    test('collapses duplicate tempo changes on the same bar into one segment', () {
      final song = _buildSong(
        endBar: 12,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 6,
            bpm: 126,
            beatsPerBar: 5,
            beatUnit: 4,
          ),
          SongTempoChange(
            id: 'tempo-2',
            barIndex: 6,
            bpm: 144,
            beatsPerBar: 6,
            beatUnit: 8,
          ),
        ],
      );

      final segments = evaluator.buildSegments(song);

      expect(segments.length, 2);
      expect(segments[0].startBarIndex, 1);
      expect(segments[0].endBarIndex, 5);
      expect(segments[1].startBarIndex, 6);
      expect(segments[1].endBarIndex, 12);
      expect(segments[1].state.bpm, 144);
      expect(segments[1].state.beatsPerBar, 6);
      expect(segments[1].state.beatUnit, 8);
    });

    test('throws when a tempo change points outside the song range', () {
      final song = _buildSong(
        endBar: 4,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 5,
            bpm: 150,
            beatsPerBar: 7,
            beatUnit: 8,
          ),
        ],
      );

      expect(
        () => evaluator.buildSegments(song),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

Song _buildSong({
  int endBar = 16,
  List<SongTempoChange> tempoChanges = const [],
}) {
  return Song(
    id: 'song-1',
    title: 'Test Song',
    createdAt: DateTime(2026, 3, 9),
    startBpm: 120,
    beatsPerBar: 4,
    beatUnit: 4,
    countInBars: 1,
    endBar: endBar,
    tempoChanges: tempoChanges,
  );
}
