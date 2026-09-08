import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/metronome_click_engine.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/subdivision.dart';

void main() {
  group('MetronomeClickEngine', () {
    late FakeMetronomeClickOutput output;
    late FakeMetronomeScheduler scheduler;
    late FakeMetronomeRunClock runClock;
    late MetronomeClickEngine engine;

    setUp(() {
      output = FakeMetronomeClickOutput();
      scheduler = FakeMetronomeScheduler();
      runClock = FakeMetronomeRunClock();
      engine = MetronomeClickEngine(
        output: output,
        scheduler: scheduler,
        runClock: runClock,
      );
    });

    test('plays the first beat immediately when started', () {
      final ticks = <MetronomeBeatTick>[];

      engine.start(
        const MetronomeClickEngineConfig(
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
          subdivision: Subdivision.one,
          accentPattern: [AccentLevel.high],
        ),
        onBeat: ticks.add,
      );

      expect(output.playedAccents, [AccentLevel.high]);
      expect(ticks.single.barIndex, 1);
      expect(ticks.single.beatIndex, 1);
      expect(ticks.single.pulseIndex, 1);
      expect(ticks.single.pulseCount, 1);
      expect(ticks.single.accentLevel, AccentLevel.high);
      expect(scheduler.scheduledDelays.single, const Duration(milliseconds: 500));
    });

    test('pads short accent patterns with normal accents for remaining beats', () {
      final ticks = <MetronomeBeatTick>[];

      engine.start(
        const MetronomeClickEngineConfig(
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
          subdivision: Subdivision.one,
          accentPattern: [AccentLevel.high, AccentLevel.low],
        ),
        onBeat: ticks.add,
      );

      scheduler.runNext();
      scheduler.runNext();
      scheduler.runNext();
      scheduler.runNext();

      expect(
        output.playedAccents,
        [
          AccentLevel.high,
          AccentLevel.low,
          AccentLevel.normal,
          AccentLevel.normal,
          AccentLevel.high,
        ],
      );
      expect(
        ticks
            .map((tick) => (tick.barIndex, tick.beatIndex, tick.accentLevel))
            .toList(),
        [
          (1, 1, AccentLevel.high),
          (1, 2, AccentLevel.low),
          (1, 3, AccentLevel.normal),
          (1, 4, AccentLevel.normal),
          (2, 1, AccentLevel.high),
        ],
      );
    });

    test('does not emit audio for mute accents but still advances the beat', () {
      final ticks = <MetronomeBeatTick>[];

      engine.start(
        const MetronomeClickEngineConfig(
          bpm: 100,
          beatsPerBar: 2,
          beatUnit: 4,
          subdivision: Subdivision.one,
          accentPattern: [AccentLevel.mute, AccentLevel.high],
        ),
        onBeat: ticks.add,
      );

      scheduler.runNext();

      expect(output.playedAccents, [AccentLevel.high]);
      expect(
        ticks.map((tick) => tick.accentLevel).toList(),
        [AccentLevel.mute, AccentLevel.high],
      );
    });

    test('uses the beat unit when calculating beat duration', () {
      engine.start(
        const MetronomeClickEngineConfig(
          bpm: 120,
          beatsPerBar: 3,
          beatUnit: 8,
          subdivision: Subdivision.one,
        ),
      );

      expect(scheduler.scheduledDelays.single, const Duration(milliseconds: 250));
    });

    test('uses the subdivision pulse count when calculating pulse duration', () {
      engine.start(
        const MetronomeClickEngineConfig(
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
          subdivision: Subdivision.four,
        ),
      );

      expect(scheduler.scheduledDelays.single, const Duration(milliseconds: 125));
    });

    test('applies beatmap sequence config changes when a new bar starts', () {
      final ticks = <MetronomeBeatTick>[];

      engine.start(
        const MetronomeClickEngineConfig(
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
          subdivision: Subdivision.one,
          accentPattern: [AccentLevel.high],
        ),
        onBeat: ticks.add,
        configSequence: const [
          MetronomeClickEngineConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [AccentLevel.high],
          ),
          MetronomeClickEngineConfig(
            bpm: 90,
            beatsPerBar: 3,
            beatUnit: 8,
            subdivision: Subdivision.one,
            accentPattern: [AccentLevel.low],
          ),
        ],
      );

      scheduler.runNext();
      scheduler.runNext();
      scheduler.runNext();
      scheduler.runNext();

      expect(
        ticks.last,
        isA<MetronomeBeatTick>()
            .having((tick) => tick.barIndex, 'barIndex', 2)
            .having((tick) => tick.beatIndex, 'beatIndex', 1)
            .having((tick) => tick.accentLevel, 'accentLevel', AccentLevel.low)
            .having((tick) => tick.bpm, 'bpm', 90)
            .having((tick) => tick.beatsPerBar, 'beatsPerBar', 3)
            .having((tick) => tick.beatUnit, 'beatUnit', 8),
      );
      scheduler.runNext();
      scheduler.runNext();
      scheduler.runNext();

      expect(
        ticks.last,
        isA<MetronomeBeatTick>()
            .having((tick) => tick.barIndex, 'barIndex', 3)
            .having((tick) => tick.beatIndex, 'beatIndex', 1)
            .having((tick) => tick.bpm, 'bpm', 90)
            .having((tick) => tick.beatsPerBar, 'beatsPerBar', 3)
            .having((tick) => tick.beatUnit, 'beatUnit', 8),
      );
    });

    test('emits subdivision pulses between beats and advances pulse position', () {
      final ticks = <MetronomeBeatTick>[];

      engine.start(
        const MetronomeClickEngineConfig(
          bpm: 120,
          beatsPerBar: 2,
          beatUnit: 4,
          subdivision: Subdivision.three,
          accentPattern: [AccentLevel.high, AccentLevel.low],
        ),
        onBeat: ticks.add,
      );

      scheduler.runNext();
      scheduler.runNext();
      scheduler.runNext();
      scheduler.runNext();
      scheduler.runNext();
      scheduler.runNext();

      expect(
        output.playedEvents,
        [
          PlayedMetronomeEvent.high,
          PlayedMetronomeEvent.subdivision,
          PlayedMetronomeEvent.subdivision,
          PlayedMetronomeEvent.low,
          PlayedMetronomeEvent.subdivision,
          PlayedMetronomeEvent.subdivision,
          PlayedMetronomeEvent.high,
        ],
      );
      expect(
        ticks
            .map(
              (tick) => (
                tick.barIndex,
                tick.beatIndex,
                tick.pulseIndex,
                tick.pulseCount,
                tick.accentLevel,
              ),
            )
            .toList(),
        [
          (1, 1, 1, 3, AccentLevel.high),
          (1, 1, 2, 3, AccentLevel.high),
          (1, 1, 3, 3, AccentLevel.high),
          (1, 2, 1, 3, AccentLevel.low),
          (1, 2, 2, 3, AccentLevel.low),
          (1, 2, 3, 3, AccentLevel.low),
          (2, 1, 1, 3, AccentLevel.high),
        ],
      );
    });

    test('keeps subdivision pulses audible when the beat accent is mute', () {
      final ticks = <MetronomeBeatTick>[];

      engine.start(
        const MetronomeClickEngineConfig(
          bpm: 120,
          beatsPerBar: 1,
          beatUnit: 4,
          subdivision: Subdivision.two,
          accentPattern: [AccentLevel.mute],
        ),
        onBeat: ticks.add,
      );

      scheduler.runNext();

      expect(
        output.playedEvents,
        [PlayedMetronomeEvent.subdivision],
      );
      expect(
        ticks.map((tick) => (tick.pulseIndex, tick.accentLevel)).toList(),
        [
          (1, AccentLevel.mute),
          (2, AccentLevel.mute),
        ],
      );
    });

    test('cancels the pending beat when stopped', () {
      engine.start(
        const MetronomeClickEngineConfig(
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
          subdivision: Subdivision.one,
        ),
      );

      final task = scheduler.tasks.single;
      engine.stop();

      expect(task.cancelled, isTrue);
      expect(engine.isRunning, isFalse);
    });

    test('throws when started twice without stopping', () {
      engine.start(
        const MetronomeClickEngineConfig(
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
        ),
      );

      expect(
        () => engine.start(
          const MetronomeClickEngineConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
          ),
        ),
        throwsStateError,
      );
    });

    test('throws for invalid config values', () {
      expect(
        () => engine.start(
          const MetronomeClickEngineConfig(
            bpm: 0,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => engine.start(
          const MetronomeClickEngineConfig(
            bpm: 120,
            beatsPerBar: 0,
            beatUnit: 4,
            subdivision: Subdivision.one,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => engine.start(
          const MetronomeClickEngineConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 0,
            subdivision: Subdivision.one,
          ),
        ),
        throwsArgumentError,
      );
    });

    test(
      'outgoing bar completes at its own timing before new config takes effect',
      () {
        // Bar 1: 4/4 @ 120 BPM → quarter note = 500ms
        // Bar 2: 3/8 @ 240 BPM → eighth note = 125ms
        //
        // The transition interval (from last beat of bar 1 to beat 1 of
        // bar 2) must use bar 1's own config (500ms). The new tempo/meter
        // takes effect from beat 1 of bar 2 forward, not on the transition.
        const bar1Interval = Duration(milliseconds: 500);
        const bar2Interval = Duration(milliseconds: 125);
        final ticks = <MetronomeBeatTick>[];

        engine.start(
          const MetronomeClickEngineConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
          ),
          onBeat: ticks.add,
          configSequence: const [
            MetronomeClickEngineConfig(
              bpm: 120,
              beatsPerBar: 4,
              beatUnit: 4,
            ),
            MetronomeClickEngineConfig(
              bpm: 240,
              beatsPerBar: 3,
              beatUnit: 8,
            ),
          ],
        );

        // start() emits beat 1 and schedules at bar 1 tempo.
        expect(scheduler.scheduledDelays.last, bar1Interval);

        // Advance the fake clock to match real elapsed time.
        runClock.elapsedValue = bar1Interval;
        scheduler.runNext(); // beat 2
        expect(scheduler.scheduledDelays.last, bar1Interval);

        runClock.elapsedValue = bar1Interval * 2;
        scheduler.runNext(); // beat 3
        expect(scheduler.scheduledDelays.last, bar1Interval);

        // Beat 4 (last beat of bar 1) — the outgoing bar's last beat must
        // still be scheduled at bar 1's own timing (500ms), not the new
        // bar's timing.
        runClock.elapsedValue = bar1Interval * 3;
        scheduler.runNext(); // beat 4
        expect(
          scheduler.scheduledDelays.last,
          bar1Interval,
          reason:
              'transition must use outgoing bar timing (500ms), not new '
              'bar timing (125ms)',
        );

        // Verify beat 1 of bar 2 fires with the correct config.
        runClock.elapsedValue = bar1Interval * 4;
        scheduler.runNext(); // bar 2, beat 1
        final bar2Beat1 = ticks.last;
        expect(bar2Beat1.barIndex, 2);
        expect(bar2Beat1.beatIndex, 1);
        expect(bar2Beat1.beatsPerBar, 3);
        expect(bar2Beat1.beatUnit, 8);
        expect(bar2Beat1.bpm, 240);

        // From beat 1 onward, bar 2's config applies.
        expect(scheduler.scheduledDelays.last, bar2Interval);

        engine.stop();
      },
    );
  });
}

