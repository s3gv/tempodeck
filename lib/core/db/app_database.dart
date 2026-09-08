import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/accent_level.dart';
import '../domain/audio_cue.dart';
import '../domain/click_sound_set.dart';
import '../domain/interval_settings.dart';
import '../domain/linked_audio_file.dart';
import '../domain/metronome_preset.dart' as domain;
import '../domain/setlist.dart' as domain;
import '../domain/song.dart' as domain;
import '../domain/song_beatmap.dart' as beatmap_domain;
import '../domain/subdivision.dart';
import '../audio/song_playback_beatmap.dart';

part 'app_database.g.dart';

@DataClassName('MetronomePresetRow')
class MetronomePresets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get bpm => integer()();
  IntColumn get beatsPerBar => integer()();
  IntColumn get beatUnit => integer()();
  TextColumn get subdivision => text()();
  TextColumn get clickSoundSet => text().withDefault(const Constant('tock'))();
  IntColumn get masterVolumePercent =>
      integer().withDefault(const Constant(100))();
  TextColumn get accentPatternJson => text().named('accent_pattern_json')();
  IntColumn get intervalMilliseconds => integer().nullable()();
  BoolColumn get intervalBpmStepEnabled => boolean().nullable()();
  IntColumn get intervalBpmStep => integer().nullable()();
  IntColumn get intervalMaxDurationMilliseconds => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SongRow')
class Songs extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get startBpm => integer()();
  IntColumn get beatsPerBar => integer()();
  IntColumn get beatUnit => integer()();
  IntColumn get countInBars => integer()();
  IntColumn get endBar => integer()();
  TextColumn get linkedAudioFilePath => text().nullable()();
  TextColumn get linkedAudioDisplayName => text().nullable()();
  IntColumn get linkedAudioOffsetMilliseconds => integer().nullable()();
  IntColumn get linkedAudioVolumePercent => integer().nullable()();
  BoolColumn get linkedAudioPlayInLiveMode => boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SongTempoChangeRow')
