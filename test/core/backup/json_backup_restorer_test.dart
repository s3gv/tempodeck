import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/backup/json_backup_restorer.dart';
import 'package:tempodeck/core/db/app_database.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/domain/metronome_preset.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/domain/subdivision.dart';
import 'package:tempodeck/core/repositories/drift_preset_repository.dart';
import 'package:tempodeck/core/repositories/drift_setlist_repository.dart';
import 'package:tempodeck/core/repositories/drift_song_repository.dart';
import 'package:tempodeck/core/repositories/preset_repository.dart';
import 'package:tempodeck/core/repositories/setlist_repository.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';

void main() {
  test('restores songs, setlists, and presets from a backup payload', () async {
    final songRepository = _MemorySongRepository(
      songs: [
        Song(
          id: 'old-song',
          title: 'Old',
          createdAt: DateTime.utc(2026, 3, 1),
          startBpm: 100,
          beatsPerBar: 4,
          beatUnit: 4,
          countInBars: 0,
          endBar: 4,
        ),
      ],
    );
    final setlistRepository = _MemorySetlistRepository(
      setlists: [
        Setlist(
          id: 'old-setlist',
          title: 'Old',
          createdAt: DateTime.utc(2026, 3, 1),
        ),
      ],
    );
    final presetRepository = _MemoryPresetRepository(
      presets: const [
        MetronomePreset(
          id: 'old-preset',
          name: 'Old',
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
          subdivision: Subdivision.one,
          accentPattern: [],
        ),
      ],
    );
    final restorer = JsonBackupRestorer(
      songRepository: songRepository,
      setlistRepository: setlistRepository,
      presetRepository: presetRepository,
      runInTransaction: _runWithoutTransaction,
    );

    await restorer.restoreJson(_validBackupJson);

    final songs = await songRepository.getAllSongs();
    final setlists = await setlistRepository.getAllSetlists();
    final presets = await presetRepository.getAllPresets();

    expect(songs.map((song) => song.id).toList(), ['song-1']);
    expect(setlists.map((setlist) => setlist.id).toList(), ['setlist-1']);
    expect(presets.map((preset) => preset.id).toList(), ['preset-1']);

    final song = songs.single;
    expect(song.linkedAudio, isNotNull);
    expect(song.linkedAudio!.offsetMilliseconds, 3000);
    expect(song.songEvents.single.audioCue!.voiceText, 'Verse');

    final setlist = setlists.single;
    expect(setlist.items.single.transitionSteps[1].audioCue, isNotNull);

    final preset = presets.single;
    expect(preset.clickSoundSet, ClickSoundSet.hype);
    expect(preset.masterVolumePercent, 67);
    expect(preset.intervalSettings, isNotNull);
    expect(preset.intervalSettings!.maxDuration, const Duration(minutes: 5));
  });

  test('rejects unsupported schema versions before mutating repositories',
      () async {
    final songRepository = _MemorySongRepository(
      songs: [
        Song(
          id: 'existing-song',
          title: 'Existing',
          createdAt: DateTime.utc(2026, 3, 1),
          startBpm: 100,
          beatsPerBar: 4,
          beatUnit: 4,
          countInBars: 0,
          endBar: 4,
        ),
      ],
    );
    final restorer = JsonBackupRestorer(
      songRepository: songRepository,
      setlistRepository: _MemorySetlistRepository(),
      presetRepository: _MemoryPresetRepository(),
      runInTransaction: _runWithoutTransaction,
    );

    await expectLater(
      restorer.restoreJson(
        '{"schemaVersion":2,"songs":[],"setlists":[],"presets":[]}',
      ),
      throwsA(isA<FormatException>()),
    );

    final songs = await songRepository.getAllSongs();
    expect(songs.map((song) => song.id).toList(), ['existing-song']);
  });

  test('rejects malformed payloads before mutating repositories', () async {
    final presetRepository = _MemoryPresetRepository(
      presets: const [
        MetronomePreset(
          id: 'existing-preset',
          name: 'Existing',
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
          subdivision: Subdivision.one,
          accentPattern: [],
        ),
      ],
    );
    final restorer = JsonBackupRestorer(
      songRepository: _MemorySongRepository(),
      setlistRepository: _MemorySetlistRepository(),
      presetRepository: presetRepository,
      runInTransaction: _runWithoutTransaction,
    );

    await expectLater(
      restorer.restoreJson(
        '{"schemaVersion":1,"songs":[],"setlists":[],"presets":[{"id":"preset-1","name":"Broken"}]}',
      ),
      throwsA(isA<FormatException>()),
    );

    final presets = await presetRepository.getAllPresets();
    expect(presets.map((preset) => preset.id).toList(), ['existing-preset']);
  });

  test('rejects domain-invalid payloads before mutating repositories',
      () async {
    final songRepository = _MemorySongRepository(
      songs: [
        Song(
          id: 'existing-song',
          title: 'Existing',
          createdAt: DateTime.utc(2026, 3, 1),
          startBpm: 100,
          beatsPerBar: 4,
          beatUnit: 4,
          countInBars: 0,
          endBar: 4,
        ),
      ],
    );
    final setlistRepository = _MemorySetlistRepository(
      setlists: [
        Setlist(
          id: 'existing-setlist',
          title: 'Existing',
          createdAt: DateTime.utc(2026, 3, 1),
        ),
      ],
    );
    final presetRepository = _MemoryPresetRepository(
      presets: const [
        MetronomePreset(
          id: 'existing-preset',
          name: 'Existing',
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
          subdivision: Subdivision.one,
          accentPattern: [],
        ),
      ],
    );
    final restorer = JsonBackupRestorer(
      songRepository: songRepository,
      setlistRepository: setlistRepository,
      presetRepository: presetRepository,
      runInTransaction: _runWithoutTransaction,
    );

    await expectLater(
      restorer.restoreJson(_domainInvalidBackupJson),
      throwsA(isA<ArgumentError>()),
    );

    final songs = await songRepository.getAllSongs();
    final setlists = await setlistRepository.getAllSetlists();
    final presets = await presetRepository.getAllPresets();

    expect(songs.map((song) => song.id).toList(), ['existing-song']);
    expect(
      setlists.map((setlist) => setlist.id).toList(),
      ['existing-setlist'],
    );
    expect(presets.map((preset) => preset.id).toList(), ['existing-preset']);
  });

  test('rolls back repository replacement when a save fails inside the transaction',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final songRepository = DriftSongRepository(songDao: database.songDao);
    final setlistRepository =
        DriftSetlistRepository(setlistDao: database.setlistDao);
    final presetRepository = _FailingPresetRepository(
      delegate: DriftPresetRepository(presetDao: database.presetDao),
    );

    await songRepository.saveSong(
      Song(
        id: 'existing-song',
        title: 'Existing',
        createdAt: DateTime.utc(2026, 3, 1),
        startBpm: 100,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 0,
        endBar: 4,
      ),
    );
    await setlistRepository.saveSetlist(
      Setlist(
        id: 'existing-setlist',
        title: 'Existing',
        createdAt: DateTime.utc(2026, 3, 1),
      ),
    );
    await database.presetDao.savePreset(
      const MetronomePreset(
        id: 'existing-preset',
        name: 'Existing',
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        subdivision: Subdivision.one,
        accentPattern: [],
      ),
    );

    final restorer = JsonBackupRestorer(
      songRepository: songRepository,
      setlistRepository: setlistRepository,
      presetRepository: presetRepository,
      runInTransaction: (action) => database.transaction(action),
    );

    await expectLater(
      restorer.restoreJson(_validBackupJson),
      throwsA(isA<StateError>()),
    );

    expect(
      (await songRepository.getAllSongs()).map((song) => song.id).toList(),
      ['existing-song'],
    );
    expect(
      (await setlistRepository.getAllSetlists())
          .map((setlist) => setlist.id)
          .toList(),
      ['existing-setlist'],
    );
    expect(
      (await database.presetDao.getAllPresets())
          .map((preset) => preset.id)
          .toList(),
      ['existing-preset'],
    );
  });

  test('restores older backups without click sound or master volume fields',
      () async {
    final presetRepository = _MemoryPresetRepository();
    final restorer = JsonBackupRestorer(
      songRepository: _MemorySongRepository(),
      setlistRepository: _MemorySetlistRepository(),
      presetRepository: presetRepository,
      runInTransaction: _runWithoutTransaction,
    );

    await restorer.restoreJson(_legacyPresetBackupJson);

    final presets = await presetRepository.getAllPresets();
    final preset = presets.single;
    expect(preset.clickSoundSet, ClickSoundSet.tock);
    expect(
      preset.masterVolumePercent,
      MetronomePreset.defaultMasterVolumePercent,
    );
  });
}

