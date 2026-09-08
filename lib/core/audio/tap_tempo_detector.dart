class TapTempoResult {
  const TapTempoResult({
    required this.bpm,
    required this.tapCount,
  });

  final int bpm;
  final int tapCount;
}

abstract class TapTempoClock {
  DateTime now();
}

class SystemTapTempoClock implements TapTempoClock {
  const SystemTapTempoClock();

  @override
  DateTime now() => DateTime.now();
}

class TapTempoDetector {
  TapTempoDetector({
    TapTempoClock? clock,
  }) : _clock = clock ?? const SystemTapTempoClock();

  static const int minimumTapCount = 4;
  static const int _maxTapWindow = 8;
  static const int _secondsPerMinute = 60;
  static const int _microsecondsPerMinute =
      _secondsPerMinute * Duration.microsecondsPerSecond;
  static const Duration silenceResetThreshold = Duration(seconds: 4);

  final TapTempoClock _clock;
  final List<DateTime> _tapTimes = <DateTime>[];

  int get tapCount => _tapTimes.length;

  TapTempoResult? registerTap() {
    final tapTime = _clock.now();
    _resetAfterSilence(tapTime);
    _tapTimes.add(tapTime);
    _trimTapWindow();

    if (_tapTimes.length < minimumTapCount) {
      return null;
    }

    final elapsedMicroseconds =
        _tapTimes.last.difference(_tapTimes.first).inMicroseconds;
    final intervalCount = _tapTimes.length - 1;
    final averageIntervalMicroseconds = elapsedMicroseconds / intervalCount;
    final bpm = (_microsecondsPerMinute / averageIntervalMicroseconds).round();

    return TapTempoResult(
      bpm: bpm,
      tapCount: _tapTimes.length,
    );
  }

  void reset() {
    _tapTimes.clear();
  }

  void _trimTapWindow() {
    if (_tapTimes.length <= _maxTapWindow) {
      return;
    }

    _tapTimes.removeAt(0);
  }

  void _resetAfterSilence(DateTime tapTime) {
    final lastTapTime = _tapTimes.isEmpty ? null : _tapTimes.last;
    if (lastTapTime == null) {
      return;
    }

    final silenceDuration = tapTime.difference(lastTapTime);
    if (silenceDuration >= silenceResetThreshold) {
      reset();
    }
  }
}
