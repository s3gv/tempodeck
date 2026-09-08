import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_variant_provider.dart';
import '../../core/theme/app_animations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_theme.dart';
import '../../core/widgets/td_animated_background.dart';
import '../../core/widgets/td_beat_indicator.dart';
import '../../core/widgets/td_bpm_display.dart';
import 'live_event.dart';
import 'live_screen_controller.dart';
import 'live_screen_state.dart';
import 'live_view_context.dart';

/// Full-screen beat visualization for live metronome, song, and setlist playback.
///
/// Features:
/// - Context header ("LIVE – Metronome" / song title / setlist title)
/// - BPM display with beat-sync pulse
/// - Beat indicator row
/// - Current and next event display (multiple simultaneous events)
/// - Dedicated exit control, with dismiss/back blocked while playback is active
/// - Swipe-up dismiss on mobile only when playback is stopped
/// - Space key playback toggle on desktop
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  final _bpmDisplayKey = GlobalKey<TDBpmDisplayState>();
  final _beatIndicatorKey = GlobalKey<TDBeatIndicatorState>();

  static const _maxContentWidth = 480.0;
  static const _dragHandleWidth = 40.0;
  static const _dragHandleHeight = 4.0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveScreenControllerProvider);
    final controller = ref.read(liveScreenControllerProvider.notifier);
    final liveContext = ref.watch(liveViewContextProvider);
    final isDesktop = ref.watch(appVariantProvider).isDesktop;
    final canExit = !state.isPlaying && !state.isStarting && !state.isTransitioning;

    // Trigger pulse + beat indicator on state changes.
    ref.listen<LiveScreenState>(liveScreenControllerProvider, (prev, next) {
      if (prev == null) return;

      // Pulse BPM display on every beat (pulse index 1).
      if (next.pulseIndex == 1 && prev.pulseIndex != 1) {
        _bpmDisplayKey.currentState?.pulse();
      }

      // Activate beat indicator on beat change.
      if (next.beatIndex != prev.beatIndex && next.beatIndex > 0) {
        _beatIndicatorKey.currentState?.activateBeat(
          next.beatIndex,
          next.accentLevel,
        );
      }
    });

    final mainContent = TDAnimatedBackground(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: OrientationBuilder(
              builder: (context, orientation) {
                if (orientation == Orientation.landscape) {
                  return _buildLandscapeLayout(
                    state,
                    controller,
                    liveContext,
                    isDesktop,
                    canExit,
                  );
                }
                return _buildPortraitLayout(
                  state,
                  controller,
                  liveContext,
                  isDesktop,
                  canExit,
                );
              },
            ),
          ),
        ),
      ),
    );

    // On desktop, overlay the exit button in the platform-appropriate corner.
    final content = isDesktop
        ? Stack(
            children: [
              mainContent,
              Positioned(
                top: AppSpacing.md,
                left: Platform.isMacOS ? AppSpacing.md : null,
                right: Platform.isMacOS ? null : AppSpacing.md,
                child: SafeArea(
                  child: _ExitButton(
                    canExit: canExit,
                    onPressed: () => context.pop(),
                  ),
                ),
              ),
            ],
          )
        : mainContent;

    final protectedContent = PopScope<void>(
      canPop: canExit,
      child: isDesktop
          ? _DesktopShortcutScope(
              onTogglePlayback: () => unawaited(controller.togglePlayback()),
              canExit: canExit,
              onExit: () => context.pop(),
              child: content,
            )
          : _SwipeUpDismissWrapper(
              canDismiss: canExit,
              child: content,
            ),
    );

    return protectedContent;
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        width: _dragHandleWidth,
        height: _dragHandleHeight,
        decoration: BoxDecoration(
          color: AppColors.textMuted,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }

  // ── Portrait layout (existing Column layout) ────────────────────────────

  Widget _buildPortraitLayout(
    LiveScreenState state,
    LiveScreenController controller,
    LiveViewContext liveContext,
    bool isDesktop,
    bool canExit,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxContentWidth),
      child: Column(
        children: [
          // ── Drag handle (mobile) ──
          if (!isDesktop) ...[
            const SizedBox(height: AppSpacing.sm),
            _TopBar(
              canExit: canExit,
              onExit: () => context.pop(),
              dragHandle: _buildDragHandle(),
            ),
          ],
          // Desktop exit button is positioned via Stack overlay — not here.
          const SizedBox(height: AppSpacing.xl),

          // ── Context header ──
          _ContextHeader(liveContext: liveContext),

          if (state.currentSongTitle != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _SetlistSongInfo(
              songTitle: state.currentSongTitle!,
              songIndex: state.currentSongIndex ?? 0,
              totalSongs: state.totalSongs ?? 0,
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          // ── Time signature + position ──
          _PositionRow(
            timeSignatureLabel: '${state.beatsPerBar}/${state.beatUnit}',
            barIndex: state.barIndex,
            barLabel: state.barLabel,
            beatIndex: state.beatIndex,
            isPlaying: state.isPlaying,
          ),

          if (state.isTransitioning &&
              state.transitionMessage != null &&
              !state.isWaitingForManualAdvance) ...[
            const Spacer(),
            Text(
              state.transitionMessage!,
              style: AppTextTheme.heading3.copyWith(color: AppColors.primary),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
          ] else ...[
            if (state.isWaitingForManualAdvance &&
                state.transitionMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                state.transitionMessage!,
                style: AppTextTheme.heading3.copyWith(color: AppColors.primary),
                textAlign: TextAlign.center,
              ),
            ],
            const Spacer(),

            // ── BPM display ──
            TDBpmDisplay(
              key: _bpmDisplayKey,
              bpm: state.bpm,
            ),

            if (state.intervalRemainingSeconds != null ||
                state.maxDurationRemainingSeconds != null) ...[
              const SizedBox(height: AppSpacing.sm),
              if (state.intervalRemainingSeconds != null)
                _IntervalCountdown(
                  label: 'Interval',
                  remainingSeconds: state.intervalRemainingSeconds!,
                ),
              if (state.maxDurationRemainingSeconds != null) ...[
                if (state.intervalRemainingSeconds != null)
                  const SizedBox(height: AppSpacing.xs),
                _IntervalCountdown(
                  label: 'Total',
                  remainingSeconds: state.maxDurationRemainingSeconds!,
                ),
              ],
            ],

            const SizedBox(height: AppSpacing.xl),

            // ── Beat indicator ──
            TDBeatIndicator(
              key: _beatIndicatorKey,
              beatsPerBar: state.beatsPerBar,
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── Event display ──
            _EventDisplay(
              currentEvents: state.currentEvents,
              nextEvents: state.nextEvents,
            ),

            const Spacer(),
          ],

          // ── Play/Stop button ──
          _PlayStopButton(
            isPlaying: state.isPlaying,
            isStarting: state.isStarting,
            onPressed: () => unawaited(controller.togglePlayback()),
          ),

          if (isDesktop) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Press Space to ${state.isPlaying ? 'stop' : 'start'}',
              style: AppTextTheme.labelSmall,
            ),
          ],

          // ── Setlist control bar ──
          if (liveContext is SetlistViewContext) ...[
            const SizedBox(height: AppSpacing.lg),
            _SetlistControlBar(
              controller: controller,
              isDisabled: state.isPlaying || state.isTransitioning,
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  // ── Landscape layout (two-panel Row layout) ─────────────────────────────

  Widget _buildLandscapeLayout(
    LiveScreenState state,
    LiveScreenController controller,
    LiveViewContext liveContext,
    bool isDesktop,
    bool canExit,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left panel: BPM + play button
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (state.isTransitioning &&
                  state.transitionMessage != null &&
                  !state.isWaitingForManualAdvance)
                Text(
                  state.transitionMessage!,
                  style:
                      AppTextTheme.heading3.copyWith(color: AppColors.primary),
                  textAlign: TextAlign.center,
                )
              else
                TDBpmDisplay(
                  key: _bpmDisplayKey,
                  bpm: state.bpm,
                ),
              const SizedBox(height: AppSpacing.lg),
              _PlayStopButton(
                isPlaying: state.isPlaying,
                isStarting: state.isStarting,
                onPressed: () => unawaited(controller.togglePlayback()),
              ),
            ],
          ),
        ),
        // Right panel: header + position + beat + events
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Desktop exit button is positioned via Stack overlay — not here.
              const SizedBox.shrink(),
              const SizedBox(height: AppSpacing.md),
              _ContextHeader(liveContext: liveContext),
              if (state.currentSongTitle != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _SetlistSongInfo(
                  songTitle: state.currentSongTitle!,
                  songIndex: state.currentSongIndex ?? 0,
                  totalSongs: state.totalSongs ?? 0,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _PositionRow(
                timeSignatureLabel: '${state.beatsPerBar}/${state.beatUnit}',
                barIndex: state.barIndex,
                barLabel: state.barLabel,
                beatIndex: state.beatIndex,
                isPlaying: state.isPlaying,
              ),
              const SizedBox(height: AppSpacing.lg),
              TDBeatIndicator(
                key: _beatIndicatorKey,
                beatsPerBar: state.beatsPerBar,
              ),
              const SizedBox(height: AppSpacing.lg),
              _EventDisplay(
                currentEvents: state.currentEvents,
                nextEvents: state.nextEvents,
              ),
              if (isDesktop) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Press Space to ${state.isPlaying ? 'stop' : 'start'}',
                  style: AppTextTheme.labelSmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Setlist Song Info ───────────────────────────────────────────────────────

class _SetlistSongInfo extends StatelessWidget {
  const _SetlistSongInfo({
    required this.songTitle,
    required this.songIndex,
    required this.totalSongs,
  });

  final String songTitle;
  final int songIndex;
  final int totalSongs;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$songIndex / $totalSongs',
          style: AppTextTheme.labelSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          songTitle,
          style: AppTextTheme.heading3,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }
}

// ─── Context Header ──────────────────────────────────────────────────────────

class _ContextHeader extends StatelessWidget {
  const _ContextHeader({required this.liveContext});

  final LiveViewContext liveContext;

  @override
  Widget build(BuildContext context) {
    return Text(
      'LIVE – ${liveContext.modeLabel}'.toUpperCase(),
      style: AppTextTheme.sectionLabel,
      textAlign: TextAlign.center,
    );
  }
}

// ─── Position Row ────────────────────────────────────────────────────────────

class _PositionRow extends StatelessWidget {
  const _PositionRow({
    required this.timeSignatureLabel,
    required this.barIndex,
    required this.barLabel,
    required this.beatIndex,
    required this.isPlaying,
  });

  final String timeSignatureLabel;
  final int barIndex;
  final String? barLabel;
  final int beatIndex;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final resolvedBarLabel = barLabel ?? '$barIndex';
    final positionText = isPlaying && barIndex > 0
        ? 'Bar $resolvedBarLabel · Beat $beatIndex'
        : 'Stopped';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(timeSignatureLabel, style: AppTextTheme.numericLarge),
        const SizedBox(width: AppSpacing.lg),
        Text(positionText, style: AppTextTheme.label),
      ],
    );
  }
}

// ─── Event Display ───────────────────────────────────────────────────────────

class _EventDisplay extends StatelessWidget {
  const _EventDisplay({
    required this.currentEvents,
    required this.nextEvents,
  });

  final List<LiveEvent> currentEvents;
  final List<LiveEvent> nextEvents;

  @override
  Widget build(BuildContext context) {
    if (currentEvents.isEmpty && nextEvents.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (currentEvents.isNotEmpty) ...[
          for (final event in currentEvents)
            _EventRow(
              event: event,
              color: AppColors.primary,
              textStyle: AppTextTheme.body,
            ),
          if (nextEvents.isNotEmpty) const SizedBox(height: AppSpacing.sm),
        ],
        if (nextEvents.isNotEmpty)
          for (final event in nextEvents)
            _EventRow(
              event: event,
              color: AppColors.textMuted,
              textStyle: AppTextTheme.bodySecondary,
              prefix: 'Next: ',
            ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.color,
    required this.textStyle,
    this.prefix = '',
  });

  final LiveEvent event;
  final Color color;
  final TextStyle textStyle;
  final String prefix;

  static const _iconSize = 18.0;

  @override
  Widget build(BuildContext context) {
    final barLabel = event.displayBarLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(event.icon, size: _iconSize, color: color),
          if (barLabel != null) ...[
            const SizedBox(width: AppSpacing.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: color.withValues(alpha: 0.24)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs / 2,
                ),
                child: Text(
                  barLabel,
                  style: AppTextTheme.labelSmall.copyWith(color: color),
                ),
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              '$prefix${event.label}',
              style: textStyle.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Play/Stop Button ────────────────────────────────────────────────────────

class _PlayStopButton extends StatefulWidget {
  const _PlayStopButton({
    required this.isPlaying,
    required this.isStarting,
    required this.onPressed,
  });

  final bool isPlaying;
  final bool isStarting;
  final VoidCallback onPressed;

  @override
  State<_PlayStopButton> createState() => _PlayStopButtonState();
}

class _PlayStopButtonState extends State<_PlayStopButton>
    with SingleTickerProviderStateMixin {
  static const _buttonSize = 112.0;
  static const _iconSize = 44.0;
  static const _glowDuration = Duration(milliseconds: 1500);
  static const _baseBlur = 20.0;
  static const _peakBlur = 40.0;
  static const _baseAlpha = 0.25;
  static const _peakAlpha = 0.5;

  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: _glowDuration,
    );
    if (widget.isPlaying && !TDAnimatedBackground.disableAnimations) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_PlayStopButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !oldWidget.isPlaying) {
      if (!TDAnimatedBackground.disableAnimations) {
        _glowController.repeat(reverse: true);
      }
    } else if (!widget.isPlaying && oldWidget.isPlaying) {
      _glowController.stop();
      _glowController.reset();
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semanticsLabel = widget.isStarting
        ? 'Starting...'
        : widget.isPlaying
            ? 'Stop'
            : 'Play';
    final icon = widget.isStarting
        ? Icons.hourglass_top
        : widget.isPlaying
            ? Icons.stop_rounded
            : Icons.play_arrow_rounded;

    final button = Tooltip(
      message: semanticsLabel,
      child: Semantics(
        button: true,
        enabled: !widget.isStarting,
        label: semanticsLabel,
        child: SizedBox(
          width: _buttonSize,
          height: _buttonSize,
          child: FilledButton(
            key: const Key('livePlayStopButton'),
            onPressed: widget.isStarting ? null : widget.onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textPrimary,
              disabledBackgroundColor: AppColors.primaryDark,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: Icon(icon, size: _iconSize),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final t = _glowController.value;
        final blur = _baseBlur + (_peakBlur - _baseBlur) * t;
        final alpha = _baseAlpha + (_peakAlpha - _baseAlpha) * t;

        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: widget.isPlaying
                ? [
                    BoxShadow(
                      color: AppColors.primaryGlow.withValues(alpha: alpha),
                      blurRadius: blur,
                    ),
                  ]
                : [],
          ),
          child: child,
        );
      },
      child: button,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.canExit,
    required this.onExit,
    required this.dragHandle,
  });

  final bool canExit;
  final VoidCallback onExit;
  final Widget dragHandle;

  /// Width of the spacer that balances the exit button so the drag handle
  /// stays centered.
  static const _exitButtonCounterbalanceWidth = 40.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: _exitButtonCounterbalanceWidth),
        Expanded(child: dragHandle),
        _ExitButton(
          canExit: canExit,
          onPressed: onExit,
        ),
      ],
    );
  }
}

