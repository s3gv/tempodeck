import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/audio_limiter_settings.dart';
import 'package:tempodeck/core/audio/click_sound_set_assets.dart';
import 'package:tempodeck/core/audio/i_audio_engine.dart';
import 'package:tempodeck/core/audio/text_to_speech_client.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/providers/audio_mixer_provider.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/providers/service_providers.dart';
import 'package:tempodeck/core/repositories/mixer_settings_repository.dart';

void main() {
  group('AudioMixerController', () {
    late _FakeAudioEngine audioEngine;
    late _FakeMixerSettingsRepository mixerSettingsRepository;
    late ProviderContainer container;

    setUp(() {
      audioEngine = _FakeAudioEngine();
      mixerSettingsRepository = _FakeMixerSettingsRepository();
      container = ProviderContainer(
        overrides: [
          audioEngineProvider.overrideWithValue(audioEngine),
          mixerSettingsRepositoryProvider
              .overrideWithValue(mixerSettingsRepository),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('initializes with 80% defaults', () {
      final state = container.read(audioMixerControllerProvider);

      expect(state.metronomeVolumePercent, 80);
      expect(state.songVolumePercent, 80);
      expect(state.cueVolumePercent, 80);
      expect(state.transitionVolumePercent, 80);
    });

    test('sets grouped metronome volume across every click variant', () {
      final controller = container.read(audioMixerControllerProvider.notifier);

      controller.setMetronomeVolumePercent(42);

      expect(
        container.read(audioMixerControllerProvider).metronomeVolumePercent,
        42,
      );
      expect(
        audioEngine.channelVolumes,
        hasLength(ClickSoundVariant.values.length),
      );

      for (final variant in ClickSoundVariant.values) {
        expect(audioEngine.channelVolumes[variant], closeTo(0.42, 0.0001));
      }
    });

    test('clamps mixer values and exposes normalized factors', () {
      final controller = container.read(audioMixerControllerProvider.notifier);

      controller.setSongVolumePercent(135);
      controller.setCueVolumePercent(-10);
      controller.setTransitionVolumePercent(55);

      final state = container.read(audioMixerControllerProvider);
      expect(state.songVolumePercent, 100);
      expect(state.cueVolumePercent, 0);
      expect(state.transitionVolumePercent, 55);
      expect(controller.songVolumeFactor(), 1);
      expect(controller.cueVolumeFactor(), 0);
      expect(controller.transitionVolumeFactor(), 0.55);
    });

    test('persists state on every setter call', () async {
      final controller = container.read(audioMixerControllerProvider.notifier);

      controller.setMetronomeVolumePercent(60);
      controller.setSongVolumePercent(70);
      controller.setCueVolumePercent(50);
      controller.setTransitionVolumePercent(90);

      // Let fire-and-forget futures complete.
      await Future<void>.delayed(Duration.zero);

      final persisted = mixerSettingsRepository.lastSaved;
      expect(persisted, isNotNull);
      expect(persisted!.metronomeVolumePercent, 60);
      expect(persisted.songVolumePercent, 70);
      expect(persisted.cueVolumePercent, 50);
      expect(persisted.transitionVolumePercent, 90);
    });

    test('loadPersistedSettings restores saved volumes', () async {
      mixerSettingsRepository.storedState = const AudioMixerState(
        metronomeVolumePercent: 55,
        songVolumePercent: 65,
        cueVolumePercent: 45,
        transitionVolumePercent: 75,
      );

      final controller = container.read(audioMixerControllerProvider.notifier);
      await controller.loadPersistedSettings();

      final state = container.read(audioMixerControllerProvider);
      expect(state.metronomeVolumePercent, 55);
      expect(state.songVolumePercent, 65);
      expect(state.cueVolumePercent, 45);
      expect(state.transitionVolumePercent, 75);

      // Metronome volume should also be applied to click channels.
      for (final variant in ClickSoundVariant.values) {
        expect(audioEngine.channelVolumes[variant], closeTo(0.55, 0.0001));
      }
    });

    test('loadPersistedSettings falls back to defaults on failure', () async {
      mixerSettingsRepository.shouldFailOnLoad = true;

      final controller = container.read(audioMixerControllerProvider.notifier);
      await controller.loadPersistedSettings();

      final state = container.read(audioMixerControllerProvider);
      expect(state.metronomeVolumePercent, 80);
      expect(state.songVolumePercent, 80);

      // Default metronome volume must still be applied to the engine.
      for (final variant in ClickSoundVariant.values) {
        expect(audioEngine.channelVolumes[variant], closeTo(0.80, 0.0001));
      }
    });

    test('persists writes in order during rapid slider changes', () async {
      final controller = container.read(audioMixerControllerProvider.notifier);

      // Simulate rapid slider drag: many changes in quick succession.
      for (var i = 50; i <= 70; i++) {
        controller.setMetronomeVolumePercent(i);
      }

      // Let all chained futures complete.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // The last persisted state must reflect the final slider position.
      expect(mixerSettingsRepository.lastSaved?.metronomeVolumePercent, 70);
    });
  });
}

class _FakeMixerSettingsRepository implements MixerSettingsRepository {
  AudioMixerState? storedState;
  AudioMixerState? lastSaved;
  bool shouldFailOnLoad = false;

  @override
  Future<AudioMixerState> load() async {
    if (shouldFailOnLoad) {
      throw Exception('Simulated load failure');
    }
    return storedState ?? AudioMixerState.initial();
  }

  @override
  Future<void> save(AudioMixerState state) async {
    lastSaved = state;
  }
}

class _FakeAudioEngine implements IAudioEngine {
  final Map<ClickSoundVariant, double> channelVolumes = {};

  @override
  bool get isInitialized => true;

  @override
  Future<void> dispose() async {}

  @override
  Future<List<TextToSpeechVoice>> getAvailableVoices() async => [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadClickSoundSet(ClickSoundSet set) async {}

  @override
  Future<void> playCue(AudioCue cue) async {}

  @override
  Future<void> preloadLinkedAudio(String filePath) async {}

  @override
  Future<PreparedLinkedAudioHandle> prepareLinkedAudioPlayback(
    String filePath, {
    required Duration offset,
    required double volume,
  }) async =>
      const PreparedLinkedAudioHandle('audio-mixer-test');

  @override
  Future<void> playPreparedLinkedAudio(
    PreparedLinkedAudioHandle handle,
  ) async {}

  @override
  Future<void> releasePreparedLinkedAudio(
    PreparedLinkedAudioHandle handle,
  ) async {}

  @override
  void playClick(AccentLevel accent) {}

  @override
  void playSubdivisionClick() {}

  @override
  Future<void> playLinkedAudio(
    String filePath, {
    required Duration offset,
    required double volume,
  }) async {}

  @override
  void selectClickSoundSet(ClickSoundSet set) {}

  @override
  void setClickChannelVolume(ClickSoundVariant variant, double volume) {
    channelVolumes[variant] = volume;
  }

  @override
  void setLimiter(AudioLimiterSettings settings) {}

  @override
  void setMasterVolume(double volume) {}

  @override
  Future<void> speakCue(String text, {String? voiceIdentifier}) async {}

  @override
  Future<void> stop() async {}
}
