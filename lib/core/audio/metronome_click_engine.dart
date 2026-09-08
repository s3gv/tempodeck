import 'dart:async';

import '../domain/accent_level.dart';
import '../domain/subdivision.dart';
import 'metronome_drift_compensator.dart';
import 'precision_metronome_scheduler.dart';

class MetronomeClickEngineConfig {
  const MetronomeClickEngineConfig({
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
    this.subdivision = Subdivision.one,
    this.accentPattern = const [],
  });

  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
  final Subdivision subdivision;
  final List<AccentLevel> accentPattern;
}

class MetronomeBeatTick {
  const MetronomeBeatTick({
    required this.barIndex,
    required this.beatIndex,
    required this.pulseIndex,
    required this.pulseCount,
    required this.accentLevel,
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
  });

  final int barIndex;
  final int beatIndex;
  final int pulseIndex;
  final int pulseCount;
  final AccentLevel accentLevel;
  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
}

abstract class MetronomeClickOutput {
  void playHighBeat();
  void playNormalBeat();
  void playLowBeat();
  void playSubdivisionPulse();
}

abstract class MetronomeScheduledTask {
  void cancel();
}

abstract class MetronomeScheduler {
  MetronomeScheduledTask schedule({
    required Duration delay,
    required void Function() callback,
  });
}

abstract class MetronomeRunClock {
  Duration get elapsed;
  void reset();
  void start();
  void stop();
}

class TimerMetronomeScheduler implements MetronomeScheduler {
  const TimerMetronomeScheduler();

  @override
  MetronomeScheduledTask schedule({
    required Duration delay,
    required void Function() callback,
  }) {
    return _TimerMetronomeScheduledTask(
      Timer(delay, callback),
    );
  }
}

class StopwatchMetronomeRunClock implements MetronomeRunClock {
  StopwatchMetronomeRunClock() : _stopwatch = Stopwatch();

  final Stopwatch _stopwatch;

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  void reset() {
    _stopwatch.reset();
  }

  @override
  void start() {
    _stopwatch.start();
  }

  @override
  void stop() {
    _stopwatch.stop();
  }
}

class MetronomeClickEngine {
  static const int _secondsPerMinute = 60;
  static const int _quarterNotesPerWholeNote = 4;

  MetronomeClickEngine({
    required MetronomeClickOutput output,
    MetronomeScheduler? scheduler,
    MetronomeRunClock? runClock,
  }) : _output = output,
       _scheduler = scheduler ?? const PrecisionMetronomeScheduler(),
       _runClock = runClock ?? StopwatchMetronomeRunClock();

  final MetronomeClickOutput _output;
  final MetronomeScheduler _scheduler;
  final MetronomeRunClock _runClock;
  final MetronomeDriftCompensator _driftCompensator = MetronomeDriftCompensator();

  MetronomeScheduledTask? _scheduledTask;
  MetronomeClickEngineConfig? _config;
  void Function(MetronomeBeatTick tick)? _onBeat;
  List<MetronomeClickEngineConfig>? _configSequence;
  int _currentBarIndex = 1;
  int _currentBeatIndex = 1;
  int _currentPulseIndex = 1;

  bool get isRunning => _config != null;

  void start(
    MetronomeClickEngineConfig config, {
    void Function(MetronomeBeatTick tick)? onBeat,
    List<MetronomeClickEngineConfig>? configSequence,
  }) {
    if (isRunning) {
      throw StateError('Metronome click engine is already running.');
    }

    _validateConfig(config);
    _validateConfigSequence(configSequence);

    _config = configSequence?.first ?? config;
    _configSequence = configSequence == null
        ? null
        : List<MetronomeClickEngineConfig>.unmodifiable(configSequence);
    _onBeat = onBeat;
    _currentBarIndex = 1;
    _currentBeatIndex = 1;
    _currentPulseIndex = 1;
    _driftCompensator.reset();
    _runClock.reset();
    _runClock.start();

    _emitCurrentBeat();
    _scheduleNextBeat();
  }

  void stop() {
    _scheduledTask?.cancel();
    _scheduledTask = null;
    _config = null;
    _configSequence = null;
    _onBeat = null;
    _runClock.stop();
  }

