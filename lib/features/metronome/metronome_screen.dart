import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/tap_tempo_detector.dart';
import '../../core/domain/accent_level.dart';
import '../../core/domain/interval_settings.dart';
import '../../core/domain/metronome_preset.dart';
import '../../core/domain/subdivision.dart';
import '../../core/providers/app_variant_provider.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_animations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_theme.dart';
import '../../core/widgets/td_accent_grid.dart';
import '../../core/widgets/td_animated_background.dart';
import '../../core/widgets/td_button.dart';
import '../../core/widgets/td_card.dart';
import '../../core/widgets/td_dialog.dart';
import '../../core/widgets/td_dropdown_card.dart';
import '../../core/widgets/td_list_tile.dart';
import '../../core/widgets/td_live_access_bar.dart';
import '../../core/widgets/td_section_header.dart';
import '../../core/widgets/td_slider.dart';
import '../../core/widgets/td_stepper.dart';
import '../../core/widgets/td_text_field.dart';
import '../../core/widgets/td_toggle.dart';
import '../live/live_view_context.dart';
import 'metronome_interval_preview_builder.dart';
import 'metronome_preset_list_provider.dart';
import 'metronome_screen_controller.dart';
import 'metronome_screen_state.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const double _bpmStepperIconSize = 28;
const double _tapTempoButtonSize = 64;
const double _tapTempoBorderWidth = 1.5;
const double _tapTempoScalePressed = 0.95;
const double _tapTempoFeedbackScalePeak = 1.32;
const double _tapTempoFeedbackScalePeakResolved = 1.46;
const double _tapTempoFeedbackOpacityPeak = 0.22;
const double _tapTempoFeedbackOpacityPeakResolved = 0.34;
const double _tapTempoFeedbackBlur = 16;
const double _tapTempoFeedbackBlurResolved = 24;
const int _durationMinClamp = 0;
const int _durationMaxClamp = 59;

class MetronomeScreen extends ConsumerStatefulWidget {
  const MetronomeScreen({
    super.key,
    this.intervalPreviewBuilder = const MetronomeIntervalPreviewBuilder(),
  });

  final MetronomeIntervalPreviewBuilder intervalPreviewBuilder;

