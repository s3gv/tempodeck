import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/db/app_database.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/repositories/drift_song_repository.dart';

void main() {
  late AppDatabase database;
  late DriftSongRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftSongRepository(songDao: database.songDao);
  });

  tearDown(() async {
    await database.close();
  });

  test('persists and reloads songs through the repository contract', () async {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
    );

    await repository.saveSong(song);

    final loadedSong = await repository.getSongById(song.id);
    final allSongs = await repository.getAllSongs();

    expect(loadedSong, isNotNull);
    expect(loadedSong!.id, song.id);
    expect(loadedSong.title, song.title);
    expect(allSongs.map((item) => item.id).toList(), ['song-1']);
  });

  test('watchAllSongs emits repository updates', () async {
    final emittedSongs = <List<Song>>[];
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
    );
    final subscription = repository.watchAllSongs().listen(emittedSongs.add);

    await Future<void>.delayed(Duration.zero);
    await repository.saveSong(song);
    await Future<void>.delayed(Duration.zero);
    await repository.deleteSong(song.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emittedSongs.first, isEmpty);
    expect(emittedSongs[1].map((item) => item.id).toList(), ['song-1']);
    expect(emittedSongs.last, isEmpty);
  });

  test('watchSongById emits song updates and null after deletion', () async {
    final emittedSongs = <Song?>[];
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
    );
    final subscription =
        repository.watchSongById(song.id).listen(emittedSongs.add);

    await Future<void>.delayed(Duration.zero);
    await repository.saveSong(song);
    await Future<void>.delayed(Duration.zero);
    await repository.deleteSong(song.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emittedSongs.first, isNull);
    expect(emittedSongs[1], isNotNull);
    expect(emittedSongs[1]!.id, song.id);
    expect(emittedSongs.last, isNull);
  });

  test('loadSong returns the stored song for export source loading', () async {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
    );

    await repository.saveSong(song);

    final loadedSong = await repository.loadSong(song.id);

    expect(loadedSong.id, song.id);
    expect(loadedSong.title, song.title);
  });

  test('loadSong throws when the song does not exist', () async {
    await expectLater(
      repository.loadSong('missing-song'),
      throwsA(isA<StateError>()),
    );
  });

  test('loadSongBeatmap returns the persisted beatmap contract', () async {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 12,
      loops: const [
        SongLoop(
          id: 'loop-1',
          startBar: 5,
          endBar: 6,
          repeatCount: 1,
          alternativeEndings: [
            SongLoopAlternativeEnding(
              id: 'ending-1',
              repeatPass: 2,
              lengthBars: 1,
            ),
          ],
        ),
      ],
      songEvents: const [
        SongEvent(
          id: 'event-1',
          barIndex: 8,
          label: 'Cue',
          audioCue: AudioCue(type: AudioCueType.highPulse),
          audioCueBarsBefore: 1,
        ),
      ],
    );

    await repository.saveSong(song);
    await repository.regenerateBeatmap(song.id);

    final beatmap = await repository.loadSongBeatmap(song.id);

    expect(beatmap.countInBarCount, 2);
    expect(
      beatmap.entries.any((entry) => entry.barLabel == '1.1.2'),
      isTrue,
    );
    expect(
      beatmap.entries
          .expand((entry) => entry.audioCueTriggers)
          .map((trigger) => trigger.label),
      contains('Cue'),
    );
  });

  test('saveSong rejects invalid song data before writing', () async {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 10,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
    );

    expect(
      () => repository.saveSong(song),
      throwsA(isA<ArgumentError>()),
    );

    final storedSongs = await repository.getAllSongs();
    expect(storedSongs, isEmpty);
  });
}