class SongTempoChanges extends Table {
  TextColumn get id => text()();
  TextColumn get songId =>
      text().references(Songs, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer()();
  IntColumn get barIndex => integer()();
  IntColumn get bpm => integer()();
  IntColumn get beatsPerBar => integer()();
  IntColumn get beatUnit => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SongLoopRow')
class SongLoops extends Table {
  TextColumn get id => text()();
  TextColumn get songId =>
      text().references(Songs, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer()();
  IntColumn get startBar => integer()();
  IntColumn get endBar => integer()();
  IntColumn get repeatCount => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SongLoopAlternativeEndingRow')
class SongLoopAlternativeEndings extends Table {
  TextColumn get id => text()();
  TextColumn get loopId =>
      text().references(SongLoops, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer()();
  IntColumn get repeatPass => integer()();
  IntColumn get lengthBars => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SongAlternativeEndingTempoChangeRow')
class SongAlternativeEndingTempoChanges extends Table {
  TextColumn get id => text()();
  TextColumn get alternativeEndingId => text().references(
        SongLoopAlternativeEndings,
        #id,
        onDelete: KeyAction.cascade,
      )();
  IntColumn get sortOrder => integer()();
  IntColumn get barIndex => integer()();
  IntColumn get bpm => integer()();
  IntColumn get beatsPerBar => integer()();
  IntColumn get beatUnit => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SongAlternativeEndingEventRow')
class SongAlternativeEndingEvents extends Table {
  TextColumn get id => text()();
  TextColumn get alternativeEndingId => text().references(
        SongLoopAlternativeEndings,
        #id,
        onDelete: KeyAction.cascade,
      )();
  IntColumn get sortOrder => integer()();
  IntColumn get barIndex => integer()();
  TextColumn get label => text()();
  TextColumn get audioCueType => text().nullable()();
  TextColumn get audioCueVoiceText => text().nullable()();
  TextColumn get audioCueVoiceIdentifier => text().nullable()();
  TextColumn get audioCueCustomFilePath => text().nullable()();
  TextColumn get audioCueCustomFileDisplayName => text().nullable()();

  IntColumn get audioCueVolumePercent => integer().nullable()();
  IntColumn get audioCueBarsBefore => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SongAlternativeEndingBeatPatternRow')
class SongAlternativeEndingBeatPatterns extends Table {
  TextColumn get id => text()();
  TextColumn get alternativeEndingId => text().references(
        SongLoopAlternativeEndings,
        #id,
        onDelete: KeyAction.cascade,
      )();
  IntColumn get sortOrder => integer()();
  IntColumn get barIndex => integer()();
  TextColumn get accentsJson => text().named('accents_json')();
  TextColumn get subdivision => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SongEventRow')
class SongEvents extends Table {
  TextColumn get id => text()();
  TextColumn get songId =>
      text().references(Songs, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer()();
  IntColumn get barIndex => integer()();
  TextColumn get label => text()();
  TextColumn get audioCueType => text().nullable()();
  TextColumn get audioCueVoiceText => text().nullable()();
  TextColumn get audioCueVoiceIdentifier => text().nullable()();
  TextColumn get audioCueCustomFilePath => text().nullable()();
  TextColumn get audioCueCustomFileDisplayName => text().nullable()();

  IntColumn get audioCueVolumePercent => integer().nullable()();
  IntColumn get audioCueBarsBefore => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SongBarBeatPatternRow')
class SongBarBeatPatterns extends Table {
  TextColumn get id => text()();
  TextColumn get songId =>
      text().references(Songs, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer()();
  IntColumn get barIndex => integer()();
  TextColumn get accentsJson => text().named('accents_json')();
  TextColumn get subdivision => text()();
  IntColumn get repeatPass => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SongBeatmapEntryRow')
class SongBeatmapEntries extends Table {
  TextColumn get id => text()();
  TextColumn get songId =>
      text().references(Songs, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer()();
  IntColumn get playbackBarIndex => integer()();
  TextColumn get barLabel => text()();
  TextColumn get barKind => text()();
  IntColumn get repeatPass => integer()();
  IntColumn get notationBarIndex => integer().nullable()();
  TextColumn get loopId => text().nullable()();
  TextColumn get alternativeEndingId => text().nullable()();
  IntColumn get alternativeEndingBarIndex => integer().nullable()();
  IntColumn get bpm => integer()();
  IntColumn get beatsPerBar => integer()();
  IntColumn get beatUnit => integer()();
  TextColumn get subdivision => text()();
  TextColumn get accentPatternJson => text().named('accent_pattern_json')();
  TextColumn get eventsJson => text().named('events_json')();
  TextColumn get audioCueTriggersJson => text().named('audio_cue_triggers_json')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SetlistRow')
class Setlists extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SetlistItemRow')
class SetlistItems extends Table {
  TextColumn get id => text()();
  TextColumn get setlistId =>
      text().references(Setlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer()();
  // Intentionally no foreign key: setlist items keep a snapshot song reference
  // plus denormalized title so setlists survive song deletion.
  TextColumn get songId => text()();
  TextColumn get songTitle => text()();
  BoolColumn get playbackEnabled => boolean()();
  BoolColumn get playAttachedAudio => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SetlistTransitionStepRow')
class SetlistTransitionSteps extends Table {
  TextColumn get id => text()();
  TextColumn get setlistItemId =>
      text().references(SetlistItems, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer()();
  TextColumn get type => text()();
  IntColumn get value => integer()();
  TextColumn get audioCueType => text().nullable()();
  TextColumn get audioCueVoiceText => text().nullable()();
  TextColumn get audioCueVoiceIdentifier => text().nullable()();
  TextColumn get audioCueCustomFilePath => text().nullable()();
  TextColumn get audioCueCustomFileDisplayName => text().nullable()();

  IntColumn get audioCueVolumePercent => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftAccessor(
  tables: [
    Songs,
    SongTempoChanges,
    SongLoops,
    SongLoopAlternativeEndings,
    SongAlternativeEndingTempoChanges,
    SongAlternativeEndingEvents,
    SongAlternativeEndingBeatPatterns,
    SongEvents,
    SongBarBeatPatterns,
    SongBeatmapEntries,
  ],
)
class SongDao extends DatabaseAccessor<AppDatabase> with _$SongDaoMixin {
  SongDao(super.attachedDatabase);

  Future<List<domain.Song>> getAllSongs() async {
    final rows = await (select(songs)
          ..orderBy([
            (table) => OrderingTerm.desc(table.createdAt),
            (table) => OrderingTerm.asc(table.id),
          ]))
        .get();
    return Future.wait(rows.map(_loadSongFromRow));
  }

  Stream<List<domain.Song>> watchAllSongs() {
    final query = select(songs)
      ..orderBy([
        (table) => OrderingTerm.desc(table.createdAt),
        (table) => OrderingTerm.asc(table.id),
      ]);
    return query.watch().asyncMap(
          (rows) => Future.wait(rows.map(_loadSongFromRow)),
        );
  }

  Future<domain.Song?> getSongById(String songId) async {
    final row = await (select(songs)..where((table) => table.id.equals(songId)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }

    return _loadSongFromRow(row);
  }

  Stream<domain.Song?> watchSongById(String songId) {
    final query = select(songs)..where((table) => table.id.equals(songId));
    return query.watchSingleOrNull().asyncMap((row) {
      if (row == null) {
        return Future<domain.Song?>.value(null);
      }

      return _loadSongFromRow(row);
    });
  }

  Future<void> saveSong(domain.Song song) {
    return transaction(() async {
      await into(songs).insertOnConflictUpdate(_songCompanion(song));
      await _replaceTempoChanges(song);
      await _replaceLoops(song);
      await _replaceEvents(song);
      await _replaceBeatPatterns(song);
    });
  }

  Future<void> regenerateBeatmap(String songId) {
    return transaction(() async {
      final song = await getSongById(songId);
      if (song == null) {
        throw StateError('Cannot regenerate beatmap: song not found ($songId)');
      }
      await _replaceBeatmap(song);
    });
  }

  Future<void> deleteSong(String songId) {
    return (delete(songs)..where((table) => table.id.equals(songId))).go();
  }

  Future<void> _replaceTempoChanges(domain.Song song) async {
    await (delete(songTempoChanges)
          ..where((table) => table.songId.equals(song.id)))
        .go();
    await batch((batch) {
      batch.insertAll(
        songTempoChanges,
        [
          for (var index = 0; index < song.tempoChanges.length; index += 1)
            SongTempoChangesCompanion.insert(
              id: song.tempoChanges[index].id,
              songId: song.id,
              sortOrder: index,
              barIndex: song.tempoChanges[index].barIndex,
              bpm: song.tempoChanges[index].bpm,
              beatsPerBar: song.tempoChanges[index].beatsPerBar,
              beatUnit: song.tempoChanges[index].beatUnit,
            ),
        ],
      );
    });
  }

  Future<void> _replaceLoops(domain.Song song) async {
    await (delete(songLoops)..where((table) => table.songId.equals(song.id)))
        .go();
    await batch((batch) {
      batch.insertAll(
        songLoops,
        [
          for (var index = 0; index < song.loops.length; index += 1)
            SongLoopsCompanion.insert(
              id: song.loops[index].id,
              songId: song.id,
              sortOrder: index,
              startBar: song.loops[index].startBar,
              endBar: song.loops[index].endBar,
              repeatCount: song.loops[index].repeatCount,
            ),
        ],
      );
    });
    await _replaceAlternativeEndings(song);
  }

  Future<void> _replaceAlternativeEndings(domain.Song song) async {
    final alternativeEndings = <SongLoopAlternativeEndingsCompanion>[];
    final tempoChanges = <SongAlternativeEndingTempoChangesCompanion>[];
    final events = <SongAlternativeEndingEventsCompanion>[];
    final beatPatterns = <SongAlternativeEndingBeatPatternsCompanion>[];

    for (var loopIndex = 0; loopIndex < song.loops.length; loopIndex += 1) {
      final loop = song.loops[loopIndex];
      for (var endingIndex = 0;
          endingIndex < loop.alternativeEndings.length;
          endingIndex += 1) {
        final alternativeEnding = loop.alternativeEndings[endingIndex];
        alternativeEndings.add(
          SongLoopAlternativeEndingsCompanion.insert(
            id: alternativeEnding.id,
            loopId: loop.id,
            sortOrder: endingIndex,
            repeatPass: alternativeEnding.repeatPass,
            lengthBars: alternativeEnding.lengthBars,
          ),
        );

        for (var changeIndex = 0;
            changeIndex < alternativeEnding.tempoChanges.length;
            changeIndex += 1) {
          final change = alternativeEnding.tempoChanges[changeIndex];
          tempoChanges.add(
            SongAlternativeEndingTempoChangesCompanion.insert(
              id: change.id,
              alternativeEndingId: alternativeEnding.id,
              sortOrder: changeIndex,
              barIndex: change.barIndex,
              bpm: change.bpm,
              beatsPerBar: change.beatsPerBar,
              beatUnit: change.beatUnit,
            ),
          );
        }

        for (var eventIndex = 0;
            eventIndex < alternativeEnding.songEvents.length;
            eventIndex += 1) {
          events.add(
            _alternativeEndingEventCompanion(
              alternativeEndingId: alternativeEnding.id,
              songEvent: alternativeEnding.songEvents[eventIndex],
              sortOrder: eventIndex,
            ),
          );
        }

        for (var patternIndex = 0;
            patternIndex < alternativeEnding.beatPatterns.length;
            patternIndex += 1) {
          final pattern = alternativeEnding.beatPatterns[patternIndex];
          beatPatterns.add(
            SongAlternativeEndingBeatPatternsCompanion.insert(
              id: pattern.id,
              alternativeEndingId: alternativeEnding.id,
              sortOrder: patternIndex,
              barIndex: pattern.barIndex,
              accentsJson: _encodeAccentLevels(pattern.accents),
              subdivision: pattern.subdivision.name,
            ),
          );
        }
      }
    }

    await batch((batch) {
      batch.insertAll(songLoopAlternativeEndings, alternativeEndings);
      batch.insertAll(songAlternativeEndingTempoChanges, tempoChanges);
      batch.insertAll(songAlternativeEndingEvents, events);
      batch.insertAll(songAlternativeEndingBeatPatterns, beatPatterns);
    });
  }

  Future<void> _replaceEvents(domain.Song song) async {
    await (delete(songEvents)..where((table) => table.songId.equals(song.id)))
        .go();
    await batch((batch) {
      batch.insertAll(
        songEvents,
        [
          for (var index = 0; index < song.songEvents.length; index += 1)
            _songEventCompanion(
              songId: song.id,
              songEvent: song.songEvents[index],
              sortOrder: index,
            ),
        ],
      );
    });
  }

  Future<void> _replaceBeatPatterns(domain.Song song) async {
    await (delete(songBarBeatPatterns)
          ..where((table) => table.songId.equals(song.id)))
        .go();
    await batch((batch) {
      batch.insertAll(
        songBarBeatPatterns,
        [
          for (var index = 0; index < song.beatPatterns.length; index += 1)
            SongBarBeatPatternsCompanion.insert(
              id: song.beatPatterns[index].id,
              songId: song.id,
              sortOrder: index,
              barIndex: song.beatPatterns[index].barIndex,
              accentsJson:
                  _encodeAccentLevels(song.beatPatterns[index].accents),
              subdivision: song.beatPatterns[index].subdivision.name,
              repeatPass: Value(song.beatPatterns[index].repeatPass),
            ),
        ],
      );
    });
  }

  Future<void> _replaceBeatmap(domain.Song song) async {
    await (delete(songBeatmapEntries)
          ..where((table) => table.songId.equals(song.id)))
        .go();
    final beatmap = const SongPlaybackBeatmapBuilder().build(song);
    await batch((batch) {
      batch.insertAll(
        songBeatmapEntries,
        [
          for (var index = 0; index < beatmap.entries.length; index += 1)
            SongBeatmapEntriesCompanion.insert(
              id: '${song.id}:${beatmap.entries[index].playbackBarIndex}',
              songId: song.id,
              sortOrder: index,
              playbackBarIndex: beatmap.entries[index].playbackBarIndex,
              barLabel: beatmap.entries[index].barLabel,
              barKind: beatmap.entries[index].barKind.name,
              repeatPass: beatmap.entries[index].repeatPass,
              notationBarIndex:
                  Value(beatmap.entries[index].notationBarIndex),
              loopId: Value(beatmap.entries[index].loopId),
              alternativeEndingId:
                  Value(beatmap.entries[index].alternativeEndingId),
              alternativeEndingBarIndex:
                  Value(beatmap.entries[index].alternativeEndingBarIndex),
              bpm: beatmap.entries[index].bpm,
              beatsPerBar: beatmap.entries[index].beatsPerBar,
              beatUnit: beatmap.entries[index].beatUnit,
              subdivision: beatmap.entries[index].subdivision.name,
              accentPatternJson:
                  _encodeAccentLevels(beatmap.entries[index].accentPattern),
              eventsJson: _encodeBeatmapEvents(beatmap.entries[index].events),
              audioCueTriggersJson: _encodeAudioCueTriggers(
                beatmap.entries[index].audioCueTriggers,
              ),
            ),
        ],
      );
    });
  }

  Future<domain.Song> _loadSongFromRow(SongRow row) async {
    final tempoRows = await _tempoChangeRows(row.id);
    final loopRows = await _loopRows(row.id);
    final alternativeEndingRows = await _alternativeEndingRows(row.id);
    final alternativeEndingTempoRows =
        await _alternativeEndingTempoRows(row.id);
    final alternativeEndingEventRows =
        await _alternativeEndingEventRows(row.id);
    final alternativeEndingBeatPatternRows =
        await _alternativeEndingBeatPatternRows(row.id);
    final eventRows = await _eventRows(row.id);
    final beatPatternRows = await _beatPatternRows(row.id);
    final alternativeEndingsByLoopId = _groupAlternativeEndingsByLoopId(
      alternativeEndingRows: alternativeEndingRows,
      tempoRows: alternativeEndingTempoRows,
      eventRows: alternativeEndingEventRows,
      beatPatternRows: alternativeEndingBeatPatternRows,
    );

    return domain.Song(
      id: row.id,
      title: row.title,
      createdAt: row.createdAt,
      startBpm: row.startBpm,
      beatsPerBar: row.beatsPerBar,
      beatUnit: row.beatUnit,
      countInBars: row.countInBars,
      endBar: row.endBar,
      tempoChanges: [for (final item in tempoRows) _mapTempoChange(item)],
      loops: [
        for (final item in loopRows)
          _mapLoop(
            item,
            alternativeEndings: alternativeEndingsByLoopId[item.id] ?? const [],
          ),
      ],
      songEvents: [for (final item in eventRows) _mapSongEvent(item)],
      beatPatterns: [
        for (final item in beatPatternRows) _mapBeatPattern(item),
      ],
      linkedAudio: _mapLinkedAudio(row),
    );
  }

  Future<List<SongTempoChangeRow>> _tempoChangeRows(String songId) {
    return (select(songTempoChanges)
          ..where((table) => table.songId.equals(songId))
          ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
        .get();
  }

  Future<List<SongLoopRow>> _loopRows(String songId) {
    return (select(songLoops)
          ..where((table) => table.songId.equals(songId))
          ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
        .get();
  }

  Future<List<SongLoopAlternativeEndingRow>> _alternativeEndingRows(
    String songId,
  ) {
    final query = select(songLoopAlternativeEndings).join([
      innerJoin(
        songLoops,
        songLoops.id.equalsExp(songLoopAlternativeEndings.loopId),
      ),
    ])
      ..where(songLoops.songId.equals(songId))
      ..orderBy([
        OrderingTerm.asc(songLoops.sortOrder),
        OrderingTerm.asc(songLoopAlternativeEndings.sortOrder),
      ]);
    return query.map((row) => row.readTable(songLoopAlternativeEndings)).get();
  }

  Future<List<SongAlternativeEndingTempoChangeRow>> _alternativeEndingTempoRows(
    String songId,
  ) {
    final query = select(songAlternativeEndingTempoChanges).join([
      innerJoin(
        songLoopAlternativeEndings,
        songLoopAlternativeEndings.id.equalsExp(
          songAlternativeEndingTempoChanges.alternativeEndingId,
        ),
      ),
      innerJoin(
        songLoops,
        songLoops.id.equalsExp(songLoopAlternativeEndings.loopId),
      ),
    ])
      ..where(songLoops.songId.equals(songId))
      ..orderBy([
        OrderingTerm.asc(songLoops.sortOrder),
        OrderingTerm.asc(songLoopAlternativeEndings.sortOrder),
        OrderingTerm.asc(songAlternativeEndingTempoChanges.sortOrder),
      ]);
    return query
        .map((row) => row.readTable(songAlternativeEndingTempoChanges))
        .get();
  }

  Future<List<SongAlternativeEndingEventRow>> _alternativeEndingEventRows(
    String songId,
  ) {
    final query = select(songAlternativeEndingEvents).join([
      innerJoin(
        songLoopAlternativeEndings,
        songLoopAlternativeEndings.id.equalsExp(
          songAlternativeEndingEvents.alternativeEndingId,
        ),
      ),
      innerJoin(
        songLoops,
        songLoops.id.equalsExp(songLoopAlternativeEndings.loopId),
      ),
    ])
      ..where(songLoops.songId.equals(songId))
      ..orderBy([
        OrderingTerm.asc(songLoops.sortOrder),
        OrderingTerm.asc(songLoopAlternativeEndings.sortOrder),
        OrderingTerm.asc(songAlternativeEndingEvents.sortOrder),
      ]);
    return query.map((row) => row.readTable(songAlternativeEndingEvents)).get();
  }

  Future<List<SongAlternativeEndingBeatPatternRow>>
      _alternativeEndingBeatPatternRows(String songId) {
    final query = select(songAlternativeEndingBeatPatterns).join([
      innerJoin(
        songLoopAlternativeEndings,
        songLoopAlternativeEndings.id.equalsExp(
          songAlternativeEndingBeatPatterns.alternativeEndingId,
        ),
      ),
      innerJoin(
        songLoops,
        songLoops.id.equalsExp(songLoopAlternativeEndings.loopId),
      ),
    ])
      ..where(songLoops.songId.equals(songId))
      ..orderBy([
        OrderingTerm.asc(songLoops.sortOrder),
        OrderingTerm.asc(songLoopAlternativeEndings.sortOrder),
        OrderingTerm.asc(songAlternativeEndingBeatPatterns.sortOrder),
      ]);
    return query
        .map((row) => row.readTable(songAlternativeEndingBeatPatterns))
        .get();
  }

  Future<List<SongEventRow>> _eventRows(String songId) {
    return (select(songEvents)
          ..where((table) => table.songId.equals(songId))
          ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
        .get();
  }

  Future<List<SongBarBeatPatternRow>> _beatPatternRows(String songId) {
    return (select(songBarBeatPatterns)
          ..where((table) => table.songId.equals(songId))
          ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
        .get();
  }

  Future<beatmap_domain.SongBeatmap> getSongBeatmap(String songId) async {
    final rows = await (select(songBeatmapEntries)
          ..where((table) => table.songId.equals(songId))
          ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
        .get();
    if (rows.isEmpty) {
      throw StateError('Beatmap not found for song: $songId');
    }

    return beatmap_domain.SongBeatmap(
      entries: [
        for (final row in rows) _mapBeatmapEntry(row),
      ],
    );
  }

  SongsCompanion _songCompanion(domain.Song song) {
    final linkedAudio = song.linkedAudio;
    return SongsCompanion.insert(
      id: song.id,
      title: song.title,
      createdAt: song.createdAt,
      startBpm: song.startBpm,
      beatsPerBar: song.beatsPerBar,
      beatUnit: song.beatUnit,
      countInBars: song.countInBars,
      endBar: song.endBar,
      linkedAudioFilePath: Value(linkedAudio?.filePath),
      linkedAudioDisplayName: Value(linkedAudio?.displayName),

      linkedAudioOffsetMilliseconds: Value(linkedAudio?.offsetMilliseconds),
      linkedAudioVolumePercent: Value(linkedAudio?.volumePercent),
      linkedAudioPlayInLiveMode: Value(linkedAudio?.playInLiveMode),
    );
  }

  SongEventsCompanion _songEventCompanion({
    required String songId,
    required domain.SongEvent songEvent,
    required int sortOrder,
  }) {
    final audioCue = songEvent.audioCue;
    return SongEventsCompanion.insert(
      id: songEvent.id,
      songId: songId,
      sortOrder: sortOrder,
      barIndex: songEvent.barIndex,
      label: songEvent.label,
      audioCueType: Value(audioCue?.type.name),
      audioCueVoiceText: Value(audioCue?.voiceText),
      audioCueVoiceIdentifier: Value(audioCue?.voiceIdentifier),
      audioCueCustomFilePath: Value(audioCue?.customFilePath),
      audioCueCustomFileDisplayName: Value(audioCue?.customFileDisplayName),

      audioCueVolumePercent: Value(audioCue?.volumePercent),
      audioCueBarsBefore: songEvent.audioCueBarsBefore,
    );
  }

  SongAlternativeEndingEventsCompanion _alternativeEndingEventCompanion({
    required String alternativeEndingId,
    required domain.SongEvent songEvent,
    required int sortOrder,
  }) {
    final audioCue = songEvent.audioCue;
    return SongAlternativeEndingEventsCompanion.insert(
      id: songEvent.id,
      alternativeEndingId: alternativeEndingId,
      sortOrder: sortOrder,
      barIndex: songEvent.barIndex,
      label: songEvent.label,
      audioCueType: Value(audioCue?.type.name),
      audioCueVoiceText: Value(audioCue?.voiceText),
      audioCueVoiceIdentifier: Value(audioCue?.voiceIdentifier),
      audioCueCustomFilePath: Value(audioCue?.customFilePath),
      audioCueCustomFileDisplayName: Value(audioCue?.customFileDisplayName),

      audioCueVolumePercent: Value(audioCue?.volumePercent),
      audioCueBarsBefore: songEvent.audioCueBarsBefore,
    );
  }

  domain.SongTempoChange _mapTempoChange(SongTempoChangeRow row) {
    return domain.SongTempoChange(
      id: row.id,
      barIndex: row.barIndex,
      bpm: row.bpm,
      beatsPerBar: row.beatsPerBar,
      beatUnit: row.beatUnit,
    );
  }

  domain.SongLoop _mapLoop(
    SongLoopRow row, {
    required List<domain.SongLoopAlternativeEnding> alternativeEndings,
  }) {
    return domain.SongLoop(
      id: row.id,
      startBar: row.startBar,
      endBar: row.endBar,
      repeatCount: row.repeatCount,
      alternativeEndings: alternativeEndings,
    );
  }

  domain.SongEvent _mapSongEvent(SongEventRow row) {
    return domain.SongEvent(
      id: row.id,
      barIndex: row.barIndex,
      label: row.label,
      audioCue: _mapAudioCue(
        typeName: row.audioCueType,
        voiceText: row.audioCueVoiceText,
        voiceIdentifier: row.audioCueVoiceIdentifier,
        customFilePath: row.audioCueCustomFilePath,
        customFileDisplayName: row.audioCueCustomFileDisplayName,
        volumePercent: row.audioCueVolumePercent,
      ),
      audioCueBarsBefore: row.audioCueBarsBefore,
    );
  }

  domain.SongBarBeatPattern _mapBeatPattern(SongBarBeatPatternRow row) {
    return domain.SongBarBeatPattern(
      id: row.id,
      barIndex: row.barIndex,
      accents: _decodeAccentLevels(row.accentsJson),
      subdivision: Subdivision.values.byName(row.subdivision),
      repeatPass: row.repeatPass,
    );
  }

  Map<String, List<domain.SongLoopAlternativeEnding>>
      _groupAlternativeEndingsByLoopId({
    required List<SongLoopAlternativeEndingRow> alternativeEndingRows,
    required List<SongAlternativeEndingTempoChangeRow> tempoRows,
    required List<SongAlternativeEndingEventRow> eventRows,
    required List<SongAlternativeEndingBeatPatternRow> beatPatternRows,
  }) {
    final temposByEndingId = <String, List<domain.SongTempoChange>>{};
    for (final row in tempoRows) {
      temposByEndingId.putIfAbsent(row.alternativeEndingId, () => []).add(
            domain.SongTempoChange(
              id: row.id,
              barIndex: row.barIndex,
              bpm: row.bpm,
              beatsPerBar: row.beatsPerBar,
              beatUnit: row.beatUnit,
            ),
          );
    }

    final eventsByEndingId = <String, List<domain.SongEvent>>{};
    for (final row in eventRows) {
      eventsByEndingId.putIfAbsent(row.alternativeEndingId, () => []).add(
            _mapSongEvent(
              SongEventRow(
                id: row.id,
                songId: '',
                sortOrder: row.sortOrder,
                barIndex: row.barIndex,
                label: row.label,
                audioCueType: row.audioCueType,
                audioCueVoiceText: row.audioCueVoiceText,
                audioCueVoiceIdentifier: row.audioCueVoiceIdentifier,
                audioCueCustomFilePath: row.audioCueCustomFilePath,
                audioCueCustomFileDisplayName: row.audioCueCustomFileDisplayName,
                audioCueVolumePercent: row.audioCueVolumePercent,
                audioCueBarsBefore: row.audioCueBarsBefore,
              ),
            ),
          );
    }

    final beatPatternsByEndingId = <String, List<domain.SongBarBeatPattern>>{};
    for (final row in beatPatternRows) {
      beatPatternsByEndingId.putIfAbsent(row.alternativeEndingId, () => []).add(
            domain.SongBarBeatPattern(
              id: row.id,
              barIndex: row.barIndex,
              accents: _decodeAccentLevels(row.accentsJson),
              subdivision: Subdivision.values.byName(row.subdivision),
            ),
          );
    }

    final grouped = <String, List<domain.SongLoopAlternativeEnding>>{};
    for (final row in alternativeEndingRows) {
      grouped.putIfAbsent(row.loopId, () => []).add(
            domain.SongLoopAlternativeEnding(
              id: row.id,
              repeatPass: row.repeatPass,
              lengthBars: row.lengthBars,
              tempoChanges: temposByEndingId[row.id] ?? const [],
              songEvents: eventsByEndingId[row.id] ?? const [],
              beatPatterns: beatPatternsByEndingId[row.id] ?? const [],
            ),
          );
    }
    return grouped;
  }

  beatmap_domain.SongBeatmapEntry _mapBeatmapEntry(SongBeatmapEntryRow row) {
    return beatmap_domain.SongBeatmapEntry(
      playbackBarIndex: row.playbackBarIndex,
      barLabel: row.barLabel,
      barKind: beatmap_domain.SongBeatmapBarKind.values.byName(row.barKind),
      repeatPass: row.repeatPass,
      notationBarIndex: row.notationBarIndex,
      loopId: row.loopId,
      alternativeEndingId: row.alternativeEndingId,
      alternativeEndingBarIndex: row.alternativeEndingBarIndex,
      bpm: row.bpm,
      beatsPerBar: row.beatsPerBar,
      beatUnit: row.beatUnit,
      subdivision: Subdivision.values.byName(row.subdivision),
      accentPattern: _decodeAccentLevels(row.accentPatternJson),
      events: _decodeBeatmapEvents(row.eventsJson),
      audioCueTriggers: _decodeAudioCueTriggers(row.audioCueTriggersJson),
    );
  }

  LinkedAudioFile? _mapLinkedAudio(SongRow row) {
    if (row.linkedAudioFilePath == null || row.linkedAudioDisplayName == null) {
      return null;
    }

    return LinkedAudioFile(
      filePath: row.linkedAudioFilePath!,
      displayName: row.linkedAudioDisplayName!,
      offsetMilliseconds: row.linkedAudioOffsetMilliseconds ?? 0,
      volumePercent: row.linkedAudioVolumePercent ?? 100,
      playInLiveMode: row.linkedAudioPlayInLiveMode ?? true,
    );
  }
}

@DriftAccessor(
  tables: [
    Setlists,
    SetlistItems,
    SetlistTransitionSteps,
  ],
)
class SetlistDao extends DatabaseAccessor<AppDatabase> with _$SetlistDaoMixin {
  SetlistDao(super.attachedDatabase);

  Future<List<domain.Setlist>> getAllSetlists() async {
    final rows = await (select(setlists)
          ..orderBy([
            (table) => OrderingTerm.desc(table.createdAt),
            (table) => OrderingTerm.asc(table.id),
          ]))
        .get();
    return Future.wait(rows.map(_loadSetlistFromRow));
  }

  Stream<List<domain.Setlist>> watchAllSetlists() {
    final query = select(setlists)
      ..orderBy([
        (table) => OrderingTerm.desc(table.createdAt),
        (table) => OrderingTerm.asc(table.id),
      ]);
    return query.watch().asyncMap(
          (rows) => Future.wait(rows.map(_loadSetlistFromRow)),
        );
  }

  Future<domain.Setlist?> getSetlistById(String setlistId) async {
    final row = await (select(setlists)
          ..where((table) => table.id.equals(setlistId)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }

    return _loadSetlistFromRow(row);
  }

  Stream<domain.Setlist?> watchSetlistById(String setlistId) {
    final query = select(setlists)
      ..where((table) => table.id.equals(setlistId));
    return query.watchSingleOrNull().asyncMap((row) {
      if (row == null) {
        return Future<domain.Setlist?>.value(null);
      }

      return _loadSetlistFromRow(row);
    });
  }

  Future<void> saveSetlist(domain.Setlist setlist) {
    return transaction(() async {
      await into(setlists).insertOnConflictUpdate(
        SetlistsCompanion.insert(
          id: setlist.id,
          title: setlist.title,
          createdAt: setlist.createdAt,
        ),
      );
      await _replaceItems(setlist);
    });
  }

  Future<void> deleteSetlist(String setlistId) {
    return (delete(setlists)..where((table) => table.id.equals(setlistId)))
        .go();
  }

  Future<void> _replaceItems(domain.Setlist setlist) async {
    await (delete(setlistItems)
          ..where((table) => table.setlistId.equals(setlist.id)))
        .go();

    await batch((batch) {
      batch.insertAll(
        setlistItems,
        [
          for (var index = 0; index < setlist.items.length; index += 1)
            SetlistItemsCompanion.insert(
              id: setlist.items[index].id,
              setlistId: setlist.id,
              sortOrder: index,
              songId: setlist.items[index].songId,
              songTitle: setlist.items[index].songTitle,
              playbackEnabled: setlist.items[index].playbackEnabled,
              playAttachedAudio: setlist.items[index].playAttachedAudio,
            ),
        ],
      );
    });

    await batch((batch) {
      batch.insertAll(
        setlistTransitionSteps,
        [
          for (var itemIndex = 0;
              itemIndex < setlist.items.length;
              itemIndex += 1)
            for (var stepIndex = 0;
                stepIndex < setlist.items[itemIndex].transitionSteps.length;
                stepIndex += 1)
              _setlistTransitionStepCompanion(
                setlistItemId: setlist.items[itemIndex].id,
                step: setlist.items[itemIndex].transitionSteps[stepIndex],
                sortOrder: stepIndex,
              ),
        ],
      );
    });
  }

  Future<domain.Setlist> _loadSetlistFromRow(SetlistRow row) async {
    final itemRows = await _setlistItemRows(row.id);
    return domain.Setlist(
      id: row.id,
      title: row.title,
      createdAt: row.createdAt,
      items: [
        for (final item in itemRows) await _mapSetlistItem(item),
      ],
    );
  }

  Future<List<SetlistItemRow>> _setlistItemRows(String setlistId) {
    return (select(setlistItems)
          ..where((table) => table.setlistId.equals(setlistId))
          ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
        .get();
  }

  Future<List<SetlistTransitionStepRow>> _transitionStepRows(
    String setlistItemId,
  ) {
    return (select(setlistTransitionSteps)
          ..where((table) => table.setlistItemId.equals(setlistItemId))
          ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
        .get();
  }

  Future<domain.SetlistItem> _mapSetlistItem(SetlistItemRow row) async {
    final stepRows = await _transitionStepRows(row.id);
    return domain.SetlistItem(
      id: row.id,
      songId: row.songId,
      songTitle: row.songTitle,
      playbackEnabled: row.playbackEnabled,
      playAttachedAudio: row.playAttachedAudio,
      transitionSteps: [
        for (final step in stepRows) _mapSetlistTransitionStep(step),
      ],
    );
  }

  SetlistTransitionStepsCompanion _setlistTransitionStepCompanion({
    required String setlistItemId,
    required domain.SetlistTransitionStep step,
    required int sortOrder,
  }) {
    final audioCue = step.audioCue;
    return SetlistTransitionStepsCompanion.insert(
      id: step.id,
      setlistItemId: setlistItemId,
      sortOrder: sortOrder,
      type: step.type.name,
      value: step.value,
      audioCueType: Value(audioCue?.type.name),
      audioCueVoiceText: Value(audioCue?.voiceText),
      audioCueVoiceIdentifier: Value(audioCue?.voiceIdentifier),
      audioCueCustomFilePath: Value(audioCue?.customFilePath),
      audioCueCustomFileDisplayName: Value(audioCue?.customFileDisplayName),

      audioCueVolumePercent: Value(audioCue?.volumePercent),
    );
  }

  domain.SetlistTransitionStep _mapSetlistTransitionStep(
    SetlistTransitionStepRow row,
  ) {
    return domain.SetlistTransitionStep(
      id: row.id,
      type: domain.SetlistTransitionStepType.values.byName(row.type),
      value: row.value,
      audioCue: _mapAudioCue(
        typeName: row.audioCueType,
        voiceText: row.audioCueVoiceText,
        voiceIdentifier: row.audioCueVoiceIdentifier,
        customFilePath: row.audioCueCustomFilePath,
        customFileDisplayName: row.audioCueCustomFileDisplayName,
        volumePercent: row.audioCueVolumePercent,
      ),
    );
  }
}

@DriftAccessor(tables: [MetronomePresets])
class PresetDao extends DatabaseAccessor<AppDatabase> with _$PresetDaoMixin {
  PresetDao(super.attachedDatabase);

  Future<List<domain.MetronomePreset>> getAllPresets() async {
    final rows = await (select(metronomePresets)
          ..orderBy([
            (table) => OrderingTerm.asc(table.name),
            (table) => OrderingTerm.asc(table.id),
          ]))
        .get();
    return [for (final row in rows) _mapPreset(row)];
  }

  Stream<List<domain.MetronomePreset>> watchAllPresets() {
    final query = select(metronomePresets)
      ..orderBy([
        (table) => OrderingTerm.asc(table.name),
        (table) => OrderingTerm.asc(table.id),
      ]);
    return query.watch().map(
          (rows) => [for (final row in rows) _mapPreset(row)],
        );
  }

  Future<domain.MetronomePreset?> getPresetById(String presetId) async {
    final row = await (select(metronomePresets)
          ..where((table) => table.id.equals(presetId)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }

    return _mapPreset(row);
  }

  Stream<domain.MetronomePreset?> watchPresetById(String presetId) {
    final query = select(metronomePresets)
      ..where((table) => table.id.equals(presetId));
    return query.watchSingleOrNull().map((row) {
      if (row == null) {
        return null;
      }

      return _mapPreset(row);
    });
  }

  Future<void> savePreset(domain.MetronomePreset preset) {
    return into(metronomePresets)
        .insertOnConflictUpdate(_presetCompanion(preset));
  }

  Future<void> deletePreset(String presetId) {
    return (delete(metronomePresets)
          ..where((table) => table.id.equals(presetId)))
        .go();
  }

  MetronomePresetsCompanion _presetCompanion(domain.MetronomePreset preset) {
    final intervalSettings = preset.intervalSettings;
    return MetronomePresetsCompanion.insert(
      id: preset.id,
      name: preset.name,
      bpm: preset.bpm,
      beatsPerBar: preset.beatsPerBar,
      beatUnit: preset.beatUnit,
      subdivision: preset.subdivision.name,
      clickSoundSet: Value(preset.clickSoundSet.name),
      masterVolumePercent: Value(preset.masterVolumePercent),
      accentPatternJson: _encodeAccentLevels(preset.accentPattern),
      intervalMilliseconds: Value(intervalSettings?.interval.inMilliseconds),
      intervalBpmStepEnabled: Value(intervalSettings?.bpmStepEnabled),
      intervalBpmStep: Value(intervalSettings?.bpmStep),
      intervalMaxDurationMilliseconds:
          Value(intervalSettings?.maxDuration?.inMilliseconds),
    );
  }

  domain.MetronomePreset _mapPreset(MetronomePresetRow row) {
    return domain.MetronomePreset(
      id: row.id,
      name: row.name,
      bpm: row.bpm,
      beatsPerBar: row.beatsPerBar,
      beatUnit: row.beatUnit,
      subdivision: Subdivision.values.byName(row.subdivision),
      clickSoundSet: ClickSoundSet.values.byName(row.clickSoundSet),
      masterVolumePercent: row.masterVolumePercent,
      accentPattern: _decodeAccentLevels(row.accentPatternJson),
      intervalSettings: _mapIntervalSettings(row),
    );
  }

  IntervalSettings? _mapIntervalSettings(MetronomePresetRow row) {
    if (row.intervalMilliseconds == null) {
      return null;
    }

    return IntervalSettings(
      interval: Duration(milliseconds: row.intervalMilliseconds!),
      bpmStepEnabled: row.intervalBpmStepEnabled ?? false,
      bpmStep: row.intervalBpmStep ?? 5,
      maxDuration: row.intervalMaxDurationMilliseconds == null
          ? null
          : Duration(milliseconds: row.intervalMaxDurationMilliseconds!),
    );
  }
}

@DriftDatabase(
  tables: [
    MetronomePresets,
    Songs,
    SongTempoChanges,
    SongLoops,
    SongLoopAlternativeEndings,
    SongAlternativeEndingTempoChanges,
    SongAlternativeEndingEvents,
    SongAlternativeEndingBeatPatterns,
    SongEvents,
    SongBarBeatPatterns,
    SongBeatmapEntries,
    Setlists,
    SetlistItems,
    SetlistTransitionSteps,
  ],
  daos: [SongDao, SetlistDao, PresetDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
        },
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await customStatement(
              "ALTER TABLE metronome_presets ADD COLUMN click_sound_set TEXT NOT NULL DEFAULT 'tock'",
            );
            await customStatement(
              'ALTER TABLE metronome_presets ADD COLUMN master_volume_percent INTEGER NOT NULL DEFAULT 100',
            );
          }
          if (from < 3) {
            await migrator.createTable(songLoopAlternativeEndings);
            await migrator.createTable(songAlternativeEndingTempoChanges);
            await migrator.createTable(songAlternativeEndingEvents);
            await migrator.createTable(songAlternativeEndingBeatPatterns);
            await migrator.createTable(songBeatmapEntries);
          }
          if (from < 4) {
            await customStatement(
              'ALTER TABLE songs DROP COLUMN linked_audio_bookmark_base64',
            );
            await customStatement(
              'ALTER TABLE song_events DROP COLUMN audio_cue_custom_file_bookmark_base64',
            );
            await customStatement(
              'ALTER TABLE song_alternative_ending_events DROP COLUMN audio_cue_custom_file_bookmark_base64',
            );
            await customStatement(
              'ALTER TABLE setlist_transition_steps DROP COLUMN audio_cue_custom_file_bookmark_base64',
            );
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await _refreshPersistedSongBeatmaps();
        },
      );

  Future<void> _refreshPersistedSongBeatmaps() async {
    final allSongs = await songDao.getAllSongs();
    for (final song in allSongs) {
      await songDao.regenerateBeatmap(song.id);
    }
  }
}

AudioCue? _mapAudioCue({
  required String? typeName,
  required String? voiceText,
  required String? voiceIdentifier,
  required String? customFilePath,
  required String? customFileDisplayName,
  required int? volumePercent,
}) {
  if (typeName == null) {
    return null;
  }

  return AudioCue(
    type: AudioCueType.values.byName(typeName),
    voiceText: voiceText,
    voiceIdentifier: voiceIdentifier,
    customFilePath: customFilePath,
    customFileDisplayName: customFileDisplayName,
    volumePercent: volumePercent ?? 100,
  );
}

String _encodeAccentLevels(List<AccentLevel> accents) {
  return jsonEncode([
    for (final accent in accents) accent.name,
  ]);
}

String _encodeBeatmapEvents(List<beatmap_domain.SongBeatmapEvent> events) {
  return jsonEncode([
    for (final event in events)
      {
        'id': event.id,
        'kind': event.kind.name,
        'label': event.label,
        'barLabel': event.barLabel,
        'bpm': event.bpm,
        'beatsPerBar': event.beatsPerBar,
        'beatUnit': event.beatUnit,
        'loopStartBar': event.loopStartBar,
        'loopEndBar': event.loopEndBar,
        'loopIteration': event.loopIteration,
        'loopTotalIterations': event.loopTotalIterations,
        'sourceBarIndex': event.sourceBarIndex,
      },
  ]);
}

List<beatmap_domain.SongBeatmapEvent> _decodeBeatmapEvents(String encoded) {
  final decoded = _requireList(jsonDecode(encoded), 'Beatmap events');
  return [
    for (final item in decoded)
      beatmap_domain.SongBeatmapEvent(
        id: _requireString(item['id'], 'Beatmap event id'),
        kind: beatmap_domain.SongBeatmapEventKind.values.byName(
          _requireString(item['kind'], 'Beatmap event kind'),
        ),
        label: _requireString(item['label'], 'Beatmap event label'),
        barLabel: _nullableString(item['barLabel']),
        bpm: _nullableInt(item['bpm']),
        beatsPerBar: _nullableInt(item['beatsPerBar']),
        beatUnit: _nullableInt(item['beatUnit']),
        loopStartBar: _nullableInt(item['loopStartBar']),
        loopEndBar: _nullableInt(item['loopEndBar']),
        loopIteration: _nullableInt(item['loopIteration']),
        loopTotalIterations: _nullableInt(item['loopTotalIterations']),
        sourceBarIndex: _nullableInt(item['sourceBarIndex']),
      ),
  ];
}

String _encodeAudioCueTriggers(
  List<beatmap_domain.SongBeatmapAudioCueTrigger> triggers,
) {
  return jsonEncode([
    for (final trigger in triggers)
      {
        'sourceEventId': trigger.sourceEventId,
        'sourceBarLabel': trigger.sourceBarLabel,
        'label': trigger.label,
        'audioCue': _encodeAudioCue(trigger.audioCue),
      },
  ]);
}

List<beatmap_domain.SongBeatmapAudioCueTrigger> _decodeAudioCueTriggers(
  String encoded,
) {
  final decoded = _requireList(jsonDecode(encoded), 'Beatmap cue triggers');
  return [
    for (final item in decoded)
      beatmap_domain.SongBeatmapAudioCueTrigger(
        sourceEventId: _requireString(
          item['sourceEventId'],
          'Beatmap cue trigger sourceEventId',
        ),
        sourceBarLabel: _requireString(
          item['sourceBarLabel'],
          'Beatmap cue trigger sourceBarLabel',
        ),
        label: _requireString(item['label'], 'Beatmap cue trigger label'),
        audioCue: _decodeAudioCue(
          _requireMap(item['audioCue'], 'Beatmap cue trigger audio cue'),
        ),
      ),
  ];
}

List<AccentLevel> _decodeAccentLevels(String encodedAccents) {
  final Object? decoded = jsonDecode(encodedAccents);
  if (decoded is! List<Object?>) {
    throw const FormatException('Accent pattern JSON must decode to a list.');
  }

  return [
    for (final item in decoded)
      AccentLevel.values.byName(_requireString(item, 'Accent pattern item')),
  ];
}

Map<String, Object?> _encodeAudioCue(AudioCue audioCue) {
  return {
    'type': audioCue.type.name,
    'voiceText': audioCue.voiceText,
    'voiceIdentifier': audioCue.voiceIdentifier,
    'customFilePath': audioCue.customFilePath,
    'customFileDisplayName': audioCue.customFileDisplayName,
    'customFileBookmarkBase64': null,
    'volumePercent': audioCue.volumePercent,
  };
}

AudioCue _decodeAudioCue(Map<String, Object?> encoded) {
  return AudioCue(
    type: AudioCueType.values.byName(
      _requireString(encoded['type'], 'AudioCue.type'),
    ),
    voiceText: _nullableString(encoded['voiceText']),
    voiceIdentifier: _nullableString(encoded['voiceIdentifier']),
    customFilePath: _nullableString(encoded['customFilePath']),
    customFileDisplayName: _nullableString(encoded['customFileDisplayName']),
    volumePercent:
        _nullableInt(encoded['volumePercent']) ?? 100,
  );
}

String _requireString(Object? value, String label) {
  if (value is! String) {
    throw FormatException('$label must be a string.');
  }

  return value;
}

List<Map<String, Object?>> _requireList(Object? value, String label) {
  if (value is! List<Object?>) {
    throw FormatException('$label must decode to a list.');
  }

  return [
    for (final item in value) _requireMap(item, '$label item'),
  ];
}

Map<String, Object?> _requireMap(Object? value, String label) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$label must decode to a map.');
  }

  return {
    for (final entry in value.entries)
      _requireString(entry.key, '$label key'): entry.value,
  };
}

String? _nullableString(Object? value) {
  if (value == null) {
    return null;
  }
  return _requireString(value, 'Nullable string');
}

int? _nullableInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  throw const FormatException('Nullable int must be an int.');
}