  void _scheduleNextBeat() {
    final currentBarConfig = _configForBar(_currentBarIndex);
    // Always schedule the next pulse at the current bar's own timing. The
    // outgoing bar must complete fully — BPM, beat unit, and subdivision —
    // before the new bar's config takes effect. The new tempo/meter starts
    // from beat 1 of the next bar forward, not on the transition interval.
    final interval = _beatDuration(currentBarConfig);
    _scheduledTask = _scheduler.schedule(
      delay: _driftCompensator.nextDelay(
        interval: interval,
        elapsed: _runClock.elapsed,
      ),
      callback: _handleTick,
    );
  }

  void _handleTick() {
    if (!isRunning) {
      return;
    }

    _advanceBeat();
    _emitCurrentBeat();

    if (isRunning) {
      _scheduleNextBeat();
    }
  }

  void _advanceBeat() {
    final config = _requireConfig();
    final pulseCount = config.subdivision.pulseCount;
    if (_currentPulseIndex < pulseCount) {
      _currentPulseIndex++;
      return;
    }

    _currentPulseIndex = 1;
    if (_currentBeatIndex < config.beatsPerBar) {
      _currentBeatIndex++;
      return;
    }

    _currentBeatIndex = 1;
    _currentBarIndex++;
  }

  void _emitCurrentBeat() {
    final config = _configForBar(_currentBarIndex);
    _config = config;
    final accentLevel = _accentForCurrentBeat(config);
    if (_isBeatPulse) {
      switch (accentLevel) {
        case AccentLevel.high:
          _output.playHighBeat();
        case AccentLevel.normal:
          _output.playNormalBeat();
        case AccentLevel.low:
          _output.playLowBeat();
        case AccentLevel.mute:
          break;
      }
    } else {
      _output.playSubdivisionPulse();
    }

    _onBeat?.call(
      MetronomeBeatTick(
        barIndex: _currentBarIndex,
        beatIndex: _currentBeatIndex,
        pulseIndex: _currentPulseIndex,
        pulseCount: config.subdivision.pulseCount,
        accentLevel: accentLevel,
        bpm: config.bpm,
        beatsPerBar: config.beatsPerBar,
        beatUnit: config.beatUnit,
      ),
    );
  }

  MetronomeClickEngineConfig _configForBar(int barIndex) {
    final sequence = _configSequence;
    if (sequence == null) {
      return _requireConfig();
    }

    final sequenceIndex = (barIndex - 1).clamp(0, sequence.length - 1);
    final config = sequence[sequenceIndex];
    _validateConfig(config);
    return config;
  }

  bool get _isBeatPulse => _currentPulseIndex == 1;

  AccentLevel _accentForCurrentBeat(MetronomeClickEngineConfig config) {
    final accentIndex = _currentBeatIndex - 1;
    if (accentIndex < config.accentPattern.length) {
      return config.accentPattern[accentIndex];
    }

    return AccentLevel.normal;
  }

  Duration _beatDuration(MetronomeClickEngineConfig config) {
    final quarterNoteDurationSeconds = _secondsPerMinute / config.bpm;
    final beatDurationSeconds =
        quarterNoteDurationSeconds *
        (_quarterNotesPerWholeNote / config.beatUnit);
    final pulseDurationSeconds =
        beatDurationSeconds / config.subdivision.pulseCount;
    return Duration(
      microseconds: (pulseDurationSeconds * Duration.microsecondsPerSecond)
          .round(),
    );
  }

  MetronomeClickEngineConfig _requireConfig() {
    final config = _config;
    if (config == null) {
      throw StateError('Metronome click engine is not running.');
    }

    return config;
  }

  void _validateConfig(MetronomeClickEngineConfig config) {
    if (config.bpm < 1) {
      throw ArgumentError.value(config.bpm, 'config.bpm', 'must be at least 1');
    }
    if (config.beatsPerBar < 1) {
      throw ArgumentError.value(
        config.beatsPerBar,
        'config.beatsPerBar',
        'must be at least 1',
      );
    }
    if (config.beatUnit < 1) {
      throw ArgumentError.value(
        config.beatUnit,
        'config.beatUnit',
        'must be at least 1',
      );
    }
  }

  void _validateConfigSequence(List<MetronomeClickEngineConfig>? configSequence) {
    if (configSequence == null) {
      return;
    }
    if (configSequence.isEmpty) {
      throw ArgumentError.value(
        configSequence,
        'configSequence',
        'must not be empty',
      );
    }
    for (final config in configSequence) {
      _validateConfig(config);
    }
  }
}

class _TimerMetronomeScheduledTask implements MetronomeScheduledTask {
  _TimerMetronomeScheduledTask(this._timer);

  final Timer _timer;

  @override
  void cancel() {
    _timer.cancel();
  }
}
