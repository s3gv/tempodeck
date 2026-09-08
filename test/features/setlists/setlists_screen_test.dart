import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/repositories/setlist_repository.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/core/router/routes.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_animated_background.dart';
import 'package:tempodeck/core/widgets/td_list_tile.dart';
import 'package:tempodeck/features/setlists/setlist_editor_screen.dart';
import 'package:tempodeck/features/setlists/setlists_screen.dart';

void main() {
  setUpAll(() {
    TDAnimatedBackground.disableAnimations = true;
  });

  tearDownAll(() {
    TDAnimatedBackground.disableAnimations = false;
  });

  testWidgets('shows setlist title and song count', (tester) async {
    final container = _createTestContainer(setlists: [_newerSetlist, _olderSetlist]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SetlistsScreenHarness(container: container));
    await tester.pumpAndSettle();

    expect(find.text('Tour Set'), findsOneWidget);
    expect(find.text('3 songs'), findsOneWidget);
    expect(find.text('Warmup'), findsOneWidget);
    expect(find.text('1 song'), findsOneWidget);
  });

  testWidgets('shows empty state when there are no setlists', (tester) async {
    final container = _createTestContainer(setlists: const []);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SetlistsScreenHarness(container: container));
    await tester.pumpAndSettle();

    expect(find.text('No setlists yet'), findsOneWidget);
  });

  testWidgets('renders setlists in newest-first order', (tester) async {
    final container = _createTestContainer(setlists: [_newerSetlist, _olderSetlist]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SetlistsScreenHarness(container: container));
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<TDListTile>(find.byType(TDListTile))
        .map((tile) => tile.title)
        .toList();

    expect(titles, ['Tour Set', 'Warmup']);
  });

  testWidgets('creates a setlist via the FAB and name dialog', (tester) async {
    final repository = _RecordingSetlistRepository();
    final container = _createTestContainer(repository: repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SetlistsScreenHarness(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Festival Set');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.savedSetlists, hasLength(1));
    expect(repository.savedSetlists.single.title, 'Festival Set');
  });

  testWidgets('renames a setlist via the popup menu', (tester) async {
    final repository = _RecordingSetlistRepository(initial: [_newerSetlist]);
    final container = _createTestContainer(repository: repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SetlistsScreenHarness(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Arena Set');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.savedSetlists, hasLength(1));
    expect(repository.savedSetlists.single.id, _newerSetlist.id);
    expect(repository.savedSetlists.single.title, 'Arena Set');
  });

  testWidgets('deletes a setlist after confirmation', (tester) async {
    final repository = _RecordingSetlistRepository(initial: [_newerSetlist]);
    final container = _createTestContainer(repository: repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SetlistsScreenHarness(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(repository.deletedIds, [_newerSetlist.id]);
  });

  testWidgets('adds a song to a setlist via the song browser', (tester) async {
    final repository = _RecordingSetlistRepository(initial: [_newerSetlist]);
    final songRepository = _RecordingSongRepository(
      songs: [
        Song(
          id: 'song-9',
          title: 'Encore',
          createdAt: DateTime(2024, 3, 1),
          startBpm: 132,
          beatsPerBar: 4,
          beatUnit: 4,
          countInBars: 1,
          endBar: 32,
        ),
      ],
    );
    final container = _createTestContainer(
      repository: repository,
      songRepository: songRepository,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_SetlistsScreenHarness(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add song'));
    await tester.pumpAndSettle();

    expect(find.text('Encore'), findsOneWidget);
    await tester.tap(find.text('Encore'));
    await tester.pumpAndSettle();

    expect(repository.savedSetlists, hasLength(1));
    final saved = repository.savedSetlists.single;
    expect(saved.items, hasLength(4));
    expect(saved.items.last.songId, 'song-9');
    expect(saved.items.last.songTitle, 'Encore');
  });

  testWidgets('navigates to setlist editor on tap', (tester) async {
    final container = _createTestContainer(setlists: [_newerSetlist]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SetlistsRouterHarness(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tour Set'));
    await tester.pumpAndSettle();

    expect(find.byType(SetlistEditorScreen), findsOneWidget);
    expect(find.text('Intro'), findsOneWidget);
  });

  testWidgets('shows export option in popup menu', (tester) async {
    final container = _createTestContainer(setlists: [_newerSetlist]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SetlistsScreenHarness(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    expect(find.text('Export'), findsOneWidget);
  });
}

final _olderSetlist = Setlist(
  id: 'setlist-1',
  title: 'Warmup',
  createdAt: DateTime(2024, 1, 1),
  items: const [
    SetlistItem(
      id: 'item-1',
      songId: 'song-1',
      songTitle: 'Warmup Song',
    ),
  ],
);

final _newerSetlist = Setlist(
  id: 'setlist-2',
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
      songTitle: 'Single',
    ),
    SetlistItem(
      id: 'item-3',
      songId: 'song-3',
      songTitle: 'Finale',
    ),
  ],
);

ProviderContainer _createTestContainer({
  List<Setlist> setlists = const [],
  _RecordingSetlistRepository? repository,
  _RecordingSongRepository? songRepository,
}) {
  return ProviderContainer(
    overrides: [
      appVariantProvider.overrideWithValue(AppVariant.mobile),
      setlistRepositoryProvider.overrideWithValue(
        repository ?? _RecordingSetlistRepository(initial: setlists),
      ),
      songRepositoryProvider.overrideWithValue(
        songRepository ?? _RecordingSongRepository(),
      ),
    ],
  );
}

class _SetlistsScreenHarness extends StatelessWidget {
  const _SetlistsScreenHarness({required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const SetlistsScreen(),
      ),
    );
  }
}

class _SetlistsRouterHarness extends StatelessWidget {
  const _SetlistsRouterHarness({required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: GoRouter(
          initialLocation: Routes.setlists,
          routes: [
            GoRoute(
              path: Routes.setlists,
              builder: (_, __) => const SetlistsScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, state) => SetlistEditorScreen(
                    setlistId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingSetlistRepository implements SetlistRepository {
  _RecordingSetlistRepository({List<Setlist> initial = const []})
      : _setlists = List.of(initial);

  final List<Setlist> _setlists;
  final List<Setlist> savedSetlists = [];
  final List<String> deletedIds = [];

  @override
  Future<void> deleteSetlist(String setlistId) async => deletedIds.add(setlistId);

  @override
  Future<List<Setlist>> getAllSetlists() async => List.of(_setlists);

  @override
  Future<Setlist?> getSetlistById(String setlistId) async =>
      _setlists.where((setlist) => setlist.id == setlistId).firstOrNull;

  @override
  Future<Setlist> loadSetlist(String setlistId) async {
    final setlist = _setlists.where((item) => item.id == setlistId).firstOrNull;
    if (setlist == null) {
      throw StateError('Setlist not found: $setlistId');
    }

    return setlist;
  }

  @override
  Future<void> saveSetlist(Setlist setlist) async => savedSetlists.add(setlist);

  @override
  Stream<List<Setlist>> watchAllSetlists() async* {
    yield List.of(_setlists);
  }

  @override
  Stream<Setlist?> watchSetlistById(String setlistId) async* {
    yield await getSetlistById(setlistId);
  }
}

class _RecordingSongRepository implements SongRepository {
  _RecordingSongRepository({List<Song> songs = const []}) : _songs = List.of(songs);

  final List<Song> _songs;

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) => throw UnimplementedError();

  @override
  Future<void> deleteSong(String songId) => throw UnimplementedError();

  @override
  Future<List<Song>> getAllSongs() async => List.of(_songs);

  @override
  Future<Song?> getSongById(String songId) async =>
      _songs.where((song) => song.id == songId).firstOrNull;

  @override
  Future<Song> loadSong(String songId) async {
    final song = await getSongById(songId);
    if (song == null) {
      throw StateError('Song not found: $songId');
    }

    return song;
  }

  @override
  Future<void> saveSong(Song song) => throw UnimplementedError();

  @override
  Future<void> regenerateBeatmap(String songId) async {}

  @override
  Stream<List<Song>> watchAllSongs() async* {
    yield List.of(_songs);
  }

  @override
  Stream<Song?> watchSongById(String songId) async* {
    yield await getSongById(songId);
  }
}
