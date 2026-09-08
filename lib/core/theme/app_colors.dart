import 'package:flutter/material.dart';

/// TempoDeck V2 color tokens.
///
/// All UI colors are defined here – no hardcoded hex values elsewhere.
/// The primary purple (#9B5DFF) is the signature TempoDeck accent.
///
/// See DESIGN_GUIDE.md for full color system documentation.
abstract final class AppColors {
  // ── Primary ──────────────────────────────────────────────

  /// Main accent color. Primary buttons, active states, focus rings.
  static const primary = Color(0xFF9B5DFF);

  /// Lighter variant (+20% brightness). Hover states, highlights.
  static const primaryLight = Color(0xFFB98AFF);

  /// Darker variant (-20% brightness). Pressed states.
  static const primaryDark = Color(0xFF7A3FD9);

  /// 25% opacity primary. Glow effects, shadows, beat pulse.
  static const primaryGlow = Color(0x409B5DFF);

  // ── Backgrounds ──────────────────────────────────────────

  /// Deepest black with subtle blue tint. Splash screen, overlays.
  static const backgroundDeep = Color(0xFF0A0A0F);

  /// Main app background.
  static const background = Color(0xFF0D0D0F);

  /// Card and surface background.
  static const surface = Color(0xFF1A1A22);

  /// Elevated surfaces – dialogs, sheets, floating elements.
  static const surfaceElevated = Color(0xFF222230);

  // ── Text ─────────────────────────────────────────────────

  /// Pure white. Headlines, primary content, BPM display.
  static const textPrimary = Color(0xFFFFFFFF);

  /// Muted lavender. Secondary text, labels, subtitles.
  static const textSecondary = Color(0xFFB0B0C8);

  /// Dark muted. Tertiary text, placeholders, disabled states.
  static const textMuted = Color(0xFF6B6B88);

  // ── Semantic ─────────────────────────────────────────────

  /// Success green. Confirmations, positive states.
  static const success = Color(0xFF4ADE80);

  /// Warning amber. Caution indicators, low-quota warnings.
  static const warning = Color(0xFFFBBF24);

  /// Error / destructive red.
  static const error = Color(0xFFF87171);

  // ── Beat Indicators ──────────────────────────────────────

  /// Accent beat (beat 1). Full primary color + glow effect.
  static const beatAccent = Color(0xFF9B5DFF);

  /// Normal beats. Slightly muted purple.
  static const beatNormal = Color(0xFF7A3FD9);

  /// Subdivision beats. Strongly muted.
  static const beatSubdivision = Color(0xFF4A2D7A);

  /// Inactive/off beat indicator.
  static const beatOff = Color(0xFF2A2A3A);

  // ── Shared border color ──────────────────────────────────

  /// Subtle border for cards, dividers, separators.
  static const border = Color(0xFF2A2A3A);

  // ── Glass Morphism ─────────────────────────────────────

  /// Glass panel background. White at 5% opacity.
  static const glassBackground = Color(0x0DFFFFFF);

  /// Glass panel border. Primary color at 15% opacity.
  static const glassBorder = Color(0x269B5DFF);

  /// Gradient start for premium backgrounds.
  static const backgroundGradientStart = backgroundDeep;

  /// Gradient end for premium backgrounds.
  static const backgroundGradientEnd = background;

  // ── Legacy aliases (deprecated – migrate to new names) ───
  // These maintain backward compatibility during migration.

  /// @deprecated Use [primary] instead.
  static const accent = primary;

  /// @deprecated Use [primaryGlow] instead.
  static const accentGlow = Color(0x669B5DFF);

  /// @deprecated Use [error] instead.
  static const destructive = error;
}
