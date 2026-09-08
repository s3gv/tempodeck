import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/stub_audio_engine.dart';
import 'package:tempodeck/core/domain/metronome_preset.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/providers/service_providers.dart';
import 'package:tempodeck/core/repositories/preset_repository.dart';
import 'package:tempodeck/core/repositories/setlist_repository.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/core/router/app_router.dart';
import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_animated_background.dart';
import 'package:tempodeck/features/live/live_screen.dart';
import 'package:tempodeck/features/setlists/setlist_editor_screen.dart';

void main() {
  setUpAll(() {
    TDAnimatedBackground.disableAnimations = true;
  });

  tearDownAll(() {
    TDAnimatedBackground.disableAnimations = false;
  });

  testWidgets(
      'desktop shell renders a navigation rail and navigates between sections',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        audioEngineProvider.overrideWithValue(StubAudioEngine()),
        presetRepositoryProvider.overrideWithValue(_FakePresetRepository()),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository()),
        setlistRepositoryProvider.overrideWithValue(_FakeSetlistRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_DesktopAppHarness(container: container));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('TempoDeck'), findsWidgets);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Metronome'), findsWidgets);

    await tester.tap(find.text('Songs').last);
    await tester.pumpAndSettle();
    expect(_selectedIndex(tester), 1);
    expect(find.text('Songs'), findsWidgets);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(_selectedIndex(tester), 3);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets(
      'desktop shell keeps the setlists branch selected for detail routes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        audioEngineProvider.overrideWithValue(StubAudioEngine()),
        presetRepositoryProvider.overrideWithValue(_FakePresetRepository()),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository()),
        setlistRepositoryProvider.overrideWithValue(
          _FakeSetlistRepository(
            setlist: Setlist(
              id: 'setlist-1',
              title: 'Tour Set',
              createdAt: DateTime(2024, 1, 1),
              items: const [
                SetlistItem(
                  id: 'item-1',
                  songId: 'song-1',
                  songTitle: 'Intro',
                ),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_DesktopAppHarness(container: container));
    await tester.pumpAndSettle();

    final router = container.read(_routerProvider);
    router.go('/setlists/setlist-1');
    await tester.pumpAndSettle();

    expect(_selectedIndex(tester), 2);
    expect(find.byType(SetlistEditorScreen), findsOneWidget);
    expect(find.text('Tour Set'), findsWidgets);
  });

  testWidgets('desktop shell hides navigation rail on live route',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        audioEngineProvider.overrideWithValue(StubAudioEngine()),
        presetRepositoryProvider.overrideWithValue(_FakePresetRepository()),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository()),
        setlistRepositoryProvider.overrideWithValue(_FakeSetlistRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_DesktopAppHarness(container: container));
    await tester.pumpAndSettle();

    final router = container.read(_routerProvider);
    router.go('/metronome/live');
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(LiveScreen), findsOneWidget);
  });
}

final _routerProvider = Provider((ref) {
  return buildRouter(ref.watch(appVariantProvider));
});

class _DesktopAppHarness extends ConsumerWidget {
  const _DesktopAppHarness({required this.container});

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

int _selectedIndex(WidgetTester tester) {
  return tester
          .widget<NavigationRail>(find.byType(NavigationRail))
          .selectedIndex ??
      -1;
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
  Stream<List<Song>> watchAllSongs() => Stream<List<Song>>.value([]);

  @override
  Stream<Song?> watchSongById(String songId) => Stream<Song?>.value(null);
}

class _FakeSetlistRepository implements SetlistRepository {
  _FakeSetlistRepository({
    Setlist? setlist,
  }) : _setlist = setlist;

  final Setlist? _setlist;

  @override
  Future<void> deleteSetlist(String setlistId) async {}

  @override
  Future<List<Setlist>> getAllSetlists() async =>
      _setlist == null ? const [] : [_setlist];

  @override
  Future<Setlist?> getSetlistById(String setlistId) async => _setlist;

  @override
  Future<Setlist> loadSetlist(String setlistId) async {
    if (_setlist == null) {
      throw StateError('Setlist not found: $setlistId');
    }
    return _setlist;
  }

  @override
  Future<void> saveSetlist(Setlist setlist) async {}

  @override
  Stream<List<Setlist>> watchAllSetlists() =>
      Stream<List<Setlist>>.value(_setlist == null ? const [] : [_setlist]);

  @override
  Stream<Setlist?> watchSetlistById(String setlistId) =>
      Stream<Setlist?>.value(_setlist);
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
