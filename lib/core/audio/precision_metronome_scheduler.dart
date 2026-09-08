import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';

import 'metronome_click_engine.dart';

final _logger = Logger('PrecisionMetronomeScheduler');

typedef PrecisionMetronomeIsolateSpawner = Future<Isolate> Function({
  required SendPort sendPort,
  required int delayMicroseconds,
});

class PrecisionMetronomeScheduler implements MetronomeScheduler {
  const PrecisionMetronomeScheduler({
    PrecisionMetronomeIsolateSpawner? isolateSpawner,
  }) : _isolateSpawner = isolateSpawner ?? _spawnPrecisionScheduleIsolate;

  static const int _aggressiveSleepThresholdUs = 2000;
  static const int _aggressiveSleepBufferUs = 1000;
  static const int _microSleepThresholdUs = 200;
  static const int _microSleepStepUs = 100;

  final PrecisionMetronomeIsolateSpawner _isolateSpawner;

  @override
  MetronomeScheduledTask schedule({
    required Duration delay,
    required void Function() callback,
  }) {
    final receivePort = ReceivePort();
    final task = _PrecisionMetronomeScheduledTask(
      callback: callback,
      receivePort: receivePort,
    );

    final request = _PrecisionMetronomeScheduleRequest(
      delayMicroseconds: delay.inMicroseconds,
      sendPort: receivePort.sendPort,
    );
    late Future<Isolate> spawnFuture;
    try {
      spawnFuture = _isolateSpawner(
        sendPort: request.sendPort,
        delayMicroseconds: request.delayMicroseconds,
      );
    } catch (error, stackTrace) {
      _logger.severe('Isolate spawn failed synchronously.', error, stackTrace);
      scheduleMicrotask(task.handleSpawnFailure);
      return task;
    }

    spawnFuture.then(
      task.attachIsolate,
      onError: (Object error, StackTrace stackTrace) {
        _logger.severe('Isolate spawn failed asynchronously.', error, stackTrace);
        task.handleSpawnFailure();
      },
    );

    return task;
  }
}

class _PrecisionMetronomeScheduledTask implements MetronomeScheduledTask {
  _PrecisionMetronomeScheduledTask({
    required void Function() callback,
    required ReceivePort receivePort,
  })  : _callback = callback,
        _receivePort = receivePort {
    _subscription = _receivePort.listen((_) {
      if (_isCancelled) {
        return;
      }

      _close();
      _callback();
    });
  }

  final void Function() _callback;
  final ReceivePort _receivePort;
  late final StreamSubscription<void> _subscription;

  Isolate? _isolate;
  bool _isCancelled = false;

  void attachIsolate(Isolate isolate) {
    if (_isCancelled) {
      isolate.kill(priority: Isolate.immediate);
      return;
    }

    _isolate = isolate;
  }

  /// Cleans up resources and fires the callback so the tick chain continues.
  ///
  /// A spawn failure causes one mis-timed tick, but the
  /// [MetronomeDriftCompensator] corrects on the next beat.
  void handleSpawnFailure() {
    if (_isCancelled) {
      return;
    }

    _close();
    _callback();
  }

  @override
  void cancel() {
    if (_isCancelled) {
      return;
    }

    _isCancelled = true;
    _close();
    _isolate?.kill(priority: Isolate.immediate);
  }

  void _close() {
    _subscription.cancel();
    _receivePort.close();
  }
}

class _PrecisionMetronomeScheduleRequest {
  const _PrecisionMetronomeScheduleRequest({
    required this.delayMicroseconds,
    required this.sendPort,
  });

  final int delayMicroseconds;
  final SendPort sendPort;
}

void _runPrecisionSchedule(_PrecisionMetronomeScheduleRequest request) {
  final delayMicroseconds = request.delayMicroseconds;
  if (delayMicroseconds <= 0) {
    request.sendPort.send(null);
    return;
  }

  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsedMicroseconds < delayMicroseconds) {
    final remainingMicroseconds =
        delayMicroseconds - stopwatch.elapsedMicroseconds;

    if (remainingMicroseconds >
        PrecisionMetronomeScheduler._aggressiveSleepThresholdUs) {
      sleep(
        Duration(
          microseconds: remainingMicroseconds -
              PrecisionMetronomeScheduler._aggressiveSleepBufferUs,
        ),
      );
      continue;
    }

    if (remainingMicroseconds >
        PrecisionMetronomeScheduler._microSleepThresholdUs) {
      sleep(
        const Duration(
          microseconds: PrecisionMetronomeScheduler._microSleepStepUs,
        ),
      );
    }
  }

  request.sendPort.send(null);
}

Future<Isolate> _spawnPrecisionScheduleIsolate({
  required SendPort sendPort,
  required int delayMicroseconds,
}) {
  return Isolate.spawn<_PrecisionMetronomeScheduleRequest>(
    _runPrecisionSchedule,
    _PrecisionMetronomeScheduleRequest(
      delayMicroseconds: delayMicroseconds,
      sendPort: sendPort,
    ),
  );
}
