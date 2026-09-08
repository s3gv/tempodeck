import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/stub_audio_engine.dart';
import 'package:tempodeck/core/domain/metronome_preset.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/providers/service_providers.dart';
import 'package:tempodeck/core/repositories/preset_repository.dart';
import 'package:tempodeck/core/repositories/setlist_repository.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/core/router/app_router.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_animated_background.dart';
import 'package:tempodeck/platform/desktop/desktop_songs_screen.dart';
import 'package:tempodeck/features/songs/song_editor_screen.dart';
import 'package:tempodeck/core/domain/setlist.dart';

void main() {
  setUpAll(() {
    TDAnimatedBackground.disableAnimations = true;
  });

  tearDownAll(() {
    TDAnimatedBackground.disableAnimations = false;
  });

  testWidgets('desktop songs route shows list and placeholder side by side',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        audioEngineProvider.overrideWithValue(StubAudioEngine()),
        songRepositoryProvider.overrideWithValue(
          _FakeSongRepository(
            songs: [
              Song(
                id: 'song-1',
                title: 'Rock Ballad',
                createdAt: DateTime(2024, 1, 1),
                startBpm: 120,
                beatsPerBar: 4,
                beatUnit: 4,
                countInBars: 1,
                endBar: 32,
              ),
            ],
          ),
        ),
        setlistRepositoryProvider.overrideWithValue(_FakeSetlistRepository()),
        presetRepositoryProvider.overrideWithValue(_FakePresetRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_DesktopSongsHarness(container: container));
    await tester.pumpAndSettle();

    final router = container.read(_routerProvider);
    router.go('/songs');
    await tester.pumpAndSettle();

    expect(find.byType(DesktopSongsScreen), findsOneWidget);
    expect(find.text('New Song'), findsOneWidget);
    expect(find.text('Rock Ballad'), findsOneWidget);
    expect(find.text('Select a song to edit'), findsOneWidget);
    expect(find.byType(SongEditorScreen), findsNothing);
  });

  testWidgets('desktop songs detail route keeps list visible and shows editor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final song = Song(
      id: 'song-1',
      title: 'Rock Ballad',
      createdAt: DateTime(2024, 1, 1),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 1,
      endBar: 32,
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        audioEngineProvider.overrideWithValue(StubAudioEngine()),
        songRepositoryProvider.overrideWithValue(
          _FakeSongRepository(songs: [song]),
        ),
        setlistRepositoryProvider.overrideWithValue(_FakeSetlistRepository()),
        presetRepositoryProvider.overrideWithValue(_FakePresetRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_DesktopSongsHarness(container: container));
    await tester.pumpAndSettle();

    final router = container.read(_routerProvider);
    router.go('/songs/song-1');
    await tester.pumpAndSettle();

    expect(find.byType(DesktopSongsScreen), findsOneWidget);
    expect(find.byType(SongEditorScreen), findsOneWidget);
    expect(find.text('Rock Ballad'), findsWidgets);
    expect(find.byKey(const Key('songEditorTitleField')), findsOneWidget);
  });
}

final _routerProvider = Provider((ref) {
  return buildRouter(ref.watch(appVariantProvider));
});

class _DesktopSongsHarness extends ConsumerWidget {
  const _DesktopSongsHarness({required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          final router = ref.watch(_routerProvider);
          return MaterialApp.router(
            theme: AppTheme.dark,
            routerConfig: router,
          );
        },
      ),
    );
  }
}

class _FakeSongRepository implements SongRepository {
  _FakeSongRepository({required List<Song> songs}) : _songs = songs;

  final List<Song> _songs;

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteSong(String songId) async {}

  @override
  Future<List<Song>> getAllSongs() async => _songs;

  @override
  Future<Song?> getSongById(String songId) async =>
      _songs.where((song) => song.id == songId).firstOrNull;

  @override
  Future<Song> loadSong(String songId) async {
    final song = _songs.where((candidate) => candidate.id == songId).firstOrNull;
    if (song == null) {
      throw StateError('Song not found: $songId');
    }

    return song;
  }

  @override
  Future<void> saveSong(Song song) async {}

  @override
  Future<void> regenerateBeatmap(String songId) async {}

  @override
  Stream<List<Song>> watchAllSongs() => Stream<List<Song>>.value(_songs);

  @override
  Stream<Song?> watchSongById(String songId) =>
      Stream<Song?>.value(_songs.where((song) => song.id == songId).firstOrNull);
}

class _FakeSetlistRepository implements SetlistRepository {
  @override
  Future<void> deleteSetlist(String setlistId) async {}

  @override
  Future<List<Setlist>> getAllSetlists() async => const [];

  @override
  Future<Setlist?> getSetlistById(String setlistId) async => null;

  @override
  Future<Setlist> loadSetlist(String setlistId) async {
    throw StateError('Setlist not found: $setlistId');
  }

  @override
  Future<void> saveSetlist(Setlist setlist) async {}

  @override
  Stream<List<Setlist>> watchAllSetlists() => Stream<List<Setlist>>.value([]);

  @override
  Stream<Setlist?> watchSetlistById(String setlistId) =>
      Stream<Setlist?>.value(null);
}

class _FakePresetRepository implements PresetRepository {
  @override
  Future<void> deletePreset(String presetId) async {}

  @override
  Future<List<MetronomePreset>> getAllPresets() async => const [];

  @override
  Future<MetronomePreset?> getPresetById(String presetId) async => null;

  @override
  Future<void> savePreset(MetronomePreset preset) async {}

  @override
  Stream<List<MetronomePreset>> watchAllPresets() =>
      Stream<List<MetronomePreset>>.value([]);

  @override
  Stream<MetronomePreset?> watchPresetById(String presetId) =>
      Stream<MetronomePreset?>.value(null);
}
