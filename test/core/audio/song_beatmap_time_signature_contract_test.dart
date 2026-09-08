import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/metronome_click_engine.dart';
import 'package:tempodeck/core/audio/song_playback_beatmap.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';

void main() {
  group('Beatmap time signature contract', () {
    test('bars after a time event carry the changed time signature', () {
      final song = Song(
        id: 'song-1',
        title: 'Time Sig Song',
        createdAt: DateTime(2024),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 5,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 3,
            bpm: 200,
            beatsPerBar: 9,
            beatUnit: 8,
          ),
        ],
      );

      final beatmap = const SongPlaybackBeatmapBuilder().build(song);

      expect(beatmap.totalPlaybackBars, 5);

      // Bars 1-2: original 4/4 @ 100 BPM
      for (final barIndex in [1, 2]) {
        final entry = beatmap.entryForPlaybackBar(barIndex);
        expect(entry.bpm, 100, reason: 'bar $barIndex BPM');
        expect(entry.beatsPerBar, 4, reason: 'bar $barIndex beatsPerBar');
        expect(entry.beatUnit, 4, reason: 'bar $barIndex beatUnit');
      }

      // Bar 3: time event → 9/8 @ 200 BPM
      final bar3 = beatmap.entryForPlaybackBar(3);
      expect(bar3.bpm, 200, reason: 'bar 3 BPM after time event');
      expect(bar3.beatsPerBar, 9, reason: 'bar 3 beatsPerBar after time event');
      expect(bar3.beatUnit, 8, reason: 'bar 3 beatUnit after time event');

      // Bars 4-5: must CARRY 9/8 @ 200 BPM (no revert to 4/4)
      for (final barIndex in [4, 5]) {
        final entry = beatmap.entryForPlaybackBar(barIndex);
        expect(entry.bpm, 200, reason: 'bar $barIndex BPM must stay 200');
        expect(
          entry.beatsPerBar,
          9,
          reason: 'bar $barIndex beatsPerBar must stay 9 (NOT revert to 4)',
        );
        expect(
          entry.beatUnit,
          8,
          reason: 'bar $barIndex beatUnit must stay 8 (NOT revert to 4)',
        );
      }
    });

    test('count-in bars use bar-1 time signature, not the song default', () {
      final song = Song(
        id: 'song-1',
        title: 'Count-in Sig Song',
        createdAt: DateTime(2024),
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 2,
        endBar: 4,
        tempoChanges: const [],
      );

      final beatmap = const SongPlaybackBeatmapBuilder().build(song);

      // Count-in bars use bar-1 settings
      for (final pbIndex in [1, 2]) {
        final entry = beatmap.entryForPlaybackBar(pbIndex);
        expect(entry.barKind, SongBeatmapBarKind.countIn);
        expect(entry.beatsPerBar, 4);
        expect(entry.beatUnit, 4);
        expect(entry.bpm, 120);
      }
    });

    test('time event at bar 1 applies to count-in bars', () {
      // A tempo change at bar 1 defines the "starting" tempo for the song,
      // and count-in bars should pick up bar-1's resolved config.
      final song = Song(
        id: 'song-1',
        title: 'Tempo at bar 1',
        createdAt: DateTime(2024),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 2,
        endBar: 4,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 1,
            bpm: 140,
            beatsPerBar: 7,
            beatUnit: 8,
          ),
        ],
      );

      final beatmap = const SongPlaybackBeatmapBuilder().build(song);

      // Count-in bars resolve bar 1's tempo config
      final countIn1 = beatmap.entryForPlaybackBar(1);
      expect(countIn1.barKind, SongBeatmapBarKind.countIn);
      expect(countIn1.bpm, 140);
      expect(countIn1.beatsPerBar, 7);
      expect(countIn1.beatUnit, 8);
    });

    test('multiple sequential time events each carry forward correctly', () {
      final song = Song(
        id: 'song-1',
        title: 'Multi Tempo Song',
        createdAt: DateTime(2024),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 8,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 3,
            bpm: 150,
            beatsPerBar: 3,
            beatUnit: 8,
          ),
          SongTempoChange(
            id: 'tempo-2',
            barIndex: 6,
            bpm: 80,
            beatsPerBar: 6,
            beatUnit: 4,
          ),
        ],
      );

      final beatmap = const SongPlaybackBeatmapBuilder().build(song);

      // Bars 1-2: 4/4 @ 100 BPM
      expect(beatmap.entryForPlaybackBar(1).beatsPerBar, 4);
      expect(beatmap.entryForPlaybackBar(2).beatsPerBar, 4);

      // Bars 3-5: 3/8 @ 150 BPM
      for (final barIndex in [3, 4, 5]) {
        final entry = beatmap.entryForPlaybackBar(barIndex);
        expect(entry.bpm, 150, reason: 'bar $barIndex');
        expect(entry.beatsPerBar, 3, reason: 'bar $barIndex');
        expect(entry.beatUnit, 8, reason: 'bar $barIndex');
      }

      // Bars 6-8: 6/4 @ 80 BPM
      for (final barIndex in [6, 7, 8]) {
        final entry = beatmap.entryForPlaybackBar(barIndex);
        expect(entry.bpm, 80, reason: 'bar $barIndex');
        expect(entry.beatsPerBar, 6, reason: 'bar $barIndex');
        expect(entry.beatUnit, 4, reason: 'bar $barIndex');
      }
    });

    test('loop bars carry time signature across repeat passes', () {
      final song = Song(
        id: 'song-1',
        title: 'Loop Sig Song',
        createdAt: DateTime(2024),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 6,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 2,
            bpm: 200,
            beatsPerBar: 7,
            beatUnit: 8,
          ),
        ],
        loops: const [
          SongLoop(
            id: 'loop-1',
            startBar: 2,
            endBar: 4,
            repeatCount: 1,
          ),
        ],
      );

      final beatmap = const SongPlaybackBeatmapBuilder().build(song);

      // Bar 1: 4/4 @ 100
      expect(beatmap.entryForPlaybackBar(1).beatsPerBar, 4);

      // Loop pass 1, bars 2-4 (pb 2-4): 7/8 @ 200
      for (final pbIndex in [2, 3, 4]) {
        final entry = beatmap.entryForPlaybackBar(pbIndex);
        expect(entry.beatsPerBar, 7, reason: 'pass 1, pb $pbIndex');
        expect(entry.beatUnit, 8, reason: 'pass 1, pb $pbIndex');
      }

      // Loop pass 2, bars 2-4 (pb 5-7): must still be 7/8 @ 200
      for (final pbIndex in [5, 6, 7]) {
        final entry = beatmap.entryForPlaybackBar(pbIndex);
        expect(
          entry.beatsPerBar,
          7,
          reason: 'pass 2, pb $pbIndex: must stay 7/8 not revert to 4/4',
        );
        expect(entry.beatUnit, 8, reason: 'pass 2, pb $pbIndex');
      }

      // Post-loop bars 5-6 (pb 8-9): carry 7/8 @ 200
      for (final pbIndex in [8, 9]) {
        final entry = beatmap.entryForPlaybackBar(pbIndex);
        expect(
          entry.beatsPerBar,
          7,
          reason: 'post-loop pb $pbIndex: must carry 7/8',
        );
        expect(entry.beatUnit, 8, reason: 'post-loop pb $pbIndex');
      }
    });

    test('loop bars with .2/.3 labels carry correct time signature', () {
      final song = Song(
        id: 'song-1',
        title: 'Loop Label Song',
        createdAt: DateTime(2024),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 4,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 1,
            bpm: 120,
            beatsPerBar: 5,
            beatUnit: 8,
          ),
        ],
        loops: const [
          SongLoop(
            id: 'loop-1',
            startBar: 1,
            endBar: 2,
            repeatCount: 2,
          ),
        ],
      );

      final beatmap = const SongPlaybackBeatmapBuilder().build(song);

      // Pass 1: bars 1, 2 → 5/8 @ 120
      expect(beatmap.entryForPlaybackBar(1).barLabel, '1');
      expect(beatmap.entryForPlaybackBar(1).beatsPerBar, 5);
      expect(beatmap.entryForPlaybackBar(2).barLabel, '2');
      expect(beatmap.entryForPlaybackBar(2).beatsPerBar, 5);

      // Pass 2: bars 1.2, 2.2 → 5/8 @ 120
      expect(beatmap.entryForPlaybackBar(3).barLabel, '1.2');
      expect(beatmap.entryForPlaybackBar(3).beatsPerBar, 5);
      expect(beatmap.entryForPlaybackBar(4).barLabel, '2.2');
      expect(beatmap.entryForPlaybackBar(4).beatsPerBar, 5);

      // Pass 3: bars 1.3, 2.3 → 5/8 @ 120
      expect(beatmap.entryForPlaybackBar(5).barLabel, '1.3');
      expect(beatmap.entryForPlaybackBar(5).beatsPerBar, 5);
      expect(beatmap.entryForPlaybackBar(6).barLabel, '2.3');
      expect(beatmap.entryForPlaybackBar(6).beatsPerBar, 5);
    });
  });

  group('Beatmap-driven transport contract', () {
    test('engine ticks carry correct beatsPerBar after time event at bar 3', () {
      final song = Song(
        id: 'song-1',
        title: 'Transport Song',
        createdAt: DateTime(2024),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 5,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 3,
            bpm: 200,
            beatsPerBar: 9,
            beatUnit: 8,
          ),
        ],
      );

      final beatmap = const SongPlaybackBeatmapBuilder().build(song);

      // Build transport sequence exactly as the controller does
      final sequence = <MetronomeClickEngineConfig>[
        for (var i = 1; i <= beatmap.totalPlaybackBars; i++)
          MetronomeClickEngineConfig(
            bpm: beatmap.entryForPlaybackBar(i).bpm,
            beatsPerBar: beatmap.entryForPlaybackBar(i).beatsPerBar,
            beatUnit: beatmap.entryForPlaybackBar(i).beatUnit,
            subdivision: beatmap.entryForPlaybackBar(i).subdivision,
            accentPattern: beatmap.entryForPlaybackBar(i).accentPattern,
          ),
      ];

      // Run through the MetronomeClickEngine with this sequence
      final output = _SilentClickOutput();
      final scheduler = _ImmediateScheduler();
      final runClock = _FakeRunClock();
      final engine = MetronomeClickEngine(
        output: output,
        scheduler: scheduler,
        runClock: runClock,
      );

      final ticks = <MetronomeBeatTick>[];
      engine.start(
        sequence.first,
        onBeat: ticks.add,
        configSequence: sequence,
      );

      // Play through all bars: 2 bars of 4/4 + 3 bars of 9/8
      // Total beats: 2*4 + 3*9 = 8 + 27 = 35
      // First tick is emitted on start, then we need 34 more scheduler runs
      for (var i = 0; i < 34; i++) {
        scheduler.runNext();
      }

      engine.stop();

      // Verify bar-by-bar that beatsPerBar is correct
      final ticksByBar = <int, List<MetronomeBeatTick>>{};
      for (final tick in ticks) {
        ticksByBar.putIfAbsent(tick.barIndex, () => []).add(tick);
      }

      // Bars 1-2: beatsPerBar=4
      for (final bar in [1, 2]) {
        final barTicks = ticksByBar[bar]!;
        expect(barTicks.length, 4, reason: 'bar $bar should have 4 beats');
        for (final tick in barTicks) {
          expect(tick.beatsPerBar, 4, reason: 'bar $bar tick beatsPerBar');
          expect(tick.beatUnit, 4, reason: 'bar $bar tick beatUnit');
          expect(tick.bpm, 100, reason: 'bar $bar tick bpm');
        }
      }

      // Bars 3-5: beatsPerBar=9
      for (final bar in [3, 4, 5]) {
        final barTicks = ticksByBar[bar]!;
        expect(barTicks.length, 9, reason: 'bar $bar should have 9 beats');
        for (final tick in barTicks) {
          expect(
            tick.beatsPerBar,
            9,
            reason: 'bar $bar tick beatsPerBar must stay 9 (NOT revert to 4)',
          );
          expect(tick.beatUnit, 8, reason: 'bar $bar tick beatUnit');
          expect(tick.bpm, 200, reason: 'bar $bar tick bpm');
        }
      }

      // No bar 6 should exist (only 5 bars)
      expect(ticksByBar.containsKey(6), isFalse);
    });

    // The outgoing bar must always complete at its own beat-unit duration.
    // The new time signature only kicks in on beat 1 of the new bar. This
    // must hold for every direction of beat-unit change.
    //
    // Expected transition interval = 60 / bpm * (4 / outgoingBeatUnit)
    //   (in seconds, converted to microseconds for comparison).
    for (final testCase in [
      (
        name: '4/4 → 9/8',
        from: const MetronomeClickEngineConfig(bpm: 120, beatsPerBar: 4, beatUnit: 4),
        to: const MetronomeClickEngineConfig(bpm: 120, beatsPerBar: 9, beatUnit: 8),
      ),
      (
        name: '9/8 → 4/4',
        from: const MetronomeClickEngineConfig(bpm: 120, beatsPerBar: 9, beatUnit: 8),
        to: const MetronomeClickEngineConfig(bpm: 120, beatsPerBar: 4, beatUnit: 4),
      ),
      (
        name: '3/4 → 6/8',
        from: const MetronomeClickEngineConfig(bpm: 120, beatsPerBar: 3, beatUnit: 4),
        to: const MetronomeClickEngineConfig(bpm: 120, beatsPerBar: 6, beatUnit: 8),
      ),
      (
        name: '6/8 → 3/4',
        from: const MetronomeClickEngineConfig(bpm: 120, beatsPerBar: 6, beatUnit: 8),
        to: const MetronomeClickEngineConfig(bpm: 120, beatsPerBar: 3, beatUnit: 4),
      ),
      (
        name: '7/8 → 5/4',
        from: const MetronomeClickEngineConfig(bpm: 120, beatsPerBar: 7, beatUnit: 8),
        to: const MetronomeClickEngineConfig(bpm: 120, beatsPerBar: 5, beatUnit: 4),
      ),
      (
        name: '5/4 → 7/8',
        from: const MetronomeClickEngineConfig(bpm: 120, beatsPerBar: 5, beatUnit: 4),
        to: const MetronomeClickEngineConfig(bpm: 120, beatsPerBar: 7, beatUnit: 8),
      ),
      (
        name: '4/4@100 → 9/8@200 (BPM and beat unit change)',
        from: const MetronomeClickEngineConfig(bpm: 100, beatsPerBar: 4, beatUnit: 4),
        to: const MetronomeClickEngineConfig(bpm: 200, beatsPerBar: 9, beatUnit: 8),
      ),
      (
        name: '6/8@160 → 3/4@80 (faster to slower)',
        from: const MetronomeClickEngineConfig(bpm: 160, beatsPerBar: 6, beatUnit: 8),
        to: const MetronomeClickEngineConfig(bpm: 80, beatsPerBar: 3, beatUnit: 4),
      ),
    ]) {
      test(
          'outgoing bar completes at its own beat-unit duration: '
          '${testCase.name}', () {
        final output = _SilentClickOutput();
        final scheduler = _IntervalCapturingScheduler();
        final runClock = _FakeRunClock();
        final engine = MetronomeClickEngine(
          output: output,
          scheduler: scheduler,
          runClock: runClock,
        );

        final ticks = <MetronomeBeatTick>[];
        engine.start(
          testCase.from,
          onBeat: ticks.add,
          configSequence: [testCase.from, testCase.to],
        );

        // Advance through bar 1 until the last beat has been emitted.
        // start() already emitted beat 1, so we need beatsPerBar - 1 more.
        for (var i = 0; i < testCase.from.beatsPerBar - 1; i++) {
          scheduler.runNext();
        }

        // The interval scheduled after the last beat of bar 1 must use the
        // outgoing bar's own timing (BPM and beat unit), not the new bar's.
        const secondsPerMinute = 60.0;
        const quarterNotesPerWholeNote = 4;
        final expectedMicroseconds =
            (secondsPerMinute /
                    testCase.from.bpm *
                    (quarterNotesPerWholeNote / testCase.from.beatUnit) *
                    Duration.microsecondsPerSecond)
                .round();

        expect(
          scheduler.lastScheduledInterval.inMicroseconds,
          expectedMicroseconds,
          reason:
              '${testCase.name}: transition interval must use outgoing beat '
              'unit (${testCase.from.beatUnit}), got '
              '${scheduler.lastScheduledInterval.inMilliseconds}ms',
        );

        // Verify bar 1 completed with all beats.
        final bar1Ticks = ticks.where((t) => t.barIndex == 1).toList();
        expect(
          bar1Ticks.length,
          testCase.from.beatsPerBar,
          reason:
              '${testCase.name}: bar 1 must have ${testCase.from.beatsPerBar} '
              'beats before switching',
        );

        engine.stop();
      });
    }

    test('engine ticks handle count-in then time event at bar 3 correctly', () {
      final song = Song(
        id: 'song-1',
        title: 'Count-in Time Event Song',
        createdAt: DateTime(2024),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 2,
        endBar: 5,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 3,
            bpm: 200,
            beatsPerBar: 9,
            beatUnit: 8,
          ),
        ],
      );

      final beatmap = const SongPlaybackBeatmapBuilder().build(song);

      // Build transport sequence from playbackBarIndex 1
      final sequence = <MetronomeClickEngineConfig>[
        for (var i = 1; i <= beatmap.totalPlaybackBars; i++)
          MetronomeClickEngineConfig(
            bpm: beatmap.entryForPlaybackBar(i).bpm,
            beatsPerBar: beatmap.entryForPlaybackBar(i).beatsPerBar,
            beatUnit: beatmap.entryForPlaybackBar(i).beatUnit,
            subdivision: beatmap.entryForPlaybackBar(i).subdivision,
            accentPattern: beatmap.entryForPlaybackBar(i).accentPattern,
          ),
      ];

      final output = _SilentClickOutput();
      final scheduler = _ImmediateScheduler();
      final runClock = _FakeRunClock();
      final engine = MetronomeClickEngine(
        output: output,
        scheduler: scheduler,
        runClock: runClock,
      );

      final ticks = <MetronomeBeatTick>[];
      engine.start(
        sequence.first,
        onBeat: ticks.add,
        configSequence: sequence,
      );

      // 2 count-in bars (4/4) + 2 notation bars (4/4) + 3 notation bars (9/8)
      // = 2*4 + 2*4 + 3*9 = 8 + 8 + 27 = 43 beats
      // First tick on start, need 42 more
      for (var i = 0; i < 42; i++) {
        scheduler.runNext();
      }
      engine.stop();

      final ticksByBar = <int, List<MetronomeBeatTick>>{};
      for (final tick in ticks) {
        ticksByBar.putIfAbsent(tick.barIndex, () => []).add(tick);
      }

      // Engine bars 1-2 (count-in): 4/4 @ 100 BPM
      for (final bar in [1, 2]) {
        expect(ticksByBar[bar]!.length, 4, reason: 'count-in bar $bar');
        expect(ticksByBar[bar]!.first.bpm, 100);
        expect(ticksByBar[bar]!.first.beatsPerBar, 4);
      }

      // Engine bars 3-4 (notation bars 1-2): 4/4 @ 100 BPM
      for (final bar in [3, 4]) {
        expect(ticksByBar[bar]!.length, 4, reason: 'notation bar $bar');
        expect(ticksByBar[bar]!.first.bpm, 100);
        expect(ticksByBar[bar]!.first.beatsPerBar, 4);
      }

      // Engine bars 5-7 (notation bars 3-5): 9/8 @ 200 BPM
      for (final bar in [5, 6, 7]) {
        expect(ticksByBar[bar]!.length, 9, reason: 'bar $bar should have 9 beats');
        for (final tick in ticksByBar[bar]!) {
          expect(
            tick.beatsPerBar,
            9,
            reason: 'engine bar $bar must carry 9/8 time signature',
          );
          expect(tick.bpm, 200);
        }
      }
    });

    test('engine ticks with loop + time event inside loop', () {
      final song = Song(
        id: 'song-1',
        title: 'Loop Time Event Song',
        createdAt: DateTime(2024),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 5,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 2,
            bpm: 150,
            beatsPerBar: 3,
            beatUnit: 8,
          ),
        ],
        loops: const [
          SongLoop(
            id: 'loop-1',
            startBar: 1,
            endBar: 3,
            repeatCount: 1,
          ),
        ],
      );

      final beatmap = const SongPlaybackBeatmapBuilder().build(song);

      // Verify the beatmap structure:
      // Pass 1: bars 1(4/4), 2(3/8 tempo change), 3(3/8 carry)
      // Pass 2: bars 1.2(re-evaluated), 2.2(3/8 tempo change), 3.2(3/8 carry)
      // Post-loop: bars 4(3/8 carry), 5(3/8 carry)

      // Check pass 2 bars carry 3/8 not revert to 4/4
      // Pass 2 starts at pb 4 (after pass 1: pb 1,2,3)
      final pass2Bar1 = beatmap.entryForPlaybackBar(4);
      expect(pass2Bar1.barLabel, '1.2');
      // Bar 1 in pass 2: rootConfigAtBar(1, 2) → no tempo change at bar 1
      // So it uses the song's startBpm/beatsPerBar: 4/4 @ 100 BPM
      // (the tempo change at bar 2 hasn't been hit yet in pass 2)
      expect(pass2Bar1.beatsPerBar, 4, reason: 'bar 1 in pass 2 is before tempo change');
      expect(pass2Bar1.bpm, 100);

      final pass2Bar2 = beatmap.entryForPlaybackBar(5);
      expect(pass2Bar2.barLabel, '2.2');
      expect(pass2Bar2.beatsPerBar, 3, reason: 'bar 2 in pass 2 hits tempo change');
      expect(pass2Bar2.bpm, 150);

      final pass2Bar3 = beatmap.entryForPlaybackBar(6);
      expect(pass2Bar3.barLabel, '3.2');
      expect(pass2Bar3.beatsPerBar, 3, reason: 'bar 3 in pass 2 carries from bar 2');
      expect(pass2Bar3.bpm, 150);

      // Post-loop bars carry the config from the last loop pass
      final postLoop4 = beatmap.entryForPlaybackBar(7);
      expect(postLoop4.barLabel, '4');
      expect(postLoop4.beatsPerBar, 3, reason: 'post-loop bar carries 3/8');
      expect(postLoop4.bpm, 150);
    });
  });

  group('Beatmap accent pattern contract', () {
    test('default accent pattern length matches beatsPerBar after time event', () {
      final song = Song(
        id: 'song-1',
        title: 'Accent Pattern Song',
        createdAt: DateTime(2024),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 5,
        tempoChanges: const [
          SongTempoChange(
            id: 'tempo-1',
            barIndex: 3,
            bpm: 200,
            beatsPerBar: 9,
            beatUnit: 8,
          ),
        ],
      );

      final beatmap = const SongPlaybackBeatmapBuilder().build(song);

      // Bars 1-2: 4 accents
      expect(beatmap.entryForPlaybackBar(1).accentPattern.length, 4);
      expect(beatmap.entryForPlaybackBar(2).accentPattern.length, 4);

      // Bars 3-5: 9 accents (default pattern for 9 beats)
      for (final barIndex in [3, 4, 5]) {
        expect(
          beatmap.entryForPlaybackBar(barIndex).accentPattern.length,
          9,
          reason: 'bar $barIndex must have 9 accents for 9/8 time',
        );
      }
    });
  });
}

