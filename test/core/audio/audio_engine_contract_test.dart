import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/audio_engine_config.dart';
import 'package:tempodeck/core/audio/audio_limiter_settings.dart';
import 'package:tempodeck/core/audio/click_sound_set_assets.dart';
import 'package:tempodeck/core/audio/soloud_audio_engine.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';

import 'audio_playback_session_test_support.dart';
import 'soloud_audio_engine_test.dart';

/// Contract tests for [SoLoudAudioEngine] proving the full lifecycle works
/// end-to-end with a real engine instance backed by [FakeSoLoudClient].
///
/// These tests exercise real intermediate classes and verify the engine
/// honors its contract across init, playback, stop, restart, and dispose.
void main() {
  group('SoLoudAudioEngine contract', () {
    late FakeSoLoudClient client;
    late FakeTextToSpeechClient textToSpeechClient;
    late FakeAudioPlaybackSession playbackSession;
    late SoLoudAudioEngine engine;

    setUp(() {
      client = FakeSoLoudClient();
      textToSpeechClient = FakeTextToSpeechClient();
      playbackSession = FakeAudioPlaybackSession();
      engine = SoLoudAudioEngine(
        soLoudClient: client,
        textToSpeechClient: textToSpeechClient,
        playbackSession: playbackSession,
        config: const AudioEngineConfig(),
      );
    });

    group('full lifecycle: init -> play clicks -> play cues -> '
        'play linked audio -> stop -> restart -> dispose', () {
      test('executes the complete lifecycle without errors', () async {
        // Phase 1: Initialize
        await engine.initialize();
        expect(client.initCallCount, 1);
        expect(client.isInitializedValue, isTrue);
        expect(
          client.loadedAssetPaths,
          hasLength(ClickSoundSet.values.length * 4),
        );
        expect(client.loadedGeneratedSources, hasLength(5));

        // Phase 2: Play clicks
        engine.playClick(AccentLevel.high);
        engine.playClick(AccentLevel.normal);
        engine.playClick(AccentLevel.low);
        expect(client.playedAssetPaths, hasLength(3));
        expect(
          client.playedAssetPaths,
          [
            'assets/audio/click_kits/tock/tock_accent_high.wav',
            'assets/audio/click_kits/tock/tock_normal.wav',
            'assets/audio/click_kits/tock/tock_accent_low.wav',
          ],
        );

        // Phase 3: Play cues
        await engine.playCue(
          const AudioCue(type: AudioCueType.intervalSignal),
        );
        await engine.playCue(
          const AudioCue(type: AudioCueType.highPulse, volumePercent: 50),
        );
        expect(
          client.playedAssetPaths.sublist(3),
          [
            'generated://cue/interval_signal.wav',
            'generated://cue/high_pulse.wav',
          ],
        );

        // Phase 4: Play linked audio
        await engine.playLinkedAudio(
          '/tmp/lifecycle-test.wav',
          offset: const Duration(seconds: 5),
          volume: 0.7,
        );
        expect(client.loadedFilePaths, ['/tmp/lifecycle-test.wav']);
        expect(
          client.playedAssetPaths.last,
          '/tmp/lifecycle-test.wav',
        );
        expect(client.seekOffsets, [const Duration(seconds: 5)]);

        // Phase 5: Stop
        await engine.stop();
        expect(
          client.stoppedAssetPaths,
          isNotEmpty,
        );
        expect(textToSpeechClient.stopCallCount, 1);

        // Phase 6: Restart with new config
        engine.setMasterVolume(0.5);
        engine.playClick(AccentLevel.high);
        await engine.playLinkedAudio(
          '/tmp/lifecycle-test.wav',
          offset: const Duration(seconds: 10),
          volume: 0.9,
        );
        expect(client.globalVolume, 0.5);
        expect(
          client.seekOffsets.last,
          const Duration(seconds: 10),
        );
        expect(client.playedVolumes.last, 0.9);

        // Phase 7: Dispose
        await engine.dispose();
        expect(client.deinitCallCount, 1);
        expect(playbackSession.deactivateCallCount, 1);
      });
    });

    group('click kit switching during active playback', () {
      test('switches all click sound sets while playing clicks', () async {
        await engine.initialize();

        for (final soundSet in ClickSoundSet.values) {
          await engine.loadClickSoundSet(soundSet);
          engine.selectClickSoundSet(soundSet);
          engine.playClick(AccentLevel.high);
        }

        // Each sound set should produce one click for AccentLevel.high.
        expect(
          client.playedAssetPaths.where(
            (path) => path.endsWith('_accent_high.wav'),
          ),
          hasLength(ClickSoundSet.values.length),
        );

        // Verify every sound set slug appears in the played paths.
        for (final soundSet in ClickSoundSet.values) {
          final assets = ClickSoundSetAssets.forSoundSet(soundSet);
          expect(
            client.playedAssetPaths,
            contains(assets.assetPathFor(ClickSoundVariant.accentHigh)),
          );
        }
      });

      test('plays clicks from the newly selected kit, not the previous one',
          () async {
        await engine.initialize();

        engine.selectClickSoundSet(ClickSoundSet.tock);
        engine.playClick(AccentLevel.normal);

        engine.selectClickSoundSet(ClickSoundSet.hype);
        engine.playClick(AccentLevel.normal);

        expect(
          client.playedAssetPaths,
          [
            'assets/audio/click_kits/tock/tock_normal.wav',
            'assets/audio/click_kits/hype/hype_normal.wav',
          ],
        );
      });
    });

    group('all cue types in sequence', () {
      test('plays interval, max, low pulse, mid pulse, high pulse, '
          'voice, and custom file cues in order', () async {
        await engine.initialize();

        // Synthetic cues
        await engine.playCue(
          const AudioCue(type: AudioCueType.intervalSignal),
        );
        await engine.playCue(
          const AudioCue(type: AudioCueType.maxSignal),
        );
        await engine.playCue(
          const AudioCue(type: AudioCueType.lowPulse),
        );
        await engine.playCue(
          const AudioCue(type: AudioCueType.midPulse),
        );
        await engine.playCue(
          const AudioCue(type: AudioCueType.highPulse, volumePercent: 60),
        );

        expect(
          client.playedAssetPaths,
          [
            'generated://cue/interval_signal.wav',
            'generated://cue/max_signal.wav',
            'generated://cue/low_pulse.wav',
            'generated://cue/mid_pulse.wav',
            'generated://cue/high_pulse.wav',
          ],
        );
        expect(client.playedVolumes[4], 0.6);

        // Voice cue
        await engine.playCue(
          const AudioCue(
            type: AudioCueType.voice,
            voiceText: 'One',
            voiceIdentifier: 'custom-voice',
          ),
        );
        expect(textToSpeechClient.spokenTexts, ['One']);
        expect(textToSpeechClient.setLanguageCalls, ['de-DE']);

        // Custom file cue
        await engine.playCue(
          const AudioCue(
            type: AudioCueType.customFile,
            customFilePath: '/tmp/custom-cue.wav',
            volumePercent: 30,
          ),
        );
        expect(client.loadedFilePaths, ['/tmp/custom-cue.wav']);
        expect(client.playedAssetPaths.last, '/tmp/custom-cue.wav');
        expect(client.playedVolumes.last, 0.3);
      });
    });

    group('concurrent linked audio and click playback', () {
      test('plays linked audio and clicks simultaneously', () async {
        await engine.initialize();

        await engine.playLinkedAudio(
          '/tmp/backing-track.wav',
          offset: const Duration(seconds: 2),
          volume: 0.8,
        );

        // Simulate ongoing clicks while linked audio plays.
        engine.playClick(AccentLevel.high);
        engine.playClick(AccentLevel.normal);
        engine.playClick(AccentLevel.low);

        // Linked audio was loaded and played.
        expect(client.loadedFilePaths, ['/tmp/backing-track.wav']);
        expect(
          client.playedAssetPaths,
          contains('/tmp/backing-track.wav'),
        );

        // Clicks were also played (3 clicks + 1 linked audio).
        expect(
          client.playedAssetPaths.where(
            (path) => path.startsWith('assets/audio/click_kits/'),
          ),
          hasLength(3),
        );
      });
    });

    group('master volume changes during playback', () {
      test('applies volume changes that take effect immediately', () async {
        await engine.initialize();
        expect(client.globalVolume, 1.0);

        engine.setMasterVolume(0.3);
        expect(client.globalVolume, 0.3);

        engine.setMasterVolume(0.8);
        expect(client.globalVolume, 0.8);

        engine.setMasterVolume(0.0);
        expect(client.globalVolume, 0.0);

        engine.setMasterVolume(1.0);
        expect(client.globalVolume, 1.0);
      });
    });

    group('limiter settings changes during playback', () {
      test('applies limiter settings that take effect immediately', () async {
        await engine.initialize();
        expect(client.limiterSettings, const AudioLimiterSettings());

        const customLimiter = AudioLimiterSettings(
          wet: 0.5,
          threshold: -12,
          outputCeiling: -3,
          kneeWidth: 6,
          releaseTimeMs: 200,
          attackTimeMs: 5,
        );
        engine.setLimiter(customLimiter);
        expect(client.limiterSettings, customLimiter);

        const defaultLimiter = AudioLimiterSettings();
        engine.setLimiter(defaultLimiter);
        expect(client.limiterSettings, defaultLimiter);
      });
    });

    group('stop clears all active sounds', () {
      test('stops clicks, cues, linked audio, and TTS in one call', () async {
        await engine.initialize();

        // Play clicks
        engine.playClick(AccentLevel.high);
        engine.playClick(AccentLevel.normal);

        // Play a cue
        await engine.playCue(
          const AudioCue(type: AudioCueType.highPulse),
        );

        // Play linked audio
        await engine.playLinkedAudio(
          '/tmp/stop-test.wav',
          offset: Duration.zero,
          volume: 1.0,
        );

        // Play voice cue
        await engine.playCue(
          const AudioCue(
            type: AudioCueType.voice,
            voiceText: 'Test',
            voiceIdentifier: 'custom-voice',
          ),
        );

        await engine.stop();

        // All sources should have their voices stopped.
        expect(
          client.stoppedAssetPaths,
          containsAll([
            'assets/audio/click_kits/tock/tock_accent_high.wav',
            'assets/audio/click_kits/tock/tock_normal.wav',
            'generated://cue/high_pulse.wav',
            '/tmp/stop-test.wav',
          ]),
        );
        // TTS was also stopped.
        expect(textToSpeechClient.stopCallCount, 1);
      });
    });

    group('restart after stop works with new config', () {
      test('plays clicks and linked audio after stop/restart cycle', () async {
        await engine.initialize();

        // First playback session
        engine.playClick(AccentLevel.high);
        await engine.playLinkedAudio(
          '/tmp/restart-test.wav',
          offset: const Duration(seconds: 1),
          volume: 0.5,
        );
        await engine.stop();

        // Second playback session with different parameters
        engine.setMasterVolume(0.7);
        engine.selectClickSoundSet(ClickSoundSet.hype);
        engine.playClick(AccentLevel.low);
        await engine.playLinkedAudio(
          '/tmp/restart-test.wav',
          offset: const Duration(seconds: 3),
          volume: 0.9,
        );

        expect(client.globalVolume, 0.7);
        expect(
          client.playedAssetPaths.last,
          '/tmp/restart-test.wav',
        );
        expect(client.seekOffsets.last, const Duration(seconds: 3));
        expect(client.playedVolumes.last, 0.9);
        expect(
          client.playedAssetPaths,
          contains('assets/audio/click_kits/hype/hype_accent_low.wav'),
        );
      });
    });

    group('dispose -> re-init -> play works cleanly', () {
      test('reinitializes after dispose and plays without errors', () async {
        await engine.initialize();
        engine.playClick(AccentLevel.high);
        await engine.playLinkedAudio(
          '/tmp/dispose-test.wav',
          offset: Duration.zero,
          volume: 1.0,
        );

        await engine.dispose();
        expect(client.deinitCallCount, 1);

        // Re-initialize
        await engine.initialize();
        expect(client.initCallCount, 2);

        // Play clicks and linked audio again
        engine.playClick(AccentLevel.normal);
        await engine.playLinkedAudio(
          '/tmp/dispose-test.wav',
          offset: const Duration(milliseconds: 500),
          volume: 0.6,
        );

        // File was loaded twice (caches cleared on dispose)
        expect(
          client.loadedFilePaths.where(
            (path) => path == '/tmp/dispose-test.wav',
          ),
          hasLength(2),
        );

        // Both plays happened
        expect(
          client.playedAssetPaths.where(
            (path) => path == '/tmp/dispose-test.wav',
          ),
          hasLength(2),
        );
      });

      test('re-initialize reloads all click sound sets', () async {
        await engine.initialize();
        final firstLoadCount = client.loadedAssetPaths.length;

        await engine.dispose();
        await engine.initialize();

        expect(client.loadedAssetPaths, hasLength(firstLoadCount * 2));
      });

      test('re-initialize reloads all generated cue sources', () async {
        await engine.initialize();
        final firstGeneratedCount = client.loadedGeneratedSources.length;

        await engine.dispose();
        await engine.initialize();

        expect(
          client.loadedGeneratedSources,
          hasLength(firstGeneratedCount * 2),
        );
      });
    });

    group('click channel volume integration', () {
      test('applies per-variant volume when playing clicks', () async {
        await engine.initialize();

        engine.setClickChannelVolume(ClickSoundVariant.accentHigh, 0.5);
        engine.setClickChannelVolume(ClickSoundVariant.normal, 0.3);
        engine.setClickChannelVolume(ClickSoundVariant.accentLow, 0.1);

        engine.playClick(AccentLevel.high);
        engine.playClick(AccentLevel.normal);
        engine.playClick(AccentLevel.low);

        expect(client.playedVolumes, [0.5, 0.3, 0.1]);
      });
    });

    group('mute accent handling', () {
      test('does not emit any sound for mute accents across the lifecycle',
          () async {
        await engine.initialize();

        engine.playClick(AccentLevel.mute);
        engine.playClick(AccentLevel.mute);
        engine.playClick(AccentLevel.mute);

        expect(client.playedAssetPaths, isEmpty);
      });
    });

    group('voice cue integration', () {
      test('resolves voices, sets language, and speaks text', () async {
        await engine.initialize();

        await engine.speakCue(
          'Ready',
          voiceIdentifier: 'custom-voice',
        );
        await engine.speakCue(
          'Set',
          voiceIdentifier: 'custom-voice',
        );
        await engine.speakCue(
          'Go',
          voiceIdentifier: 'custom-voice',
        );

        expect(textToSpeechClient.spokenTexts, ['Ready', 'Set', 'Go']);
        // Voice lookup should happen only once (cached).
        expect(textToSpeechClient.getVoicesCallCount, 1);
        // Language and voice set for each speak call.
        expect(textToSpeechClient.setLanguageCalls, hasLength(3));
        expect(textToSpeechClient.setVoiceCalls, hasLength(3));
      });

      test('falls back to English when requested voice is not available',
          () async {
        await engine.initialize();

        await engine.speakCue(
          'Hello',
          voiceIdentifier: 'nonexistent-voice',
        );

        expect(textToSpeechClient.setLanguageCalls, ['en-US']);
        expect(textToSpeechClient.spokenTexts, ['Hello']);
      });
    });

    group('preconfigured settings before initialization', () {
      test('master volume set before init is applied during initialization',
          () async {
        engine.setMasterVolume(0.42);

        await engine.initialize();

        expect(client.globalVolume, 0.42);
      });

      test('limiter set before init is applied during initialization',
          () async {
        const limiter = AudioLimiterSettings(
          wet: 0.7,
          threshold: -10,
          outputCeiling: -2,
          kneeWidth: 5,
          releaseTimeMs: 120,
          attackTimeMs: 3,
        );
        engine.setLimiter(limiter);

        await engine.initialize();

        expect(client.limiterSettings, limiter);
      });
    });
  });
}
