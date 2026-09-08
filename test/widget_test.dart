import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/audio_limiter_settings.dart';
import 'package:tempodeck/core/audio/click_sound_set_assets.dart';
import 'package:tempodeck/core/audio/export_engine.dart';
import 'package:tempodeck/core/audio/i_audio_engine.dart';
import 'package:tempodeck/core/audio/stub_audio_engine.dart';
import 'package:tempodeck/core/audio/stub_export_engine.dart';
import 'package:tempodeck/core/audio/i_export_engine.dart';
import 'package:tempodeck/core/audio/linked_audio_export_augmenter.dart';
import 'package:tempodeck/core/audio/soloud_audio_engine.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/providers/service_providers.dart';
import 'package:tempodeck/core/repositories/setlist_repository.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/core/router/app_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── AppVariant provider ────────────────────────────────────────────────
  group('AppVariant provider', () {
    test('throws UnimplementedError when not overridden', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        () => container.read(appVariantProvider),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('returns overridden value for mobile', () {
      final container = ProviderContainer(
        overrides: [appVariantProvider.overrideWithValue(AppVariant.mobile)],
      );
      addTearDown(container.dispose);
      expect(container.read(appVariantProvider), AppVariant.mobile);
    });

    test('returns overridden value for desktop', () {
      final container = ProviderContainer(
        overrides: [appVariantProvider.overrideWithValue(AppVariant.desktop)],
      );
      addTearDown(container.dispose);
      expect(container.read(appVariantProvider), AppVariant.desktop);
    });
  });

  // ─── AppVariant helpers ─────────────────────────────────────────────────
  group('AppVariant helpers', () {
    test('isDesktop matches the desktop variant', () {
      expect(AppVariant.mobile.isDesktop, isFalse);
      expect(AppVariant.desktop.isDesktop, isTrue);
    });
  });

  // ─── StubAudioEngine ────────────────────────────────────────────────────
  group('StubAudioEngine', () {
    late StubAudioEngine sut;
    setUp(() => sut = StubAudioEngine());

    test('initialize completes', () async {
      await expectLater(sut.initialize(), completes);
    });

    test('dispose completes', () async {
      await expectLater(sut.dispose(), completes);
    });

    test('loadClickSoundSet completes for every value', () async {
      for (final set in ClickSoundSet.values) {
        await expectLater(sut.loadClickSoundSet(set), completes);
      }
    });

    test('selectClickSoundSet does not throw for every value', () {
      for (final set in ClickSoundSet.values) {
        expect(() => sut.selectClickSoundSet(set), returnsNormally);
      }
    });

    test('playClick does not throw for every AccentLevel', () {
      for (final level in AccentLevel.values) {
        expect(() => sut.playClick(level), returnsNormally);
      }
    });

    test('playCue completes', () async {
      const cue = AudioCue(type: AudioCueType.intervalSignal);
      await expectLater(sut.playCue(cue), completes);
    });

    test('setMasterVolume does not throw', () {
      expect(() => sut.setMasterVolume(0.5), returnsNormally);
    });

    test('setClickChannelVolume does not throw', () {
      expect(
        () => sut.setClickChannelVolume(ClickSoundVariant.normal, 0.5),
        returnsNormally,
      );
    });

    test('setLimiter does not throw', () {
      expect(
        () => sut.setLimiter(const AudioLimiterSettings()),
        returnsNormally,
      );
    });

    test('stop does not throw', () {
      expect(() => sut.stop(), returnsNormally);
    });
  });

  // ─── StubExportEngine ───────────────────────────────────────────────────
  group('StubExportEngine', () {
    late StubExportEngine sut;
    setUp(() => sut = StubExportEngine());

    test('estimateFileSizeBytes returns positive value', () {
      final bytes = sut.estimateFileSizeBytes(
        duration: const Duration(minutes: 3),
        bitrateBps: 192000,
      );
      expect(bytes, greaterThan(0));
    });

    test('exportToMp3 yields 1.0 (completed) for song source', () async {
      final stream = sut.exportToMp3(
        source: SongExportSource('song-uuid'),
        outputPath: '/tmp/test.mp3',
      );
      await expectLater(stream, emits(1.0));
    });

    test('exportToMp3 yields 1.0 (completed) for setlist source', () async {
      final stream = sut.exportToMp3(
        source: SetlistExportSource('setlist-uuid'),
        outputPath: '/tmp/test.mp3',
      );
      await expectLater(stream, emits(1.0));
    });
  });

  group('Service providers', () {
    test('audioEngineProvider exposes the real audio engine', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final engine = container.read(audioEngineProvider);

      expect(engine, isA<IAudioEngine>());
      expect(engine, isA<SoLoudAudioEngine>());
    });

    test('song and setlist export loaders forward repository providers', () {
      final songRepository = _FakeSongRepository();
      final setlistRepository = _FakeSetlistRepository();
      final container = ProviderContainer(
        overrides: [
          songRepositoryProvider.overrideWithValue(songRepository),
          setlistRepositoryProvider.overrideWithValue(setlistRepository),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(songExportSourceLoaderProvider), same(songRepository));
      expect(
        container.read(setlistExportSourceLoaderProvider),
        same(setlistRepository),
      );
    });

    test('exportEngineProvider composes the real export engine with overrides',
        () {
      final songRepository = _FakeSongRepository();
      final setlistRepository = _FakeSetlistRepository();
      final container = ProviderContainer(
        overrides: [
          appVariantProvider.overrideWithValue(AppVariant.desktop),
          songRepositoryProvider.overrideWithValue(songRepository),
          setlistRepositoryProvider.overrideWithValue(setlistRepository),
          linkedAudioClipLoaderProvider.overrideWithValue(
            _FakeLinkedAudioClipLoader(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final engine = container.read(exportEngineProvider);

      expect(engine, isA<IExportEngine>());
      expect(engine, isA<ExportEngine>());
    });
  });

  // ─── Router ─────────────────────────────────────────────────────────────
  group('buildRouter', () {
    test('creates GoRouter for mobile variant', () {
      final router = buildRouter(AppVariant.mobile);
      addTearDown(router.dispose);
      expect(router, isNotNull);
    });

    test('creates GoRouter for desktop variant', () {
      final router = buildRouter(AppVariant.desktop);
      addTearDown(router.dispose);
      expect(router, isNotNull);
    });

    test('mobile and desktop routers share the same route count', () {
      final mobile = buildRouter(AppVariant.mobile);
      final desktop = buildRouter(AppVariant.desktop);
      addTearDown(mobile.dispose);
      addTearDown(desktop.dispose);
      // Both variants expose the same number of top-level route entries.
      expect(
        mobile.configuration.routes.length,
        desktop.configuration.routes.length,
      );
    });
  });
}

class _FakeSongRepository implements SongRepository {
  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) async {
    throw UnimplementedError('Not needed for provider composition test.');
  }

  @override
  Future<Song> loadSong(String songId) async {
    throw UnimplementedError('Not needed for provider composition test.');
  }

  @override
  Future<void> deleteSong(String songId) async {}

  @override
  Future<List<Song>> getAllSongs() async => const [];

  @override
  Future<Song?> getSongById(String songId) async => null;

  @override
  Future<void> saveSong(Song song) async {}

  @override
  Future<void> regenerateBeatmap(String songId) async {}

  @override
  Stream<List<Song>> watchAllSongs() => const Stream<List<Song>>.empty();

  @override
  Stream<Song?> watchSongById(String songId) => const Stream<Song?>.empty();
}

class _FakeSetlistRepository implements SetlistRepository {
  @override
  Future<Setlist> loadSetlist(String setlistId) async {
    throw UnimplementedError('Not needed for provider composition test.');
  }

  @override
  Future<void> deleteSetlist(String setlistId) async {}

  @override
  Future<List<Setlist>> getAllSetlists() async => const [];

  @override
  Future<Setlist?> getSetlistById(String setlistId) async => null;

  @override
  Future<void> saveSetlist(Setlist setlist) async {}

  @override
  Stream<List<Setlist>> watchAllSetlists() =>
      const Stream<List<Setlist>>.empty();

  @override
  Stream<Setlist?> watchSetlistById(String setlistId) =>
      const Stream<Setlist?>.empty();
}

class _FakeLinkedAudioClipLoader implements LinkedAudioClipLoader {
  @override
  Future<ExportAudioClip> loadClip(LinkedAudioFile linkedAudioFile) async {
    return ExportAudioClip(
      samples: Float32List.fromList(const [0.0, 0.0]),
      sampleRate: ExportAudioFormat.defaultSampleRate,
      channelCount: ExportAudioFormat.defaultChannelCount,
    );
  }
}
