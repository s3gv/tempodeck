import 'package:shared_preferences/shared_preferences.dart';

import '../providers/audio_mixer_provider.dart';

/// Persists user-configured mixer volume levels across app restarts.
abstract class MixerSettingsRepository {
  /// Loads persisted mixer volumes, falling back to [AudioMixerState] defaults.
  Future<AudioMixerState> load();

  /// Persists the given mixer volumes.
  Future<void> save(AudioMixerState state);
}

class SharedPreferencesMixerSettingsRepository
    implements MixerSettingsRepository {
  static const _metronomeVolumeKey = 'mixer_metronome_volume';
  static const _songVolumeKey = 'mixer_song_volume';
  static const _cueVolumeKey = 'mixer_cue_volume';
  static const _transitionVolumeKey = 'mixer_transition_volume';

  @override
  Future<AudioMixerState> load() async {
    final prefs = await SharedPreferences.getInstance();

    return AudioMixerState(
      metronomeVolumePercent: prefs.getInt(_metronomeVolumeKey) ??
          AudioMixerState.defaultMetronomeVolumePercent,
      songVolumePercent: prefs.getInt(_songVolumeKey) ??
          AudioMixerState.defaultSongVolumePercent,
      cueVolumePercent: prefs.getInt(_cueVolumeKey) ??
          AudioMixerState.defaultCueVolumePercent,
      transitionVolumePercent: prefs.getInt(_transitionVolumeKey) ??
          AudioMixerState.defaultTransitionVolumePercent,
    );
  }

  @override
  Future<void> save(AudioMixerState state) async {
    final prefs = await SharedPreferences.getInstance();

    await Future.wait([
      prefs.setInt(_metronomeVolumeKey, state.metronomeVolumePercent),
      prefs.setInt(_songVolumeKey, state.songVolumePercent),
      prefs.setInt(_cueVolumeKey, state.cueVolumePercent),
      prefs.setInt(_transitionVolumeKey, state.transitionVolumePercent),
    ]);
  }
}
