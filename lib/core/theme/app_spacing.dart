/// TempoDeck V2 spacing and border radius constants.
///
/// Consistent spacing eliminates guesswork and ensures visual rhythm.
/// Always use these constants – no magic pixel values in widget code.
///
/// See DESIGN_GUIDE.md for spacing rules per context.
abstract final class AppSpacing {
  /// 4dp. Micro gaps: icon padding adjustments, inline offsets.
  static const double xs = 4;

  /// 8dp. Small gaps: icon-to-label, between closely related elements.
  static const double sm = 8;

  /// 16dp. Medium gaps: between controls in a group, form field spacing.
  static const double md = 16;

  /// 24dp. Large gaps: between sections, card internal padding.
  static const double lg = 24;

  /// 32dp. Extra large: screen edge padding, between major sections.
  static const double xl = 32;

  /// 48dp. Maximum: dramatic separations, hero element breathing room.
  static const double xxl = 48;
}

/// Border radius constants for the TempoDeck design system.
abstract final class AppRadius {
  /// 8dp. Text fields, small chips, compact cards.
  static const double sm = 8;

  /// 16dp. Standard cards, panels, dialogs.
  static const double md = 16;

  /// 24dp. Large cards, sheets, sections.
  static const double lg = 24;

  /// 32dp. Primary buttons, prominent interactive elements.
  static const double xl = 32;

  /// 999dp. Fully rounded: pills, circular indicators, FABs.
  static const double pill = 999;
}
