import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// TempoDeck design system splash screen.
///
/// Displays a centered logo on [AppColors.backgroundDeep] with a rhythmic
/// pulse animation at [AppAnimations.splashPulseBpm] BPM. After a 2-second
/// hold the splash cross-fades into the [child] content.
///
/// Animation sequence:
///   1. Logo fades in over [AppAnimations.splashFadeIn] (600ms).
///   2. Logo pulses at 1.0↔1.03 scale (500ms per cycle, 120 BPM).
///   3. After ~2s the splash cross-fades to [child] over
///      [AppAnimations.splashCrossFade] (400ms).
class TDSplashScreen extends StatefulWidget {
  const TDSplashScreen({
    required this.child,
    required this.isReady,
    super.key,
  });

  /// The main app content shown after the splash animation completes.
  final Widget child;
  final bool isReady;

  @override
  State<TDSplashScreen> createState() => _TDSplashScreenState();
}

class _TDSplashScreenState extends State<TDSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeInController;
  late final Animation<double> _fadeInAnimation;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  late final AnimationController _crossFadeController;
  late final Animation<double> _crossFadeAnimation;
  Timer? _holdTimer;
  bool _minimumDisplayElapsed = false;
  bool _exitStarted = false;

  /// Scale amplitude for the pulse effect (1.0 → 1.03).
  static const _pulseScaleMin = 1.0;
  static const _pulseScaleMax = 1.07;
  static const _logoWidth = AppSpacing.xxl * 7;
  static const _screenGlowBaseOpacity = 0.14;
  static const _screenGlowPulseOpacity = 0.24;
  static const _edgeGlowBaseThickness = 0.055;
  static const _edgeGlowPulseThickness = 0.095;
  static const _cornerGlowBaseSize = 0.075;
  static const _cornerGlowPulseSize = 0.13;

  // Logo glow layer constants.
  static const _outerGlowBlurSigma = 28.0;
  static const _outerGlowOpacity = 0.42;
  static const _outerGlowScale = 1.08;
  static const _innerGlowBlurSigma = 12.0;
  static const _innerGlowOpacity = 0.6;
  static const _innerGlowScale = 1.03;

  /// Total time the splash is visible before the cross-fade begins.
  static const _splashHoldDuration = Duration(seconds: 2);

  /// 120 BPM = 500ms per beat cycle.
  static const _pulseDuration = Duration(
    milliseconds:
        Duration.millisecondsPerMinute ~/ AppAnimations.splashPulseBpm,
  );

  @override
  void initState() {
    super.initState();
    _initFadeIn();
    _initPulse();
    _initCrossFade();
    unawaited(_startSequence());
  }

  @override
  void didUpdateWidget(covariant TDSplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isReady && !oldWidget.isReady) {
      unawaited(_maybeStartExit());
    }
  }

  void _initFadeIn() {
    _fadeInController = AnimationController(
      vsync: this,
      duration: AppAnimations.splashFadeIn,
    );
    _fadeInAnimation = CurvedAnimation(
      parent: _fadeInController,
      curve: AppAnimations.enter,
    );
  }

  void _initPulse() {
    _pulseController = AnimationController(
      vsync: this,
      duration: _pulseDuration,
    );
    _pulseAnimation = Tween<double>(
      begin: _pulseScaleMin,
      end: _pulseScaleMax,
    ).animate(
      CurvedAnimation(parent: _pulseController, curve: AppAnimations.snap),
    );
  }

  void _initCrossFade() {
    _crossFadeController = AnimationController(
      vsync: this,
      duration: AppAnimations.splashCrossFade,
    );
    _crossFadeAnimation = CurvedAnimation(
      parent: _crossFadeController,
      curve: AppAnimations.smooth,
    );
  }

  Future<void> _startSequence() async {
    try {
      // 1. Fade the logo in.
      await _fadeInController.forward().orCancel;

      // 2. Begin pulsing and hold for the splash duration.
      unawaited(_pulseController.repeat(reverse: true));
      final holdCompleter = Completer<void>();
      _holdTimer = Timer(_splashHoldDuration, holdCompleter.complete);
      await holdCompleter.future;

      if (!mounted) {
        return;
      }

      _minimumDisplayElapsed = true;
      await _maybeStartExit();
    } on TickerCanceled {
      // The splash was disposed during shutdown or test teardown.
    }
  }

  Future<void> _maybeStartExit() async {
    if (!_minimumDisplayElapsed || !widget.isReady || _exitStarted || !mounted) {
      return;
    }

    _exitStarted = true;
    _pulseController.stop();
    await _crossFadeController.forward().orCancel;
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _fadeInController.dispose();
    _pulseController.dispose();
    _crossFadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _crossFadeAnimation,
      builder: (context, child) {
        // Once the cross-fade is complete, render only the child.
        if (_crossFadeAnimation.value >= 1.0) {
          return widget.child;
        }

        return Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Splash layer – fades out during cross-fade.
              Opacity(
                opacity: 1.0 - _crossFadeAnimation.value,
                child: _buildSplash(),
              ),

              // Main app layer – fades in during cross-fade.
              Opacity(
                opacity: _crossFadeAnimation.value,
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSplash() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final glowProgress =
            (_pulseAnimation.value - _pulseScaleMin) /
            (_pulseScaleMax - _pulseScaleMin);
        final glowOpacity = Tween<double>(
          begin: _screenGlowBaseOpacity,
          end: _screenGlowPulseOpacity,
        ).transform(glowProgress);
        final edgeGlowThickness = Tween<double>(
          begin: _edgeGlowBaseThickness,
          end: _edgeGlowPulseThickness,
        ).transform(glowProgress);
        final cornerGlowSize = Tween<double>(
          begin: _cornerGlowBaseSize,
          end: _cornerGlowPulseSize,
        ).transform(glowProgress);

        return ColoredBox(
          color: AppColors.backgroundDeep,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: _buildScreenEdgeGlow(
                  opacity: glowOpacity,
                  thickness: edgeGlowThickness,
                  cornerSize: cornerGlowSize,
                ),
              ),
              Center(
                child: FadeTransition(
                  opacity: _fadeInAnimation,
                  child: _buildPulsingLogo(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPulsingLogo() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        );
      },
      child: _buildLogo(),
    );
  }

  Widget _buildLogo() {
    return Stack(
      alignment: Alignment.center,
      children: [
        _buildLogoGlowLayer(
          blurSigma: _outerGlowBlurSigma,
          opacity: _outerGlowOpacity,
          scale: _outerGlowScale,
        ),
        _buildLogoGlowLayer(
          blurSigma: _innerGlowBlurSigma,
          opacity: _innerGlowOpacity,
          scale: _innerGlowScale,
        ),
        Image.asset(
          'assets/images/splash_logo.png',
          width: _logoWidth,
          filterQuality: FilterQuality.high,
        ),
      ],
    );
  }

  Widget _buildLogoGlowLayer({
    required double blurSigma,
    required double opacity,
    required double scale,
  }) {
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              AppColors.primaryGlow,
              BlendMode.srcATop,
            ),
            child: Image.asset(
              'assets/images/splash_logo.png',
              width: _logoWidth,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScreenEdgeGlow({
    required double opacity,
    required double thickness,
    required double cornerSize,
  }) {
    return Opacity(
      opacity: opacity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              widthFactor: 1,
              heightFactor: thickness,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primaryGlow.withValues(alpha: 0.82),
                      AppColors.primary.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.35, 1],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              widthFactor: 1,
              heightFactor: thickness,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.primaryGlow.withValues(alpha: 0.82),
                      AppColors.primary.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.35, 1],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: thickness,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppColors.primaryGlow.withValues(alpha: 0.82),
                      AppColors.primary.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.35, 1],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: thickness,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [
                      AppColors.primaryGlow.withValues(alpha: 0.82),
                      AppColors.primary.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.35, 1],
                  ),
                ),
              ),
            ),
          ),
          ...[
            Alignment.topLeft,
            Alignment.topRight,
            Alignment.bottomLeft,
            Alignment.bottomRight,
          ].map(
            (alignment) => Align(
              alignment: alignment,
              child: FractionallySizedBox(
                widthFactor: cornerSize,
                heightFactor: cornerSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: alignment,
                      radius: 1.15,
                      colors: [
                        AppColors.primaryGlow.withValues(alpha: 0.9),
                        AppColors.primary.withValues(alpha: 0.22),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.34, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
