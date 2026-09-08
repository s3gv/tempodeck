import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shows a TempoDeck-styled bottom sheet.
///
/// Dark background, drag handle, rounded top corners.
/// Use for presets, settings panels, and selection lists.
Future<T?> showTDSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.lg),
      ),
    ),
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _DragHandle(),
            Flexible(child: builder(context)),
          ],
        ),
      );
    },
  );
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  static const _dragHandleWidth = 40.0;
  static const _dragHandleHeight = 4.0;
  static const _dragHandleBorderRadius = 2.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Container(
        width: _dragHandleWidth,
        height: _dragHandleHeight,
        decoration: BoxDecoration(
          color: AppColors.textMuted,
          borderRadius: BorderRadius.circular(_dragHandleBorderRadius),
        ),
      ),
    );
  }
}