class _ExitButton extends StatelessWidget {
  const _ExitButton({
    required this.canExit,
    required this.onPressed,
  });

  final bool canExit;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('liveExitButton'),
      onPressed: canExit ? onPressed : null,
      tooltip: canExit ? 'Close live view' : 'Stop playback to close live view',
      icon: const Icon(Icons.close_rounded),
      color: AppColors.textPrimary,
      disabledColor: AppColors.textMuted,
    );
  }
}

// ─── Interval Countdown ──────────────────────────────────────────────────────

class _IntervalCountdown extends StatelessWidget {
  const _IntervalCountdown({
    required this.label,
    required this.remainingSeconds,
  });

  final String label;
  final int remainingSeconds;

  @override
  Widget build(BuildContext context) {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');

    return Text(
      '$label: $mm:$ss',
      style: AppTextTheme.label.copyWith(color: AppColors.primary),
      textAlign: TextAlign.center,
    );
  }
}

// ─── Setlist Control Bar ─────────────────────────────────────────────────────

class _SetlistControlBar extends StatefulWidget {
  const _SetlistControlBar({
    required this.controller,
    required this.isDisabled,
  });

  final LiveScreenController controller;
  final bool isDisabled;

  @override
  State<_SetlistControlBar> createState() => _SetlistControlBarState();
}

