import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shows a TempoDeck glass morphism dialog.
///
/// Applies a blurred backdrop, elevated surface background, and glass border
/// to create a premium dialog appearance consistent with the design system.
Future<T?> showTDDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Dialog(
        backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.95),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.lg),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        child: builder(context),
      ),
    ),
  );
}

/// Standard glass morphism shape for [AlertDialog] widgets.
///
/// Use this when migrating existing [AlertDialog] instances to the glass style
/// without converting them to [showTDDialog].
final ShapeBorder tdDialogShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(AppSpacing.lg),
  side: const BorderSide(color: AppColors.glassBorder),
);
