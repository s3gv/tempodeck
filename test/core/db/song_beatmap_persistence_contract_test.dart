import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/song_playback_beatmap.dart';
import 'package:tempodeck/core/db/app_database.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';

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

  test('save → load beatmap preserves time signature after time event', () async {
    final song = Song(
      id: 'song-1',
      title: 'Persistence Test',
      createdAt: DateTime.utc(2024),
      startBpm: 100,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 5,
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

    await dao.saveSong(song);
    await dao.regenerateBeatmap(song.id);
    final loadedBeatmap = await dao.getSongBeatmap(song.id);

    expect(loadedBeatmap.totalPlaybackBars, 5);

    // Bars 1-2: 4/4 @ 100 BPM
    for (final barIndex in [1, 2]) {
      final entry = loadedBeatmap.entryForPlaybackBar(barIndex);
      expect(entry.bpm, 100, reason: 'loaded bar $barIndex bpm');
      expect(entry.beatsPerBar, 4, reason: 'loaded bar $barIndex beatsPerBar');
      expect(entry.beatUnit, 4, reason: 'loaded bar $barIndex beatUnit');
    }

    // Bar 3: 9/8 @ 200 BPM (time event)
    final bar3 = loadedBeatmap.entryForPlaybackBar(3);
    expect(bar3.bpm, 200, reason: 'loaded bar 3 bpm');
    expect(bar3.beatsPerBar, 9, reason: 'loaded bar 3 beatsPerBar');
    expect(bar3.beatUnit, 8, reason: 'loaded bar 3 beatUnit');

    // Bars 4-5: must carry 9/8 @ 200 (not revert to 4/4)
    for (final barIndex in [4, 5]) {
      final entry = loadedBeatmap.entryForPlaybackBar(barIndex);
      expect(entry.bpm, 200, reason: 'loaded bar $barIndex bpm must stay 200');
      expect(
        entry.beatsPerBar,
        9,
        reason: 'loaded bar $barIndex beatsPerBar must stay 9 (NOT revert to 4)',
      );
      expect(
        entry.beatUnit,
        8,
        reason: 'loaded bar $barIndex beatUnit must stay 8 (NOT revert to 4)',
      );
    }
  });

  test('save → load → re-open preserves correct beatmap', () async {
    final song = Song(
      id: 'song-1',
      title: 'Re-open Test',
      createdAt: DateTime.utc(2024),
      startBpm: 100,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 5,
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

    // First save
    await dao.saveSong(song);
    await dao.regenerateBeatmap(song.id);
    final firstLoad = await dao.getSongBeatmap(song.id);

    // Simulate re-open by regenerating beatmap (like the refresh on open)
    await dao.regenerateBeatmap(song.id);
    final secondLoad = await dao.getSongBeatmap(song.id);

    // Both loads must produce identical results
    expect(secondLoad.totalPlaybackBars, firstLoad.totalPlaybackBars);
    for (var i = 1; i <= secondLoad.totalPlaybackBars; i++) {
      final first = firstLoad.entryForPlaybackBar(i);
      final second = secondLoad.entryForPlaybackBar(i);
      expect(second.bpm, first.bpm, reason: 'bar $i bpm after re-open');
      expect(
        second.beatsPerBar,
        first.beatsPerBar,
        reason: 'bar $i beatsPerBar after re-open',
      );
      expect(
        second.beatUnit,
        first.beatUnit,
        reason: 'bar $i beatUnit after re-open',
      );
      expect(
        second.barLabel,
        first.barLabel,
        reason: 'bar $i barLabel after re-open',
      );
      expect(
        second.barKind,
        first.barKind,
        reason: 'bar $i barKind after re-open',
      );
    }
  });

  test('loaded beatmap matches in-memory beatmap exactly', () async {
    final song = Song(
      id: 'song-1',
      title: 'Exact Match Test',
      createdAt: DateTime.utc(2024),
      startBpm: 100,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      endBar: 6,
      tempoChanges: const [
        SongTempoChange(
          id: 'tempo-1',
          barIndex: 3,
          bpm: 200,
          beatsPerBar: 9,
          beatUnit: 8,
        ),
      ],
      loops: const [
        SongLoop(
          id: 'loop-1',
          startBar: 1,
          endBar: 2,
          repeatCount: 1,
        ),
      ],
    );

    final inMemoryBeatmap = const SongPlaybackBeatmapBuilder().build(song);

    await dao.saveSong(song);
    await dao.regenerateBeatmap(song.id);
    final loadedBeatmap = await dao.getSongBeatmap(song.id);

    expect(
      loadedBeatmap.totalPlaybackBars,
      inMemoryBeatmap.totalPlaybackBars,
    );

    for (var i = 1; i <= inMemoryBeatmap.totalPlaybackBars; i++) {
      final mem = inMemoryBeatmap.entryForPlaybackBar(i);
      final db = loadedBeatmap.entryForPlaybackBar(i);
      expect(db.playbackBarIndex, mem.playbackBarIndex, reason: 'pb $i');
      expect(db.barLabel, mem.barLabel, reason: 'pb $i label');
      expect(db.barKind, mem.barKind, reason: 'pb $i kind');
      expect(db.bpm, mem.bpm, reason: 'pb $i bpm');
      expect(db.beatsPerBar, mem.beatsPerBar, reason: 'pb $i beatsPerBar');
      expect(db.beatUnit, mem.beatUnit, reason: 'pb $i beatUnit');
      expect(db.subdivision, mem.subdivision, reason: 'pb $i subdivision');
      expect(
        db.accentPattern.length,
        mem.accentPattern.length,
        reason: 'pb $i accentPattern length',
      );
      expect(db.events.length, mem.events.length, reason: 'pb $i events');
      expect(
        db.audioCueTriggers.length,
        mem.audioCueTriggers.length,
        reason: 'pb $i triggers',
      );
    }
  });

  test('beatmap events persist tempo change metadata', () async {
    final song = Song(
      id: 'song-1',
      title: 'Event Metadata Test',
      createdAt: DateTime.utc(2024),
      startBpm: 100,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 4,
      tempoChanges: const [
        SongTempoChange(
          id: 'tempo-1',
          barIndex: 2,
          bpm: 160,
          beatsPerBar: 7,
          beatUnit: 8,
        ),
      ],
    );

    await dao.saveSong(song);
    await dao.regenerateBeatmap(song.id);
    final beatmap = await dao.getSongBeatmap(song.id);

    final bar2 = beatmap.entryForPlaybackBar(2);
    expect(bar2.events, isNotEmpty);
    final tempoEvent = bar2.events.firstWhere(
      (e) => e.kind == SongBeatmapEventKind.tempoChange,
    );
    expect(tempoEvent.bpm, 160);
    expect(tempoEvent.beatsPerBar, 7);
    expect(tempoEvent.beatUnit, 8);
  });

  test('second save with updated tempo change updates beatmap', () async {
    final originalSong = Song(
      id: 'song-1',
      title: 'Update Test',
      createdAt: DateTime.utc(2024),
      startBpm: 100,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 4,
      tempoChanges: const [],
    );

    await dao.saveSong(originalSong);
    await dao.regenerateBeatmap(originalSong.id);
    final beatmapBefore = await dao.getSongBeatmap(originalSong.id);

    // All bars should be 4/4 @ 100 BPM
    for (var i = 1; i <= 4; i++) {
      expect(beatmapBefore.entryForPlaybackBar(i).beatsPerBar, 4);
      expect(beatmapBefore.entryForPlaybackBar(i).bpm, 100);
    }

    // Add a tempo change at bar 2
    final updatedSong = Song(
      id: 'song-1',
      title: 'Update Test',
      createdAt: DateTime.utc(2024),
      startBpm: 100,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 0,
      endBar: 4,
      tempoChanges: const [
        SongTempoChange(
          id: 'tempo-1',
          barIndex: 2,
          bpm: 180,
          beatsPerBar: 6,
          beatUnit: 8,
        ),
      ],
    );

    await dao.saveSong(updatedSong);
    await dao.regenerateBeatmap(updatedSong.id);
    final beatmapAfter = await dao.getSongBeatmap(updatedSong.id);

    expect(beatmapAfter.entryForPlaybackBar(1).beatsPerBar, 4);
    expect(beatmapAfter.entryForPlaybackBar(1).bpm, 100);

    for (var i = 2; i <= 4; i++) {
      expect(
        beatmapAfter.entryForPlaybackBar(i).beatsPerBar,
        6,
        reason: 'bar $i beatsPerBar after update',
      );
      expect(
        beatmapAfter.entryForPlaybackBar(i).bpm,
        180,
        reason: 'bar $i bpm after update',
      );
    }
  });
}
