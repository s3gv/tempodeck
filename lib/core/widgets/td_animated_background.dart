import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

/// Duration for the slow gradient rotation cycle.
const Duration _gradientCycleDuration = Duration(seconds: 8);

/// Durations for each of the three drifting orbs.
const Duration _orb1Duration = Duration(seconds: 6);
const Duration _orb2Duration = Duration(seconds: 10);
const Duration _orb3Duration = Duration(seconds: 14);

/// Orb visual sizes.
const double _orbSizeLarge = 250;
const double _orbSizeMedium = 200;
const double _orbSizeSmall = 150;

/// Orb blur and spread radii.
const double _orbBlurRadius = 150;
const double _orbSpreadRadius = 80;

/// Orb alpha range (low alpha for subtle glow).
const double _orbAlphaMin = 0.06;
const double _orbAlphaMax = 0.10;

/// Drift amplitude as fraction of screen dimension.
const double _driftAmplitude = 0.15;

/// Animated gradient background with drifting glow orbs.
///
/// Layer 1: A slowly rotating linear gradient across the background.
/// Layer 2: Three glow orbs that drift in slow sinusoidal paths.
/// The [child] is rendered on top of both layers.
///
/// Set [TDAnimatedBackground.disableAnimations] to `true` in tests to prevent
/// infinitely-repeating controllers from blocking `pumpAndSettle`.
class TDAnimatedBackground extends StatefulWidget {
  const TDAnimatedBackground({required this.child, super.key});

  /// When `true`, renders a static gradient background without animations.
  /// Useful in widget tests where `pumpAndSettle` must complete.
  static bool disableAnimations = false;

  final Widget child;

  @override
  State<TDAnimatedBackground> createState() => _TDAnimatedBackgroundState();
}

class _TDAnimatedBackgroundState extends State<TDAnimatedBackground>
    with TickerProviderStateMixin {
  AnimationController? _gradientController;
  AnimationController? _orb1Controller;
  AnimationController? _orb2Controller;
  AnimationController? _orb3Controller;

  @override
  void initState() {
    super.initState();

    if (TDAnimatedBackground.disableAnimations) return;

    _gradientController = AnimationController(
      vsync: this,
      duration: _gradientCycleDuration,
    )..repeat();

    _orb1Controller = AnimationController(
      vsync: this,
      duration: _orb1Duration,
    )..repeat();

    _orb2Controller = AnimationController(
      vsync: this,
      duration: _orb2Duration,
    )..repeat();

    _orb3Controller = AnimationController(
      vsync: this,
      duration: _orb3Duration,
    )..repeat();
  }

  @override
  void dispose() {
    _gradientController?.dispose();
    _orb1Controller?.dispose();
    _orb2Controller?.dispose();
    _orb3Controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (TDAnimatedBackground.disableAnimations) {
      return ColoredBox(
        color: AppColors.background,
        child: widget.child,
      );
    }

    return Stack(
      children: [
        // Layer 1: Animated gradient (fills entire space)
        Positioned.fill(
          child: CustomPaint(
            painter: _GradientPainter(animation: _gradientController!),
          ),
        ),

        // Layer 2: Drifting orbs
        _AnimatedOrb(
          controller: _orb1Controller!,
          orbSize: _orbSizeLarge,
          alpha: _orbAlphaMax,
          anchorFractionX: 0.75,
          anchorFractionY: 0.15,
        ),
        _AnimatedOrb(
          controller: _orb2Controller!,
          orbSize: _orbSizeMedium,
          alpha: 0.08,
          anchorFractionX: 0.15,
          anchorFractionY: 0.65,
        ),
        _AnimatedOrb(
          controller: _orb3Controller!,
          orbSize: _orbSizeSmall,
          alpha: _orbAlphaMin,
          anchorFractionX: 0.60,
          anchorFractionY: 0.50,
        ),

        // Child content on top
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

// ─── Gradient Painter ────────────────────────────────────────────────────────

class _GradientPainter extends CustomPainter {
  _GradientPainter({required this.animation}) : super(repaint: animation);

  final Animation<double> animation;

  static const _darkerShade = Color(0xFF06060A);

  @override
  void paint(Canvas canvas, Size size) {
    final angle = animation.value * 2 * pi;

    final begin = Alignment(cos(angle), sin(angle));
    final end = Alignment(-cos(angle), -sin(angle));

    final gradient = LinearGradient(
      begin: begin,
      end: end,
      colors: const [
        AppColors.backgroundGradientStart,
        AppColors.backgroundGradientEnd,
        _darkerShade,
      ],
    );

    final rect = Offset.zero & size;
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_GradientPainter oldDelegate) => true;
}

// ─── Animated Orb ────────────────────────────────────────────────────────────

class _AnimatedOrb extends StatelessWidget {
  const _AnimatedOrb({
    required this.controller,
    required this.orbSize,
    required this.alpha,
    required this.anchorFractionX,
    required this.anchorFractionY,
  });

  final AnimationController controller;
  final double orbSize;
  final double alpha;

  /// Anchor position as fraction of screen width (0..1).
  final double anchorFractionX;

  /// Anchor position as fraction of screen height (0..1).
  final double anchorFractionY;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final screenSize = MediaQuery.sizeOf(context);
        final angle = controller.value * 2 * pi;

        final driftX = sin(angle) * screenSize.width * _driftAmplitude;
        final driftY = cos(angle) * screenSize.height * _driftAmplitude;

        final centerX =
            screenSize.width * anchorFractionX + driftX - orbSize / 2;
        final centerY =
            screenSize.height * anchorFractionY + driftY - orbSize / 2;

        return Positioned(
          left: centerX,
          top: centerY,
          child: child!,
        );
      },
      child: IgnorePointer(
        child: Container(
          width: orbSize,
          height: orbSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGlow.withValues(alpha: alpha),
                blurRadius: _orbBlurRadius,
                spreadRadius: _orbSpreadRadius,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
