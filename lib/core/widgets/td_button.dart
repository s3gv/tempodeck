import 'package:flutter/material.dart';

import '../theme/app_animations.dart';
import '../theme/app_platform.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// Button variant for [TDButton].
enum TDButtonVariant {
  /// Filled purple background with glow shadow.
  primary,

  /// Dark surface background with subtle border.
  secondary,

  /// Transparent with red border and text.
  destructive,
}

/// TempoDeck design system button.
///
/// Supports three variants: [TDButtonVariant.primary] (default),
/// [TDButtonVariant.secondary], and [TDButtonVariant.destructive].
///
/// Primary buttons have a purple glow shadow and scale animation on press.
/// On desktop platforms, an additional hover glow is shown.
class TDButton extends StatefulWidget {
  const TDButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = TDButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final TDButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool expand;

  @override
  State<TDButton> createState() => _TDButtonState();
}

class _TDButtonState extends State<TDButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: AppAnimations.fast,
    );
    _scaleAnimation = Tween<double>(
      begin: 1,
      end: AppAnimations.buttonPressedScale,
    ).animate(
      CurvedAnimation(parent: _scaleController, curve: AppAnimations.snap),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null || widget.isLoading;

    return MouseRegion(
      onEnter: isDesktopPlatform ? (_) => setState(() => _isHovered = true) : null,
      onExit: isDesktopPlatform ? (_) => setState(() => _isHovered = false) : null,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: AppAnimations.fast,
          decoration: BoxDecoration(
            boxShadow: [
              if (isDesktopPlatform && _isHovered && !isDisabled)
                BoxShadow(
                  color: AppColors.primaryGlow.withValues(alpha: 0.15),
                  blurRadius: 12,
                ),
            ],
          ),
          child: _buildButton(isDisabled),
        ),
      ),
    );
  }

  Widget _buildButton(bool isDisabled) {
    return switch (widget.variant) {
      TDButtonVariant.primary => _buildPrimary(isDisabled),
      TDButtonVariant.secondary => _buildSecondary(isDisabled),
      TDButtonVariant.destructive => _buildDestructive(isDisabled),
    };
  }

  void _handleTapDown(TapDownDetails _) => _scaleController.forward();

  void _handleTapUp(TapUpDetails _) => _scaleController.reverse();

  void _handleTapCancel() => _scaleController.reverse();

  Widget _buildPrimary(bool isDisabled) {
    return GestureDetector(
      onTapDown: isDisabled ? null : _handleTapDown,
      onTapUp: isDisabled ? null : _handleTapUp,
      onTapCancel: isDisabled ? null : _handleTapCancel,
      child: Container(
        decoration: isDisabled
            ? null
            : const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGlow,
                    blurRadius: 20,
                    spreadRadius: -4,
                  ),
                ],
              ),
        width: widget.expand ? double.infinity : null,
        child: FilledButton(
          onPressed: isDisabled ? null : widget.onPressed,
          child: _buildChild(),
        ),
      ),
    );
  }

  Widget _buildSecondary(bool isDisabled) {
    return SizedBox(
      width: widget.expand ? double.infinity : null,
      child: OutlinedButton(
        onPressed: isDisabled ? null : widget.onPressed,
        child: _buildChild(),
      ),
    );
  }

  Widget _buildDestructive(bool isDisabled) {
    return SizedBox(
      width: widget.expand ? double.infinity : null,
      child: OutlinedButton(
        onPressed: isDisabled ? null : widget.onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
        ),
        child: _buildChild(color: AppColors.error),
      ),
    );
  }

  Widget _buildChild({Color? color}) {
    if (widget.isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: color ?? AppColors.textPrimary,
        ),
      );
    }

    if (widget.icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Text(
            widget.label,
            style: color != null
                ? AppTextTheme.button.copyWith(color: color)
                : null,
          ),
        ],
      );
    }

    return Text(
      widget.label,
      style:
          color != null ? AppTextTheme.button.copyWith(color: color) : null,
    );
  }
}
