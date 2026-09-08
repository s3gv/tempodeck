import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../audio/click_sound_set_assets.dart';
import 'repository_providers.dart';
import 'service_providers.dart';

class AudioMixerState {
  const AudioMixerState({
    required this.metronomeVolumePercent,
    required this.songVolumePercent,
    required this.cueVolumePercent,
    required this.transitionVolumePercent,
  });

  static const int defaultMetronomeVolumePercent = 80;
  static const int defaultSongVolumePercent = 80;
  static const int defaultCueVolumePercent = 80;
  static const int defaultTransitionVolumePercent = 80;
  static const int minimumVolumePercent = 0;
  static const int maximumVolumePercent = 100;

  factory AudioMixerState.initial() {
    return const AudioMixerState(
      metronomeVolumePercent: defaultMetronomeVolumePercent,
      songVolumePercent: defaultSongVolumePercent,
      cueVolumePercent: defaultCueVolumePercent,
      transitionVolumePercent: defaultTransitionVolumePercent,
    );
  }

  final int metronomeVolumePercent;
  final int songVolumePercent;
  final int cueVolumePercent;
  final int transitionVolumePercent;

  AudioMixerState copyWith({
    int? metronomeVolumePercent,
    int? songVolumePercent,
    int? cueVolumePercent,
    int? transitionVolumePercent,
  }) {
    return AudioMixerState(
      metronomeVolumePercent:
          metronomeVolumePercent ?? this.metronomeVolumePercent,
      songVolumePercent: songVolumePercent ?? this.songVolumePercent,
      cueVolumePercent: cueVolumePercent ?? this.cueVolumePercent,
      transitionVolumePercent:
          transitionVolumePercent ?? this.transitionVolumePercent,
    );
  }
}

final audioMixerControllerProvider =
    NotifierProvider<AudioMixerController, AudioMixerState>(
  AudioMixerController.new,
);

class AudioMixerController extends Notifier<AudioMixerState> {
  static final Logger _logger = Logger('AudioMixerController');

  /// Guards [_persist] so writes complete in call order and a slow older
  /// future can never overwrite a newer snapshot in SharedPreferences.
  Future<void> _pendingSave = Future<void>.value();

  @override
  AudioMixerState build() => AudioMixerState.initial();

  /// Loads persisted mixer volumes and applies the metronome channel volume
  /// to the audio engine.
  ///
  /// Call this once after the audio engine is initialized.
  Future<void> loadPersistedSettings() async {
    final repository = ref.read(mixerSettingsRepositoryProvider);

    try {
      final persisted = await repository.load();
      state = persisted;
      _applyMetronomeVolume(persisted.metronomeVolumePercent);
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to load persisted mixer settings. Using defaults.',
        error,
        stackTrace,
      );
      _applyMetronomeVolume(state.metronomeVolumePercent);
    }
  }

  void setMetronomeVolumePercent(int volumePercent) {
    final clampedVolume = _clampVolume(volumePercent);
    _applyMetronomeVolume(clampedVolume);
    state = state.copyWith(metronomeVolumePercent: clampedVolume);
    _persist();
  }

  void setSongVolumePercent(int volumePercent) {
    state = state.copyWith(songVolumePercent: _clampVolume(volumePercent));
    _persist();
  }

  void setCueVolumePercent(int volumePercent) {
    state = state.copyWith(cueVolumePercent: _clampVolume(volumePercent));
    _persist();
  }

  void setTransitionVolumePercent(int volumePercent) {
    state = state.copyWith(
      transitionVolumePercent: _clampVolume(volumePercent),
    );
    _persist();
  }

  double songVolumeFactor() {
    return state.songVolumePercent / AudioMixerState.maximumVolumePercent;
  }

  double cueVolumeFactor() {
    return state.cueVolumePercent / AudioMixerState.maximumVolumePercent;
  }

  double transitionVolumeFactor() {
    return state.transitionVolumePercent /
        AudioMixerState.maximumVolumePercent;
  }

  void _applyMetronomeVolume(int volumePercent) {
    final normalizedVolume =
        volumePercent / AudioMixerState.maximumVolumePercent;
    final audioEngine = ref.read(audioEngineProvider);

    for (final variant in ClickSoundVariant.values) {
      audioEngine.setClickChannelVolume(variant, normalizedVolume);
    }
  }

  /// Enqueues a save behind [_pendingSave] so overlapping slider drags
  /// always persist in call order, preventing a slow older write from
  /// overwriting a newer snapshot.
  void _persist() {
    final repository = ref.read(mixerSettingsRepositoryProvider);
    final snapshot = state;

    _pendingSave = _pendingSave.then((_) => repository.save(snapshot)).then(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning(
          'Failed to persist mixer settings.',
          error,
          stackTrace,
        );
      },
    );
  }

  int _clampVolume(int volumePercent) {
    return volumePercent.clamp(
      AudioMixerState.minimumVolumePercent,
      AudioMixerState.maximumVolumePercent,
    );
  }
}
