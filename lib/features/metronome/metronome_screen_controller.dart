import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../core/audio/tap_tempo_detector.dart';
import '../../core/domain/accent_level.dart';
import '../../core/domain/click_sound_set.dart';
import '../../core/domain/interval_settings.dart';
import '../../core/domain/metronome_preset.dart';
import '../../core/domain/subdivision.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/service_providers.dart';
import '../../core/validation/preset_write_validator.dart';
import 'metronome_screen_state.dart';

final metronomeScreenControllerProvider =
    NotifierProvider<MetronomeScreenController, MetronomeScreenState>(
  MetronomeScreenController.new,
);

final tapTempoResetSchedulerProvider = Provider<TapTempoResetScheduler>(
  (ref) => const SystemTapTempoResetScheduler(),
);

abstract class TapTempoResetTask {
  void cancel();
}

abstract class TapTempoResetScheduler {
  const TapTempoResetScheduler();

  TapTempoResetTask schedule(Duration duration, void Function() callback);
}

class SystemTapTempoResetScheduler implements TapTempoResetScheduler {
  const SystemTapTempoResetScheduler();

  @override
  TapTempoResetTask schedule(Duration duration, void Function() callback) {
    return _TimerTapTempoResetTask(Timer(duration, callback));
  }
}

class _TimerTapTempoResetTask implements TapTempoResetTask {
  const _TimerTapTempoResetTask(this._timer);

  final Timer _timer;

  @override
  void cancel() {
    _timer.cancel();
  }
}

class MetronomeScreenController extends Notifier<MetronomeScreenState> {
  static const Uuid _uuid = Uuid();
  static final Logger _logger = Logger('MetronomeScreenController');
  static const int minimumBpm = PresetWriteValidator.minimumBpm;
  static const int maximumBpm = PresetWriteValidator.maximumBpm;
  static const int minimumBeatsPerBar = PresetWriteValidator.minimumBeatsPerBar;
  static const int maximumBeatsPerBar = PresetWriteValidator.maximumBeatsPerBar;
  static const List<int> supportedBeatUnits = [1, 2, 4, 8, 16, 32];
  static const int minimumIntervalMinutes = 0;
  static const int maximumIntervalMinutes = 59;
  static const int minimumIntervalSeconds = 0;
  static const int maximumIntervalSeconds = 59;
  static const int defaultIntervalMinutes = 1;
  static const int defaultIntervalSeconds = 0;
  static const int defaultMaximumDurationMinutes = 10;
  static const int defaultMaximumDurationSeconds = 0;
  static const int minimumBpmStep = PresetWriteValidator.minimumBpmStep;
  static const int minimumMasterVolumePercent = 0;
  static const int maximumMasterVolumePercent = 100;

  int _clickSoundRequestId = 0;
  TapTempoResetTask? _tapTempoResetTask;
  Future<void> _pendingSave = Future<void>.value();

  @override
  MetronomeScreenState build() {
    ref.onDispose(() => _tapTempoResetTask?.cancel());
    return MetronomeScreenState.initial();
  }

