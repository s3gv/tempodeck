import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/db/app_database.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/subdivision.dart';

void main() {
  late AppDatabase database;
  late SongDao dao;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    dao = database.songDao;
  });

  tearDown(() async {
    await database.close();
  });

  test('saves and reloads a full song aggregate', () async {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      tempoChanges: [
        const SongTempoChange(
          id: 'tempo-1',
          barIndex: 5,
          bpm: 132,
          beatsPerBar: 4,
          beatUnit: 4,
        ),
      ],
      loops: [
        const SongLoop(
          id: 'loop-1',
          startBar: 9,
          endBar: 12,
          repeatCount: 2,
        ),
      ],
      songEvents: [
        const SongEvent(
          id: 'event-1',
          barIndex: 16,
          label: 'Verse cue',
          audioCue: AudioCue(
            type: AudioCueType.voice,
            voiceText: 'Verse',
            voiceIdentifier: 'en-US',
            volumePercent: 85,
          ),
          audioCueBarsBefore: 2,
        ),
      ],
      beatPatterns: [
        const SongBarBeatPattern(
          id: 'pattern-1',
          barIndex: 10,
          accents: [
            AccentLevel.high,
            AccentLevel.normal,
            AccentLevel.low,
            AccentLevel.low,
            AccentLevel.normal,
            AccentLevel.low,
            AccentLevel.low,
            AccentLevel.normal,
            AccentLevel.low,
            AccentLevel.low,
            AccentLevel.normal,
            AccentLevel.low,
          ],
          subdivision: Subdivision.three,
          repeatPass: 2,
        ),
      ],
      linkedAudio: const LinkedAudioFile(
        filePath: '/tmp/backing.wav',
        displayName: 'Backing Track',
        offsetMilliseconds: 250,
        volumePercent: 72,
        playInLiveMode: false,
      ),
    );

    await dao.saveSong(song);

    final loadedSong = await dao.getSongById(song.id);

    expect(loadedSong, isNotNull);
    _expectSongsEqual(loadedSong!, song);
  });

  test('updates song children and clears linked audio on overwrite', () async {
    final originalSong = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      tempoChanges: [
        const SongTempoChange(
          id: 'tempo-1',
          barIndex: 5,
          bpm: 132,
          beatsPerBar: 4,
          beatUnit: 4,
        ),
      ],
      linkedAudio: const LinkedAudioFile(
        filePath: '/tmp/backing.wav',
        displayName: 'Backing Track',
      ),
    );
    final updatedSong = Song(
      id: 'song-1',
      title: 'Warmup v2',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 140,
      beatsPerBar: 3,
      beatUnit: 8,
      countInBars: 1,
      endBar: 24,
      loops: [
        const SongLoop(
          id: 'loop-2',
          startBar: 4,
          endBar: 6,
          repeatCount: 3,
        ),
      ],
    );

    await dao.saveSong(originalSong);
    await dao.saveSong(updatedSong);

    final loadedSong = await dao.getSongById(updatedSong.id);

    expect(loadedSong, isNotNull);
    _expectSongsEqual(loadedSong!, updatedSong);
  });

  test('lists songs newest first', () async {
    final olderSong = Song(
      id: 'song-1',
      title: 'Older',
      createdAt: DateTime.utc(2026, 3, 9, 12),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 16,
    );
    final newerSong = Song(
      id: 'song-2',
      title: 'Newer',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 140,
      beatsPerBar: 7,
      beatUnit: 8,
      countInBars: 1,
      endBar: 20,
    );

    await dao.saveSong(olderSong);
    await dao.saveSong(newerSong);

    final songs = await dao.getAllSongs();

    expect(songs.map((song) => song.id).toList(), ['song-2', 'song-1']);
  });

  test('deletes songs and cascades to child rows', () async {
    final song = Song(
      id: 'song-1',
      title: 'Warmup',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 32,
      tempoChanges: [
        const SongTempoChange(
          id: 'tempo-1',
          barIndex: 5,
          bpm: 132,
          beatsPerBar: 4,
          beatUnit: 4,
        ),
      ],
    );

    await dao.saveSong(song);
    await dao.deleteSong(song.id);

    final loadedSong = await dao.getSongById(song.id);
    final remainingTempoChanges =
        await database.select(database.songTempoChanges).get();

    expect(loadedSong, isNull);
    expect(remainingTempoChanges, isEmpty);
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
    final subscription = dao.watchSongById(song.id).listen(emittedSongs.add);

    await Future<void>.delayed(Duration.zero);
    await dao.saveSong(song);
    await Future<void>.delayed(Duration.zero);
    await dao.deleteSong(song.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emittedSongs.first, isNull);
    expect(emittedSongs[1], isNotNull);
    _expectSongsEqual(emittedSongs[1]!, song);
    expect(emittedSongs.last, isNull);
  });

  test('watchAllSongs emits on insert and delete', () async {
    final emittedSongLists = <List<Song>>[];
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
    final subscription = dao.watchAllSongs().listen(emittedSongLists.add);

    await Future<void>.delayed(Duration.zero);
    await dao.saveSong(song);
    await Future<void>.delayed(Duration.zero);
    await dao.deleteSong(song.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emittedSongLists.first, isEmpty);
    expect(emittedSongLists[1].map((item) => item.id).toList(), ['song-1']);
    expect(emittedSongLists.last, isEmpty);
  });

  test('persists beatmap and alternative endings together with the song', () async {
    final song = Song(
      id: 'song-1',
      title: 'Beatmap Song',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 16,
      loops: const [
        SongLoop(
          id: 'loop-1',
          startBar: 5,
          endBar: 8,
          repeatCount: 1,
          alternativeEndings: [
            SongLoopAlternativeEnding(
              id: 'ending-1',
              repeatPass: 2,
              lengthBars: 2,
              songEvents: [
                SongEvent(
                  id: 'ending-event-1',
                  barIndex: 2,
                  label: 'Ending hit',
                  audioCue: AudioCue(type: AudioCueType.highPulse),
                ),
              ],
            ),
          ],
        ),
      ],
      songEvents: const [
        SongEvent(
          id: 'event-1',
          barIndex: 12,
          label: 'Chorus',
          audioCue: AudioCue(type: AudioCueType.voice, voiceText: 'Chorus'),
          audioCueBarsBefore: 1,
        ),
      ],
    );

    await dao.saveSong(song);
    await dao.regenerateBeatmap(song.id);

    final loadedSong = await dao.getSongById(song.id);
    final loadedBeatmap = await dao.getSongBeatmap(song.id);

    expect(loadedSong, isNotNull);
    expect(loadedSong!.loops.single.alternativeEndings.single.id, 'ending-1');
    expect(loadedBeatmap.countInBarCount, 2);
    expect(
      loadedBeatmap.entries.any((entry) => entry.barLabel == '1.2.2'),
      isTrue,
    );
    expect(
      loadedBeatmap.entries
          .expand((entry) => entry.audioCueTriggers)
          .map((trigger) => trigger.label),
      contains('Chorus'),
    );
  });

  test('refreshes persisted beatmaps on reopen so stale beatmaps cannot survive',
      () async {
    await database.close();
    final tempDir = await Directory.systemTemp.createTemp('tempodeck-song-dao');
    final databaseFile = File('${tempDir.path}/song-beatmap.sqlite');
    final song = Song(
      id: 'song-1',
      title: 'Tempo Refresh',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      startBpm: 100,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 8,
      tempoChanges: const [
        SongTempoChange(
          id: 'tempo-1',
          barIndex: 3,
          bpm: 200,
          beatsPerBar: 9,
          beatUnit: 8,
        ),
      ],
    );

    final firstDatabase = AppDatabase(NativeDatabase.createInBackground(databaseFile));
    addTearDown(() async {
      if (databaseFile.existsSync()) {
        await databaseFile.delete();
      }
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    await firstDatabase.songDao.saveSong(song);
    await firstDatabase.customStatement(
      '''
      UPDATE song_beatmap_entries
      SET beats_per_bar = 4, beat_unit = 4
      WHERE song_id = ? AND playback_bar_index = 4
      ''',
      <Object>[song.id],
    );
    await firstDatabase.close();

    final reopenedDatabase =
        AppDatabase(NativeDatabase.createInBackground(databaseFile));
    addTearDown(reopenedDatabase.close);

    final loadedBeatmap = await reopenedDatabase.songDao.getSongBeatmap(song.id);
    final barFourEntry = loadedBeatmap.entryForPlaybackBar(4);

    expect(barFourEntry.bpm, 200);
    expect(barFourEntry.beatsPerBar, 9);
    expect(barFourEntry.beatUnit, 8);
  });
}

void _expectSongsEqual(Song actual, Song expected) {
  expect(actual.id, expected.id);
  expect(actual.title, expected.title);
  expect(actual.createdAt.isAtSameMomentAs(expected.createdAt), isTrue);
  expect(actual.startBpm, expected.startBpm);
  expect(actual.beatsPerBar, expected.beatsPerBar);
  expect(actual.beatUnit, expected.beatUnit);
  expect(actual.countInBars, expected.countInBars);
  expect(actual.endBar, expected.endBar);

  expect(actual.tempoChanges.length, expected.tempoChanges.length);
  for (var index = 0; index < expected.tempoChanges.length; index += 1) {
    final actualItem = actual.tempoChanges[index];
    final expectedItem = expected.tempoChanges[index];
    expect(actualItem.id, expectedItem.id);
    expect(actualItem.barIndex, expectedItem.barIndex);
    expect(actualItem.bpm, expectedItem.bpm);
    expect(actualItem.beatsPerBar, expectedItem.beatsPerBar);
    expect(actualItem.beatUnit, expectedItem.beatUnit);
  }

  expect(actual.loops.length, expected.loops.length);
  for (var index = 0; index < expected.loops.length; index += 1) {
    final actualItem = actual.loops[index];
    final expectedItem = expected.loops[index];
    expect(actualItem.id, expectedItem.id);
    expect(actualItem.startBar, expectedItem.startBar);
    expect(actualItem.endBar, expectedItem.endBar);
    expect(actualItem.repeatCount, expectedItem.repeatCount);
    expect(
      actualItem.alternativeEndings.length,
      expectedItem.alternativeEndings.length,
    );
  }

  expect(actual.songEvents.length, expected.songEvents.length);
  for (var index = 0; index < expected.songEvents.length; index += 1) {
    final actualItem = actual.songEvents[index];
    final expectedItem = expected.songEvents[index];
    expect(actualItem.id, expectedItem.id);
    expect(actualItem.barIndex, expectedItem.barIndex);
    expect(actualItem.label, expectedItem.label);
    expect(actualItem.audioCueBarsBefore, expectedItem.audioCueBarsBefore);
    _expectAudioCueEqual(actualItem.audioCue, expectedItem.audioCue);
  }

  expect(actual.beatPatterns.length, expected.beatPatterns.length);
  for (var index = 0; index < expected.beatPatterns.length; index += 1) {
    final actualItem = actual.beatPatterns[index];
    final expectedItem = expected.beatPatterns[index];
    expect(actualItem.id, expectedItem.id);
    expect(actualItem.barIndex, expectedItem.barIndex);
    expect(actualItem.accents, expectedItem.accents);
    expect(actualItem.subdivision, expectedItem.subdivision);
    expect(actualItem.repeatPass, expectedItem.repeatPass);
  }

  final actualLinkedAudio = actual.linkedAudio;
  final expectedLinkedAudio = expected.linkedAudio;
  expect(actualLinkedAudio == null, expectedLinkedAudio == null);
  if (actualLinkedAudio != null && expectedLinkedAudio != null) {
    expect(actualLinkedAudio.filePath, expectedLinkedAudio.filePath);
    expect(actualLinkedAudio.displayName, expectedLinkedAudio.displayName);
    expect(
      actualLinkedAudio.offsetMilliseconds,
      expectedLinkedAudio.offsetMilliseconds,
    );
    expect(actualLinkedAudio.volumePercent, expectedLinkedAudio.volumePercent);
    expect(
      actualLinkedAudio.playInLiveMode,
      expectedLinkedAudio.playInLiveMode,
    );
  }
}

void _expectAudioCueEqual(AudioCue? actual, AudioCue? expected) {
  expect(actual == null, expected == null);
  if (actual == null || expected == null) {
    return;
  }

  expect(actual.type, expected.type);
  expect(actual.voiceText, expected.voiceText);
  expect(actual.voiceIdentifier, expected.voiceIdentifier);
  expect(actual.customFilePath, expected.customFilePath);
  expect(actual.customFileDisplayName, expected.customFileDisplayName);
  expect(actual.volumePercent, expected.volumePercent);
}
