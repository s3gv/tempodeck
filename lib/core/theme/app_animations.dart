import 'package:flutter/animation.dart';

/// TempoDeck V2 animation constants.
///
/// All durations and curves are centralized here – no magic numbers
/// in widget code. Animations should feel rhythmic and physical.
///
/// See DESIGN_GUIDE.md for the full animation specification table.
abstract final class AppAnimations {
  // ── Durations ────────────────────────────────────────────

  /// 80ms. Micro-interactions: opacity toggles, icon swaps.
  static const Duration instant = Duration(milliseconds: 80);

  /// 150ms. Fast feedback: button press, BPM number bounce.
  static const Duration fast = Duration(milliseconds: 150);

  /// 300ms. Standard transitions: page changes, card expand/collapse.
  static const Duration normal = Duration(milliseconds: 300);

  /// 500ms. Deliberate transitions: sheet open/close, mode changes.
  static const Duration slow = Duration(milliseconds: 500);

  /// 800ms. Dramatic transitions: splash screen, onboarding.
  static const Duration verySlow = Duration(milliseconds: 800);

  // ── Curves ───────────────────────────────────────────────

  /// Beat pulse curve. Fast attack, slow release – like a drum hit.
  static const Curve snap = Curves.easeOutExpo;

  /// Button feedback curve. Bouncy, elastic – feels physical.
  static const Curve spring = Curves.elasticOut;

  /// Page transition curve. Smooth, elegant, professional.
  static const Curve smooth = Curves.easeInOutCubic;

  /// Enter/appear curve. Quick start, gentle landing.
  static const Curve enter = Curves.easeOutCubic;

  /// Exit/disappear curve. Gentle start, accelerates out.
  static const Curve exit = Curves.easeInCubic;

  // ── Beat-specific Constants ──────────────────────────────

  /// Beat indicator attack time. Instant illumination – no delay.
  static const Duration beatAttack = Duration.zero;

  /// Beat indicator decay time. Slow fade-out after each beat.
  static const Duration beatDecay = Duration(milliseconds: 200);

  /// BPM number scale factor at peak of beat pulse (102%).
  static const double beatScalePeak = 1.02;

  /// Button scale factor when pressed (96%).
  static const double buttonPressedScale = 0.96;

  // ── Stagger Delays ──────────────────────────────────────

  /// Delay between each list item in staggered animations.
  static const Duration staggerOffset = Duration(milliseconds: 50);

  /// Splash screen logo fade-in duration.
  static const Duration splashFadeIn = Duration(milliseconds: 600);

  /// Splash screen to main UI cross-fade duration.
  static const Duration splashCrossFade = Duration(milliseconds: 400);

  /// Default splash BPM for logo pulse animation.
  static const int splashPulseBpm = 120;
}