  Future<void> loadPersistedSettings() async {
    final repository = ref.read(metronomeSettingsRepositoryProvider);
    try {
      final persisted = await repository.load();
      state = persisted;
      await _applyAudioState(persisted);
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to load persisted metronome settings. Using defaults.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _applyAudioState(MetronomeScreenState settings) async {
    final audioEngine = ref.read(audioEngineProvider);
    if (!audioEngine.isInitialized) {
      return;
    }

    audioEngine.setMasterVolume(
      settings.masterVolumePercent / maximumMasterVolumePercent,
    );

    try {
      await audioEngine.loadClickSoundSet(settings.clickSoundSet);
      audioEngine.selectClickSoundSet(settings.clickSoundSet);
    } catch (error, stackTrace) {
      _logger.severe(
        'Failed to load persisted click sound set ${settings.clickSoundSet}.',
        error,
        stackTrace,
      );
    }
  }

  void _persist() {
    final repository = ref.read(metronomeSettingsRepositoryProvider);
    final snapshot = state;
    _pendingSave = _pendingSave.then((_) => repository.save(snapshot)).then(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning(
          'Failed to persist metronome settings.',
          error,
          stackTrace,
        );
      },
    );
  }

  void setBpm(int bpm, {bool clearTapTempoProgress = true}) {
    final clampedBpm = bpm.clamp(minimumBpm, maximumBpm);
    if (clearTapTempoProgress) {
      _clearTapTempoProgress(updateState: false);
    }
    state = state.copyWith(
      bpm: clampedBpm,
      tapTempoTapCount: clearTapTempoProgress ? 0 : state.tapTempoTapCount,
    );
    _persist();
  }

  void setBeatsPerBar(int beatsPerBar) {
    final clampedBeatsPerBar = beatsPerBar.clamp(
      minimumBeatsPerBar,
      maximumBeatsPerBar,
    );
    state = state.copyWith(
      beatsPerBar: clampedBeatsPerBar,
      accentPattern: _resizeAccentPattern(
        state.accentPattern,
        beatsPerBar: clampedBeatsPerBar,
      ),
    );
    _persist();
  }

  void setBeatUnit(int beatUnit) {
    if (!supportedBeatUnits.contains(beatUnit)) {
      throw ArgumentError.value(
        beatUnit,
        'beatUnit',
        'Beat unit must be one of $supportedBeatUnits.',
      );
    }

    state = state.copyWith(beatUnit: beatUnit);
    _persist();
  }

  void setSubdivision(Subdivision subdivision) {
    state = state.copyWith(subdivision: subdivision);
    _persist();
  }

  Future<void> setClickSoundSet(ClickSoundSet clickSoundSet) async {
    final requestId = ++_clickSoundRequestId;
    final audioEngine = ref.read(audioEngineProvider);
    if (!audioEngine.isInitialized) {
      state = state.copyWith(clickSoundSet: clickSoundSet);
      _persist();
      return;
    }
    try {
      await audioEngine.loadClickSoundSet(clickSoundSet);
      if (requestId != _clickSoundRequestId) {
        return;
      }

      audioEngine.selectClickSoundSet(clickSoundSet);
      state = state.copyWith(clickSoundSet: clickSoundSet);
      _persist();
    } catch (error, stackTrace) {
      if (requestId != _clickSoundRequestId) {
        return;
      }

      _logger.severe(
        'Failed to load click sound set $clickSoundSet.',
        error,
        stackTrace,
      );
    }
  }

  void setMasterVolumePercent(int masterVolumePercent) {
    final clampedMasterVolumePercent = masterVolumePercent.clamp(
      minimumMasterVolumePercent,
      maximumMasterVolumePercent,
    );
    final audioEngine = ref.read(audioEngineProvider);
    if (audioEngine.isInitialized) {
      audioEngine.setMasterVolume(
        clampedMasterVolumePercent / maximumMasterVolumePercent,
      );
    }
    state = state.copyWith(
      masterVolumePercent: clampedMasterVolumePercent,
    );
    _persist();
  }

  void setAccentAt(int beatIndex, AccentLevel level) {
    if (beatIndex < 0 || beatIndex >= state.accentPattern.length) {
      throw RangeError.index(
        beatIndex,
        state.accentPattern,
        'beatIndex',
      );
    }

    final updatedAccentPattern = List<AccentLevel>.from(state.accentPattern);
    updatedAccentPattern[beatIndex] = level;
    state = state.copyWith(accentPattern: updatedAccentPattern);
    _persist();
  }

  TapTempoResult? tapTempo() {
    final detector = ref.read(tapTempoDetectorProvider);
    final result = detector.registerTap();
    _scheduleTapTempoReset();
    state = state.copyWith(tapTempoTapCount: detector.tapCount);
    if (result != null) {
      setBpm(result.bpm, clearTapTempoProgress: false);
    }
    return result;
  }

  void _scheduleTapTempoReset() {
    _tapTempoResetTask?.cancel();
    _tapTempoResetTask = ref.read(tapTempoResetSchedulerProvider).schedule(
          TapTempoDetector.silenceResetThreshold,
          _clearTapTempoProgress,
        );
  }

  void _clearTapTempoProgress({bool updateState = true}) {
    _tapTempoResetTask?.cancel();
    _tapTempoResetTask = null;
    final detector = ref.read(tapTempoDetectorProvider);
    detector.reset();
    if (!updateState || state.tapTempoTapCount == 0) {
      return;
    }
    state = state.copyWith(tapTempoTapCount: 0);
  }

  void applyPreset(MetronomePreset preset) {
    state = state.copyWith(
      bpm: preset.bpm,
      beatsPerBar: preset.beatsPerBar,
      beatUnit: preset.beatUnit,
      subdivision: preset.subdivision,
      clickSoundSet: preset.clickSoundSet,
      masterVolumePercent: preset.masterVolumePercent,
      accentPattern: preset.accentPattern,
      intervalSettings: preset.intervalSettings,
      appliedPresetId: preset.id,
    );
    _persist();
  }

  Future<void> saveCurrentPreset(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Preset name must not be empty.');
    }

    final presetId = _uuid.v4();
    final preset = MetronomePreset(
      id: presetId,
      name: trimmedName,
      bpm: state.bpm,
      beatsPerBar: state.beatsPerBar,
      beatUnit: state.beatUnit,
      subdivision: state.subdivision,
      clickSoundSet: state.clickSoundSet,
      masterVolumePercent: state.masterVolumePercent,
      accentPattern: state.accentPattern,
      intervalSettings: state.intervalSettings,
    );

    await ref.read(presetRepositoryProvider).savePreset(preset);
    state = state.copyWith(appliedPresetId: presetId);
    _persist();
  }

