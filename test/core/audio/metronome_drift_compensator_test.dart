import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/metronome_drift_compensator.dart';

void main() {
  group('MetronomeDriftCompensator', () {
    test('returns the nominal interval for the first scheduled tick', () {
      final compensator = MetronomeDriftCompensator();

      final delay = compensator.nextDelay(
        interval: const Duration(milliseconds: 500),
        elapsed: Duration.zero,
      );

      expect(delay, const Duration(milliseconds: 500));
    });

    test('reduces the next delay when a tick is late', () {
      final compensator = MetronomeDriftCompensator();

      compensator.nextDelay(
        interval: const Duration(milliseconds: 500),
        elapsed: Duration.zero,
      );
      final correctedDelay = compensator.nextDelay(
        interval: const Duration(milliseconds: 500),
        elapsed: const Duration(milliseconds: 600),
      );

      expect(correctedDelay, const Duration(milliseconds: 400));
    });

    test('clamps overdue ticks to zero delay', () {
      final compensator = MetronomeDriftCompensator();

      compensator.nextDelay(
        interval: const Duration(milliseconds: 500),
        elapsed: Duration.zero,
      );
      final correctedDelay = compensator.nextDelay(
        interval: const Duration(milliseconds: 500),
        elapsed: const Duration(milliseconds: 1200),
      );

      expect(correctedDelay, Duration.zero);
    });

    test('reset clears the accumulated schedule position', () {
      final compensator = MetronomeDriftCompensator();

      compensator.nextDelay(
        interval: const Duration(milliseconds: 500),
        elapsed: Duration.zero,
      );
      compensator.reset();

      final delay = compensator.nextDelay(
        interval: const Duration(milliseconds: 500),
        elapsed: Duration.zero,
      );

      expect(delay, const Duration(milliseconds: 500));
    });
  });
}
