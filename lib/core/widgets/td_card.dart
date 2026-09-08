import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_animations.dart';
import '../theme/app_platform.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'td_animated_background.dart';

/// TempoDeck design system card.
///
/// Dark surface with subtle border. Consistent padding and radius.
/// Use for grouping related content within a screen section.
///
/// When [onTap] is provided, the card becomes tappable and shows a hover
/// glow on desktop platforms.
///
/// When [glassEffect] is enabled, the card uses a frosted glass morphism
/// style with backdrop blur, translucent white background, and primary
/// accent border.
class TDCard extends StatefulWidget {
  const TDCard({
    required this.child,
    super.key,
    this.padding,
    this.onTap,
    this.glassEffect = false,
  });

  final Widget child;

  /// Override default padding ([AppSpacing.lg] all sides).
  final EdgeInsetsGeometry? padding;

  /// Optional tap callback. When provided, enables tap handling and
  /// desktop hover glow.
  final VoidCallback? onTap;

  /// When true, uses frosted glass morphism styling instead of the
  /// default opaque surface.
  final bool glassEffect;

  @override
  State<TDCard> createState() => _TDCardState();
}

class _TDCardState extends State<TDCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  AnimationController? _borderShimmerController;
  Animation<Color?>? _borderColorAnimation;

  static const _borderAlphaMin = 0.10;
  static const _borderAlphaMax = 0.20;
  static const _shimmerDuration = Duration(seconds: 3);
  static const _glassBorderBaseColor = Color(0xFF9B5DFF);

  @override
  void initState() {
    super.initState();
    _initShimmerIfNeeded();
  }

  @override
  void didUpdateWidget(TDCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.glassEffect != oldWidget.glassEffect) {
      _initShimmerIfNeeded();
    }
  }

  void _initShimmerIfNeeded() {
    if (widget.glassEffect &&
        _borderShimmerController == null &&
        !TDAnimatedBackground.disableAnimations) {
      _borderShimmerController = AnimationController(
        vsync: this,
        duration: _shimmerDuration,
      )..repeat(reverse: true);

      _borderColorAnimation = ColorTween(
        begin: _glassBorderBaseColor.withValues(alpha: _borderAlphaMin),
        end: _glassBorderBaseColor.withValues(alpha: _borderAlphaMax),
      ).animate(_borderShimmerController!);
    } else if (!widget.glassEffect && _borderShimmerController != null) {
      _borderShimmerController!.dispose();
      _borderShimmerController = null;
      _borderColorAnimation = null;
    }
  }

  @override
  void dispose() {
    _borderShimmerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showHover = isDesktopPlatform && _isHovered && widget.onTap != null;

    return MouseRegion(
      onEnter:
          isDesktopPlatform && widget.onTap != null
              ? (_) => setState(() => _isHovered = true)
              : null,
      onExit:
          isDesktopPlatform && widget.onTap != null
              ? (_) => setState(() => _isHovered = false)
              : null,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: widget.onTap != null ? HitTestBehavior.opaque : null,
        child: widget.glassEffect
            ? _buildGlassCard(showHover)
            : _buildSolidCard(showHover),
      ),
    );
  }

  Widget _buildSolidCard(bool showHover) {
    return AnimatedContainer(
      duration: AppAnimations.fast,
      padding: widget.padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.surface, AppColors.surfaceElevated],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          if (showHover)
            BoxShadow(
              color: AppColors.primaryGlow.withValues(alpha: 0.15),
              blurRadius: 12,
            ),
        ],
      ),
      child: widget.child,
    );
  }

  static const double _glassBlurSigma = 16;
  static const double _innerHighlightAlpha = 0.08;
  static const double _innerHighlightHeight = 1;

  Widget _buildGlassCard(bool showHover) {
    final borderRadius = BorderRadius.circular(AppSpacing.md);
    final animation = _borderColorAnimation;

    if (animation == null) {
      return _buildGlassCardContent(
        borderRadius: borderRadius,
        borderColor: AppColors.glassBorder,
        showHover: showHover,
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return _buildGlassCardContent(
          borderRadius: borderRadius,
          borderColor: animation.value ?? AppColors.glassBorder,
          showHover: showHover,
        );
      },
    );
  }

  Widget _buildGlassCardContent({
    required BorderRadius borderRadius,
    required Color borderColor,
    required bool showHover,
  }) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: _glassBlurSigma,
          sigmaY: _glassBlurSigma,
        ),
        child: AnimatedContainer(
          duration: AppAnimations.fast,
          decoration: BoxDecoration(
            color: AppColors.glassBackground,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor),
            boxShadow: [
              if (showHover)
                BoxShadow(
                  color: AppColors.primaryGlow.withValues(alpha: 0.2),
                  blurRadius: 16,
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Inner highlight at the top
              Container(
                height: _innerHighlightHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: borderRadius.topLeft,
                    topRight: borderRadius.topRight,
                  ),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: _innerHighlightAlpha),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Padding(
                padding:
                    widget.padding ?? const EdgeInsets.all(AppSpacing.lg),
                child: widget.child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
