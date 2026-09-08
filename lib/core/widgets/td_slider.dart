import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// TempoDeck design system slider.
///
/// Custom-styled slider with purple track and thumb, optional label
/// and value display.
class TDSlider extends StatelessWidget {
  const TDSlider({
    required this.value,
    required this.onChanged,
    super.key,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.valueLabel,
  });

  static const _trackHeight = 4.0;
  static const _thumbRadius = 10.0;

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;

  /// Optional label shown above the slider.
  final String? label;

  /// Optional formatted value shown to the right of the label.
  final String? valueLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Row(
            children: [
              Text(label!, style: AppTextTheme.heading3),
              if (valueLabel != null) ...[
                const Spacer(),
                Text(valueLabel!, style: AppTextTheme.numeric),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.surfaceElevated,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primaryGlow,
            trackHeight: _trackHeight,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: _thumbRadius),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
