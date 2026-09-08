import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/audio_engine_config.dart';
import 'package:tempodeck/core/audio/soloud_audio_engine.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';

import 'audio_playback_session_test_support.dart';
import 'soloud_audio_engine_test.dart';

/// Contract tests for the linked audio path of [SoLoudAudioEngine].
///
/// These tests exercise the real engine with [FakeSoLoudClient] to prove
/// load, play, seek, preview, prepare, restart, and caching behaviors
/// work correctly end-to-end.
void main() {
  group('SoLoudAudioEngine linked audio contract', () {
    late FakeSoLoudClient client;
    late FakeTextToSpeechClient textToSpeechClient;
    late FakeAudioPlaybackSession playbackSession;
    late SoLoudAudioEngine engine;

    setUp(() async {
      client = FakeSoLoudClient();
      textToSpeechClient = FakeTextToSpeechClient();
      playbackSession = FakeAudioPlaybackSession();
      engine = SoLoudAudioEngine(
        soLoudClient: client,
        textToSpeechClient: textToSpeechClient,
        playbackSession: playbackSession,
        config: const AudioEngineConfig(),
      );
      await engine.initialize();
    });

    group('load -> play -> seek to offset -> stop', () {
      test('loads the file, plays at offset, then stops all voices', () async {
        await engine.playLinkedAudio(
          '/tmp/track.wav',
          offset: const Duration(seconds: 5),
          volume: 0.8,
        );

        expect(client.loadedFilePaths, ['/tmp/track.wav']);
        expect(client.playedAssetPaths, contains('/tmp/track.wav'));
        expect(client.seekOffsets, [const Duration(seconds: 5)]);
        expect(client.playedVolumes.last, 0.8);

        await engine.stop();

        expect(client.stoppedAssetPaths, contains('/tmp/track.wav'));
      });
    });

    group('preload -> prepare -> play prepared -> stop', () {
      test('preloads, prepares paused, then unpauses on play', () async {
        // Preload: file loaded, nothing played.
        await engine.preloadLinkedAudio('/tmp/prepared.wav');
        expect(client.loadedFilePaths, ['/tmp/prepared.wav']);
        expect(client.playedAssetPaths, isEmpty);

        // Prepare: file played paused, seeked to offset.
        final handle = await engine.prepareLinkedAudioPlayback(
          '/tmp/prepared.wav',
          offset: const Duration(milliseconds: 3000),
          volume: 0.6,
        );
        expect(client.playedAssetPaths, ['/tmp/prepared.wav']);
        expect(client.playedPausedStates, [true]);
        expect(client.seekOffsets, [const Duration(milliseconds: 3000)]);
        expect(client.playedVolumes, [0.6]);

        // Play prepared: unpauses the voice.
        await engine.playPreparedLinkedAudio(handle);
        expect(client.pauseStates, [false]);

        // Stop: all sources stopped.
        await engine.stop();
        expect(client.stoppedAssetPaths, contains('/tmp/prepared.wav'));
      });
    });

    group('load same file twice (cache reuse)', () {
      test('loads the file source only once across two plays', () async {
        await engine.playLinkedAudio(
          '/tmp/cached.wav',
          offset: Duration.zero,
          volume: 1.0,
        );
        await engine.playLinkedAudio(
          '/tmp/cached.wav',
          offset: const Duration(seconds: 2),
          volume: 0.5,
        );

        // File loaded only once.
        expect(client.loadedFilePaths, hasLength(1));
        expect(client.loadedFilePaths, ['/tmp/cached.wav']);

        // Played twice.
        expect(
          client.playedAssetPaths.where((p) => p == '/tmp/cached.wav'),
          hasLength(2),
        );
        expect(client.playedVolumes, [1.0, 0.5]);
      });
    });

    group('play at zero offset (no seek)', () {
      test('does not seek or pause when offset is zero', () async {
        await engine.playLinkedAudio(
          '/tmp/zero-offset.wav',
          offset: Duration.zero,
          volume: 1.0,
        );

        expect(client.loadedFilePaths, ['/tmp/zero-offset.wav']);
        expect(client.playedAssetPaths, ['/tmp/zero-offset.wav']);
        // No seek needed when offset is zero.
        expect(client.seekOffsets, isEmpty);
        // Not started paused when offset is zero.
        expect(client.playedPausedStates, [false]);
      });
    });

    group('play at nonzero offset (seek + unpause)', () {
      test('starts paused, seeks, then unpauses', () async {
        await engine.playLinkedAudio(
          '/tmp/offset-track.wav',
          offset: const Duration(milliseconds: 7500),
          volume: 0.9,
        );

        expect(client.playedAssetPaths, ['/tmp/offset-track.wav']);
        // Started paused because offset > 0.
        expect(client.playedPausedStates, [true]);
        // Seeked to the offset.
        expect(client.seekOffsets, [const Duration(milliseconds: 7500)]);
        // Unpaused after seek.
        expect(client.pauseStates, [false]);
        expect(client.playedVolumes, [0.9]);
      });
    });

    group('stop and restart with different offset', () {
      test('stops, then replays at a different offset', () async {
        await engine.playLinkedAudio(
          '/tmp/restart-offset.wav',
          offset: const Duration(seconds: 1),
          volume: 1.0,
        );
        await engine.stop();

        expect(client.stoppedAssetPaths, contains('/tmp/restart-offset.wav'));

        await engine.playLinkedAudio(
          '/tmp/restart-offset.wav',
          offset: const Duration(seconds: 10),
          volume: 0.7,
        );

        // File loaded only once (cached across stop).
        expect(
          client.loadedFilePaths.where(
            (p) => p == '/tmp/restart-offset.wav',
          ),
          hasLength(1),
        );

        // Played twice.
        expect(
          client.playedAssetPaths.where(
            (p) => p == '/tmp/restart-offset.wav',
          ),
          hasLength(2),
        );

        // Both offsets recorded.
        expect(
          client.seekOffsets,
          [
            const Duration(seconds: 1),
            const Duration(seconds: 10),
          ],
        );

        // Volume changed.
        expect(client.playedVolumes.last, 0.7);
      });
    });

    group('release prepared handle', () {
      test('releases the prepared handle and stops its voices', () async {
        final handle = await engine.prepareLinkedAudioPlayback(
          '/tmp/release-test.wav',
          offset: const Duration(seconds: 2),
          volume: 0.5,
        );

        // Voices are playing (paused) for the prepared handle.
        expect(client.playedAssetPaths, ['/tmp/release-test.wav']);

        await engine.releasePreparedLinkedAudio(handle);

        // Source voices stopped on release.
        expect(client.stoppedAssetPaths, contains('/tmp/release-test.wav'));
      });

      test('releasing an already-released handle is a no-op', () async {
        final handle = await engine.prepareLinkedAudioPlayback(
          '/tmp/double-release.wav',
          offset: Duration.zero,
          volume: 1.0,
        );

        await engine.releasePreparedLinkedAudio(handle);
        final stopCountAfterFirst = client.stoppedAssetPaths.length;

        // Second release should not throw or stop anything extra.
        await engine.releasePreparedLinkedAudio(handle);
        expect(client.stoppedAssetPaths.length, stopCountAfterFirst);
      });
    });

    group('prepare new handle replaces old prepared handle for same file', () {
      test('old prepared handle is stopped when a new one is prepared',
          () async {
        final handle1 = await engine.prepareLinkedAudioPlayback(
          '/tmp/replace-test.wav',
          offset: const Duration(seconds: 1),
          volume: 0.5,
        );

        expect(client.playedAssetPaths, ['/tmp/replace-test.wav']);
        expect(client.stoppedAssetPaths, isEmpty);

        // Prepare a new handle for the same file — old one should be stopped.
        final handle2 = await engine.prepareLinkedAudioPlayback(
          '/tmp/replace-test.wav',
          offset: const Duration(seconds: 5),
          volume: 0.8,
        );

        // The old handle's voices were stopped.
        expect(client.stoppedAssetPaths, contains('/tmp/replace-test.wav'));

        // New handle was created.
        expect(
          client.playedAssetPaths.where(
            (p) => p == '/tmp/replace-test.wav',
          ),
          hasLength(2),
        );
        expect(client.seekOffsets.last, const Duration(seconds: 5));
        expect(client.playedVolumes.last, 0.8);

        // Both handles share the same internal key (derived from file path).
        // Playing handle2 unpauses the new prepared voice.
        await engine.playPreparedLinkedAudio(handle2);
        expect(client.pauseStates.last, false);

        // After handle2 was played and consumed, its entry is removed.
        // Playing handle1 (same key) now throws because no entry remains.
        await expectLater(
          engine.playPreparedLinkedAudio(handle1),
          throwsStateError,
        );
      });
    });

    group('custom file cue through playCue -> delegates to playLinkedAudio',
        () {
      test('playCue with customFile type loads and plays the file', () async {
        await engine.playCue(
          const AudioCue(
            type: AudioCueType.customFile,
            customFilePath: '/tmp/cue-custom.wav',
            volumePercent: 40,
          ),
        );

        expect(client.loadedFilePaths, ['/tmp/cue-custom.wav']);
        expect(client.playedAssetPaths, contains('/tmp/cue-custom.wav'));
        expect(client.playedVolumes.last, 0.4);
      });

      test('custom file cues reuse cached file sources', () async {
        await engine.playCue(
          const AudioCue(
            type: AudioCueType.customFile,
            customFilePath: '/tmp/cue-reuse.wav',
            volumePercent: 50,
          ),
        );
        await engine.playCue(
          const AudioCue(
            type: AudioCueType.customFile,
            customFilePath: '/tmp/cue-reuse.wav',
            volumePercent: 80,
          ),
        );

        // Loaded only once.
        expect(
          client.loadedFilePaths.where((p) => p == '/tmp/cue-reuse.wav'),
          hasLength(1),
        );

        // Played twice.
        expect(
          client.playedAssetPaths.where((p) => p == '/tmp/cue-reuse.wav'),
          hasLength(2),
        );
      });
    });

    group('preload and play overlap reuses the same source', () {
      test('concurrent preload and play share the same file load', () async {
        final delayedClient = DelayedFileLoadSoLoudClient();
        engine = SoLoudAudioEngine(
          soLoudClient: delayedClient,
          textToSpeechClient: textToSpeechClient,
          playbackSession: playbackSession,
          config: const AudioEngineConfig(),
        );
        await engine.initialize();

        final preloadFuture = engine.preloadLinkedAudio('/tmp/overlap.wav');
        final playFuture = engine.playLinkedAudio(
          '/tmp/overlap.wav',
          offset: Duration.zero,
          volume: 1,
        );

        // Only one file load initiated.
        expect(delayedClient.loadedFilePaths, ['/tmp/overlap.wav']);

        delayedClient.completePendingFileLoad();
        await preloadFuture;
        await playFuture;

        // File loaded exactly once.
        expect(
          delayedClient.loadedFilePaths.where(
            (p) => p == '/tmp/overlap.wav',
          ),
          hasLength(1),
        );

        // Played once.
        expect(
          delayedClient.playedAssetPaths.where(
            (p) => p == '/tmp/overlap.wav',
          ),
          hasLength(1),
        );
      });
    });

    group('prepare with zero offset skips seek', () {
      test('prepareLinkedAudioPlayback at zero offset does not seek', () async {
        final handle = await engine.prepareLinkedAudioPlayback(
          '/tmp/zero-prepare.wav',
          offset: Duration.zero,
          volume: 1.0,
        );

        expect(client.playedPausedStates, [true]);
        // No seek when offset is zero.
        expect(client.seekOffsets, isEmpty);

        await engine.playPreparedLinkedAudio(handle);
        expect(client.pauseStates, [false]);
      });
    });

    group('prepare with nonzero offset applies seek', () {
      test('prepareLinkedAudioPlayback at nonzero offset seeks correctly',
          () async {
        final handle = await engine.prepareLinkedAudioPlayback(
          '/tmp/nonzero-prepare.wav',
          offset: const Duration(milliseconds: 4200),
          volume: 0.7,
        );

        expect(client.playedPausedStates, [true]);
        expect(client.seekOffsets, [const Duration(milliseconds: 4200)]);
        expect(client.playedVolumes, [0.7]);

        await engine.playPreparedLinkedAudio(handle);
        expect(client.pauseStates, [false]);
      });
    });

    group('volume clamping', () {
      test('volumes above 1.0 are clamped to 1.0', () async {
        await engine.playLinkedAudio(
          '/tmp/clamp-high.wav',
          offset: Duration.zero,
          volume: 2.5,
        );

        expect(client.playedVolumes.last, 1.0);
      });

      test('volumes below 0.0 are clamped to 0.0', () async {
        await engine.playLinkedAudio(
          '/tmp/clamp-low.wav',
          offset: Duration.zero,
          volume: -0.5,
        );

        expect(client.playedVolumes.last, 0.0);
      });
    });

    group('dispose clears linked audio caches', () {
      test('file sources are reloaded after dispose and reinitialize',
          () async {
        await engine.playLinkedAudio(
          '/tmp/dispose-linked.wav',
          offset: Duration.zero,
          volume: 1.0,
        );
        expect(client.loadedFilePaths, ['/tmp/dispose-linked.wav']);

        await engine.dispose();
        await engine.initialize();

        await engine.playLinkedAudio(
          '/tmp/dispose-linked.wav',
          offset: Duration.zero,
          volume: 1.0,
        );

        // Loaded twice because cache was cleared on dispose.
        expect(
          client.loadedFilePaths.where(
            (p) => p == '/tmp/dispose-linked.wav',
          ),
          hasLength(2),
        );
      });
    });

    group('stop clears prepared linked audio handles', () {
      test('prepared handles are invalidated after stop', () async {
        await engine.prepareLinkedAudioPlayback(
          '/tmp/stop-prepared.wav',
          offset: const Duration(seconds: 1),
          volume: 0.5,
        );

        await engine.stop();

        // Prepared handles map is cleared — sources are stopped.
        expect(client.stoppedAssetPaths, contains('/tmp/stop-prepared.wav'));
      });
    });
  });
}
