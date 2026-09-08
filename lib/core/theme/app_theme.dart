import 'package:flutter/material.dart';

import 'app_animations.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_theme.dart';

/// TempoDeck V2 theme.
///
/// Builds a complete [ThemeData] from AppColors / AppTextTheme / AppSpacing
/// tokens. Dark mode only – there is no light theme.
///
/// See DESIGN_GUIDE.md for full documentation.
abstract final class AppTheme {
  /// The single dark theme for TempoDeck V2.
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,

      // ── Colors ─────────────────────────────────────────
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: AppColors.textPrimary,
        secondary: AppColors.primaryLight,
        onSecondary: AppColors.textPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        onError: AppColors.textPrimary,
        outline: AppColors.textMuted,
      ),
      cardColor: AppColors.surface,
      dividerColor: AppColors.border,

      // ── Typography ─────────────────────────────────────
      fontFamily: AppTextTheme.bodyFont,
      textTheme: const TextTheme(
        displayLarge: AppTextTheme.bpmDisplay,
        displayMedium: AppTextTheme.bpmDisplaySmall,
        headlineLarge: AppTextTheme.heading1,
        headlineMedium: AppTextTheme.heading2,
        headlineSmall: AppTextTheme.heading3,
        titleLarge: AppTextTheme.heading2,
        titleMedium: AppTextTheme.heading3,
        titleSmall: AppTextTheme.label,
        bodyLarge: AppTextTheme.body,
        bodyMedium: AppTextTheme.bodySecondary,
        bodySmall: AppTextTheme.label,
        labelLarge: AppTextTheme.button,
        labelMedium: AppTextTheme.label,
        labelSmall: AppTextTheme.labelSmall,
      ),

      // ── App Bar ────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextTheme.heading2,
      ),

      // ── Cards ──────────────────────────────────────────
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          side: BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Buttons ────────────────────────────────────────
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.primary),
          foregroundColor: WidgetStatePropertyAll(AppColors.textPrimary),
          textStyle: WidgetStatePropertyAll(AppTextTheme.button),
          minimumSize: WidgetStatePropertyAll(Size(0, 56)),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)),
            ),
          ),
          elevation: WidgetStatePropertyAll(0),
          animationDuration: AppAnimations.fast,
        ),
      ),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(AppColors.primary),
          textStyle: WidgetStatePropertyAll(AppTextTheme.button),
          animationDuration: AppAnimations.fast,
        ),
      ),
      outlinedButtonTheme: const OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(AppColors.textPrimary),
          textStyle: WidgetStatePropertyAll(AppTextTheme.button),
          side: WidgetStatePropertyAll(
            BorderSide(color: AppColors.textMuted),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
            ),
          ),
          animationDuration: AppAnimations.fast,
        ),
      ),

      // ── Input / Text Fields ────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + AppSpacing.xs,
        ),
        labelStyle: AppTextTheme.label,
        hintStyle: AppTextTheme.bodySecondary,
      ),

      // ── Slider ─────────────────────────────────────────
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surfaceElevated,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primaryGlow,
        trackHeight: 4,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
      ),

      // ── Chip ───────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceElevated,
        selectedColor: AppColors.primary,
        labelStyle: AppTextTheme.label,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),

      // ── Switch ─────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primaryGlow;
          }
          return AppColors.surfaceElevated;
        }),
      ),

      // ── Bottom Navigation ──────────────────────────────
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.primaryGlow,
        labelTextStyle: WidgetStatePropertyAll(AppTextTheme.labelSmall),
        height: 64,
        elevation: 0,
      ),

      // ── Navigation Rail (Desktop) ─────────────────────
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.primaryGlow,
        selectedIconTheme: IconThemeData(color: AppColors.primary),
        unselectedIconTheme: IconThemeData(color: AppColors.textMuted),
        selectedLabelTextStyle: AppTextTheme.label,
        unselectedLabelTextStyle: AppTextTheme.labelSmall,
      ),

      // ── Dialog ─────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        titleTextStyle: AppTextTheme.heading2,
        contentTextStyle: AppTextTheme.body,
      ),

      // ── Bottom Sheet ───────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        dragHandleColor: AppColors.textMuted,
        dragHandleSize: Size(40, 4),
      ),

      // ── Divider ────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // ── Icon ───────────────────────────────────────────
      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: 24,
      ),

      // ── Segmented Button ───────────────────────────────
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return AppColors.surfaceElevated;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.textPrimary;
            }
            return AppColors.textSecondary;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
        ),
      ),

      // ── Popup Menu ─────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: AppTextTheme.body,
      ),

      // ── Floating Action Button ─────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),

      // ── List Tile ──────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        textColor: AppColors.textPrimary,
        iconColor: AppColors.textSecondary,
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),

      // ── Tooltip ────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: AppTextTheme.labelSmall.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
