import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/accent_level.dart';
import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// TempoDeck design system beat indicator.
///
/// Renders circles representing beats in the current bar, wrapping into
/// multiple rows when needed. At most [maxDotsPerRow] dots per row and
/// [maxDots] dots total.
///
/// When [activateBeat] is called, the corresponding circle lights up with
/// instant attack and slow decay (200ms), matching the design guide spec.
///
/// Accent beats (beat 1 or [AccentLevel.high]) are 24dp with a glow shadow.
/// Normal beats are 20dp. Inactive beats use [AppColors.beatOff].
class TDBeatIndicator extends StatefulWidget {
  const TDBeatIndicator({
    required this.beatsPerBar,
    super.key,
  });

  final int beatsPerBar;

  @override
  State<TDBeatIndicator> createState() => TDBeatIndicatorState();
}

/// Public state so parent widgets can call [activateBeat] on each beat.
class TDBeatIndicatorState extends State<TDBeatIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  static const _accentSize = 24.0;
  static const _normalSize = 20.0;

  /// Maximum number of dots rendered per row before wrapping.
  static const maxDotsPerRow = 8;

  /// Maximum total dots rendered regardless of [beatsPerBar].
  static const maxDots = 32;

  int get _dotCount => math.min(widget.beatsPerBar, maxDots);

  @override
  void initState() {
    super.initState();
    _controllers = _createControllers(_dotCount);
    _accentLevels = List<AccentLevel>.filled(_dotCount, AccentLevel.normal);
  }

  @override
  void didUpdateWidget(TDBeatIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newCount = _dotCount;
    if (_controllers.length != newCount) {
      _disposeControllers();
      _controllers = _createControllers(newCount);
      _accentLevels = List<AccentLevel>.filled(newCount, AccentLevel.normal);
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  List<AnimationController> _createControllers(int count) {
    return List<AnimationController>.generate(
      count,
      (_) => AnimationController(
        vsync: this,
        duration: AppAnimations.beatDecay,
      ),
    );
  }

  void _disposeControllers() {
    for (final controller in _controllers) {
      controller.dispose();
    }
  }

  late List<AccentLevel> _accentLevels;

  /// Trigger the indicator for the given beat (1-indexed).
  ///
  /// The circle lights up instantly and fades out over [AppAnimations.beatDecay].
  /// The [accentLevel] determines the color used for the active state.
  void activateBeat(int beatIndex, AccentLevel accentLevel) {
    final index = beatIndex - 1;
    if (index < 0 || index >= _controllers.length) return;

    _accentLevels[index] = accentLevel;
    _controllers[index]
      ..value = 1.0
      ..reverse();
  }

  @override
  Widget build(BuildContext context) {
    final dotCount = _dotCount;
    final rowCount = (dotCount / maxDotsPerRow).ceil();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < rowCount; row++) ...[
          if (row > 0) const SizedBox(height: AppSpacing.sm),
          _buildRow(row, dotCount),
        ],
      ],
    );
  }

  Widget _buildRow(int rowIndex, int dotCount) {
    final start = rowIndex * maxDotsPerRow;
    final end = math.min(start + maxDotsPerRow, dotCount);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = start; i < end; i++) ...[
          if (i > start) const SizedBox(width: AppSpacing.sm),
          _BeatDot(
            controller: _controllers[i],
            accentLevel: _accentLevels[i],
          ),
        ],
      ],
    );
  }
}

class _BeatDot extends StatelessWidget {
  const _BeatDot({
    required this.controller,
    required this.accentLevel,
  });

  final AnimationController controller;
  final AccentLevel accentLevel;

  static const _glowAlpha = 0.6;
  static const _glowBlur = 20.0;
  static const _glowSpread = -4.0;

  @override
  Widget build(BuildContext context) {
    final isHigh = accentLevel == AccentLevel.high;
    final size = isHigh
        ? TDBeatIndicatorState._accentSize
        : TDBeatIndicatorState._normalSize;
    final activeColor = _colorForAccent(accentLevel);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final color =
            Color.lerp(AppColors.beatOff, activeColor, controller.value)!;
        final glowOpacity = isHigh ? controller.value * _glowAlpha : 0.0;

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: glowOpacity > 0
                ? [
                    BoxShadow(
                      color: AppColors.primaryGlow
                          .withValues(alpha: glowOpacity),
                      blurRadius: _glowBlur,
                      spreadRadius: _glowSpread,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }

  static Color _colorForAccent(AccentLevel level) {
    return switch (level) {
      AccentLevel.high => AppColors.beatAccent,
      AccentLevel.normal => AppColors.beatNormal,
      AccentLevel.low => AppColors.beatSubdivision,
      AccentLevel.mute => AppColors.beatOff,
    };
  }
}
