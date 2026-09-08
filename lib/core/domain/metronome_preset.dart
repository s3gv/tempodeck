import 'accent_level.dart';
import 'click_sound_set.dart';
import 'interval_settings.dart';
import 'subdivision.dart';

class MetronomePreset {
  static const int defaultMasterVolumePercent = 100;

  const MetronomePreset({
    required this.id,
    required this.name,
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.subdivision,
    required this.accentPattern,
    this.clickSoundSet = ClickSoundSet.tock,
    this.masterVolumePercent = defaultMasterVolumePercent,
    this.intervalSettings,
  });

  final String id;
  final String name;
  final int bpm;
  final int beatsPerBar;
  final int beatUnit;
  final Subdivision subdivision;
  final List<AccentLevel> accentPattern;
  final ClickSoundSet clickSoundSet;
  final int masterVolumePercent;
  final IntervalSettings? intervalSettings;
}
