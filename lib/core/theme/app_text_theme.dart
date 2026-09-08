import 'package:flutter/material.dart';

import 'app_colors.dart';

/// TempoDeck V2 typography system.
///
/// Two font families:
/// - **JetBrains Mono** ([displayFont]): BPM display, numeric values.
///   Fixed-width digits so BPM numbers don't "jump". Technical character.
/// - **Outfit** ([bodyFont]): All UI text, labels, buttons.
///   Geometric sans-serif, modern, clean, excellent readability.
///
/// See DESIGN_GUIDE.md for full typography documentation.
abstract final class AppTextTheme {
  /// Monospace font for BPM display and numeric values.
  static const String displayFont = 'JetBrainsMono';

  /// Sans-serif font for UI text, labels, and buttons.
  static const String bodyFont = 'Outfit';

  // ── Primary Display ──────────────────────────────────────

  /// 96px BPM display. The largest, most prominent text in the app.
  static const bpmDisplay = TextStyle(
    fontFamily: displayFont,
    fontSize: 96,
    fontWeight: FontWeight.w700,
    letterSpacing: -2,
    height: 1,
    color: AppColors.textPrimary,
  );

  /// 64px BPM display. Compact layouts, tablet secondary views.
  static const bpmDisplaySmall = TextStyle(
    fontFamily: displayFont,
    fontSize: 64,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
    height: 1,
    color: AppColors.textPrimary,
  );

  // ── Headings ─────────────────────────────────────────────

  /// 28px bold. Screen titles, major section headers.
  static const heading1 = TextStyle(
    fontFamily: bodyFont,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// 20px semi-bold. Section titles within a screen.
  static const heading2 = TextStyle(
    fontFamily: bodyFont,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// 16px semi-bold. Card titles, sub-section headers.
  static const heading3 = TextStyle(
    fontFamily: bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // ── Body Text ────────────────────────────────────────────

  /// 16px regular. Primary body text, descriptions.
  static const body = TextStyle(
    fontFamily: bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  /// 16px regular, secondary color. Subtitles, supporting text.
  static const bodySecondary = TextStyle(
    fontFamily: bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // ── Labels & Captions ───────────────────────────────────

  /// 11px uppercase tracking. Section divider labels (e.g. "TEMPO").
  static const sectionLabel = TextStyle(
    fontFamily: bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.0,
    color: AppColors.textMuted,
  );

  /// 13px medium. Form labels, chip text, metadata.
  static const label = TextStyle(
    fontFamily: bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: AppColors.textSecondary,
  );

  /// 11px medium. Navigation labels, timestamps, fine print.
  static const labelSmall = TextStyle(
    fontFamily: bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );

  // ── Buttons ──────────────────────────────────────────────

  /// 15px semi-bold. All button text.
  static const button = TextStyle(
    fontFamily: bodyFont,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: AppColors.textPrimary,
  );

  // ── Numeric ──────────────────────────────────────────────

  /// 16px monospace. Inline numeric values (volume %, durations).
  static const numeric = TextStyle(
    fontFamily: displayFont,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  /// 24px monospace. Prominent numeric values (bar/beat counters).
  static const numericLarge = TextStyle(
    fontFamily: displayFont,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // ── Legacy aliases ───────────────────────────────────────

  /// @deprecated Use [bodySecondary] instead.
  static const bodyMuted = bodySecondary;
}
