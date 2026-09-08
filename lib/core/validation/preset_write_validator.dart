import '../domain/interval_settings.dart';
import '../domain/metronome_preset.dart';
import 'validation_helpers.dart';

class PresetWriteValidator with ValidationHelpers {
  const PresetWriteValidator();

  static const int minimumBpm = 20;
  static const int maximumBpm = 320;
  static const Set<int> supportedBeatUnits = {1, 2, 4, 8, 16, 32};
  static const int minimumBeatsPerBar = 1;
  static const int maximumBeatsPerBar = 32;
  static const int minimumBpmStep = 1;
  static const int minimumMasterVolumePercent = 0;
  static const int maximumMasterVolumePercent = 100;

  void validate(MetronomePreset preset) {
    requireText(
      value: preset.name,
      label: 'MetronomePreset.name',
      message: 'Preset name must not be empty.',
    );
    requireInRange(
      value: preset.bpm,
      minimum: minimumBpm,
      maximum: maximumBpm,
      label: 'MetronomePreset.bpm',
    );
    requireInRange(
      value: preset.beatsPerBar,
      minimum: minimumBeatsPerBar,
      maximum: maximumBeatsPerBar,
      label: 'MetronomePreset.beatsPerBar',
    );
    requireBeatUnit(preset.beatUnit, 'MetronomePreset.beatUnit');
    requireInRange(
      value: preset.masterVolumePercent,
      minimum: minimumMasterVolumePercent,
      maximum: maximumMasterVolumePercent,
      label: 'MetronomePreset.masterVolumePercent',
    );

    if (preset.accentPattern.length > preset.beatsPerBar) {
      throw ArgumentError.value(
        preset.accentPattern.length,
        'MetronomePreset.accentPattern',
        'Accent pattern must not exceed beats per bar.',
      );
    }

    final intervalSettings = preset.intervalSettings;
    if (intervalSettings == null) {
      return;
    }

    _validateIntervalSettings(intervalSettings);
  }

  void _validateIntervalSettings(IntervalSettings intervalSettings) {
    if (intervalSettings.interval <= Duration.zero) {
      throw ArgumentError.value(
        intervalSettings.interval,
        'IntervalSettings.interval',
        'Interval duration must be greater than zero.',
      );
    }

    if (intervalSettings.bpmStepEnabled) {
      requireMinimum(
        value: intervalSettings.bpmStep,
        minimum: minimumBpmStep,
        label: 'IntervalSettings.bpmStep',
      );
    }

    final maxDuration = intervalSettings.maxDuration;
    if (maxDuration == null) {
      return;
    }

    if (maxDuration <= Duration.zero) {
      throw ArgumentError.value(
        maxDuration,
        'IntervalSettings.maxDuration',
        'Max duration must be greater than zero.',
      );
    }

    if (maxDuration < intervalSettings.interval) {
      throw ArgumentError.value(
        maxDuration,
        'IntervalSettings.maxDuration',
        'Max duration must be greater than or equal to the interval duration.',
      );
    }
  }
}
