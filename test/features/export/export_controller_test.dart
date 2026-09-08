import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/i_export_engine.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/files/export_file_service.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/providers/service_providers.dart';
import 'package:tempodeck/core/repositories/setlist_repository.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/features/export/export_controller.dart';

final _testSong = Song(
  id: 'song-1',
  title: 'Test Song',
  createdAt: DateTime(2024, 1, 1),
  startBpm: 120,
  beatsPerBar: 4,
  beatUnit: 4,
  countInBars: 0,
  endBar: 8,
);

final _testSetlist = Setlist(
  id: 'setlist-1',
  title: 'Test Setlist',
  createdAt: DateTime(2024, 1, 1),
  items: const [
    SetlistItem(id: 'item-1', songId: 'song-1', songTitle: 'Test Song'),
  ],
);

ProviderContainer createContainer({
  FakeExportEngine? exportEngine,
  FakeSongRepository? songRepository,
  FakeSetlistRepository? setlistRepository,
  RecordingExportFileService? fileService,
}) {
  return ProviderContainer(
    overrides: [
      exportEngineProvider
          .overrideWithValue(exportEngine ?? FakeExportEngine()),
      songRepositoryProvider
          .overrideWithValue(songRepository ?? FakeSongRepository()),
      setlistRepositoryProvider.overrideWithValue(
        setlistRepository ?? FakeSetlistRepository(),
      ),
      exportFileServiceProvider
          .overrideWithValue(fileService ?? RecordingExportFileService()),
    ],
  );
}

void main() {
  test('initial state is ExportIdle', () {
    final container = createContainer();
    addTearDown(container.dispose);
    final state = container.read(exportControllerProvider);
    expect(state, isA<ExportIdle>());
  });

  test('estimateDuration returns song duration for SongExportSource', () async {
    final container = createContainer();
    addTearDown(container.dispose);
    final controller = container.read(exportControllerProvider.notifier);

    final duration =
        await controller.estimateDuration(SongExportSource('song-1'));
    expect(duration, greaterThan(Duration.zero));
  });

  test('estimateDuration returns setlist duration for SetlistExportSource',
      () async {
    final container = createContainer();
    addTearDown(container.dispose);
    final controller = container.read(exportControllerProvider.notifier);

    final duration =
        await controller.estimateDuration(SetlistExportSource('setlist-1'));
    expect(duration, greaterThan(Duration.zero));
  });

  test('estimateDuration includes timed transition steps for setlists',
      () async {
    final songRepository = FakeSongRepository();
    final setlistRepository = FakeSetlistRepository(
      setlist: Setlist(
        id: 'setlist-1',
        title: 'Transition Setlist',
        createdAt: DateTime(2024, 1, 1),
        items: const [
          SetlistItem(
            id: 'item-1',
            songId: 'song-1',
            songTitle: 'Test Song',
            transitionSteps: [
              SetlistTransitionStep(
                id: 'count-in',
                type: SetlistTransitionStepType.countInBars,
                value: 2,
              ),
              SetlistTransitionStep(
                id: 'pause',
                type: SetlistTransitionStepType.pauseTimer,
                value: 5,
              ),
              SetlistTransitionStep(
                id: 'manual',
                type: SetlistTransitionStepType.manual,
                value: 0,
              ),
            ],
          ),
        ],
      ),
    );
    final container = createContainer(
      songRepository: songRepository,
      setlistRepository: setlistRepository,
    );
    addTearDown(container.dispose);
    final controller = container.read(exportControllerProvider.notifier);

    final duration =
        await controller.estimateDuration(SetlistExportSource('setlist-1'));
    final songDuration = await controller.estimateDuration(
      SongExportSource('song-1'),
    );

    expect(duration, songDuration + const Duration(seconds: 9));
  });

  test('cancelExport resets state to idle', () {
    final container = createContainer();
    addTearDown(container.dispose);
    final controller = container.read(exportControllerProvider.notifier);

    controller.cancelExport();
    expect(container.read(exportControllerProvider), isA<ExportIdle>());
  });

  test('reset resets state to idle', () {
    final container = createContainer();
    addTearDown(container.dispose);
    final controller = container.read(exportControllerProvider.notifier);

    controller.reset();
    expect(container.read(exportControllerProvider), isA<ExportIdle>());
  });

  test('saveExportedFiles does nothing when state is not ExportComplete',
      () async {
    final fileService = RecordingExportFileService();
    final container = createContainer(fileService: fileService);
    addTearDown(container.dispose);
    final controller = container.read(exportControllerProvider.notifier);

    await controller.saveExportedFiles();
    expect(fileService.savedFiles, isEmpty);
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class FakeExportEngine implements IExportEngine {
  @override
  int estimateFileSizeBytes({
    required Duration duration,
    int bitrateBps = 192000,
  }) {
    return (duration.inSeconds * bitrateBps / 8).round();
  }

  @override
  Stream<double> exportToMp3({
    required ExportSource source,
    required String outputPath,
    int bitrateBps = 192000,
    ExportMp3Layout layout = ExportMp3Layout.singleFile,
    ExportContentOptions contentOptions = const ExportContentOptions(),
    void Function(List<String> warnings)? onWarnings,
  }) {
    return const Stream.empty();
  }
}

class FakeSongRepository implements SongRepository {
  @override
  Future<Song> loadSong(String songId) async => _testSong;

  @override
  Future<List<Song>> getAllSongs() async => [_testSong];

  @override
  Stream<List<Song>> watchAllSongs() => Stream.value([_testSong]);

  @override
  Future<Song?> getSongById(String songId) async => _testSong;

  @override
  Stream<Song?> watchSongById(String songId) => Stream.value(_testSong);

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) =>
      throw UnimplementedError();

  @override
  Future<void> saveSong(Song song) async {}

  @override
  Future<void> regenerateBeatmap(String songId) async {}

  @override
  Future<void> deleteSong(String songId) async {}
}

class FakeSetlistRepository implements SetlistRepository {
  FakeSetlistRepository({Setlist? setlist}) : _setlist = setlist ?? _testSetlist;

  final Setlist _setlist;

  @override
  Future<Setlist> loadSetlist(String setlistId) async => _setlist;

  @override
  Future<List<Setlist>> getAllSetlists() async => [_setlist];

  @override
  Stream<List<Setlist>> watchAllSetlists() => Stream.value([_setlist]);

  @override
  Future<Setlist?> getSetlistById(String setlistId) async => _setlist;

  @override
  Stream<Setlist?> watchSetlistById(String setlistId) => Stream.value(_setlist);

  @override
  Future<void> saveSetlist(Setlist setlist) async {}

  @override
  Future<void> deleteSetlist(String setlistId) async {}
}

class RecordingExportFileService implements ExportFileService {
  final List<(String, String)> savedFiles = [];

  @override
  Future<void> saveExportedFile(String filePath, String fileName) async {
    savedFiles.add((filePath, fileName));
  }
}
