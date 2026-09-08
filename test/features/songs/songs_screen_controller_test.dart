import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/files/linked_audio_file_storage.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/providers/service_providers.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/features/songs/songs_screen_controller.dart';

void main() {
  test('createSong saves a song with correct defaults', () async {
    final repository = _CapturingSongRepository();
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await container.read(songsScreenControllerProvider).createSong('Jazz Piece');

    expect(repository.savedSongs, hasLength(1));
    final song = repository.savedSongs.single;
    expect(song.title, 'Jazz Piece');
    expect(song.startBpm, 120);
    expect(song.beatsPerBar, 4);
    expect(song.beatUnit, 4);
    expect(song.countInBars, 2);
    expect(song.endBar, 32);
    expect(song.id, isNotEmpty);
  });

  test('createSong assigns a unique id each time', () async {
    final repository = _CapturingSongRepository();
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    final controller = container.read(songsScreenControllerProvider);
    await controller.createSong('Song A');
    await controller.createSong('Song B');

    final ids = repository.savedSongs.map((s) => s.id).toList();
    expect(ids[0], isNot(ids[1]));
  });

  test('renameSong saves song with new title while preserving all other fields',
      () async {
    final original = _makeSong(
      title: 'Old Name',
      startBpm: 140,
      beatsPerBar: 3,
    );
    final repository = _CapturingSongRepository();
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await container
        .read(songsScreenControllerProvider)
        .renameSong(original, 'New Name');

    expect(repository.savedSongs, hasLength(1));
    final saved = repository.savedSongs.single;
    expect(saved.id, original.id);
    expect(saved.title, 'New Name');
    expect(saved.startBpm, 140);
    expect(saved.beatsPerBar, 3);
    expect(saved.createdAt, original.createdAt);
  });

  test('renameSong trims whitespace defensively', () async {
    final original = _makeSong(title: 'Old Name');
    final repository = _CapturingSongRepository();
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await container
        .read(songsScreenControllerProvider)
        .renameSong(original, '  New Name  ');

    expect(repository.savedSongs, hasLength(1));
    expect(repository.savedSongs.single.title, 'New Name');
  });

  test('deleteSong delegates to the repository', () async {
    final repository = _CapturingSongRepository();
    final container = _createContainer(repository);
    addTearDown(container.dispose);

    await container.read(songsScreenControllerProvider).deleteSong('song-99');

    expect(repository.deletedIds, ['song-99']);
  });

  test('deleteSong cleans up custom cue files in alternative endings',
      () async {
    final song = Song(
      id: 'song-1',
      title: 'Loop Song',
      createdAt: DateTime(2024, 6, 1),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 32,
      songEvents: const [
        SongEvent(
          id: 'evt-1',
          barIndex: 1,
          label: 'Main event',
          audioCue: AudioCue(
            type: AudioCueType.customFile,
            customFilePath: '/audio/main-cue.mp3',
          ),
        ),
      ],
      loops: const [
        SongLoop(
          id: 'loop-1',
          startBar: 1,
          endBar: 8,
          repeatCount: 2,
          alternativeEndings: [
            SongLoopAlternativeEnding(
              id: 'alt-1',
              repeatPass: 2,
              lengthBars: 2,
              songEvents: [
                SongEvent(
                  id: 'evt-2',
                  barIndex: 1,
                  label: 'Alt ending event',
                  audioCue: AudioCue(
                    type: AudioCueType.customFile,
                    customFilePath: '/audio/alt-cue.mp3',
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final repository = _CapturingSongRepository(songToReturn: song);
    final storage = _CapturingLinkedAudioFileStorage();
    final container = ProviderContainer(
      overrides: [
        songRepositoryProvider.overrideWithValue(repository),
        linkedAudioFileStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await container.read(songsScreenControllerProvider).deleteSong('song-1');

    expect(repository.deletedIds, ['song-1']);
    expect(
      storage.deletedPaths,
      containsAll(['/audio/main-cue.mp3', '/audio/alt-cue.mp3']),
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer _createContainer(_CapturingSongRepository repository) {
  return ProviderContainer(
    overrides: [
      songRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

Song _makeSong({
  String id = 'song-1',
  String title = 'Test Song',
  int startBpm = 120,
  int beatsPerBar = 4,
  int beatUnit = 4,
}) {
  return Song(
    id: id,
    title: title,
    createdAt: DateTime(2024, 6, 1),
    startBpm: startBpm,
    beatsPerBar: beatsPerBar,
    beatUnit: beatUnit,
    countInBars: 1,
    endBar: 32,
  );
}

class _CapturingSongRepository implements SongRepository {
  _CapturingSongRepository({this.songToReturn});

  final Song? songToReturn;
  final List<Song> savedSongs = [];
  final List<String> deletedIds = [];

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) => throw UnimplementedError();

  @override
  Future<void> saveSong(Song song) async => savedSongs.add(song);

  @override
  Future<void> regenerateBeatmap(String songId) async {}

  @override
  Future<void> deleteSong(String songId) async => deletedIds.add(songId);

  @override
  Future<List<Song>> getAllSongs() async => [];

  @override
  Stream<List<Song>> watchAllSongs() => const Stream.empty();

  @override
  Future<Song?> getSongById(String songId) async => songToReturn;

  @override
  Stream<Song?> watchSongById(String songId) => const Stream.empty();

  @override
  Future<Song> loadSong(String songId) => throw UnimplementedError();
}

class _CapturingLinkedAudioFileStorage implements LinkedAudioFileStorage {
  final List<String> deletedPaths = [];

  @override
  Future<void> deleteFromStorage(String filePath) async {
    deletedPaths.add(filePath);
  }

  @override
  Future<String> copyToStorage(
    String sourcePath,
    String displayName,
  ) =>
      throw UnimplementedError();
}