  @override
  ConsumerState<MetronomeScreen> createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends ConsumerState<MetronomeScreen> {
  bool _rhythmExpanded = true;
  bool _intervalExpanded = false;
  bool _presetsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(metronomeScreenControllerProvider);
    final controller = ref.read(metronomeScreenControllerProvider.notifier);
    final presetList = ref.watch(metronomePresetListProvider);
    final isMobile = !ref.watch(appVariantProvider).isDesktop;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Metronome', style: AppTextTheme.heading2),
        backgroundColor: Colors.transparent,
      ),
      body: TDAnimatedBackground(
        child: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                isMobile ? 100 : AppSpacing.lg,
              ),
              children: [
                _buildTempoSection(state, controller),
                const SizedBox(height: AppSpacing.lg),
                _buildRhythmHeader(),
                if (_rhythmExpanded) ...[
                  const SizedBox(height: AppSpacing.md),
                  _buildRhythmSection(state, controller),
                ],
                const SizedBox(height: AppSpacing.lg),
                _buildIntervalHeader(),
                if (_intervalExpanded) ...[
                  const SizedBox(height: AppSpacing.md),
                  _buildIntervalSection(state, controller),
                ],
                const SizedBox(height: AppSpacing.lg),
                _buildPresetsHeader(),
                if (_presetsExpanded) ...[
                  const SizedBox(height: AppSpacing.md),
                  _buildPresetsSection(presetList, state, controller),
                ],
              ],
            ),

            // Live access bar
            if (isMobile)
              TDLiveAccessBar(
                onPlay: () async {
                  ref
                      .read(liveViewContextProvider.notifier)
                      .set(const MetronomeViewContext());
                  context.go(Routes.live);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Section builders (kept shallow) ──────────────────────────────────────

  Widget _buildTempoSection(
    MetronomeScreenState state,
    MetronomeScreenController controller,
  ) {
    return _TempoSection(
      bpm: state.bpm,
      tapTempoTapCount: state.tapTempoTapCount,
      onBpmChanged: (value) => controller.setBpm(value.round()),
      onTapTempo: controller.tapTempo,
    );
  }

  Widget _buildRhythmHeader() {
    return TDSectionHeader(
      icon: Icons.music_note,
      label: 'Time & Rhythm',
      isExpanded: _rhythmExpanded,
      onToggle: () => setState(() => _rhythmExpanded = !_rhythmExpanded),
    );
  }

  Widget _buildRhythmSection(
    MetronomeScreenState state,
    MetronomeScreenController controller,
  ) {
    return _RhythmSection(
      beatsPerBar: state.beatsPerBar,
      beatUnit: state.beatUnit,
      subdivision: state.subdivision,
      accentPattern: state.accentPattern,
      onBeatsPerBarChanged: controller.setBeatsPerBar,
      onBeatUnitChanged: controller.setBeatUnit,
      onSubdivisionChanged: controller.setSubdivision,
      onAccentChanged: controller.setAccentAt,
    );
  }

  Widget _buildIntervalHeader() {
    return TDSectionHeader(
      icon: Icons.replay,
      label: 'Interval Mode',
      isExpanded: _intervalExpanded,
      onToggle: () => setState(() => _intervalExpanded = !_intervalExpanded),
    );
  }

  Widget _buildIntervalSection(
    MetronomeScreenState state,
    MetronomeScreenController controller,
  ) {
    return _IntervalSection(
      intervalSettings: state.intervalSettings,
      bpm: state.bpm,
      intervalPreviewBuilder: widget.intervalPreviewBuilder,
      onModeEnabledChanged: controller.setIntervalModeEnabled,
      onIntervalMinutesChanged: controller.setIntervalDurationMinutes,
      onIntervalSecondsChanged: controller.setIntervalDurationSeconds,
      onBpmStepEnabledChanged: controller.setBpmStepEnabled,
      onIncrementBpmStep: controller.incrementBpmStep,
      onDecrementBpmStep: controller.decrementBpmStep,
      onMaxDurationEnabledChanged: controller.setMaximumDurationEnabled,
      onMaxDurationMinutesChanged: controller.setMaximumDurationMinutes,
      onMaxDurationSecondsChanged: controller.setMaximumDurationSeconds,
    );
  }

  Widget _buildPresetsHeader() {
    return TDSectionHeader(
      icon: Icons.bookmarks_outlined,
      label: 'Presets',
      isExpanded: _presetsExpanded,
      onToggle: () => setState(
        () => _presetsExpanded = !_presetsExpanded,
      ),
    );
  }

  Widget _buildPresetsSection(
    AsyncValue<List<MetronomePreset>> presetList,
    MetronomeScreenState state,
    MetronomeScreenController controller,
  ) {
    return _PresetsSection(
      presetList: presetList,
      appliedPresetId: state.appliedPresetId,
      onApply: controller.applyPreset,
      onSaveCurrent: controller.saveCurrentPreset,
      onRename: controller.renamePreset,
      onDelete: controller.deletePreset,
    );
  }
}

// ─── Tempo Section ───────────────────────────────────────────────────────────

class _TempoSection extends StatefulWidget {
  const _TempoSection({
    required this.bpm,
    required this.tapTempoTapCount,
    required this.onBpmChanged,
    required this.onTapTempo,
  });

  final int bpm;
  final int tapTempoTapCount;
  final ValueChanged<double> onBpmChanged;
  final TapTempoResult? Function() onTapTempo;

  @override
  State<_TempoSection> createState() => _TempoSectionState();
}

class _TempoSectionState extends State<_TempoSection>
    with TickerProviderStateMixin {
  late final AnimationController _tapScaleController;
  late final AnimationController _tapFeedbackController;
  late final Animation<double> _tapScaleAnimation;
  late final Animation<double> _tapFeedbackScaleAnimation;
  late final Animation<double> _tapFeedbackOpacityAnimation;
  bool _showResolvedFeedback = false;

  @override
  void initState() {
    super.initState();
    _tapScaleController = AnimationController(
      vsync: this,
      duration: AppAnimations.fast,
    );
    _tapScaleAnimation = Tween<double>(
      begin: 1,
      end: _tapTempoScalePressed,
    ).animate(
      CurvedAnimation(
        parent: _tapScaleController,
        curve: AppAnimations.snap,
      ),
    );
    _tapFeedbackController = AnimationController(
      vsync: this,
      duration: AppAnimations.normal,
    );
    _tapFeedbackScaleAnimation = CurvedAnimation(
      parent: _tapFeedbackController,
      curve: AppAnimations.enter,
    );
    _tapFeedbackOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 1),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0),
        weight: 75,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _tapFeedbackController,
        curve: AppAnimations.smooth,
      ),
    );
  }

  @override
  void dispose() {
    _tapScaleController.dispose();
    _tapFeedbackController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) => _tapScaleController.forward();

  void _handleTapUp(TapUpDetails _) => _tapScaleController.reverse();

  void _handleTapCancel() => _tapScaleController.reverse();

  void _handleTap() {
    final result = widget.onTapTempo();
    _triggerTapFeedback(resolvedTempo: result != null);
  }

  void _triggerTapFeedback({required bool resolvedTempo}) {
    setState(() {
      _showResolvedFeedback = resolvedTempo;
    });
    _tapFeedbackController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final isAtMin =
        widget.bpm <= MetronomeScreenController.minimumBpm;
    final isAtMax =
        widget.bpm >= MetronomeScreenController.maximumBpm;

    return TDCard(
      glassEffect: true,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('bpm-decrement'),
                onPressed: isAtMin
                    ? null
                    : () => widget.onBpmChanged(
                          (widget.bpm - 1).toDouble(),
                        ),
                icon: Icon(
                  Icons.remove_circle_outline,
                  size: _bpmStepperIconSize,
                  color: isAtMin
                      ? AppColors.textMuted
                      : AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('${widget.bpm}', style: AppTextTheme.bpmDisplaySmall),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                key: const Key('bpm-increment'),
                onPressed: isAtMax
                    ? null
                    : () => widget.onBpmChanged(
                          (widget.bpm + 1).toDouble(),
                        ),
                icon: Icon(
                  Icons.add_circle_outline,
                  size: _bpmStepperIconSize,
                  color: isAtMax
                      ? AppColors.textMuted
                      : AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text('BPM', style: AppTextTheme.sectionLabel),
          const SizedBox(height: AppSpacing.md),
          _buildSliderWithTapTempo(),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _tapTempoHintText(),
            key: const Key('tap-tempo-hint'),
            style: AppTextTheme.labelSmall.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  String _tapTempoHintText() {
    if (widget.tapTempoTapCount == 0) {
      return 'Tap ${TapTempoDetector.minimumTapCount}x to detect tempo';
    }

    final tapsRemaining =
        TapTempoDetector.minimumTapCount - widget.tapTempoTapCount;
    if (tapsRemaining <= 0) {
      return 'Tempo detected';
    }

    return '$tapsRemaining taps left';
  }

  Widget _buildSliderWithTapTempo() {
    return Row(
      children: [
        Expanded(
          child: TDSlider(
            key: const Key('bpm-slider'),
            value: widget.bpm.toDouble(),
            min: MetronomeScreenController.minimumBpm.toDouble(),
            max: MetronomeScreenController.maximumBpm.toDouble(),
            divisions: MetronomeScreenController.maximumBpm -
                MetronomeScreenController.minimumBpm,
            onChanged: widget.onBpmChanged,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        _buildTapTempoButton(),
      ],
    );
  }

  Widget _buildTapTempoButton() {
    return GestureDetector(
      key: const Key('tap-tempo-button'),
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTap: _handleTap,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _tapScaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _tapScaleAnimation.value,
            child: child,
          );
        },
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            AnimatedBuilder(
              animation: _tapFeedbackController,
              builder: (context, child) {
                if (_tapFeedbackController.value == 0) {
                  return const SizedBox.shrink();
                }

                final peakScale = _showResolvedFeedback
                    ? _tapTempoFeedbackScalePeakResolved
                    : _tapTempoFeedbackScalePeak;
                final scale = Tween<double>(
                  begin: 1,
                  end: peakScale,
                ).evaluate(_tapFeedbackScaleAnimation);
                final opacity = _showResolvedFeedback
                    ? _tapTempoFeedbackOpacityPeakResolved
                    : _tapTempoFeedbackOpacityPeak;

                return FadeTransition(
                  opacity: _tapFeedbackOpacityAnimation,
                  child: Transform.scale(
                    scale: scale,
                    child: DecoratedBox(
                      key: const Key('tap-tempo-feedback-ring'),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              AppColors.primaryGlow.withValues(alpha: opacity),
                          width: _tapTempoBorderWidth,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryGlow.withValues(
                              alpha: opacity,
                            ),
                            blurRadius: _showResolvedFeedback
                                ? _tapTempoFeedbackBlurResolved
                                : _tapTempoFeedbackBlur,
                          ),
                        ],
                      ),
                      child: const SizedBox(
                        width: _tapTempoButtonSize,
                        height: _tapTempoButtonSize,
                      ),
                    ),
                  ),
                );
              },
            ),
            Container(
              width: _tapTempoButtonSize,
              height: _tapTempoButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(
                  color: AppColors.primary,
                  width: _tapTempoBorderWidth,
                ),
              ),
              alignment: Alignment.center,
              child: const Text('TAP', style: AppTextTheme.label),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Rhythm Section ──────────────────────────────────────────────────────────

class _RhythmSection extends StatelessWidget {
  const _RhythmSection({
    required this.beatsPerBar,
    required this.beatUnit,
    required this.subdivision,
    required this.accentPattern,
    required this.onBeatsPerBarChanged,
    required this.onBeatUnitChanged,
    required this.onSubdivisionChanged,
    required this.onAccentChanged,
  });

  final int beatsPerBar;
  final int beatUnit;
  final Subdivision subdivision;
  final List<AccentLevel> accentPattern;
  final ValueChanged<int> onBeatsPerBarChanged;
  final ValueChanged<int> onBeatUnitChanged;
  final ValueChanged<Subdivision> onSubdivisionChanged;
  final AccentChangedCallback onAccentChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDropdownRow(),
        const SizedBox(height: AppSpacing.md),
        const Text('Accent Pattern', style: AppTextTheme.label),
        const SizedBox(height: AppSpacing.sm),
        TDAccentGrid(
          accentPattern: accentPattern,
          onAccentChanged: onAccentChanged,
        ),
      ],
    );
  }

  Widget _buildDropdownRow() {
    return Row(
      children: [
        Expanded(
          child: TDDropdownCard<int>(
            label: 'Beats Per Bar',
            value: beatsPerBar,
            options: List<int>.generate(
              MetronomeScreenController.maximumBeatsPerBar,
              (index) => index + 1,
            ),
            itemLabel: (value) => '$value',
            onChanged: onBeatsPerBarChanged,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: TDDropdownCard<int>(
            label: 'Beat Unit',
            value: beatUnit,
            options: MetronomeScreenController.supportedBeatUnits,
            itemLabel: (value) => '$value',
            onChanged: onBeatUnitChanged,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: TDDropdownCard<Subdivision>(
            label: 'Subdivision',
            value: subdivision,
            options: Subdivision.values,
            itemLabel: _subdivisionLabel,
            onChanged: onSubdivisionChanged,
          ),
        ),
      ],
    );
  }
}

String _subdivisionLabel(Subdivision subdivision) {
  return subdivision.displayLabel;
}

// ─── Interval Section ────────────────────────────────────────────────────────

class _IntervalSection extends StatelessWidget {
  const _IntervalSection({
    required this.intervalSettings,
    required this.bpm,
    required this.intervalPreviewBuilder,
    required this.onModeEnabledChanged,
    required this.onIntervalMinutesChanged,
    required this.onIntervalSecondsChanged,
    required this.onBpmStepEnabledChanged,
    required this.onIncrementBpmStep,
    required this.onDecrementBpmStep,
    required this.onMaxDurationEnabledChanged,
    required this.onMaxDurationMinutesChanged,
    required this.onMaxDurationSecondsChanged,
  });

  final IntervalSettings? intervalSettings;
  final int bpm;
  final MetronomeIntervalPreviewBuilder intervalPreviewBuilder;
  final ValueChanged<bool> onModeEnabledChanged;
  final ValueChanged<int> onIntervalMinutesChanged;
  final ValueChanged<int> onIntervalSecondsChanged;
  final ValueChanged<bool> onBpmStepEnabledChanged;
  final VoidCallback onIncrementBpmStep;
  final VoidCallback onDecrementBpmStep;
  final ValueChanged<bool> onMaxDurationEnabledChanged;
  final ValueChanged<int> onMaxDurationMinutesChanged;
  final ValueChanged<int> onMaxDurationSecondsChanged;

  @override
  Widget build(BuildContext context) {
    final isEnabled = intervalSettings != null;
    final intervalDuration = intervalSettings?.interval;
    final maxDuration = intervalSettings?.maxDuration;
    final maxDurationEnabled = maxDuration != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ToggleRow(
          key: const Key('interval-mode-switch'),
          label: 'Enable Interval Mode',
          subtitle: 'Cycle at fixed durations with optional BPM steps.',
          value: isEnabled,
          onChanged: onModeEnabledChanged,
        ),
        if (isEnabled) ...[
          const SizedBox(height: AppSpacing.md),
          _DurationRow(
            label: 'Interval Duration',
            minutes: intervalDuration?.inMinutes ?? 0,
            seconds:
                (intervalDuration?.inSeconds ?? 0) % Duration.secondsPerMinute,
            onMinutesChanged: onIntervalMinutesChanged,
            onSecondsChanged: onIntervalSecondsChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildBpmStepRow(),
          if (intervalSettings!.bpmStepEnabled) ...[
            const SizedBox(height: AppSpacing.sm),
            TDStepper(
              label: 'BPM Step Size',
              value: intervalSettings!.bpmStep,
              onIncrement: onIncrementBpmStep,
              onDecrement: onDecrementBpmStep,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _buildMaxDurationRow(maxDurationEnabled, maxDuration),
          const SizedBox(height: AppSpacing.md),
          _IntervalPreviewCard(
            items: intervalPreviewBuilder.build(
              bpm: bpm,
              intervalSettings: intervalSettings!,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBpmStepRow() {
    return _ToggleRow(
      label: 'BPM Step',
      subtitle: intervalSettings!.bpmStepEnabled
          ? 'Changes by ${intervalSettings!.bpmStep} BPM each interval.'
          : 'Disabled',
      value: intervalSettings!.bpmStepEnabled,
      onChanged: onBpmStepEnabledChanged,
    );
  }

  Widget _buildMaxDurationRow(bool enabled, Duration? maxDuration) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ToggleRow(
          label: 'Max Duration',
          subtitle: enabled
              ? 'Stops after the selected total duration.'
              : 'Runs until you stop it manually.',
          value: enabled,
          onChanged: onMaxDurationEnabledChanged,
        ),
        if (enabled) ...[
          const SizedBox(height: AppSpacing.sm),
          _DurationRow(
            label: 'Maximum Duration',
            minutes: maxDuration!.inMinutes,
            seconds: maxDuration.inSeconds % Duration.secondsPerMinute,
            onMinutesChanged: onMaxDurationMinutesChanged,
            onSecondsChanged: onMaxDurationSecondsChanged,
          ),
        ],
      ],
    );
  }
}

// ─── Toggle Row ──────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextTheme.body),
              if (subtitle != null)
                Text(subtitle!, style: AppTextTheme.bodySecondary),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        TDToggle(value: value, onChanged: onChanged),
      ],
    );
  }
}

// ─── Duration Row ────────────────────────────────────────────────────────────

class _DurationRow extends StatefulWidget {
  const _DurationRow({
    required this.label,
    required this.minutes,
    required this.seconds,
    required this.onMinutesChanged,
    required this.onSecondsChanged,
  });

  final String label;
  final int minutes;
  final int seconds;
  final ValueChanged<int> onMinutesChanged;
  final ValueChanged<int> onSecondsChanged;

  @override
  State<_DurationRow> createState() => _DurationRowState();
}

class _DurationRowState extends State<_DurationRow> {
  late final TextEditingController _minutesController;
  late final TextEditingController _secondsController;

  @override
  void initState() {
    super.initState();
    _minutesController = TextEditingController(
      text: widget.minutes.toString(),
    );
    _secondsController = TextEditingController(
      text: widget.seconds.toString().padLeft(2, '0'),
    );
  }

  @override
  void didUpdateWidget(_DurationRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minutes != widget.minutes) {
      _minutesController.text = widget.minutes.toString();
    }
    if (oldWidget.seconds != widget.seconds) {
      _secondsController.text = widget.seconds.toString().padLeft(2, '0');
    }
  }

  @override
  void dispose() {
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  void _onMinutesEditingComplete() {
    final parsed = int.tryParse(_minutesController.text) ?? 0;
    final clamped = parsed.clamp(_durationMinClamp, _durationMaxClamp);
    _minutesController.text = clamped.toString();
    widget.onMinutesChanged(clamped);
  }

  void _onSecondsEditingComplete() {
    final parsed = int.tryParse(_secondsController.text) ?? 0;
    final clamped = parsed.clamp(_durationMinClamp, _durationMaxClamp);
    _secondsController.text = clamped.toString().padLeft(2, '0');
    widget.onSecondsChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AppTextTheme.label),
        const SizedBox(height: AppSpacing.sm),
        _buildInputRow(),
      ],
    );
  }

  Widget _buildInputRow() {
    return Row(
      children: [
        Expanded(
          child: Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus) _onMinutesEditingComplete();
            },
            child: TDTextField(
              controller: _minutesController,
              keyboardType: TextInputType.number,
              hint: 'min',
              onSubmitted: (_) => _onMinutesEditingComplete(),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(':', style: AppTextTheme.heading2),
        ),
        Expanded(
          child: Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus) _onSecondsEditingComplete();
            },
            child: TDTextField(
              controller: _secondsController,
              keyboardType: TextInputType.number,
              hint: 'sec',
              onSubmitted: (_) => _onSecondsEditingComplete(),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Interval Preview Card ───────────────────────────────────────────────────

class _IntervalPreviewCard extends StatelessWidget {
  const _IntervalPreviewCard({required this.items});

  final List<MetronomeIntervalPreviewItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return TDCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Interval Preview', style: AppTextTheme.heading3),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < items.length; i++) ...[
            _buildPreviewRow(i),
            if (i < items.length - 1)
              const Divider(height: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewRow(int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(items[index].title, style: AppTextTheme.body),
          ),
          Text(items[index].subtitle, style: AppTextTheme.bodySecondary),
        ],
      ),
    );
  }
}

