import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Centralized haptic feedback for TempoDeck.
///
/// All haptic calls are guarded to only fire on iOS and Android.
/// Desktop platforms silently ignore calls.
abstract final class TDHaptics {
  /// Light impact – used on every metronome beat.
  static void beat() {
    if (_isMobile) HapticFeedback.lightImpact();
  }

  /// Medium impact – used on accent beats (beat 1).
  static void accentBeat() {
    if (_isMobile) HapticFeedback.mediumImpact();
  }

  /// Selection click – used on taps (buttons, toggles, nav items).
  static void selectionClick() {
    if (_isMobile) HapticFeedback.selectionClick();
  }

  static bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
}