const String _validBackupJson = '''
{
  "schemaVersion": 1,
  "exportedAt": "2026-03-10T14:30:00.000Z",
  "songs": [
    {
      "id": "song-1",
      "title": "Intro",
      "createdAt": "2026-03-10T12:00:00.000Z",
      "startBpm": 128,
      "beatsPerBar": 4,
      "beatUnit": 4,
      "countInBars": 2,
      "endBar": 32,
      "tempoChanges": [
        {
          "id": "tempo-1",
          "barIndex": 8,
          "bpm": 132,
          "beatsPerBar": 4,
          "beatUnit": 4
        }
      ],
      "loops": [
        {
          "id": "loop-1",
          "startBar": 9,
          "endBar": 12,
          "repeatCount": 2
        }
      ],
      "songEvents": [
        {
          "id": "event-1",
          "barIndex": 16,
          "label": "Verse",
          "audioCue": {
            "type": "voice",
            "voiceText": "Verse",
            "voiceIdentifier": null,
            "customFilePath": null,
            "customFileDisplayName": null,
            "customFileBookmarkBase64": null,
            "volumePercent": 80
          },
          "audioCueBarsBefore": 2
        }
      ],
      "beatPatterns": [
        {
          "id": "pattern-1",
          "barIndex": 20,
          "accents": ["high", "normal", "low", "normal"],
          "subdivision": "four",
          "repeatPass": 2
        }
      ],
      "linkedAudio": {
        "filePath": "/tmp/intro.wav",
        "displayName": "Intro Track",
        "bookmarkBase64": "bookmark",
        "offsetMillis": 3000,
        "playInLiveMode": true,
        "volumePercent": 72
      }
    }
  ],
  "setlists": [
    {
      "id": "setlist-1",
      "title": "Evening Set",
      "createdAt": "2026-03-10T13:00:00.000Z",
      "items": [
        {
          "id": "item-1",
          "songId": "song-1",
          "songTitle": "Intro",
          "playbackEnabled": true,
          "playAttachedAudio": true,
          "transitionSteps": [
            {
              "id": "step-1",
              "type": "countInBars",
              "value": 2,
              "audioCue": null
            },
            {
              "id": "step-2",
              "type": "audio",
              "value": 0,
              "audioCue": {
                "type": "highPulse",
                "voiceText": null,
                "voiceIdentifier": null,
                "customFilePath": null,
                "customFileDisplayName": null,
                "customFileBookmarkBase64": null,
                "volumePercent": 65
              }
            }
          ]
        }
      ]
    }
  ],
  "presets": [
    {
      "id": "preset-1",
      "name": "Arena Intro",
      "bpm": 128,
      "beatsPerBar": 4,
      "beatUnit": 4,
      "subdivision": "four",
      "clickSoundSet": "hype",
      "masterVolumePercent": 67,
      "accentPattern": ["high", "normal", "low", "normal"],
      "intervalSettings": {
        "intervalMillis": 60000,
        "bpmStepEnabled": true,
        "bpmStep": 3,
        "maxDurationMillis": 300000
      }
    }
  ]
}
''';

