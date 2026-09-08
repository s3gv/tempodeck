import '../../core/domain/accent_level.dart';
import '../../core/domain/click_sound_set.dart';
import '../../core/domain/interval_settings.dart';
import '../../core/domain/subdivision.dart';

class MetronomeScreenState {
  static const int defaultMasterVolumePercent = 80;

  MetronomeScreenState({
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.subdivision,
    required this.clickSoundSet,
    required this.masterVolumePercent,
    required this.tapTempoTapCount,
    required List<AccentLevel> accentPattern,
    this.intervalSettings,
    this.appliedPresetId,
  }) : accentPattern = List<AccentLevel>.unmodifiable(accentPattern);

  factory MetronomeScreenState.initial() {
    return MetronomeScreenState(
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      subdivision: Subdivision.one,
      clickSoundSet: ClickSoundSet.tock,
      masterVolumePercent: defaultMasterVolumePercent,
      tapTempoTapCount: 0,
      accentPattern: [
        AccentLevel.high,
        AccentLevel.normal,
        AccentLevel.normal,
        AccentLevel.normal,
      ],
      intervalSettings: null,
      appliedPresetId: null,
    );
  }

  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
  final Subdivision subdivision;
  final ClickSoundSet clickSoundSet;
  final int masterVolumePercent;
  final int tapTempoTapCount;
  final List<AccentLevel> accentPattern;
  final IntervalSettings? intervalSettings;
  final String? appliedPresetId;

  MetronomeScreenState copyWith({
    int? bpm,
    int? beatsPerBar,
    int? beatUnit,
    Subdivision? subdivision,
    ClickSoundSet? clickSoundSet,
    int? masterVolumePercent,
    int? tapTempoTapCount,
    List<AccentLevel>? accentPattern,
    IntervalSettings? intervalSettings,
    String? appliedPresetId,
    bool clearIntervalSettings = false,
    bool clearAppliedPresetId = false,
  }) {
    return MetronomeScreenState(
      bpm: bpm ?? this.bpm,
      beatsPerBar: beatsPerBar ?? this.beatsPerBar,
      beatUnit: beatUnit ?? this.beatUnit,
      subdivision: subdivision ?? this.subdivision,
      clickSoundSet: clickSoundSet ?? this.clickSoundSet,
      masterVolumePercent: masterVolumePercent ?? this.masterVolumePercent,
      tapTempoTapCount: tapTempoTapCount ?? this.tapTempoTapCount,
      accentPattern: accentPattern ?? this.accentPattern,
      intervalSettings: clearIntervalSettings
          ? null
          : intervalSettings ?? this.intervalSettings,
      appliedPresetId:
          clearAppliedPresetId ? null : appliedPresetId ?? this.appliedPresetId,
    );
  }
}
