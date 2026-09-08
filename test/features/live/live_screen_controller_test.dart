import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tempodeck/core/audio/audio_limiter_settings.dart';
import 'package:tempodeck/core/audio/click_sound_set_assets.dart';
import 'package:tempodeck/core/audio/i_audio_engine.dart';
import 'package:tempodeck/core/audio/text_to_speech_client.dart';
import 'package:tempodeck/core/audio/metronome_click_engine.dart';
import 'package:tempodeck/core/audio/song_playback_beatmap.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/domain/subdivision.dart';
import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/providers/service_providers.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/files/linked_audio_path_repair_service.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/features/live/live_event.dart';
import 'package:tempodeck/features/live/live_metronome_transport.dart';
import 'package:tempodeck/features/live/live_screen_controller.dart';
import 'package:tempodeck/features/live/live_view_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('togglePlayback starts transport from metronome settings', () async {
    final transport = _FakeLiveMetronomeTransport();
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);

    await controller.togglePlayback();

    expect(transport.startCallCount, 1);
    expect(transport.lastConfig?.bpm, 120);
    expect(transport.lastConfig?.beatsPerBar, 4);
    expect(transport.lastConfig?.beatUnit, 4);
    expect(transport.lastConfig?.subdivision, Subdivision.one);
    expect(transport.lastConfig?.clickSoundSet, ClickSoundSet.tock);

    final state = container.read(liveScreenControllerProvider);
    expect(state.isPlaying, isTrue);
    expect(state.bpm, 120);
    expect(state.beatsPerBar, 4);
    expect(state.beatUnit, 4);
  });

  test('togglePlayback uses song BPM and time signature in song context',
      () async {
    final transport = _FakeLiveMetronomeTransport();
    final audioEngine = _FakeAudioEngine();
    final song = Song(
      id: 'song-1',
      title: 'Test Song',
      createdAt: DateTime(2024),
      startBpm: 140,
      beatsPerBar: 3,
      beatUnit: 8,
      countInBars: 0,
      endBar: 50,
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
        audioEngineProvider.overrideWithValue(audioEngine),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository(songs: [song])),
        linkedAudioPathRepairServiceProvider.overrideWithValue(
          const _PassthroughLinkedAudioPathRepairService(),
        ),
        liveViewContextProvider.overrideWith(
          () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);
    await controller.togglePlayback();

    expect(transport.lastConfig?.bpm, 140);
    expect(transport.lastConfig?.beatsPerBar, 3);
    expect(transport.lastConfig?.beatUnit, 8);

    final state = container.read(liveScreenControllerProvider);
    expect(state.bpm, 140);
    expect(state.beatsPerBar, 3);
    expect(state.beatUnit, 8);
  });

  test('song live playback starts linked audio from the configured offset',
      () async {
    final transport = _FakeLiveMetronomeTransport();
    final audioEngine = _FakeAudioEngine();
    final song = Song(
      id: 'song-1',
      title: 'Playback Song',
      createdAt: DateTime(2024),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 16,
      linkedAudio: const LinkedAudioFile(
        filePath: '/tmp/playback.mp3',
        displayName: 'playback.mp3',
        offsetMilliseconds: 2003,
        volumePercent: 80,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
        audioEngineProvider.overrideWithValue(audioEngine),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository(songs: [song])),
        linkedAudioPathRepairServiceProvider.overrideWithValue(
          const _PassthroughLinkedAudioPathRepairService(),
        ),
        liveViewContextProvider.overrideWith(
          () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);
    await controller.togglePlayback();

    expect(audioEngine.preloadedLinkedAudioPaths, ['/tmp/playback.mp3']);
    expect(audioEngine.playedLinkedAudioPaths, ['/tmp/playback.mp3']);
    expect(
      audioEngine.playedLinkedAudioOffsets,
      [const Duration(milliseconds: 2003)],
    );
    // Linked audio volumePercent (80%) × mixer songVolumeFactor (80% default).
    expect(audioEngine.playedLinkedAudioVolumes.single, closeTo(0.64, 0.001));
  });

  test('song live playback runs count-in before starting linked audio',
      () async {
    final transport = _FakeLiveMetronomeTransport();
    final audioEngine = _FakeAudioEngine();
    final song = Song(
      id: 'song-1',
      title: 'Count In Song',
      createdAt: DateTime(2024),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 16,
      linkedAudio: const LinkedAudioFile(
        filePath: '/tmp/count-in.mp3',
        displayName: 'count-in.mp3',
        offsetMilliseconds: 0,
        volumePercent: 100,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
        audioEngineProvider.overrideWithValue(audioEngine),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository(songs: [song])),
        linkedAudioPathRepairServiceProvider.overrideWithValue(
          const _PassthroughLinkedAudioPathRepairService(),
        ),
        liveViewContextProvider.overrideWith(
          () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);
    unawaited(controller.togglePlayback());
    await Future<void>.delayed(Duration.zero);

    expect(audioEngine.preloadedLinkedAudioPaths, ['/tmp/count-in.mp3']);
    expect(transport.startCallCount, 1);
    expect(audioEngine.playedLinkedAudioPaths, isEmpty);
    expect(
      container.read(liveScreenControllerProvider).transitionMessage,
      'Count-in: 2 bars',
    );

    transport.emitTick(
      _tick(
        barIndex: 1,
        beatIndex: 4,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(audioEngine.playedLinkedAudioPaths, isEmpty);
    expect(
      container.read(liveScreenControllerProvider).transitionMessage,
      'Count-in: 1 bar',
    );

    transport.emitTick(
      _tick(
        barIndex: 2,
        beatIndex: 4,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(transport.startCallCount, 1);
    transport.emitTick(
      _tick(
        barIndex: 3,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(audioEngine.playedLinkedAudioPaths, ['/tmp/count-in.mp3']);
  });

  test('song count-in keeps the first song bar meter for every count-in bar',
      () async {
    final transport = _FakeLiveMetronomeTransport();
    final song = Song(
      id: 'song-1',
      title: 'Count In Meter Song',
      createdAt: DateTime(2024),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 16,
      tempoChanges: const [
        SongTempoChange(
          id: 'tempo-1',
          barIndex: 2,
          bpm: 90,
          beatsPerBar: 3,
          beatUnit: 4,
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository(songs: [song])),
        liveViewContextProvider.overrideWith(
          () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);
    unawaited(controller.togglePlayback());
    await Future<void>.delayed(Duration.zero);

    expect(transport.lastConfig?.beatsPerBar, 4);

    expect(transport.beatmapSequence, isNotNull);
    expect(transport.beatmapSequence, hasLength(greaterThanOrEqualTo(2)));
    expect(transport.beatmapSequence![0].beatsPerBar, 4);
    expect(transport.beatmapSequence![0].beatUnit, 4);
    expect(transport.beatmapSequence![1].beatsPerBar, 4);
    expect(transport.beatmapSequence![1].beatUnit, 4);
  });

  test('song live playback repairs stale linked audio paths before playback',
      () async {
    final transport = _FakeLiveMetronomeTransport();
    final audioEngine = _FakeAudioEngine();
    const repairedPath = '/documents/repaired.mp3';
    final song = Song(
      id: 'song-1',
      title: 'Repaired Song',
      createdAt: DateTime(2024),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 16,
      linkedAudio: const LinkedAudioFile(
        filePath: '/stale/container/tmp/repaired.mp3',
        displayName: 'repaired.mp3',
        offsetMilliseconds: 2003,
        volumePercent: 100,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
        audioEngineProvider.overrideWithValue(audioEngine),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository(songs: [song])),
        linkedAudioPathRepairServiceProvider.overrideWithValue(
          const _FakeLinkedAudioPathRepairService(repairedPath: repairedPath),
        ),
        liveViewContextProvider.overrideWith(
          () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);
    await controller.togglePlayback();

    expect(audioEngine.preloadedLinkedAudioPaths, [repairedPath]);
    expect(audioEngine.playedLinkedAudioPaths, [repairedPath]);
    expect(
      audioEngine.playedLinkedAudioOffsets,
      [const Duration(milliseconds: 2003)],
    );
  });

  test('song live playback labels repeated loop bars with pass suffixes',
      () async {
    final transport = _FakeLiveMetronomeTransport();
    final audioEngine = _FakeAudioEngine();
    final song = Song(
      id: 'song-1',
      title: 'Loop Song',
      createdAt: DateTime(2024),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 16,
      loops: const [
        SongLoop(
          id: 'loop-1',
          startBar: 5,
          endBar: 8,
          repeatCount: 1,
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
        audioEngineProvider.overrideWithValue(audioEngine),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository(songs: [song])),
        linkedAudioPathRepairServiceProvider.overrideWithValue(
          const _PassthroughLinkedAudioPathRepairService(),
        ),
        liveViewContextProvider.overrideWith(
          () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);
    await controller.togglePlayback();

    transport.emitTick(
      _tick(
        barIndex: 4,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
      ),
    );
    expect(container.read(liveScreenControllerProvider).barLabel, '4');

    transport.emitTick(
      _tick(
        barIndex: 5,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
      ),
    );
    expect(container.read(liveScreenControllerProvider).barLabel, '5');

    transport.emitTick(
      _tick(
        barIndex: 8,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
      ),
    );
    expect(container.read(liveScreenControllerProvider).barLabel, '8');

    transport.emitTick(
      _tick(
        barIndex: 9,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
      ),
    );
    expect(container.read(liveScreenControllerProvider).barLabel, '5.2');

    transport.emitTick(
      _tick(
        barIndex: 10,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
      ),
    );
    expect(container.read(liveScreenControllerProvider).barLabel, '6.2');

    transport.emitTick(
      _tick(
        barIndex: 13,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
      ),
    );
    expect(container.read(liveScreenControllerProvider).barLabel, '9');
  });

  test('song live playback triggers song events on their configured bar', () async {
    final transport = _FakeLiveMetronomeTransport();
    final audioEngine = _FakeAudioEngine();
    final song = Song(
      id: 'song-1',
      title: 'Event Song',
      createdAt: DateTime(2024),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 16,
      songEvents: const [
        SongEvent(
          id: 'event-1',
          barIndex: 3,
          label: 'Cue',
          audioCue: AudioCue(type: AudioCueType.highPulse),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
        audioEngineProvider.overrideWithValue(audioEngine),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository(songs: [song])),
        liveViewContextProvider.overrideWith(
          () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);
    await controller.togglePlayback();

    transport.emitTick(
      _tick(
        barIndex: 2,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(audioEngine.playedCues, isEmpty);

    transport.emitTick(
      _tick(
        barIndex: 3,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(audioEngine.playedCues, hasLength(1));
    expect(audioEngine.playedCues.single.type, AudioCueType.highPulse);
  });

  test('song live playback exposes current bar-1 song events immediately', () async {
    final transport = _FakeLiveMetronomeTransport();
    final song = Song(
      id: 'song-1',
      title: 'Intro Song',
      createdAt: DateTime(2024),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 8,
      songEvents: const [
        SongEvent(
          id: 'event-1',
          barIndex: 1,
          label: 'Intro',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository(songs: [song])),
        liveViewContextProvider.overrideWith(
          () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);
    await controller.togglePlayback();

    final state = container.read(liveScreenControllerProvider);
    expect(state.currentEvents, hasLength(1));
    expect(state.currentEvents.single, isA<SongMarkerEvent>());
    expect(state.currentEvents.single.label, 'Intro');
    expect(state.currentEvents.single.displayBarLabel, '1');
  });

  test('song live playback keeps the current event visible until the next event',
      () async {
    final transport = _FakeLiveMetronomeTransport();
    final song = Song(
      id: 'song-1',
      title: 'Persistent Events Song',
      createdAt: DateTime(2024),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 8,
      songEvents: const [
        SongEvent(
          id: 'event-1',
          barIndex: 1,
          label: 'Intro',
        ),
        SongEvent(
          id: 'event-2',
          barIndex: 4,
          label: 'Verse',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository(songs: [song])),
        liveViewContextProvider.overrideWith(
          () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);
    await controller.togglePlayback();

    transport.emitTick(
      _tick(
        barIndex: 2,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
      ),
    );

    final state = container.read(liveScreenControllerProvider);
    expect(state.currentEvents, hasLength(1));
    expect(state.currentEvents.single.label, 'Intro');
    expect(state.currentEvents.single.displayBarLabel, '1');
    expect(state.nextEvents, hasLength(1));
    expect(state.nextEvents.single.label, 'Verse');
    expect(state.nextEvents.single.displayBarLabel, '4');
  });

  test('song live playback exposes first-song-bar events immediately after count-in',
      () async {
    final transport = _FakeLiveMetronomeTransport();
    final song = Song(
      id: 'song-1',
      title: 'Count In Intro Song',
      createdAt: DateTime(2024),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 1,
      endBar: 8,
      songEvents: const [
        SongEvent(
          id: 'event-1',
          barIndex: 1,
          label: 'Intro',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository(songs: [song])),
        liveViewContextProvider.overrideWith(
          () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);
    await controller.togglePlayback();

    transport.emitTick(
      _tick(
        barIndex: 1,
        beatIndex: 4,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      ),
    );
    transport.emitTick(
      _tick(
        barIndex: 2,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final state = container.read(liveScreenControllerProvider);
    expect(state.barLabel, '1');
    expect(state.currentEvents, hasLength(1));
    expect(state.currentEvents.single.label, 'Intro');
    expect(state.currentEvents.single.displayBarLabel, '1');
  });

  test('song live playback applies tempo and meter changes to live state', () async {
    final transport = _FakeLiveMetronomeTransport();
    final song = Song(
      id: 'song-1',
      title: 'Tempo Song',
      createdAt: DateTime(2024),
      startBpm: 100,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 16,
      tempoChanges: const [
        SongTempoChange(
          id: 'tempo-1',
          barIndex: 3,
          bpm: 200,
          beatsPerBar: 9,
          beatUnit: 8,
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository(songs: [song])),
        liveViewContextProvider.overrideWith(
          () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);
    await controller.togglePlayback();

    expect(transport.beatmapSequence, isNotNull);
    expect(transport.beatmapSequence![2].bpm, 200);
    expect(transport.beatmapSequence![2].beatsPerBar, 9);
    expect(transport.beatmapSequence![2].beatUnit, 8);

    transport.emitTick(
      _tick(
        barIndex: 3,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
        bpm: 200,
        beatsPerBar: 9,
        beatUnit: 8,
      ),
    );

    final state = container.read(liveScreenControllerProvider);
    expect(state.bpm, 200);
    expect(state.beatsPerBar, 9);
    expect(state.beatUnit, 8);
    expect(state.currentEvents, hasLength(1));
    expect(state.currentEvents.single.label, 'Tempo → 200 BPM (9/8)');
    expect(state.currentEvents.single.displayBarLabel, '3');

    transport.emitTick(
      _tick(
        barIndex: 4,
        beatIndex: 1,
        pulseIndex: 1,
        pulseCount: 1,
        accentLevel: AccentLevel.high,
        bpm: 200,
        beatsPerBar: 9,
        beatUnit: 8,
      ),
    );

    final persistedState = container.read(liveScreenControllerProvider);
    expect(persistedState.bpm, 200);
    expect(persistedState.beatsPerBar, 9);
    expect(persistedState.beatUnit, 8);
  });

  test('togglePlayback stops an active transport', () async {
    final transport = _FakeLiveMetronomeTransport();
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);

    await controller.togglePlayback();
    await controller.togglePlayback();

    expect(transport.stopCallCount, 1);
    expect(container.read(liveScreenControllerProvider).isPlaying, isFalse);
  });

  test('updates bar beat and pulse position from transport ticks', () async {
    final transport = _FakeLiveMetronomeTransport();
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);
    await controller.togglePlayback();

    transport.emitTick(
      _tick(
        barIndex: 3,
        beatIndex: 2,
        pulseIndex: 4,
        pulseCount: 4,
        accentLevel: AccentLevel.normal,
      ),
    );

    final state = container.read(liveScreenControllerProvider);
    expect(state.barIndex, 3);
    expect(state.beatIndex, 2);
    expect(state.pulseIndex, 4);
    expect(state.pulseCount, 4);
  });

  test('ignores a second toggle while start is still in progress', () async {
    final transport = _FakeLiveMetronomeTransport(delayStart: true);
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(liveScreenControllerProvider.notifier);

    final firstToggle = controller.togglePlayback();
    await controller.togglePlayback();
    transport.completePendingStart();
    await firstToggle;

    expect(transport.startCallCount, 1);
    expect(container.read(liveScreenControllerProvider).isPlaying, isTrue);
  });

  test(
    'togglePlayback starts transport with first song BPM in setlist context',
    () async {
      final transport = _FakeLiveMetronomeTransport();
      final audioEngine = _FakeAudioEngine();
      final songRepository = _FakeSongRepository(
        songs: [
          Song(
            id: 'song-1',
            title: 'Opener',
            createdAt: DateTime(2024),
            startBpm: 160,
            beatsPerBar: 3,
            beatUnit: 8,
            countInBars: 0,
            endBar: 40,
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
          liveMetronomeTransportProvider.overrideWithValue(transport),
          audioEngineProvider.overrideWithValue(audioEngine),
          songRepositoryProvider.overrideWithValue(songRepository),
          liveViewContextProvider.overrideWith(
            () => _FixedLiveViewContextNotifier(SetlistViewContext(
              setlist: Setlist(
                id: 'setlist-1',
                title: 'Test Setlist',
                createdAt: DateTime(2024),
                items: const [
                  SetlistItem(
                    id: 'item-1',
                    songId: 'song-1',
                    songTitle: 'Opener',
                  ),
                ],
              ),
            ),),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(liveScreenControllerProvider.notifier);
      await controller.togglePlayback();

      expect(transport.startCallCount, 1);
      expect(transport.lastConfig?.bpm, 160);
      expect(transport.lastConfig?.beatsPerBar, 3);
      expect(transport.lastConfig?.beatUnit, 8);

      final state = container.read(liveScreenControllerProvider);
      expect(state.isPlaying, isTrue);
      expect(state.currentSongTitle, 'Opener');
      expect(state.currentSongIndex, 1);
      expect(state.totalSongs, 1);
    },
  );

  test(
    'setlist live preload warms song audio and custom file cues for upcoming songs',
    () async {
      final transport = _FakeLiveMetronomeTransport();
      final audioEngine = _FakeAudioEngine();
      final songRepository = _FakeSongRepository(
        songs: [
          Song(
            id: 'song-1',
            title: 'Opener',
            createdAt: DateTime(2024),
            startBpm: 160,
            beatsPerBar: 3,
            beatUnit: 8,
            countInBars: 0,
            endBar: 40,
            linkedAudio: const LinkedAudioFile(
              filePath: '/tmp/song-1.mp3',
              displayName: 'song-1.mp3',
            ),
            songEvents: const [
              SongEvent(
                id: 'event-1',
                barIndex: 8,
                label: 'Cue',
                audioCueBarsBefore: 1,
                audioCue: AudioCue(
                  type: AudioCueType.customFile,
                  customFilePath: '/tmp/cue-1.wav',
                ),
              ),
            ],
          ),
          Song(
            id: 'song-2',
            title: 'Second',
            createdAt: DateTime(2024),
            startBpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            countInBars: 0,
            endBar: 24,
            linkedAudio: const LinkedAudioFile(
              filePath: '/tmp/song-2.mp3',
              displayName: 'song-2.mp3',
            ),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
          liveMetronomeTransportProvider.overrideWithValue(transport),
          audioEngineProvider.overrideWithValue(audioEngine),
          songRepositoryProvider.overrideWithValue(songRepository),
          linkedAudioPathRepairServiceProvider.overrideWithValue(
            const _PassthroughLinkedAudioPathRepairService(),
          ),
          liveViewContextProvider.overrideWith(
            () => _FixedLiveViewContextNotifier(SetlistViewContext(
              setlist: Setlist(
                id: 'setlist-1',
                title: 'Test Setlist',
                createdAt: DateTime(2024),
                items: const [
                  SetlistItem(
                    id: 'item-1',
                    songId: 'song-1',
                    songTitle: 'Opener',
                    transitionSteps: [
                      SetlistTransitionStep(
                        id: 'step-1',
                        type: SetlistTransitionStepType.audio,
                        value: 0,
                        audioCue: AudioCue(
                          type: AudioCueType.customFile,
                          customFilePath: '/tmp/transition.wav',
                        ),
                      ),
                    ],
                  ),
                  SetlistItem(
                    id: 'item-2',
                    songId: 'song-2',
                    songTitle: 'Second',
                  ),
                ],
              ),
            ),),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(liveScreenControllerProvider.notifier);
      await controller.togglePlayback();

      expect(
        audioEngine.preloadedLinkedAudioPaths,
        containsAll([
          '/tmp/transition.wav',
          '/tmp/song-1.mp3',
          '/tmp/cue-1.wav',
          '/tmp/song-2.mp3',
        ]),
      );
    },
  );

  test(
    'setlist count-in runs before the next song starts',
    () async {
      final transport = _FakeLiveMetronomeTransport();
      final songRepository = _FakeSongRepository(
        songs: [
          Song(
            id: 'song-1',
            title: 'Opener',
            createdAt: DateTime(2024),
            startBpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            countInBars: 0,
            endBar: 2,
          ),
          Song(
            id: 'song-2',
            title: 'Finale',
            createdAt: DateTime(2024),
            startBpm: 160,
            beatsPerBar: 3,
            beatUnit: 8,
            countInBars: 0,
            endBar: 16,
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
          liveMetronomeTransportProvider.overrideWithValue(transport),
          songRepositoryProvider.overrideWithValue(songRepository),
          liveViewContextProvider.overrideWith(
            () => _FixedLiveViewContextNotifier(SetlistViewContext(
              setlist: Setlist(
                id: 'setlist-1',
                title: 'Encore',
                createdAt: DateTime(2024),
                items: const [
                  SetlistItem(
                    id: 'item-1',
                    songId: 'song-1',
                    songTitle: 'Opener',
                  ),
                  SetlistItem(
                    id: 'item-2',
                    songId: 'song-2',
                    songTitle: 'Finale',
                    transitionSteps: [
                      SetlistTransitionStep(
                        id: 'step-1',
                        type: SetlistTransitionStepType.countInBars,
                        value: 2,
                      ),
                    ],
                  ),
                ],
              ),
            ),),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(liveScreenControllerProvider.notifier);
      await controller.togglePlayback();

      expect(transport.startCallCount, 1);
      expect(transport.lastConfig?.bpm, 120);
      expect(songRepository.loadSongBeatmapCallCount, 2);

      transport.emitTick(
        _tick(
          barIndex: 2,
          beatIndex: 4,
          pulseIndex: 1,
          pulseCount: 1,
          accentLevel: AccentLevel.high,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(transport.startCallCount, 2);
      expect(transport.lastConfig?.bpm, 160);
      expect(
        songRepository.loadSongBeatmapCallCount,
        2,
        reason: 'controller must execute the loaded plan without reloading beatmaps',
      );

      transport.emitTick(
        _tick(
          barIndex: 1,
          beatIndex: 3,
          pulseIndex: 1,
          pulseCount: 1,
          accentLevel: AccentLevel.high,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(transport.startCallCount, 2);

      transport.emitTick(
        _tick(
          barIndex: 2,
          beatIndex: 3,
          pulseIndex: 1,
          pulseCount: 1,
          accentLevel: AccentLevel.high,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(transport.startCallCount, 2);
    },
  );

  group('Beatmap contract: controller state follows time signature changes', () {
    test('transport receives correct beatmap sequence for song with time event',
        () async {
      final transport = _FakeLiveMetronomeTransport();
      final audioEngine = _FakeAudioEngine();
      final song = Song(
        id: 'song-1',
        title: 'Time Event Song',
        createdAt: DateTime(2024),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 5,
        tempoChanges: const [
          SongTempoChange(
            id: 't1',
            barIndex: 3,
            bpm: 200,
            beatsPerBar: 9,
            beatUnit: 8,
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
          liveMetronomeTransportProvider.overrideWithValue(transport),
          audioEngineProvider.overrideWithValue(audioEngine),
          songRepositoryProvider
              .overrideWithValue(_FakeSongRepository(songs: [song])),
          linkedAudioPathRepairServiceProvider.overrideWithValue(
            const _PassthroughLinkedAudioPathRepairService(),
          ),
          liveViewContextProvider.overrideWith(
            () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(liveScreenControllerProvider.notifier);
      await controller.togglePlayback();

      // Transport must receive the beatmap sequence with correct time signatures
      final sequence = transport.beatmapSequence!;
      expect(sequence, hasLength(5));

      // Bars 1-2: 4/4 @ 100 BPM
      expect(sequence[0].beatsPerBar, 4);
      expect(sequence[0].beatUnit, 4);
      expect(sequence[0].bpm, 100);
      expect(sequence[1].beatsPerBar, 4);
      expect(sequence[1].bpm, 100);

      // Bars 3-5: 9/8 @ 200 BPM
      for (var i = 2; i < 5; i++) {
        expect(
          sequence[i].beatsPerBar,
          9,
          reason: 'sequence[$i] must carry 9/8',
        );
        expect(sequence[i].beatUnit, 8);
        expect(sequence[i].bpm, 200);
      }
    });

    test(
        'controller state reflects 9/8 after tick in bar after time event, '
        'NOT 4/4 revert', () async {
      final transport = _FakeLiveMetronomeTransport();
      final audioEngine = _FakeAudioEngine();
      final song = Song(
        id: 'song-1',
        title: 'Time Event Song',
        createdAt: DateTime(2024),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 5,
        tempoChanges: const [
          SongTempoChange(
            id: 't1',
            barIndex: 3,
            bpm: 200,
            beatsPerBar: 9,
            beatUnit: 8,
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
          liveMetronomeTransportProvider.overrideWithValue(transport),
          audioEngineProvider.overrideWithValue(audioEngine),
          songRepositoryProvider
              .overrideWithValue(_FakeSongRepository(songs: [song])),
          linkedAudioPathRepairServiceProvider.overrideWithValue(
            const _PassthroughLinkedAudioPathRepairService(),
          ),
          liveViewContextProvider.overrideWith(
            () => _FixedLiveViewContextNotifier(SongViewContext(song: song)),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(liveScreenControllerProvider.notifier);
      await controller.togglePlayback();

      // Simulate tick at bar 1 (4/4 @ 100)
      transport.emitTick(
        _tick(
          barIndex: 1,
          beatIndex: 1,
          pulseIndex: 1,
          pulseCount: 1,
          accentLevel: AccentLevel.high,
          bpm: 100,
          beatsPerBar: 4,
          beatUnit: 4,
        ),
      );
      var state = container.read(liveScreenControllerProvider);
      expect(state.beatsPerBar, 4);
      expect(state.beatUnit, 4);
      expect(state.bpm, 100);

      // Simulate tick at bar 3 (after time event: 9/8 @ 200)
      transport.emitTick(
        _tick(
          barIndex: 3,
          beatIndex: 1,
          pulseIndex: 1,
          pulseCount: 1,
          accentLevel: AccentLevel.high,
          bpm: 200,
          beatsPerBar: 9,
          beatUnit: 8,
        ),
      );
      state = container.read(liveScreenControllerProvider);
      expect(
        state.beatsPerBar,
        9,
        reason: 'state must show 9/8, NOT revert to 4/4',
      );
      expect(state.beatUnit, 8);
      expect(state.bpm, 200);

      // Simulate tick at bar 5 (still 9/8 @ 200 - must carry forward)
      transport.emitTick(
        _tick(
          barIndex: 5,
          beatIndex: 1,
          pulseIndex: 1,
          pulseCount: 1,
          accentLevel: AccentLevel.high,
          bpm: 200,
          beatsPerBar: 9,
          beatUnit: 8,
        ),
      );
      state = container.read(liveScreenControllerProvider);
      expect(
        state.beatsPerBar,
        9,
        reason: 'bar 5 must still carry 9/8 forward',
      );
      expect(state.beatUnit, 8);
      expect(state.bpm, 200);
    });
  });

  test(
    'manual transition as first step waits for play and advances exactly once',
    () async {
      final transport = _FakeLiveMetronomeTransport();
      final audioEngine = _FakeAudioEngine();
      final song = Song(
        id: 'song-1',
        title: 'Opener',
        createdAt: DateTime(2024),
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 8,
      );
      final songRepository = _FakeSongRepository(songs: [song]);
      final container = ProviderContainer(
        overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
          liveMetronomeTransportProvider.overrideWithValue(transport),
          audioEngineProvider.overrideWithValue(audioEngine),
          songRepositoryProvider.overrideWithValue(songRepository),
          linkedAudioPathRepairServiceProvider.overrideWithValue(
            const _PassthroughLinkedAudioPathRepairService(),
          ),
          liveViewContextProvider.overrideWith(
            () => _FixedLiveViewContextNotifier(SetlistViewContext(
              setlist: Setlist(
                id: 'setlist-1',
                title: 'Test Setlist',
                createdAt: DateTime(2024),
                items: const [
                  SetlistItem(
                    id: 'item-1',
                    songId: 'song-1',
                    songTitle: 'Opener',
                    transitionSteps: [
                      SetlistTransitionStep(
                        id: 'step-1',
                        type: SetlistTransitionStepType.manual,
                        value: 0,
                      ),
                    ],
                  ),
                ],
              ),
            ),),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(liveScreenControllerProvider.notifier);

      // Start setlist playback — first segment is manual.
      await controller.togglePlayback();

      var state = container.read(liveScreenControllerProvider);
      expect(state.isWaitingForManualAdvance, isTrue);
      expect(state.isPlaying, isFalse);
      expect(state.transitionMessage, 'Press Play to continue');
      expect(
        transport.startCallCount,
        0,
        reason: 'no playback started yet',
      );

      // User taps play to advance past the manual step.
      await controller.togglePlayback();
      await Future<void>.delayed(Duration.zero);

      state = container.read(liveScreenControllerProvider);
      expect(state.isWaitingForManualAdvance, isFalse);
      expect(state.isPlaying, isTrue);
      expect(
        transport.startCallCount,
        1,
        reason: 'song should have started exactly once',
      );
    },
  );

  test(
    'setlist mode shows first song BPM before playback starts',
    () {
      fakeAsync((async) {
        final transport = _FakeLiveMetronomeTransport();
        final audioEngine = _FakeAudioEngine();
        final songRepository = _FakeSongRepository(
          songs: [
            Song(
              id: 'song-1',
              title: 'Opener',
              createdAt: DateTime(2024),
              startBpm: 175,
              beatsPerBar: 7,
              beatUnit: 8,
              countInBars: 0,
              endBar: 20,
            ),
          ],
        );
        final container = ProviderContainer(
          overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
            liveMetronomeTransportProvider.overrideWithValue(transport),
            audioEngineProvider.overrideWithValue(audioEngine),
            songRepositoryProvider.overrideWithValue(songRepository),
            liveViewContextProvider.overrideWith(
              () => _FixedLiveViewContextNotifier(SetlistViewContext(
                setlist: Setlist(
                  id: 'setlist-1',
                  title: 'Test Setlist',
                  createdAt: DateTime(2024),
                  items: const [
                    SetlistItem(
                      id: 'item-1',
                      songId: 'song-1',
                      songTitle: 'Opener',
                    ),
                  ],
                ),
              ),),
            ),
          ],
        );

        // Trigger the provider read which fires _loadSetlistInitialState.
        container.read(liveScreenControllerProvider);
        async.flushMicrotasks();

        final state = container.read(liveScreenControllerProvider);
        expect(state.isPlaying, isFalse);
        expect(state.bpm, 175);
        expect(state.beatsPerBar, 7);
        expect(state.beatUnit, 8);

        container.dispose();
      });
    },
  );

  test(
    'setlist pause countdown formats as mm:ss',
    () {
      fakeAsync((async) {
        final transport = _FakeLiveMetronomeTransport();
        final audioEngine = _FakeAudioEngine();
        final songRepository = _FakeSongRepository(
          songs: [
            Song(
              id: 'song-1',
              title: 'Opener',
              createdAt: DateTime(2024),
              startBpm: 120,
              beatsPerBar: 4,
              beatUnit: 4,
              countInBars: 0,
              endBar: 20,
            ),
          ],
        );
        final container = ProviderContainer(
          overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
            liveMetronomeTransportProvider.overrideWithValue(transport),
            audioEngineProvider.overrideWithValue(audioEngine),
            songRepositoryProvider.overrideWithValue(songRepository),
            liveViewContextProvider.overrideWith(
              () => _FixedLiveViewContextNotifier(SetlistViewContext(
                setlist: Setlist(
                  id: 'setlist-1',
                  title: 'Test Setlist',
                  createdAt: DateTime(2024),
                  items: const [
                    SetlistItem(
                      id: 'item-1',
                      songId: 'song-1',
                      songTitle: 'Opener',
                      transitionSteps: [
                        SetlistTransitionStep(
                          id: 'step-1',
                          type: SetlistTransitionStepType.pauseTimer,
                          value: 75,
                        ),
                      ],
                    ),
                  ],
                ),
              ),),
            ),
          ],
        );

        final controller =
            container.read(liveScreenControllerProvider.notifier);
        unawaited(controller.togglePlayback());
        async.flushMicrotasks();

        var state = container.read(liveScreenControllerProvider);
        expect(state.isTransitioning, isTrue);
        expect(state.transitionMessage, 'Pause: 01:15');

        // After 10 seconds, the countdown should update.
        async.elapse(const Duration(seconds: 10));
        state = container.read(liveScreenControllerProvider);
        expect(state.transitionMessage, 'Pause: 01:05');

        container.dispose();
      });
    },
  );

  test(
    'setlist resumes from current song transition instead of beginning',
    () async {
      final transport = _FakeLiveMetronomeTransport();
      final audioEngine = _FakeAudioEngine();
      final song1 = Song(
        id: 'song-1',
        title: 'Song 1',
        createdAt: DateTime(2024),
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 4,
      );
      final song2 = Song(
        id: 'song-2',
        title: 'Song 2',
        createdAt: DateTime(2024),
        startBpm: 140,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 4,
      );
      final songRepository = _FakeSongRepository(songs: [song1, song2]);
      final container = ProviderContainer(
        overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
          liveMetronomeTransportProvider.overrideWithValue(transport),
          audioEngineProvider.overrideWithValue(audioEngine),
          songRepositoryProvider.overrideWithValue(songRepository),
          linkedAudioPathRepairServiceProvider.overrideWithValue(
            const _PassthroughLinkedAudioPathRepairService(),
          ),
          liveViewContextProvider.overrideWith(
            () => _FixedLiveViewContextNotifier(SetlistViewContext(
              setlist: Setlist(
                id: 'setlist-1',
                title: 'Test Setlist',
                createdAt: DateTime(2024),
                items: const [
                  SetlistItem(
                    id: 'item-1',
                    songId: 'song-1',
                    songTitle: 'Song 1',
                    transitionSteps: [
                      SetlistTransitionStep(
                        id: 'step-1',
                        type: SetlistTransitionStepType.manual,
                        value: 0,
                      ),
                    ],
                  ),
                  SetlistItem(
                    id: 'item-2',
                    songId: 'song-2',
                    songTitle: 'Song 2',
                    transitionSteps: [
                      SetlistTransitionStep(
                        id: 'step-2',
                        type: SetlistTransitionStepType.manual,
                        value: 0,
                      ),
                    ],
                  ),
                ],
              ),
            ),),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(liveScreenControllerProvider.notifier);

      // Start setlist — first segment is manual for song 1.
      await controller.togglePlayback();
      var state = container.read(liveScreenControllerProvider);
      expect(state.isWaitingForManualAdvance, isTrue);
      expect(state.currentSongTitle, 'Song 1');

      // Advance past the manual step to start song 1.
      await controller.togglePlayback();
      await Future<void>.delayed(Duration.zero);
      state = container.read(liveScreenControllerProvider);
      expect(state.isPlaying, isTrue);
      expect(state.currentSongTitle, 'Song 1');

      // Simulate song 1 ending by ticking past the end bar.
      for (var bar = 1; bar <= 5; bar++) {
        for (var beat = 1; beat <= 4; beat++) {
          transport.emitTick(_tick(
            barIndex: bar,
            beatIndex: beat,
            pulseIndex: 1,
            pulseCount: 1,
            accentLevel: beat == 1
                ? AccentLevel.high
                : AccentLevel.normal,
          ),);
        }
      }
      await Future<void>.delayed(Duration.zero);

      // Now we should be at the manual transition for song 2.
      state = container.read(liveScreenControllerProvider);
      expect(state.currentSongTitle, 'Song 2');

      // Stop playback mid-setlist.
      await controller.togglePlayback();
      state = container.read(liveScreenControllerProvider);
      expect(state.isPlaying, isFalse);

      // Resume — should start from song 2's transition, not song 1.
      await controller.togglePlayback();
      state = container.read(liveScreenControllerProvider);
      expect(state.currentSongTitle, 'Song 2');
    },
  );

  test(
    'setlist jumpToNextSong and jumpToPreviousSong navigate while stopped',
    () async {
      final transport = _FakeLiveMetronomeTransport();
      final audioEngine = _FakeAudioEngine();
      final song1 = Song(
        id: 'song-1',
        title: 'First',
        createdAt: DateTime(2024),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 4,
      );
      final song2 = Song(
        id: 'song-2',
        title: 'Second',
        createdAt: DateTime(2024),
        startBpm: 200,
        beatsPerBar: 6,
        beatUnit: 8,
        countInBars: 0,
        endBar: 4,
      );
      final songRepository = _FakeSongRepository(songs: [song1, song2]);
      final container = ProviderContainer(
        overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
          liveMetronomeTransportProvider.overrideWithValue(transport),
          audioEngineProvider.overrideWithValue(audioEngine),
          songRepositoryProvider.overrideWithValue(songRepository),
          linkedAudioPathRepairServiceProvider.overrideWithValue(
            const _PassthroughLinkedAudioPathRepairService(),
          ),
          liveViewContextProvider.overrideWith(
            () => _FixedLiveViewContextNotifier(SetlistViewContext(
              setlist: Setlist(
                id: 'setlist-1',
                title: 'Test Setlist',
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
            ),),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(liveScreenControllerProvider.notifier);

      // Start and immediately stop to populate the playback plan.
      await controller.togglePlayback();
      await controller.togglePlayback();

      // Jump to next song.
      await controller.jumpToNextSetlistSong();
      var state = container.read(liveScreenControllerProvider);
      expect(state.currentSongTitle, 'Second');
      expect(state.bpm, 200);
      expect(state.beatsPerBar, 6);
      expect(state.beatUnit, 8);

      // Jump back to previous song.
      await controller.jumpToPreviousSetlistSong();
      state = container.read(liveScreenControllerProvider);
      expect(state.currentSongTitle, 'First');
      expect(state.bpm, 100);
    },
  );

  test(
    'setlist transition toggle skips non-song segments when disabled',
    () async {
      final transport = _FakeLiveMetronomeTransport();
      final audioEngine = _FakeAudioEngine();
      final songRepository = _FakeSongRepository(
        songs: [
          Song(
            id: 'song-1',
            title: 'Opener',
            createdAt: DateTime(2024),
            startBpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            countInBars: 0,
            endBar: 20,
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
          liveMetronomeTransportProvider.overrideWithValue(transport),
          audioEngineProvider.overrideWithValue(audioEngine),
          songRepositoryProvider.overrideWithValue(songRepository),
          linkedAudioPathRepairServiceProvider.overrideWithValue(
            const _PassthroughLinkedAudioPathRepairService(),
          ),
          liveViewContextProvider.overrideWith(
            () => _FixedLiveViewContextNotifier(SetlistViewContext(
              setlist: Setlist(
                id: 'setlist-1',
                title: 'Test Setlist',
                createdAt: DateTime(2024),
                items: const [
                  SetlistItem(
                    id: 'item-1',
                    songId: 'song-1',
                    songTitle: 'Opener',
                    transitionSteps: [
                      SetlistTransitionStep(
                        id: 'step-1',
                        type: SetlistTransitionStepType.manual,
                        value: 0,
                      ),
                    ],
                  ),
                ],
              ),
            ),),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(liveScreenControllerProvider.notifier);

      // Disable transitions.
      controller.setTransitionEnabled(false);

      // Start playback — should skip the manual transition and start the song.
      await controller.togglePlayback();

      final state = container.read(liveScreenControllerProvider);
      expect(state.isPlaying, isTrue);
      expect(state.isWaitingForManualAdvance, isFalse);
      expect(state.currentSongTitle, 'Opener');
      expect(transport.startCallCount, 1);
    },
  );
}

MetronomeBeatTick _tick({
  required int barIndex,
  required int beatIndex,
  required int pulseIndex,
  required int pulseCount,
  required AccentLevel accentLevel,
  int bpm = 120,
  int beatsPerBar = 4,
  int beatUnit = 4,
}) {
  return MetronomeBeatTick(
    barIndex: barIndex,
    beatIndex: beatIndex,
    pulseIndex: pulseIndex,
    pulseCount: pulseCount,
    accentLevel: accentLevel,
    bpm: bpm,
    beatsPerBar: beatsPerBar,
    beatUnit: beatUnit,
  );
}

class _FakeLiveMetronomeTransport implements LiveMetronomeTransport {
  _FakeLiveMetronomeTransport({this.delayStart = false});

  int startCallCount = 0;
  int stopCallCount = 0;
  LiveMetronomeTransportConfig? lastConfig;
  void Function(MetronomeBeatTick tick)? _onTick;
  List<MetronomeClickEngineConfig>? beatmapSequence;
  final bool delayStart;
  Completer<void>? _pendingStart;
  bool _isRunning = false;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> start(
    LiveMetronomeTransportConfig config, {
    required void Function(MetronomeBeatTick tick) onTick,
    List<MetronomeClickEngineConfig>? beatmapSequence,
  }) async {
    startCallCount++;
    lastConfig = config;
    _onTick = onTick;
    this.beatmapSequence = beatmapSequence;
    if (delayStart) {
      _pendingStart = Completer<void>();
      await _pendingStart!.future;
    }
    _isRunning = true;
  }

  @override
  void stop() {
    stopCallCount++;
    _isRunning = false;
  }

  @override
  Future<void> stopAllAudio() async {
    stop();
  }

  void emitTick(MetronomeBeatTick tick) {
    _onTick?.call(tick);
  }

  void completePendingStart() {
    _pendingStart?.complete();
  }
}

class _FakeSongRepository implements SongRepository {
  _FakeSongRepository({this.songs = const []});

  final List<Song> songs;
  int loadSongBeatmapCallCount = 0;

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) async {
    loadSongBeatmapCallCount += 1;
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

class _FakeAudioEngine implements IAudioEngine {
  final List<String> preloadedLinkedAudioPaths = [];
  final List<String> preparedLinkedAudioPaths = [];
  final List<String> playedLinkedAudioPaths = [];
  final List<Duration> playedLinkedAudioOffsets = [];
  final List<double> playedLinkedAudioVolumes = [];
  final List<AudioCue> playedCues = [];

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
  Future<void> playCue(AudioCue cue) async {
    playedCues.add(cue);
  }

  @override
  Future<void> preloadLinkedAudio(String filePath) async {
    preloadedLinkedAudioPaths.add(filePath);
  }

  @override
  Future<PreparedLinkedAudioHandle> prepareLinkedAudioPlayback(
    String filePath, {
    required Duration offset,
    required double volume,
  }) async {
    preparedLinkedAudioPaths.add(filePath);
    playedLinkedAudioOffsets.add(offset);
    playedLinkedAudioVolumes.add(volume);
    return PreparedLinkedAudioHandle(filePath);
  }

  @override
  Future<void> playPreparedLinkedAudio(PreparedLinkedAudioHandle handle) async {
    playedLinkedAudioPaths.add(handle.id);
  }

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
  }) async {
    playedLinkedAudioPaths.add(filePath);
    playedLinkedAudioOffsets.add(offset);
    playedLinkedAudioVolumes.add(volume);
  }

  @override
  void selectClickSoundSet(ClickSoundSet set) {}

  @override
  void setClickChannelVolume(ClickSoundVariant variant, double volume) {}

  @override
  void setLimiter(AudioLimiterSettings settings) {}

  @override
  void setMasterVolume(double volume) {}

  @override
  Future<void> speakCue(String text, {String? voiceIdentifier}) async {}

  @override
  Future<void> stop() async {}
}

class _FakeLinkedAudioPathRepairService implements LinkedAudioPathRepairService {
  const _FakeLinkedAudioPathRepairService({required this.repairedPath});

  final String repairedPath;

  @override
  Future<LinkedAudioFile> repairIfNeeded(LinkedAudioFile linkedAudioFile) async {
    return LinkedAudioFile(
      filePath: repairedPath,
      displayName: linkedAudioFile.displayName,
      offsetMilliseconds: linkedAudioFile.offsetMilliseconds,
      volumePercent: linkedAudioFile.volumePercent,
      playInLiveMode: linkedAudioFile.playInLiveMode,
    );
  }
}

class _PassthroughLinkedAudioPathRepairService
    implements LinkedAudioPathRepairService {
  const _PassthroughLinkedAudioPathRepairService();

  @override
  Future<LinkedAudioFile> repairIfNeeded(LinkedAudioFile linkedAudioFile) async {
    return linkedAudioFile;
  }
}

class _FixedLiveViewContextNotifier extends LiveViewContextNotifier {
  _FixedLiveViewContextNotifier(this._initial);

  final LiveViewContext _initial;

  @override
  LiveViewContext build() => _initial;
}