Future<void> _runWithoutTransaction(Future<void> Function() action) {
  return action();
}

const String _domainInvalidBackupJson = '''
{
  "schemaVersion": 1,
  "exportedAt": "2026-03-10T14:30:00.000Z",
  "songs": [
    {
      "id": "song-1",
      "title": "Broken Song",
      "createdAt": "2026-03-10T12:00:00.000Z",
      "startBpm": 10,
      "beatsPerBar": 4,
      "beatUnit": 4,
      "countInBars": 0,
      "endBar": 8,
      "tempoChanges": [],
      "loops": [],
      "songEvents": [],
      "beatPatterns": [],
      "linkedAudio": null
    }
  ],
  "setlists": [],
  "presets": []
}
''';

const String _legacyPresetBackupJson = '''
{
  "schemaVersion": 1,
  "exportedAt": "2026-03-10T14:30:00.000Z",
  "songs": [],
  "setlists": [],
  "presets": [
    {
      "id": "preset-legacy",
      "name": "Legacy",
      "bpm": 120,
      "beatsPerBar": 4,
      "beatUnit": 4,
      "subdivision": "one",
      "accentPattern": ["high", "normal", "normal", "normal"],
      "intervalSettings": null
    }
  ]
}
''';

class _MemorySongRepository implements SongRepository {
  _MemorySongRepository({List<Song> songs = const []}) : _songs = [...songs];

