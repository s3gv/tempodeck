import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'core/app/tempodeck_app.dart';
import 'core/logging/app_logging.dart';
import 'core/providers/app_variant_provider.dart';

void main() {
  initializeAppLogging();
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      runApp(
        ProviderScope(
          overrides: [
            appVariantProvider.overrideWithValue(AppVariant.mobile),
          ],
          child: const TempoDeckApp(),
        ),
      );
    },
    (error, stackTrace) {
      Logger('Zone').severe('Unhandled async error.', error, stackTrace);
    },
  );
}
