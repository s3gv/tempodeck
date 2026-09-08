import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/stub_audio_engine.dart';
import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/providers/service_providers.dart';
import 'package:tempodeck/core/repositories/preset_repository.dart';
import 'package:tempodeck/core/repositories/setlist_repository.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/core/router/app_router.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_animated_background.dart';
import 'package:tempodeck/core/widgets/td_nav_bar.dart';
import 'package:tempodeck/features/live/live_screen.dart';
import 'package:tempodeck/core/domain/metronome_preset.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';

void main() {
  setUpAll(() {
    TDAnimatedBackground.disableAnimations = true;
  });

  tearDownAll(() {
    TDAnimatedBackground.disableAnimations = false;
  });

  testWidgets('mobile shell hides the navigation bar on live routes',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.mobile),
        audioEngineProvider.overrideWithValue(StubAudioEngine()),
        presetRepositoryProvider.overrideWithValue(_FakePresetRepository()),
        songRepositoryProvider.overrideWithValue(_FakeSongRepository()),
        setlistRepositoryProvider.overrideWithValue(_FakeSetlistRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_MobileAppHarness(container: container));
    await tester.pumpAndSettle();

    expect(find.byType(TDNavBar), findsOneWidget);

    final router = container.read(_routerProvider);
    router.go('/metronome/live');
    await tester.pumpAndSettle();

    expect(find.byType(TDNavBar), findsNothing);
    expect(find.byType(LiveScreen), findsOneWidget);
  });
}

final _routerProvider = Provider((ref) {
  return buildRouter(ref.watch(appVariantProvider));
});

class _MobileAppHarness extends ConsumerWidget {
  const _MobileAppHarness({required this.container});

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
  Stream<List<Setlist>> watchAllSetlists() => Stream<List<Setlist>>.value(
        const [],
      );

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
      Stream<List<MetronomePreset>>.value(const []);

  @override
  Stream<MetronomePreset?> watchPresetById(String presetId) =>
      Stream<MetronomePreset?>.value(null);
}
