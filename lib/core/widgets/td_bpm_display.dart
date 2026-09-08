import 'package:flutter/material.dart';

import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// TempoDeck BPM display with optional beat-sync pulse animation.
///
/// Shows the current BPM as a large, prominent number.
/// When [pulse] is called, the number briefly scales up (102%) and
/// a subtle glow appears, synced to the beat.
class TDBpmDisplay extends StatefulWidget {
  const TDBpmDisplay({
    required this.bpm,
    super.key,
    this.label = 'BPM',
  });

  final int bpm;
  final String label;

  @override
  State<TDBpmDisplay> createState() => TDBpmDisplayState();
}

/// Public state so parent widgets can call [pulse] on each beat.
class TDBpmDisplayState extends State<TDBpmDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: AppAnimations.fast,
    );
    _scaleAnimation = Tween<double>(
      begin: 1,
      end: AppAnimations.beatScalePeak,
    ).animate(
      CurvedAnimation(parent: _pulseController, curve: AppAnimations.snap),
    );
    _glowAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _pulseController, curve: AppAnimations.snap),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Trigger one beat pulse. Call this on each metronome beat.
  void pulse() {
    _pulseController
      ..reset()
      ..forward().then((_) {
        if (mounted) {
          _pulseController.reverse();
        }
      });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGlow
                          .withValues(alpha: _glowAnimation.value * 0.4),
                      blurRadius: 40,
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: Text(
                  '${widget.bpm}',
                  style: AppTextTheme.bpmDisplay,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.label,
                style: AppTextTheme.sectionLabel,
              ),
            ],
          ),
        );
      },
    );
  }
}
