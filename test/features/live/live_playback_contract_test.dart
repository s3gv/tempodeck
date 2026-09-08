import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tempodeck/core/audio/audio_engine_config.dart';
import 'package:tempodeck/core/audio/metronome_click_engine.dart';
import 'package:tempodeck/core/audio/soloud_audio_engine.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/audio/song_playback_beatmap.dart';
import 'package:tempodeck/core/files/linked_audio_path_repair_service.dart';
import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/providers/service_providers.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/features/live/live_metronome_transport.dart';
import 'package:tempodeck/features/live/live_screen_controller.dart';
import 'package:tempodeck/features/live/live_view_context.dart';

import '../../core/audio/audio_playback_session_test_support.dart';
import '../../core/audio/foreground_playback_service_test_support.dart';
import '../../core/audio/metronome_click_engine_test.dart';
import '../../core/audio/soloud_audio_engine_test.dart';

/// Contract tests for [LiveScreenController] using a real
/// [AudioEngineLiveMetronomeTransport] + real [MetronomeClickEngine] + real
/// [SoLoudAudioEngine] backed by [FakeSoLoudClient].
///
/// These tests prove the controller -> transport -> click engine -> audio
/// engine chain works end-to-end for song, setlist, and metronome playback.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSoLoudClient soLoudClient;
  late FakeTextToSpeechClient textToSpeechClient;
  late FakeAudioPlaybackSession playbackSession;
  late SoLoudAudioEngine audioEngine;
  late FakeMetronomeScheduler scheduler;
  late FakeMetronomeRunClock runClock;
  late MetronomeClickEngine clickEngine;
  late AudioEngineLiveMetronomeTransport transport;
  late FakeForegroundPlaybackService foregroundService;

  setUp(() {
    soLoudClient = FakeSoLoudClient();
    textToSpeechClient = FakeTextToSpeechClient();
    playbackSession = FakeAudioPlaybackSession();
    audioEngine = SoLoudAudioEngine(
      soLoudClient: soLoudClient,
      textToSpeechClient: textToSpeechClient,
      playbackSession: playbackSession,
      config: const AudioEngineConfig(),
    );

    scheduler = FakeMetronomeScheduler();
    runClock = FakeMetronomeRunClock();
    clickEngine = MetronomeClickEngine(
      output: _AudioEngineClickOutput(audioEngine),
      scheduler: scheduler,
      runClock: runClock,
    );

    transport = AudioEngineLiveMetronomeTransport(
      audioEngine: audioEngine,
      clickEngine: clickEngine,
    );

    foregroundService = FakeForegroundPlaybackService();
  });

  ProviderContainer createContainer({
    required LiveViewContext viewContext,
    List<Song> songs = const [],
  }) {
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
        audioEngineProvider.overrideWithValue(audioEngine),
        foregroundPlaybackServiceProvider.overrideWithValue(foregroundService),
        songRepositoryProvider.overrideWithValue(
          _FakeSongRepository(songs: songs),
        ),
        linkedAudioPathRepairServiceProvider.overrideWithValue(
          const _PassthroughLinkedAudioPathRepairService(),
        ),
        liveViewContextProvider.overrideWith(
          () => _FixedLiveViewContextNotifier(viewContext),
        ),
      ],
    );
    return container;
  }

  group('metronome start -> ticks fire -> clicks played -> stop -> '
      'UI state resets', () {
    test('full metronome playback lifecycle', () async {
      final container = createContainer(
        viewContext: const MetronomeViewContext(),
      );

      final controller =
          container.read(liveScreenControllerProvider.notifier);

      // Start playback.
      await controller.togglePlayback();

      var state = container.read(liveScreenControllerProvider);
      expect(state.isPlaying, isTrue);
      expect(state.bpm, 120);
      expect(state.beatsPerBar, 4);
      expect(state.beatUnit, 4);

      // First click was played immediately.
      expect(
        soLoudClient.playedAssetPaths,
        contains('assets/audio/click_kits/tock/tock_accent_high.wav'),
      );

      // Advance a few beats via the scheduler.
      const beatInterval = Duration(milliseconds: 500);
      for (var i = 1; i <= 3; i++) {
        runClock.elapsedValue = beatInterval * i;
        scheduler.runNext();
      }

      state = container.read(liveScreenControllerProvider);
      expect(state.barIndex, 1);
      expect(state.beatIndex, 4);

      // Stop playback.
      await controller.togglePlayback();

      state = container.read(liveScreenControllerProvider);
      expect(state.isPlaying, isFalse);
      expect(transport.isRunning, isFalse);

      container.dispose();
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('song playback with beatmap -> correct bar progression -> '
      'stop at endBar', () {
    test('song plays through bars and stops at endBar', () async {
      final song = Song(
        id: 'song-1',
        title: 'Contract Song',
        createdAt: DateTime(2024),
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 3,
      );
      final container = createContainer(
        viewContext: SongViewContext(song: song),
        songs: [song],
      );

      final controller =
          container.read(liveScreenControllerProvider.notifier);
      await controller.togglePlayback();

      var state = container.read(liveScreenControllerProvider);
      expect(state.isPlaying, isTrue);
      expect(state.bpm, 120);

      // Advance through 3 bars (3 bars * 4 beats = 12 beats total).
      // First beat was already emitted, so we need 11 more.
      const beatInterval = Duration(milliseconds: 500);
      for (var i = 1; i <= 11; i++) {
        runClock.elapsedValue = beatInterval * i;
        scheduler.runNext();
      }
      await Future<void>.delayed(Duration.zero);

      state = container.read(liveScreenControllerProvider);
      // Song should have stopped after endBar.
      expect(state.isPlaying, isFalse);

      container.dispose();
      // Allow any pending async cleanup to complete.
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('song with linked audio -> file loaded -> played at offset', () {
    test('preloads, prepares, and plays linked audio with the song',
        () async {
      final song = Song(
        id: 'song-1',
        title: 'Linked Audio Song',
        createdAt: DateTime(2024),
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 8,
        linkedAudio: const LinkedAudioFile(
          filePath: '/tmp/contract-backing.mp3',
          displayName: 'contract-backing.mp3',
          offsetMilliseconds: 1500,
          volumePercent: 75,
        ),
      );
      final container = createContainer(
        viewContext: SongViewContext(song: song),
        songs: [song],
      );

      final controller =
          container.read(liveScreenControllerProvider.notifier);
      await controller.togglePlayback();

      // Linked audio was loaded.
      expect(
        soLoudClient.loadedFilePaths,
        contains('/tmp/contract-backing.mp3'),
      );

      // Linked audio was played (via prepare + play prepared).
      expect(
        soLoudClient.playedAssetPaths,
        contains('/tmp/contract-backing.mp3'),
      );

      // Offset was applied.
      expect(
        soLoudClient.seekOffsets,
        contains(const Duration(milliseconds: 1500)),
      );

      // Allow any pending async preload operations to settle before cleanup.
      // The controller fires _preloadContextLinkedAudio on build, which
      // adds entries to the engine's _loadedFileSources asynchronously.
      // Flushing microtasks ensures all file loads complete before stop
      // iterates the map.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await audioEngine.stop();
      container.dispose();
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('song with audio cues -> cues fire at configured bars', () {
    test('plays audio cue on the configured bar', () async {
      final song = Song(
        id: 'song-1',
        title: 'Cue Song',
        createdAt: DateTime(2024),
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 8,
        songEvents: const [
          SongEvent(
            id: 'event-1',
            barIndex: 3,
            label: 'Cue Signal',
            audioCue: AudioCue(type: AudioCueType.highPulse),
          ),
        ],
      );
      final container = createContainer(
        viewContext: SongViewContext(song: song),
        songs: [song],
      );

      final controller =
          container.read(liveScreenControllerProvider.notifier);
      await controller.togglePlayback();

      // Record which generated cues have been played so far.
      final initialCuePlays = soLoudClient.playedAssetPaths
          .where((p) => p.startsWith('generated://cue/'))
          .toList();

      // Advance to bar 2 (4 more beats from beat 1 of bar 1).
      const interval = Duration(milliseconds: 500);
      for (var i = 1; i <= 4; i++) {
        runClock.elapsedValue = interval * i;
        scheduler.runNext();
      }
      await Future<void>.delayed(Duration.zero);

      // Bar 2 should not have triggered the cue.
      final afterBar2CuePlays = soLoudClient.playedAssetPaths
          .where((p) => p.startsWith('generated://cue/'))
          .toList();
      expect(afterBar2CuePlays.length, initialCuePlays.length);

      // Advance to bar 3 (4 more beats).
      for (var i = 5; i <= 8; i++) {
        runClock.elapsedValue = interval * i;
        scheduler.runNext();
      }
      await Future<void>.delayed(Duration.zero);

      // The highPulse cue should now have been triggered.
      expect(
        soLoudClient.playedAssetPaths,
        contains('generated://cue/high_pulse.wav'),
      );

      // Stop playback before disposing to avoid async cleanup errors.
      await controller.togglePlayback();
      container.dispose();
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('song with count-in -> transition shown -> then song plays', () {
    test('shows count-in transition and then starts song playback',
        () async {
      final song = Song(
        id: 'song-1',
        title: 'Count-In Song',
        createdAt: DateTime(2024),
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 2,
        endBar: 8,
      );
      final container = createContainer(
        viewContext: SongViewContext(song: song),
        songs: [song],
      );

      final controller =
          container.read(liveScreenControllerProvider.notifier);
      unawaited(controller.togglePlayback());
      await Future<void>.delayed(Duration.zero);

      var state = container.read(liveScreenControllerProvider);
      expect(state.isTransitioning, isTrue);
      expect(state.transitionMessage, 'Count-in: 2 bars');

      // Advance through count-in bar 1 (3 more beats after first).
      const interval = Duration(milliseconds: 500);
      for (var i = 1; i <= 3; i++) {
        runClock.elapsedValue = interval * i;
        scheduler.runNext();
      }

      state = container.read(liveScreenControllerProvider);
      expect(state.transitionMessage, 'Count-in: 1 bar');

      // Advance through count-in bar 2 (beats 1-4, indices 4-7).
      for (var i = 4; i <= 7; i++) {
        runClock.elapsedValue = interval * i;
        scheduler.runNext();
      }

      // The last pulse of count-in bar 2 has fired. Now advance to
      // beat 1 of bar 3 (the first song bar), which triggers
      // _hasReachedFirstSongBar and _enterSongPlaybackPhase.
      runClock.elapsedValue = interval * 8;
      scheduler.runNext();
      await Future<void>.delayed(Duration.zero);

      state = container.read(liveScreenControllerProvider);
      // After reaching the first song bar, the transition clears.
      expect(state.isTransitioning, isFalse);
      expect(state.isPlaying, isTrue);

      await controller.togglePlayback();
      container.dispose();
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('setlist playback -> transitions between songs -> '
      'foreground service started/stopped', () {
    test('plays first song and advances to second on song end', () async {
      final song1 = Song(
        id: 'song-1',
        title: 'First',
        createdAt: DateTime(2024),
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 2,
      );
      final song2 = Song(
        id: 'song-2',
        title: 'Second',
        createdAt: DateTime(2024),
        startBpm: 140,
        beatsPerBar: 3,
        beatUnit: 8,
        countInBars: 0,
        endBar: 2,
      );
      final container = createContainer(
        viewContext: SetlistViewContext(
          setlist: Setlist(
            id: 'setlist-1',
            title: 'Contract Setlist',
            createdAt: DateTime(2024),
            items: const [
              SetlistItem(
                id: 'item-1',
                songId: 'song-1',
                songTitle: 'First',
              ),
              SetlistItem(
                id: 'item-2',
                songId: 'song-2',
                songTitle: 'Second',
              ),
            ],
          ),
        ),
        songs: [song1, song2],
      );
      final controller =
          container.read(liveScreenControllerProvider.notifier);
      await controller.togglePlayback();

      var state = container.read(liveScreenControllerProvider);
      expect(state.isPlaying, isTrue);
      expect(state.currentSongTitle, 'First');
      expect(state.currentSongIndex, 1);
      expect(state.totalSongs, 2);

      // Foreground service started.
      expect(foregroundService.startCallCount, greaterThanOrEqualTo(1));

      // Advance through song 1 (2 bars * 4 beats = 8 beats, first already played).
      const interval = Duration(milliseconds: 500);
      for (var i = 1; i <= 7; i++) {
        runClock.elapsedValue = interval * i;
        scheduler.runNext();
      }
      await Future<void>.delayed(Duration.zero);

      // Song 1 should be done, and song 2 should have started.
      // The transport is restarted for song 2 with a new scheduler.
      state = container.read(liveScreenControllerProvider);
      expect(state.currentSongTitle, 'Second');

      await controller.togglePlayback();
      container.dispose();
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('external stop resets UI state', () {
    test('incrementing external stop counter resets playing state', () async {
      final container = createContainer(
        viewContext: const MetronomeViewContext(),
      );

      final controller =
          container.read(liveScreenControllerProvider.notifier);
      await controller.togglePlayback();

      var state = container.read(liveScreenControllerProvider);
      expect(state.isPlaying, isTrue);

      // Simulate external stop.
      container.read(externalAudioStopCounterProvider.notifier).state += 1;

      state = container.read(liveScreenControllerProvider);
      expect(state.isPlaying, isFalse);
      expect(state.isStarting, isFalse);

      container.dispose();
      await Future<void>.delayed(Duration.zero);
    });
  });
}

class _AudioEngineClickOutput implements MetronomeClickOutput {
  const _AudioEngineClickOutput(this._engine);

  final SoLoudAudioEngine _engine;

  @override
  void playHighBeat() => _engine.playClick(AccentLevel.high);

  @override
  void playLowBeat() => _engine.playClick(AccentLevel.low);

  @override
  void playNormalBeat() => _engine.playClick(AccentLevel.normal);

  @override
  void playSubdivisionPulse() => _engine.playSubdivisionClick();
}

class _FakeSongRepository implements SongRepository {
  _FakeSongRepository({this.songs = const []});

  final List<Song> songs;

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) async {
    return const SongPlaybackBeatmapBuilder().build(await loadSong(songId));
  }

  @override
  Future<Song> loadSong(String songId) async {
    return songs.firstWhere(
      (s) => s.id == songId,
      orElse: () => throw StateError('Song not found: $songId'),
    );
  }

  @override
  Future<void> deleteSong(String songId) => throw UnimplementedError();

  @override
  Future<List<Song>> getAllSongs() => throw UnimplementedError();

  @override
  Future<Song?> getSongById(String songId) => throw UnimplementedError();

  @override
  Future<void> saveSong(Song song) => throw UnimplementedError();

  @override
  Future<void> regenerateBeatmap(String songId) async {}

  @override
  Stream<List<Song>> watchAllSongs() => throw UnimplementedError();

  @override
  Stream<Song?> watchSongById(String songId) => throw UnimplementedError();
}

class _PassthroughLinkedAudioPathRepairService
    implements LinkedAudioPathRepairService {
  const _PassthroughLinkedAudioPathRepairService();

  @override
  Future<LinkedAudioFile> repairIfNeeded(
    LinkedAudioFile linkedAudioFile,
  ) async {
    return linkedAudioFile;
  }
}

class _FixedLiveViewContextNotifier extends LiveViewContextNotifier {
  _FixedLiveViewContextNotifier(this._initial);

  final LiveViewContext _initial;

  @override
  LiveViewContext build() => _initial;
}
