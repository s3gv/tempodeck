import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/stub_audio_engine.dart';
import 'package:tempodeck/core/domain/metronome_preset.dart';
import 'package:tempodeck/core/domain/setlist.dart';
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
import 'package:tempodeck/features/setlists/setlist_editor_screen.dart';
import 'package:tempodeck/platform/desktop/desktop_setlists_screen.dart';

void main() {
  setUpAll(() {
    TDAnimatedBackground.disableAnimations = true;
  });

  tearDownAll(() {
    TDAnimatedBackground.disableAnimations = false;
  });

  testWidgets('desktop setlists route shows list and placeholder side by side',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        audioEngineProvider.overrideWithValue(StubAudioEngine()),
        setlistRepositoryProvider.overrideWithValue(
          _FakeSetlistRepository(setlists: [_tourSet]),
        ),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository()),
        presetRepositoryProvider.overrideWithValue(_FakePresetRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_DesktopSetlistsHarness(container: container));
    await tester.pumpAndSettle();

    final router = container.read(_routerProvider);
    router.go('/setlists');
    await tester.pumpAndSettle();

    expect(find.byType(DesktopSetlistsScreen), findsOneWidget);
    expect(find.text('Tour Set'), findsOneWidget);
    expect(find.text('Select a setlist to edit'), findsOneWidget);
    expect(find.byType(SetlistEditorScreen), findsNothing);
  });

  testWidgets(
      'desktop setlist detail route keeps list visible and shows editor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        audioEngineProvider.overrideWithValue(StubAudioEngine()),
        setlistRepositoryProvider.overrideWithValue(
          _FakeSetlistRepository(setlists: [_tourSet]),
        ),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository()),
        presetRepositoryProvider.overrideWithValue(_FakePresetRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_DesktopSetlistsHarness(container: container));
    await tester.pumpAndSettle();

    final router = container.read(_routerProvider);
    router.go('/setlists/setlist-1');
    await tester.pumpAndSettle();

    expect(find.byType(DesktopSetlistsScreen), findsOneWidget);
    expect(find.byType(SetlistEditorScreen), findsOneWidget);
    expect(find.text('Tour Set'), findsWidgets);
    expect(find.text('Intro'), findsOneWidget);
  });
}

final _tourSet = Setlist(
  id: 'setlist-1',
  title: 'Tour Set',
  createdAt: DateTime(2024, 2, 1),
  items: const [
    SetlistItem(
      id: 'item-1',
      songId: 'song-1',
      songTitle: 'Intro',
    ),
    SetlistItem(
      id: 'item-2',
      songId: 'song-2',
      songTitle: 'Finale',
    ),
  ],
);

final _routerProvider = Provider((ref) {
  return buildRouter(ref.watch(appVariantProvider));
});

class _DesktopSetlistsHarness extends ConsumerWidget {
  const _DesktopSetlistsHarness({required this.container});

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

class _FakeSetlistRepository implements SetlistRepository {
  _FakeSetlistRepository({required List<Setlist> setlists}) : _setlists = setlists;

  final List<Setlist> _setlists;

  @override
  Future<void> deleteSetlist(String setlistId) async {}

  @override
  Future<List<Setlist>> getAllSetlists() async => _setlists;

  @override
  Future<Setlist?> getSetlistById(String setlistId) async =>
      _setlists.where((setlist) => setlist.id == setlistId).firstOrNull;

  @override
  Future<Setlist> loadSetlist(String setlistId) async {
    final setlist =
        _setlists.where((candidate) => candidate.id == setlistId).firstOrNull;
    if (setlist == null) {
      throw StateError('Setlist not found: $setlistId');
    }

    return setlist;
  }

  @override
  Future<void> saveSetlist(Setlist setlist) async {}

  @override
  Stream<List<Setlist>> watchAllSetlists() =>
      Stream<List<Setlist>>.value(_setlists);

  @override
  Stream<Setlist?> watchSetlistById(String setlistId) => Stream<Setlist?>.value(
        _setlists.where((setlist) => setlist.id == setlistId).firstOrNull,
      );
}

class _FakeSongRepository implements SongRepository {
  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteSong(String songId) async {}

  @override
  Future<List<Song>> getAllSongs() async => const [];

  @override
  Future<Song?> getSongById(String songId) async => null;

  @override
  Future<Song> loadSong(String songId) async {
    throw StateError('Song not found: $songId');
  }

  @override
  Future<void> saveSong(Song song) async {}

  @override
  Future<void> regenerateBeatmap(String songId) async {}

  @override
  Stream<List<Song>> watchAllSongs() => Stream<List<Song>>.value(const []);

  @override
  Stream<Song?> watchSongById(String songId) => Stream<Song?>.value(null);
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
      Stream<List<MetronomePreset>>.value(const []);

  @override
  Stream<MetronomePreset?> watchPresetById(String presetId) =>
      Stream<MetronomePreset?>.value(null);
}
