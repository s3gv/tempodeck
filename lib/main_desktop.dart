import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'core/app/tempodeck_app.dart';
import 'core/logging/app_logging.dart';
import 'core/providers/app_variant_provider.dart';
import 'core/providers/service_providers.dart';

final _log = Logger('DesktopMain');

void main() {
  initializeAppLogging();
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      final container = ProviderContainer(
        overrides: [
          appVariantProvider.overrideWithValue(AppVariant.desktop),
        ],
      );

      // Register a lifecycle channel so macOS AppDelegate can trigger
      // a clean shutdown before the Dart VM exits. This prevents the
      // "unexpectedly quit" crash dialog caused by FFI callbacks
      // (SoLoud, SQLite) firing after VM teardown.
      const lifecycleChannel =
          MethodChannel('com.tempodeck.app/lifecycle');
      lifecycleChannel.setMethodCallHandler((call) async {
        if (call.method == 'shutdown') {
          _log.info('Received shutdown signal — disposing resources.');
          try {
            final engine = container.read(audioEngineProvider);
            await engine.dispose();
          } catch (e) {
            _log.fine('Audio engine dispose during shutdown: $e');
          }
          _log.info('Shutdown complete.');
        }
      });

      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const TempoDeckApp(),
        ),
      );
    },
    (error, stackTrace) {
      Logger('Zone').severe('Unhandled async error.', error, stackTrace);
    },
  );
}