  Future<void> renamePreset(MetronomePreset preset, String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Preset name must not be empty.');
    }

    await ref.read(presetRepositoryProvider).savePreset(
          MetronomePreset(
            id: preset.id,
            name: trimmedName,
            bpm: preset.bpm,
            beatsPerBar: preset.beatsPerBar,
            beatUnit: preset.beatUnit,
            subdivision: preset.subdivision,
            clickSoundSet: preset.clickSoundSet,
            masterVolumePercent: preset.masterVolumePercent,
            accentPattern: preset.accentPattern,
            intervalSettings: preset.intervalSettings,
          ),
        );
  }

  Future<void> deletePreset(String presetId) async {
    await ref.read(presetRepositoryProvider).deletePreset(presetId);
    if (state.appliedPresetId == presetId) {
      state = state.copyWith(clearAppliedPresetId: true);
      _persist();
    }
  }

  void setIntervalModeEnabled(bool enabled) {
    if (!enabled) {
      state = state.copyWith(clearIntervalSettings: true);
      _persist();
      return;
    }

    state = state.copyWith(
      intervalSettings: state.intervalSettings ?? _defaultIntervalSettings(),
    );
    _persist();
  }

  /// Returns the effective interval settings.
  IntervalSettings? get effectiveIntervalSettings => state.intervalSettings;

  void setIntervalDurationMinutes(int minutes) {
    _updateIntervalSettings((intervalSettings) {
      final duration = intervalSettings.interval;
      return IntervalSettings(
        interval: Duration(
          minutes: minutes.clamp(
            minimumIntervalMinutes,
            maximumIntervalMinutes,
          ),
          seconds: duration.inSeconds % Duration.secondsPerMinute,
        ),
        bpmStepEnabled: intervalSettings.bpmStepEnabled,
        bpmStep: intervalSettings.bpmStep,
        maxDuration: intervalSettings.maxDuration,
      );
    });
  }

  void setIntervalDurationSeconds(int seconds) {
    _updateIntervalSettings((intervalSettings) {
      final duration = intervalSettings.interval;
      return IntervalSettings(
        interval: Duration(
          minutes: duration.inMinutes,
          seconds: seconds.clamp(
            minimumIntervalSeconds,
            maximumIntervalSeconds,
          ),
        ),
        bpmStepEnabled: intervalSettings.bpmStepEnabled,
        bpmStep: intervalSettings.bpmStep,
        maxDuration: intervalSettings.maxDuration,
      );
    });
  }

  void setBpmStepEnabled(bool enabled) {
    _updateIntervalSettings((intervalSettings) {
      return IntervalSettings(
        interval: intervalSettings.interval,
        bpmStepEnabled: enabled,
        bpmStep: intervalSettings.bpmStep,
        maxDuration: intervalSettings.maxDuration,
      );
    });
  }

  void incrementBpmStep() {
    _updateIntervalSettings((intervalSettings) {
      return IntervalSettings(
        interval: intervalSettings.interval,
        bpmStepEnabled: intervalSettings.bpmStepEnabled,
        bpmStep: intervalSettings.bpmStep + 1,
        maxDuration: intervalSettings.maxDuration,
      );
    });
  }

  void decrementBpmStep() {
    _updateIntervalSettings((intervalSettings) {
      final nextBpmStep = intervalSettings.bpmStep - 1;
      return IntervalSettings(
        interval: intervalSettings.interval,
        bpmStepEnabled: intervalSettings.bpmStepEnabled,
        bpmStep: nextBpmStep < minimumBpmStep ? minimumBpmStep : nextBpmStep,
        maxDuration: intervalSettings.maxDuration,
      );
    });
  }

  void setMaximumDurationEnabled(bool enabled) {
    _updateIntervalSettings((intervalSettings) {
      return IntervalSettings(
        interval: intervalSettings.interval,
        bpmStepEnabled: intervalSettings.bpmStepEnabled,
        bpmStep: intervalSettings.bpmStep,
        maxDuration: enabled
            ? intervalSettings.maxDuration ??
                const Duration(
                  minutes: defaultMaximumDurationMinutes,
                  seconds: defaultMaximumDurationSeconds,
                )
            : null,
      );
    });
  }

  void setMaximumDurationMinutes(int minutes) {
    _updateIntervalSettings((intervalSettings) {
      final maxDuration = intervalSettings.maxDuration;
      if (maxDuration == null) {
        return intervalSettings;
      }

      return IntervalSettings(
        interval: intervalSettings.interval,
        bpmStepEnabled: intervalSettings.bpmStepEnabled,
        bpmStep: intervalSettings.bpmStep,
        maxDuration: Duration(
          minutes: minutes.clamp(
            minimumIntervalMinutes,
            maximumIntervalMinutes,
          ),
          seconds: maxDuration.inSeconds % Duration.secondsPerMinute,
        ),
      );
    });
  }

  void setMaximumDurationSeconds(int seconds) {
    _updateIntervalSettings((intervalSettings) {
      final maxDuration = intervalSettings.maxDuration;
      if (maxDuration == null) {
        return intervalSettings;
      }

      return IntervalSettings(
        interval: intervalSettings.interval,
        bpmStepEnabled: intervalSettings.bpmStepEnabled,
        bpmStep: intervalSettings.bpmStep,
        maxDuration: Duration(
          minutes: maxDuration.inMinutes,
          seconds: seconds.clamp(
            minimumIntervalSeconds,
            maximumIntervalSeconds,
          ),
        ),
      );
    });
  }

  List<AccentLevel> _resizeAccentPattern(
    List<AccentLevel> accentPattern, {
    required int beatsPerBar,
  }) {
    if (accentPattern.length == beatsPerBar) {
      return accentPattern;
    }

    final resizedAccentPattern = List<AccentLevel>.from(
      accentPattern.take(beatsPerBar),
    );
    while (resizedAccentPattern.length < beatsPerBar) {
      resizedAccentPattern.add(AccentLevel.normal);
    }

    if (resizedAccentPattern.isNotEmpty &&
        resizedAccentPattern.first == AccentLevel.mute) {
      resizedAccentPattern[0] = AccentLevel.high;
    }

    return List<AccentLevel>.unmodifiable(resizedAccentPattern);
  }

  void _updateIntervalSettings(
    IntervalSettings Function(IntervalSettings intervalSettings) update,
  ) {
    final currentIntervalSettings = state.intervalSettings;
    if (currentIntervalSettings == null) {
      return;
    }

    state = state.copyWith(
      intervalSettings: update(currentIntervalSettings),
    );
    _persist();
  }

  IntervalSettings _defaultIntervalSettings() {
    return const IntervalSettings(
      interval: Duration(
        minutes: defaultIntervalMinutes,
        seconds: defaultIntervalSeconds,
      ),
    );
  }
}