class _SilentClickOutput implements MetronomeClickOutput {
  @override
  void playHighBeat() {}
  @override
  void playNormalBeat() {}
  @override
  void playLowBeat() {}
  @override
  void playSubdivisionPulse() {}
}

class _IntervalCapturingScheduler implements MetronomeScheduler {
  final List<_ImmediateTask> _tasks = [];
  final List<Duration> scheduledDelays = [];

  /// The interval for the most recently scheduled tick, derived from the
  /// difference between consecutive drift-compensated delays. Because the
  /// test uses a [_FakeRunClock] with zero elapsed time, the drift
  /// compensator returns the cumulative sum of all intervals. The difference
  /// between consecutive cumulative values is the raw interval.
  Duration get lastScheduledInterval {
    if (scheduledDelays.length < 2) {
      return scheduledDelays.last;
    }
    return scheduledDelays.last - scheduledDelays[scheduledDelays.length - 2];
  }

  @override
  MetronomeScheduledTask schedule({
    required Duration delay,
    required void Function() callback,
  }) {
    scheduledDelays.add(delay);
    final task = _ImmediateTask(callback);
    _tasks.add(task);
    return task;
  }

  void runNext() {
    final task = _tasks.firstWhere((t) => !t.cancelled);
    task.callback();
  }
}

class _ImmediateScheduler implements MetronomeScheduler {
  final List<_ImmediateTask> _tasks = [];

  @override
  MetronomeScheduledTask schedule({
    required Duration delay,
    required void Function() callback,
  }) {
    final task = _ImmediateTask(callback);
    _tasks.add(task);
    return task;
  }

  void runNext() {
    final task = _tasks.firstWhere((t) => !t.cancelled);
    task.callback();
  }
}

class _ImmediateTask implements MetronomeScheduledTask {
  _ImmediateTask(this.callback);
  final void Function() callback;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
  }
}

class _FakeRunClock implements MetronomeRunClock {
  Duration _elapsed = Duration.zero;

  @override
  Duration get elapsed => _elapsed;

  @override
  void reset() => _elapsed = Duration.zero;

  @override
  void start() {}

  @override
  void stop() {}
}