// ─── Presets Section ─────────────────────────────────────────────────────────

class _PresetsSection extends StatelessWidget {
  const _PresetsSection({
    required this.presetList,
    required this.appliedPresetId,
    required this.onApply,
    required this.onSaveCurrent,
    required this.onRename,
    required this.onDelete,
  });

  final AsyncValue<List<MetronomePreset>> presetList;
  final String? appliedPresetId;
  final ValueChanged<MetronomePreset> onApply;
  final Future<void> Function(String name) onSaveCurrent;
  final Future<void> Function(MetronomePreset preset, String name) onRename;
  final Future<void> Function(String presetId) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TDButton(
          label: 'Save Current as Preset',
          icon: Icons.save_outlined,
          variant: TDButtonVariant.secondary,
          onPressed: () => _showPresetNameDialog(
            context,
            title: 'Save Preset',
            confirmLabel: 'Save',
            onSubmitted: onSaveCurrent,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        presetList.when(
          data: (presets) => _buildPresetList(context, presets),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
          error: (error, _) => Text(
            'Failed to load presets: $error',
            style: AppTextTheme.bodySecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildPresetList(BuildContext context, List<MetronomePreset> presets) {
    if (presets.isEmpty) {
      return const Text(
        'No presets saved yet.',
        style: AppTextTheme.bodySecondary,
      );
    }

    return Column(
      children: [
        for (final preset in presets)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: TDListTile(
              title: preset.name,
              subtitle: _presetSummary(preset),
              isSelected: appliedPresetId == preset.id,
              trailing: PopupMenuButton<_PresetAction>(
                icon: const Icon(
                  Icons.more_vert,
                  color: AppColors.textSecondary,
                ),
                onSelected: (action) =>
                    _handlePresetAction(context, action, preset),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _PresetAction.apply,
                    child: Text('Apply'),
                  ),
                  PopupMenuItem(
                    value: _PresetAction.rename,
                    child: Text('Rename'),
                  ),
                  PopupMenuItem(
                    value: _PresetAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              ),
              onTap: () => onApply(preset),
            ),
          ),
      ],
    );
  }

  void _handlePresetAction(
    BuildContext context,
    _PresetAction action,
    MetronomePreset preset,
  ) {
    switch (action) {
      case _PresetAction.apply:
        onApply(preset);
      case _PresetAction.rename:
        _showPresetNameDialog(
          context,
          title: 'Rename Preset',
          initialValue: preset.name,
          confirmLabel: 'Rename',
          onSubmitted: (name) => onRename(preset, name),
        );
      case _PresetAction.delete:
        _showPresetDeleteDialog(context, preset: preset);
    }
  }

  void _showPresetDeleteDialog(
    BuildContext context, {
    required MetronomePreset preset,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: tdDialogShape,
        title: const Text('Delete Preset', style: AppTextTheme.heading3),
        content: Text(
          'Delete "${preset.name}"?',
          style: AppTextTheme.body,
        ),
        actions: [
          TDButton(
            label: 'Cancel',
            variant: TDButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          TDButton(
            label: 'Delete',
            variant: TDButtonVariant.destructive,
            onPressed: () async {
              await onDelete(preset.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  String _presetSummary(MetronomePreset preset) {
    return '${preset.bpm} BPM \u00B7 '
        '${preset.beatsPerBar}/${preset.beatUnit} \u00B7 '
        '${preset.subdivision.pulseCount} pulses';
  }
}

enum _PresetAction { apply, rename, delete }

// ─── Helpers ─────────────────────────────────────────────────────────────────

Future<void> _showPresetNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required Future<void> Function(String name) onSubmitted,
  String initialValue = '',
}) async {
  final controller = TextEditingController(text: initialValue);

  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: tdDialogShape,
        title: Text(title, style: AppTextTheme.heading3),
        content: TDTextField(
          key: const Key('preset-name-field'),
          controller: controller,
          autofocus: true,
          label: 'Preset Name',
        ),
        actions: [
          TDButton(
            label: 'Cancel',
            variant: TDButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          TDButton(
            label: confirmLabel,
            onPressed: () async {
              await onSubmitted(controller.text);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}
