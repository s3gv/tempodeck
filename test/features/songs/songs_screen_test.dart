import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_animated_background.dart';
import 'package:tempodeck/features/songs/song_editor_screen.dart';
import 'package:tempodeck/features/songs/songs_screen.dart';

void main() {
  setUpAll(() {
    TDAnimatedBackground.disableAnimations = true;
  });

  tearDownAll(() {
    TDAnimatedBackground.disableAnimations = false;
  });

  testWidgets('shows song title and basic settings', (tester) async {
    final container = _createTestContainer(songs: [_testSong]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SongsScreenHarness(container: container));
    await tester.pumpAndSettle();

    expect(find.text('Rock Ballad'), findsOneWidget);
    expect(find.text('120 BPM · 4/4'), findsOneWidget);
  });

  testWidgets('shows empty state when there are no songs', (tester) async {
    final container = _createTestContainer(songs: const []);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SongsScreenHarness(container: container));
    await tester.pumpAndSettle();

    expect(find.text('No songs yet'), findsOneWidget);
  });

  testWidgets('navigates to song editor on tap', (tester) async {
    final container = _createTestContainer(songs: [_testSong]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SongsScreenHarness(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rock Ballad'));
    await tester.pumpAndSettle();

    expect(find.byType(SongEditorScreen), findsOneWidget);
  });

  testWidgets('creates a song via the FAB and name dialog', (tester) async {
    final repository = _RecordingSongRepository();
    final container = _createTestContainer(repository: repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SongsScreenHarness(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Blues Groove');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.savedSongs, hasLength(1));
    expect(repository.savedSongs.single.title, 'Blues Groove');
  });

  testWidgets('renames a song via the popup menu', (tester) async {
    final repository = _RecordingSongRepository(initial: [_testSong]);
    final container = _createTestContainer(repository: repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SongsScreenHarness(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Renamed Song');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.savedSongs.last.title, 'Renamed Song');
    expect(repository.savedSongs.last.id, _testSong.id);
  });

  testWidgets('deletes a song after confirmation', (tester) async {
    final repository = _RecordingSongRepository(initial: [_testSong]);
    final container = _createTestContainer(repository: repository);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SongsScreenHarness(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(repository.deletedIds, [_testSong.id]);
  });

  testWidgets('shows export option in popup menu', (tester) async {
    final container = _createTestContainer(songs: [_testSong]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_SongsScreenHarness(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Export'), findsOneWidget);
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

final _testSong = Song(
  id: 'song-1',
  title: 'Rock Ballad',
  createdAt: DateTime(2024, 1, 1),
  startBpm: 120,
  beatsPerBar: 4,
  beatUnit: 4,
  countInBars: 1,
  endBar: 32,
);

ProviderContainer _createTestContainer({
  List<Song> songs = const [],
  _RecordingSongRepository? repository,
}) {
  return ProviderContainer(
    overrides: [
      appVariantProvider.overrideWithValue(AppVariant.mobile),
      songRepositoryProvider.overrideWithValue(
        repository ?? _RecordingSongRepository(initial: songs),
      ),
    ],
  );
}

class _SongsScreenHarness extends StatelessWidget {
  const _SongsScreenHarness({required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: GoRouter(
          initialLocation: '/songs',
          routes: [
            GoRoute(
              path: '/songs',
              builder: (_, __) => const SongsScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, state) => SongEditorScreen(
                    songId: state.pathParameters['id']!,
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

class _RecordingSongRepository implements SongRepository {
  _RecordingSongRepository({List<Song> initial = const []})
      : _songs = List.of(initial);

  final List<Song> _songs;
  final List<Song> savedSongs = [];
  final List<String> deletedIds = [];

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) => throw UnimplementedError();

  @override
  Future<List<Song>> getAllSongs() async => List.of(_songs);

  @override
  Stream<List<Song>> watchAllSongs() => Stream.value(List.of(_songs));

  @override
  Future<Song?> getSongById(String songId) async =>
      _songs.where((s) => s.id == songId).firstOrNull;

  @override
  Stream<Song?> watchSongById(String songId) =>
      Stream.value(_songs.where((s) => s.id == songId).firstOrNull);

  @override
  Future<void> saveSong(Song song) async => savedSongs.add(song);

  @override
  Future<void> regenerateBeatmap(String songId) async {}

  @override
  Future<void> deleteSong(String songId) async => deletedIds.add(songId);

  @override
  Future<Song> loadSong(String songId) async {
    final song = _songs.where((s) => s.id == songId).firstOrNull;
    if (song == null) throw StateError('Song not found: $songId');
    return song;
  }
}
