import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// TempoDeck floating play button for entering the live view.
///
/// Consistent across Metronome, Song Editor, and Setlist Editor screens.
/// Positioned at the bottom center, above the navigation bar safe area.
///
/// Features:
/// - Circular 56dp button with primary color and glow shadow
/// - Scale animation on press (96% → 100%)
/// - Play icon (28dp), replaced by a spinner while [onPlay] is running
class TDLiveAccessBar extends StatefulWidget {
  const TDLiveAccessBar({
    required this.onPlay,
    super.key,
  });

  /// Called when the user taps the play button. While the returned [Future]
  /// is pending, the button shows a loading spinner and ignores further taps.
  final Future<void> Function() onPlay;

  @override
  State<TDLiveAccessBar> createState() => _TDLiveAccessBarState();
}

class _TDLiveAccessBarState extends State<TDLiveAccessBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;
  bool _isLoading = false;

  static const _buttonSize = 56.0;
  static const _iconSize = 28.0;
  static const _spinnerSize = 22.0;

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

  void _handleTapDown(TapDownDetails _) {
    if (_isLoading) return;
    _scaleController.forward();
  }

  Future<void> _handleTapUp(TapUpDetails _) async {
    unawaited(_scaleController.reverse());
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await widget.onPlay();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleTapCancel() => _scaleController.reverse();

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Positioned(
      bottom: AppSpacing.lg + bottomPadding,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            );
          },
          child: Semantics(
            label: _isLoading ? 'Saving changes…' : 'Open live view',
            button: true,
            child: GestureDetector(
              onTapDown: _handleTapDown,
              onTapUp: _handleTapUp,
              onTapCancel: _handleTapCancel,
              child: Container(
                width: _buttonSize,
                height: _buttonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isLoading
                      ? AppColors.primary.withValues(alpha: 0.6)
                      : AppColors.primary,
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.primaryGlow,
                      blurRadius: 20,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: _isLoading
                    ? const Center(
                        child: SizedBox(
                          width: _spinnerSize,
                          height: _spinnerSize,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.play_arrow_rounded,
                        color: AppColors.textPrimary,
                        size: _iconSize,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
