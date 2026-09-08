import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// TempoDeck design system stepper row.
///
/// A horizontal row with a label, current value, and +/- buttons.
/// Used for integer controls like BPM step size.
class TDStepper extends StatelessWidget {
  const TDStepper({
    required this.label,
    required this.value,
    super.key,
    this.onIncrement,
    this.onDecrement,
  });

  /// Descriptive label on the left side of the row.
  final String label;

  /// Current numeric value displayed between the buttons.
  final int value;

  /// Called when the user taps (+). Pass `null` to disable.
  final VoidCallback? onIncrement;

  /// Called when the user taps (−). Pass `null` to disable.
  final VoidCallback? onDecrement;

  static const _iconSize = 24.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: AppTextTheme.heading3),
        ),
        IconButton(
          onPressed: onDecrement,
          icon: Icon(
            Icons.remove_circle_outline,
            size: _iconSize,
            color: onDecrement != null
                ? AppColors.primary
                : AppColors.textMuted,
          ),
        ),
        SizedBox(
          width: AppSpacing.xl,
          child: Text(
            '$value',
            style: AppTextTheme.numericLarge,
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          onPressed: onIncrement,
          icon: Icon(
            Icons.add_circle_outline,
            size: _iconSize,
            color: onIncrement != null
                ? AppColors.primary
                : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
