import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

bool _loggingInitialized = false;

void initializeAppLogging() {
  if (_loggingInitialized) {
    return;
  }
  _loggingInitialized = true;

  Logger.root.level = kDebugMode ? Level.ALL : Level.INFO;
  Logger.root.onRecord.listen((record) {
    final message = '${record.level.name} [${record.loggerName}] '
        '${record.message}';
    final error = record.error;
    final stackTrace = record.stackTrace;

    // debugPrint outputs to stderr which shows in Xcode and flutter run.
    if (error != null) {
      debugPrint('$message\n  Error: $error');
    } else {
      debugPrint(message);
    }
    if (stackTrace != null) {
      debugPrint('$stackTrace');
    }

    // developer.log goes to Dart DevTools.
    developer.log(
      record.message,
      time: record.time,
      level: record.level.value,
      name: record.loggerName,
      error: error,
      stackTrace: stackTrace,
    );
  });

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Logger('FlutterError').severe(
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    Logger('PlatformDispatcher').severe(
      'Unhandled platform error.',
      error,
      stackTrace,
    );
    return true;
  };
}
