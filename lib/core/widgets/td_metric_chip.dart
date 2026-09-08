import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// TempoDeck design system metric chip.
///
/// A compact, non-interactive informational badge for displaying
/// metadata such as "120 BPM", "4/4", or "3 songs".
class TDMetricChip extends StatelessWidget {
  const TDMetricChip({
    required this.label,
    super.key,
    this.icon,
    this.color,
  });

  /// Display text (e.g. "120 BPM").
  final String label;

  /// Optional leading icon (14dp).
  final IconData? icon;

  /// Override accent color for icon and text.
  /// Defaults to [AppColors.textSecondary].
  final Color? color;

  static const _iconSize = 14.0;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: _iconSize, color: effectiveColor),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: AppTextTheme.label.copyWith(color: effectiveColor),
          ),
        ],
      ),
    );
  }
}
