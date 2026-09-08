import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runtime app variant.
///
/// Mobile and desktop share the same domain and features, but differ in
/// platform-specific service wiring (audio engines, file services, UI shell).
enum AppVariant {
  mobile,
  desktop;

  /// Whether this variant uses a desktop UI shell (navigation rail, etc.).
  bool get isDesktop => this == desktop;
}

final appVariantProvider = Provider<AppVariant>(
  (ref) => throw UnimplementedError('appVariantProvider must be overridden at root'),
);
