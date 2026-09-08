import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/metronome/metronome_screen_state.dart';
import '../domain/accent_level.dart';
import '../domain/click_sound_set.dart';
import '../domain/interval_settings.dart';
import '../domain/subdivision.dart';

/// Persists the current metronome working state across app restarts.
abstract class MetronomeSettingsRepository {
  /// Loads persisted metronome settings, falling back to
  /// [MetronomeScreenState.initial] defaults.
  Future<MetronomeScreenState> load();

  /// Persists the given metronome settings.
  Future<void> save(MetronomeScreenState state);
}

class SharedPreferencesMetronomeSettingsRepository
    implements MetronomeSettingsRepository {
  static const _bpmKey = 'metronome_bpm';
  static const _beatsPerBarKey = 'metronome_beats_per_bar';
  static const _beatUnitKey = 'metronome_beat_unit';
  static const _subdivisionKey = 'metronome_subdivision';
  static const _clickSoundSetKey = 'metronome_click_sound_set';
  static const _masterVolumeKey = 'metronome_master_volume';
  static const _accentPatternKey = 'metronome_accent_pattern';
  static const _appliedPresetIdKey = 'metronome_applied_preset_id';
  static const _intervalMsKey = 'metronome_interval_ms';
  static const _intervalBpmStepEnabledKey =
      'metronome_interval_bpm_step_enabled';
  static const _intervalBpmStepKey = 'metronome_interval_bpm_step';
  static const _intervalMaxDurationMsKey =
      'metronome_interval_max_duration_ms';

  @override
  Future<MetronomeScreenState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = MetronomeScreenState.initial();

    final accentPatternJson = prefs.getString(_accentPatternKey);
    final accentPattern = accentPatternJson != null
        ? _decodeAccentPattern(accentPatternJson)
        : defaults.accentPattern;

    final subdivisionName = prefs.getString(_subdivisionKey);
    final subdivision = subdivisionName != null
        ? Subdivision.values.byName(subdivisionName)
        : defaults.subdivision;

    final clickSoundSetName = prefs.getString(_clickSoundSetKey);
    final clickSoundSet = clickSoundSetName != null
        ? ClickSoundSet.values.byName(clickSoundSetName)
        : defaults.clickSoundSet;

    final intervalMs = prefs.getInt(_intervalMsKey);
    final IntervalSettings? intervalSettings;
    if (intervalMs != null) {
      intervalSettings = IntervalSettings(
        interval: Duration(milliseconds: intervalMs),
        bpmStepEnabled: prefs.getBool(_intervalBpmStepEnabledKey) ?? false,
        bpmStep: prefs.getInt(_intervalBpmStepKey) ?? 1,
        maxDuration: prefs.getInt(_intervalMaxDurationMsKey) != null
            ? Duration(
                milliseconds: prefs.getInt(_intervalMaxDurationMsKey)!,
              )
            : null,
      );
    } else {
      intervalSettings = null;
    }

    return MetronomeScreenState(
      bpm: prefs.getInt(_bpmKey) ?? defaults.bpm,
      beatsPerBar: prefs.getInt(_beatsPerBarKey) ?? defaults.beatsPerBar,
      beatUnit: prefs.getInt(_beatUnitKey) ?? defaults.beatUnit,
      subdivision: subdivision,
      clickSoundSet: clickSoundSet,
      masterVolumePercent:
          prefs.getInt(_masterVolumeKey) ?? defaults.masterVolumePercent,
      tapTempoTapCount: 0,
      accentPattern: accentPattern,
      intervalSettings: intervalSettings,
      appliedPresetId: prefs.getString(_appliedPresetIdKey),
    );
  }

  @override
  Future<void> save(MetronomeScreenState state) async {
    final prefs = await SharedPreferences.getInstance();

    await Future.wait([
      prefs.setInt(_bpmKey, state.bpm),
      prefs.setInt(_beatsPerBarKey, state.beatsPerBar),
      prefs.setInt(_beatUnitKey, state.beatUnit),
      prefs.setString(_subdivisionKey, state.subdivision.name),
      prefs.setString(_clickSoundSetKey, state.clickSoundSet.name),
      prefs.setInt(_masterVolumeKey, state.masterVolumePercent),
      prefs.setString(_accentPatternKey, _encodeAccentPattern(state.accentPattern)),
      if (state.appliedPresetId != null)
        prefs.setString(_appliedPresetIdKey, state.appliedPresetId!)
      else
        prefs.remove(_appliedPresetIdKey),
      if (state.intervalSettings != null) ...[
        prefs.setInt(
          _intervalMsKey,
          state.intervalSettings!.interval.inMilliseconds,
        ),
        prefs.setBool(
          _intervalBpmStepEnabledKey,
          state.intervalSettings!.bpmStepEnabled,
        ),
        prefs.setInt(_intervalBpmStepKey, state.intervalSettings!.bpmStep),
        if (state.intervalSettings!.maxDuration != null)
          prefs.setInt(
            _intervalMaxDurationMsKey,
            state.intervalSettings!.maxDuration!.inMilliseconds,
          )
        else
          prefs.remove(_intervalMaxDurationMsKey),
      ] else ...[
        prefs.remove(_intervalMsKey),
        prefs.remove(_intervalBpmStepEnabledKey),
        prefs.remove(_intervalBpmStepKey),
        prefs.remove(_intervalMaxDurationMsKey),
      ],
    ]);
  }

  String _encodeAccentPattern(List<AccentLevel> pattern) {
    return jsonEncode(pattern.map((level) => level.name).toList());
  }

  List<AccentLevel> _decodeAccentPattern(String json) {
    final decoded = (jsonDecode(json) as List<Object?>).cast<String>();
    return decoded.map(AccentLevel.values.byName).toList();
  }
}
