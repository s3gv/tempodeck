class MetronomeDriftCompensator {
  int _targetElapsedMicroseconds = 0;

  void reset() {
    _targetElapsedMicroseconds = 0;
  }

  Duration nextDelay({
    required Duration interval,
    required Duration elapsed,
  }) {
    _targetElapsedMicroseconds += interval.inMicroseconds;
    final remainingMicroseconds =
        _targetElapsedMicroseconds - elapsed.inMicroseconds;

    if (remainingMicroseconds <= 0) {
      return Duration.zero;
    }

    return Duration(microseconds: remainingMicroseconds);
  }
}
