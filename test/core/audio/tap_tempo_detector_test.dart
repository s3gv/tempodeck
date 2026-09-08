import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/tap_tempo_detector.dart';

void main() {
  group('TapTempoDetector', () {
    late _FakeTapTempoClock clock;
    late TapTempoDetector detector;

    setUp(() {
      clock = _FakeTapTempoClock(
        DateTime.utc(2026, 3, 10, 12, 0, 0),
      );
      detector = TapTempoDetector(clock: clock);
    });

    test('does not return bpm before the fourth tap', () {
      expect(detector.registerTap(), isNull);

      clock.advance(const Duration(milliseconds: 500));
      expect(detector.registerTap(), isNull);

      clock.advance(const Duration(milliseconds: 500));
      expect(detector.registerTap(), isNull);
    });

    test('returns bpm on the fourth tap using the average interval', () {
      detector.registerTap();

      clock.advance(const Duration(milliseconds: 500));
      detector.registerTap();

      clock.advance(const Duration(milliseconds: 500));
      detector.registerTap();

      clock.advance(const Duration(milliseconds: 500));
      final result = detector.registerTap();

      expect(result, isNotNull);
      expect(result!.bpm, 120);
      expect(result.tapCount, 4);
    });

    test('keeps refining bpm after additional taps', () {
      detector.registerTap();

      clock.advance(const Duration(milliseconds: 500));
      detector.registerTap();

      clock.advance(const Duration(milliseconds: 500));
      detector.registerTap();

      clock.advance(const Duration(milliseconds: 500));
      detector.registerTap();

      clock.advance(const Duration(milliseconds: 480));
      final result = detector.registerTap();

      expect(result, isNotNull);
      expect(result!.tapCount, 5);
      expect(result.bpm, 121);
    });

    test('uses a bounded rolling window for tempo changes', () {
      detector.registerTap();

      for (var index = 0; index < 7; index += 1) {
        clock.advance(const Duration(milliseconds: 500));
        detector.registerTap();
      }

      TapTempoResult? result;
      for (var index = 0; index < 5; index += 1) {
        clock.advance(const Duration(milliseconds: 429));
        result = detector.registerTap();
      }

      expect(result, isNotNull);
      expect(result!.tapCount, 8);
      expect(result.bpm, 134);
    });

    test('resets after four seconds of silence', () {
      detector.registerTap();
      clock.advance(const Duration(milliseconds: 500));
      detector.registerTap();

      clock.advance(const Duration(seconds: 4));
      final result = detector.registerTap();

      expect(result, isNull);
      expect(detector.tapCount, 1);
    });

    test('reset clears accumulated taps', () {
      detector.registerTap();
      clock.advance(const Duration(milliseconds: 500));
      detector.registerTap();

      detector.reset();

      expect(detector.tapCount, 0);
      expect(detector.registerTap(), isNull);
    });
  });
}

class _FakeTapTempoClock implements TapTempoClock {
  _FakeTapTempoClock(this._now);

  DateTime _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }

  @override
  DateTime now() => _now;
}