class FakeMetronomeClickOutput implements MetronomeClickOutput {
  final List<PlayedMetronomeEvent> playedEvents = [];

  List<AccentLevel> get playedAccents {
    return playedEvents
        .where((event) => event != PlayedMetronomeEvent.subdivision)
        .map(
          (event) => switch (event) {
            PlayedMetronomeEvent.high => AccentLevel.high,
            PlayedMetronomeEvent.normal => AccentLevel.normal,
            PlayedMetronomeEvent.low => AccentLevel.low,
            PlayedMetronomeEvent.subdivision => throw StateError(
              'Subdivision events do not map to beat accents.',
            ),
          },
        )
        .toList(growable: false);
  }

  @override
  void playNormalBeat() {
    playedEvents.add(PlayedMetronomeEvent.normal);
  }

  @override
  void playHighBeat() {
    playedEvents.add(PlayedMetronomeEvent.high);
  }

  @override
  void playLowBeat() {
    playedEvents.add(PlayedMetronomeEvent.low);
  }

  @override
  void playSubdivisionPulse() {
    playedEvents.add(PlayedMetronomeEvent.subdivision);
  }
}

enum PlayedMetronomeEvent { high, normal, low, subdivision }

class FakeMetronomeScheduler implements MetronomeScheduler {
  final List<Duration> scheduledDelays = [];
  final List<FakeMetronomeScheduledTask> tasks = [];

  @override
  MetronomeScheduledTask schedule({
    required Duration delay,
    required void Function() callback,
  }) {
    scheduledDelays.add(delay);
    final task = FakeMetronomeScheduledTask(callback);
    tasks.add(task);
    return task;
  }

  void runNext() {
    final task = tasks.firstWhere((candidate) => !candidate.cancelled);
    task.callback();
  }
}

class FakeMetronomeRunClock implements MetronomeRunClock {
  Duration elapsedValue = Duration.zero;

  @override
  Duration get elapsed => elapsedValue;

  @override
  void reset() {
    elapsedValue = Duration.zero;
  }

  @override
  void start() {}

  @override
  void stop() {}
}

class FakeMetronomeScheduledTask implements MetronomeScheduledTask {
  FakeMetronomeScheduledTask(this.callback);

  final void Function() callback;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
  }
}
