import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/precision_metronome_scheduler.dart';

void main() {
  group('PrecisionMetronomeScheduler', () {
    test('runs the callback after the scheduled delay', () async {
      final scheduler = const PrecisionMetronomeScheduler();
      final completer = Completer<Duration>();
      final stopwatch = Stopwatch()..start();

      scheduler.schedule(
        delay: const Duration(milliseconds: 20),
        callback: () {
          if (!completer.isCompleted) {
            completer.complete(stopwatch.elapsed);
          }
        },
      );

      final elapsed = await completer.future.timeout(const Duration(seconds: 1));
      expect(elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 15)));
    });

    test('does not run the callback after cancellation', () async {
      final scheduler = const PrecisionMetronomeScheduler();
      var callbackCount = 0;

      final task = scheduler.schedule(
        delay: const Duration(milliseconds: 30),
        callback: () {
          callbackCount++;
        },
      );

      task.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(callbackCount, 0);
    });

    test('can cancel twice without throwing', () {
      final scheduler = const PrecisionMetronomeScheduler();
      final task = scheduler.schedule(
        delay: const Duration(milliseconds: 10),
        callback: () {},
      );

      expect(() => task.cancel(), returnsNormally);
      expect(() => task.cancel(), returnsNormally);
    });

    test('recovers from synchronous spawn failure via drift-compensated fallback tick',
        () async {
      final completer = Completer<void>();
      final scheduler = PrecisionMetronomeScheduler(
        isolateSpawner: ({
          required SendPort sendPort,
          required int delayMicroseconds,
        }) {
          throw StateError('spawn failed');
        },
      );

      scheduler.schedule(
        delay: const Duration(milliseconds: 20),
        callback: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      await expectLater(completer.future, completes);
    });

    test('recovers from asynchronous spawn failure via drift-compensated fallback tick',
        () async {
      final completer = Completer<void>();
      final scheduler = PrecisionMetronomeScheduler(
        isolateSpawner: ({
          required SendPort sendPort,
          required int delayMicroseconds,
        }) async {
          throw StateError('async spawn failed');
        },
      );

      scheduler.schedule(
        delay: const Duration(milliseconds: 20),
        callback: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      await expectLater(completer.future, completes);
    });

    test('does not recover from spawn failure after cancellation', () async {
      var callbackCount = 0;
      final scheduler = PrecisionMetronomeScheduler(
        isolateSpawner: ({
          required SendPort sendPort,
          required int delayMicroseconds,
        }) {
          throw StateError('spawn failed');
        },
      );

      final task = scheduler.schedule(
        delay: const Duration(milliseconds: 20),
        callback: () {
          callbackCount++;
        },
      );

      task.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(callbackCount, 0);
    });
  });
}