  final List<Song> _songs;

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) => throw UnimplementedError();

  @override
  Future<void> deleteSong(String songId) async {
    _songs.removeWhere((song) => song.id == songId);
  }

  @override
  Future<List<Song>> getAllSongs() async => List<Song>.unmodifiable(_songs);

  @override
  Future<Song?> getSongById(String songId) async {
    for (final song in _songs) {
      if (song.id == songId) {
        return song;
      }
    }

    return null;
  }

  @override
  Future<Song> loadSong(String songId) async {
    final song = await getSongById(songId);
    if (song == null) {
      throw StateError('Song not found: $songId');
    }

    return song;
  }

  @override
  Future<void> saveSong(Song song) async {
    _songs.removeWhere((existingSong) => existingSong.id == song.id);
    _songs.add(song);
  }

  @override
  Future<void> regenerateBeatmap(String songId) async {}

  @override
  Stream<List<Song>> watchAllSongs() => const Stream.empty();

  @override
  Stream<Song?> watchSongById(String songId) => const Stream.empty();
}

class _MemorySetlistRepository implements SetlistRepository {
  _MemorySetlistRepository({List<Setlist> setlists = const []})
      : _setlists = [...setlists];

  final List<Setlist> _setlists;

  @override
  Future<void> deleteSetlist(String setlistId) async {
    _setlists.removeWhere((setlist) => setlist.id == setlistId);
  }

  @override
  Future<List<Setlist>> getAllSetlists() async =>
      List<Setlist>.unmodifiable(_setlists);

  @override
  Future<Setlist?> getSetlistById(String setlistId) async {
    for (final setlist in _setlists) {
      if (setlist.id == setlistId) {
        return setlist;
      }
    }

    return null;
  }

  @override
  Future<Setlist> loadSetlist(String setlistId) async {
    final setlist = await getSetlistById(setlistId);
    if (setlist == null) {
      throw StateError('Setlist not found: $setlistId');
    }

    return setlist;
  }

  @override
  Future<void> saveSetlist(Setlist setlist) async {
    _setlists
        .removeWhere((existingSetlist) => existingSetlist.id == setlist.id);
    _setlists.add(setlist);
  }

  @override
  Stream<List<Setlist>> watchAllSetlists() => const Stream.empty();

  @override
  Stream<Setlist?> watchSetlistById(String setlistId) => const Stream.empty();
}

class _MemoryPresetRepository implements PresetRepository {
  _MemoryPresetRepository({List<MetronomePreset> presets = const []})
      : _presets = [...presets];

  final List<MetronomePreset> _presets;

  @override
  Future<void> deletePreset(String presetId) async {
    _presets.removeWhere((preset) => preset.id == presetId);
  }

  @override
  Future<List<MetronomePreset>> getAllPresets() async =>
      List<MetronomePreset>.unmodifiable(_presets);

  @override
  Future<MetronomePreset?> getPresetById(String presetId) async {
    for (final preset in _presets) {
      if (preset.id == presetId) {
        return preset;
      }
    }

    return null;
  }

  @override
  Future<void> savePreset(MetronomePreset preset) async {
    _presets.removeWhere((existingPreset) => existingPreset.id == preset.id);
    _presets.add(preset);
  }

  @override
  Stream<List<MetronomePreset>> watchAllPresets() => const Stream.empty();

  @override
  Stream<MetronomePreset?> watchPresetById(String presetId) =>
      const Stream.empty();
}

class _FailingPresetRepository implements PresetRepository {
  const _FailingPresetRepository({required DriftPresetRepository delegate})
      : _delegate = delegate;

  final DriftPresetRepository _delegate;

  @override
  Future<void> deletePreset(String presetId) => _delegate.deletePreset(presetId);

  @override
  Future<List<MetronomePreset>> getAllPresets() => _delegate.getAllPresets();

  @override
  Future<MetronomePreset?> getPresetById(String presetId) =>
      _delegate.getPresetById(presetId);

  @override
  Future<void> savePreset(MetronomePreset preset) async {
    throw StateError('Preset save failed.');
  }

  @override
  Stream<List<MetronomePreset>> watchAllPresets() =>
      _delegate.watchAllPresets();

  @override
  Stream<MetronomePreset?> watchPresetById(String presetId) =>
      _delegate.watchPresetById(presetId);
}
