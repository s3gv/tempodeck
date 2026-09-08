import 'package:flutter/material.dart';

import '../domain/accent_level.dart';
import '../theme/app_colors.dart';

/// Maps an [AccentLevel] to its display color.
///
/// Used by accent grids and dot visualizations to consistently
/// color-code beats by their accent level.
Color colorForAccentLevel(AccentLevel level) {
  return switch (level) {
    AccentLevel.high => AppColors.beatAccent,
    AccentLevel.normal => AppColors.beatNormal,
    AccentLevel.low => AppColors.beatSubdivision,
    AccentLevel.mute => AppColors.beatOff,
  };
}

/// Returns a single-character label for an [AccentLevel].
///
/// Used by accent grids and dot visualizations to display a compact
/// text indicator inside colored segments or dots.
String shortLabelForAccentLevel(AccentLevel level) {
  return switch (level) {
    AccentLevel.high => 'H',
    AccentLevel.normal => 'N',
    AccentLevel.low => 'L',
    AccentLevel.mute => 'M',
  };
}
