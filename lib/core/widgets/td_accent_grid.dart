import 'package:flutter/material.dart';

import '../../core/domain/accent_level.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';
import 'accent_level_display.dart';

/// Callback signature for accent changes in [TDAccentGrid].
typedef AccentChangedCallback = void Function(int index, AccentLevel level);

/// TempoDeck accent grid with segmented accent selection.
///
/// Displays one row per beat as a vertical list. Each row contains the
/// beat number label followed by a 4-option segmented control for
/// selecting the accent level (High, Normal, Low, Mute).
class TDAccentGrid extends StatelessWidget {
  const TDAccentGrid({
    required this.accentPattern,
    required this.onAccentChanged,
    super.key,
  });

  /// Current accent level for each beat.
  final List<AccentLevel> accentPattern;

  /// Called when the user selects an accent level for a beat.
  final AccentChangedCallback onAccentChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < accentPattern.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _AccentRow(
            beatIndex: i,
            accentLevel: accentPattern[i],
            onChanged: (level) => onAccentChanged(i, level),
          ),
        ],
      ],
    );
  }
}

/// Single beat row: beat number label + segmented accent control.
class _AccentRow extends StatelessWidget {
  const _AccentRow({
    required this.beatIndex,
    required this.accentLevel,
    required this.onChanged,
  });

  static const _beatLabelWidth = 32.0;

  final int beatIndex;
  final AccentLevel accentLevel;
  final ValueChanged<AccentLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _beatLabelWidth,
          child: Text(
            '${beatIndex + 1}',
            style: AppTextTheme.numeric.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _AccentSegmentedButton(
            selected: accentLevel,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Themed segmented button for selecting an [AccentLevel].
///
/// The selected segment gets a colored background matching its accent
/// level color. Unselected segments use [AppColors.surface].
class _AccentSegmentedButton extends StatelessWidget {
  const _AccentSegmentedButton({
    required this.selected,
    required this.onChanged,
  });

  static const _segmentHeight = 36.0;

  final AccentLevel selected;
  final ValueChanged<AccentLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedColor = colorForAccentLevel(selected);

    return SegmentedButton<AccentLevel>(
      selected: {selected},
      onSelectionChanged: (selection) => onChanged(selection.first),
      showSelectedIcon: false,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, _segmentHeight)),
        maximumSize: const WidgetStatePropertyAll(
          Size(double.infinity, _segmentHeight),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return selectedColor;
          return AppColors.surface;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.textPrimary;
          }
          return AppColors.textMuted;
        }),
        side: const WidgetStatePropertyAll(
          BorderSide(color: AppColors.border),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppSpacing.sm)),
          ),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: AppTextTheme.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      segments: [
        for (final level in AccentLevel.values)
          ButtonSegment<AccentLevel>(
            value: level,
            label: Text(shortLabelForAccentLevel(level)),
          ),
      ],
    );
  }
}