class _SetlistControlBarState extends State<_SetlistControlBar> {
  late bool _transitionEnabled;

  @override
  void initState() {
    super.initState();
    _transitionEnabled = widget.controller.isTransitionEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final disabledOpacity = widget.isDisabled ? 0.45 : 1.0;

    return Opacity(
      opacity: disabledOpacity,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous song',
            onPressed: widget.isDisabled
                ? null
                : () => unawaited(widget.controller.jumpToPreviousSetlistSong()),
            color: AppColors.textPrimary,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next song',
            onPressed: widget.isDisabled
                ? null
                : () => unawaited(widget.controller.jumpToNextSetlistSong()),
            color: AppColors.textPrimary,
          ),
          const Spacer(),
          Text(
            'Transition',
            style: AppTextTheme.label.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Switch(
            value: _transitionEnabled,
            onChanged: widget.isDisabled
                ? null
                : (value) {
                    setState(() => _transitionEnabled = value);
                    widget.controller.setTransitionEnabled(value);
                  },
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

// ─── Swipe-Up Dismiss (Mobile) ───────────────────────────────────────────────

class _SwipeUpDismissWrapper extends StatefulWidget {
  const _SwipeUpDismissWrapper({
    required this.canDismiss,
    required this.child,
  });

  final bool canDismiss;
  final Widget child;

  @override
  State<_SwipeUpDismissWrapper> createState() => _SwipeUpDismissWrapperState();
}

class _SwipeUpDismissWrapperState extends State<_SwipeUpDismissWrapper>
    with SingleTickerProviderStateMixin {
  static const _transformKey = Key('liveDismissTransform');
  double _dragOffset = 0;
  late final AnimationController _springController;
  late Animation<double> _springAnimation;

  static const _dismissThresholdFraction = 0.2;
  static const _dismissVelocity = 300.0;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: AppAnimations.normal,
    );
    _springAnimation =
        Tween<double>(begin: 0, end: 0).animate(_springController);
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SwipeUpDismissWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.canDismiss && oldWidget.canDismiss && _dragOffset != 0) {
      _animateBackToOrigin();
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!widget.canDismiss) {
      return;
    }
    // Only allow upward drag (negative dy).
    if (details.delta.dy < 0 || _dragOffset < 0) {
      setState(() {
        _dragOffset += details.delta.dy;
        _dragOffset = _dragOffset.clamp(-double.infinity, 0);
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!widget.canDismiss) {
      if (_dragOffset != 0) {
        _animateBackToOrigin();
      }
      return;
    }
    final screenHeight = MediaQuery.sizeOf(context).height;
    final fraction = _dragOffset.abs() / screenHeight;
    final velocity = details.primaryVelocity ?? 0;

    if (fraction > _dismissThresholdFraction || velocity < -_dismissVelocity) {
      // Dismiss: animate off screen then pop.
      _springAnimation = Tween<double>(
        begin: _dragOffset,
        end: -screenHeight,
      ).animate(
        CurvedAnimation(
          parent: _springController,
          curve: AppAnimations.exit,
        ),
      );
      _springController
        ..reset()
        ..forward().then((_) {
          if (mounted) {
            context.pop();
          }
        });
    } else {
      _animateBackToOrigin();
    }
  }

  void _animateBackToOrigin() {
    _springAnimation = Tween<double>(
      begin: _dragOffset,
      end: 0,
    ).animate(
      CurvedAnimation(
        parent: _springController,
        curve: AppAnimations.smooth,
      ),
    );
    _springController
      ..reset()
      ..forward().then((_) {
        if (mounted) {
          setState(() => _dragOffset = 0);
        }
      });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: AnimatedBuilder(
        animation: _springController,
        builder: (context, child) {
          final offset = _springController.isAnimating
              ? _springAnimation.value
              : _dragOffset;
          return Transform.translate(
            key: _transformKey,
            offset: Offset(0, offset),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

// ─── Desktop Shortcut Scope ──────────────────────────────────────────────────

class _DesktopShortcutScope extends StatefulWidget {
  const _DesktopShortcutScope({
    required this.onTogglePlayback,
    required this.canExit,
    required this.onExit,
    required this.child,
  });

  final VoidCallback onTogglePlayback;
  final bool canExit;
  final VoidCallback onExit;
  final Widget child;

  @override
  State<_DesktopShortcutScope> createState() => _DesktopShortcutScopeState();
}

class _DesktopShortcutScopeState extends State<_DesktopShortcutScope> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      widget.onTogglePlayback();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && widget.canExit) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _focusNode.requestFocus(),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: widget.child,
      ),
    );
  }
}
