import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/metronome_click_engine.dart';
import 'package:tempodeck/core/domain/subdivision.dart';

void main() {
  test('MetronomeClickEngine compensates accumulated drift when scheduling', () {
    final scheduler = _FakeMetronomeScheduler();
    final runClock = _FakeMetronomeRunClock();
    final engine = MetronomeClickEngine(
      output: _FakeMetronomeClickOutput(),
      scheduler: scheduler,
      runClock: runClock,
    );

    engine.start(
      const MetronomeClickEngineConfig(
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        subdivision: Subdivision.one,
      ),
    );

    expect(scheduler.scheduledDelays.first, const Duration(milliseconds: 500));

    runClock.elapsedValue = const Duration(milliseconds: 600);
    scheduler.runNext();

    expect(scheduler.scheduledDelays.last, const Duration(milliseconds: 400));
  });
}

class _FakeMetronomeClickOutput implements MetronomeClickOutput {
  @override
  void playHighBeat() {}

  @override
  void playLowBeat() {}

  @override
  void playNormalBeat() {}

  @override
  void playSubdivisionPulse() {}
}

class _FakeMetronomeScheduler implements MetronomeScheduler {
  final List<Duration> scheduledDelays = [];
  final List<_FakeMetronomeScheduledTask> tasks = [];

  @override
  MetronomeScheduledTask schedule({
    required Duration delay,
    required void Function() callback,
  }) {
    scheduledDelays.add(delay);
    final task = _FakeMetronomeScheduledTask(callback);
    tasks.add(task);
    return task;
  }

  void runNext() {
    final task = tasks.firstWhere((candidate) => !candidate.cancelled);
    task.callback();
  }
}

class _FakeMetronomeScheduledTask implements MetronomeScheduledTask {
  _FakeMetronomeScheduledTask(this.callback);

  final void Function() callback;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
  }
}

class _FakeMetronomeRunClock implements MetronomeRunClock {
  Duration elapsedValue = Duration.zero;
  bool isRunning = false;

  @override
  Duration get elapsed => elapsedValue;

  @override
  void reset() {
    elapsedValue = Duration.zero;
  }

  @override
  void start() {
    isRunning = true;
  }

  @override
  void stop() {
    isRunning = false;
  }
}
