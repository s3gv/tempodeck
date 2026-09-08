import 'package:flutter/foundation.dart';

/// Whether the app runs on a desktop platform (macOS, Windows, Linux).
///
/// Shared utility to avoid duplicating platform checks across widgets.
bool get isDesktopPlatform {
  final platform = defaultTargetPlatform;
  return platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux;
}
