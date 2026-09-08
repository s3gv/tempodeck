import 'dart:convert';

import '../domain/accent_level.dart';
import '../domain/audio_cue.dart';
import '../domain/click_sound_set.dart';
import '../domain/interval_settings.dart';
import '../domain/linked_audio_file.dart';
import '../domain/metronome_preset.dart';
import '../domain/setlist.dart';
import '../domain/song.dart';
import '../domain/subdivision.dart';
import '../repositories/preset_repository.dart';
import '../repositories/setlist_repository.dart';
import '../repositories/song_repository.dart';
import '../validation/preset_write_validator.dart';
import '../validation/setlist_write_validator.dart';
import '../validation/song_write_validator.dart';
import 'json_backup_exporter.dart';

typedef JsonBackupTransactionRunner = Future<void> Function(
  Future<void> Function() action,
);

class JsonBackupRestorer {
  JsonBackupRestorer({
    required SongRepository songRepository,
    required SetlistRepository setlistRepository,
    required PresetRepository presetRepository,
    required JsonBackupTransactionRunner runInTransaction,
    SongWriteValidator songWriteValidator = const SongWriteValidator(),
    SetlistWriteValidator setlistWriteValidator = const SetlistWriteValidator(),
    PresetWriteValidator presetWriteValidator = const PresetWriteValidator(),
  })  : _songRepository = songRepository,
        _setlistRepository = setlistRepository,
        _presetRepository = presetRepository,
        _runInTransaction = runInTransaction,
        _songWriteValidator = songWriteValidator,
        _setlistWriteValidator = setlistWriteValidator,
        _presetWriteValidator = presetWriteValidator;

  final SongRepository _songRepository;
  final SetlistRepository _setlistRepository;
  final PresetRepository _presetRepository;
  final JsonBackupTransactionRunner _runInTransaction;
  final SongWriteValidator _songWriteValidator;
  final SetlistWriteValidator _setlistWriteValidator;
  final PresetWriteValidator _presetWriteValidator;

  Future<void> restoreJson(String jsonString) async {
    final root = _decodeRoot(jsonString);
    _validateSchemaVersion(root);

    final songs = _readObjectList(root, 'songs').map(_decodeSong).toList(
          growable: false,
        );
    final setlists = _readObjectList(root, 'setlists')
        .map(_decodeSetlist)
        .toList(growable: false);
    final presets = _readObjectList(root, 'presets').map(_decodePreset).toList(
          growable: false,
        );

    _validateDecodedBackup(
      songs: songs,
      setlists: setlists,
      presets: presets,
    );

    await _replaceAllData(
      songs: songs,
      setlists: setlists,
      presets: presets,
    );
  }

  Map<String, Object?> _decodeRoot(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }

    throw const FormatException('Backup root must be a JSON object.');
  }

  void _validateSchemaVersion(Map<String, Object?> root) {
    final schemaVersion = _readInt(root, 'schemaVersion');
    if (schemaVersion == JsonBackupExporter.schemaVersion) {
      return;
    }

    throw FormatException(
      'Unsupported backup schema version: $schemaVersion.',
    );
  }

  Future<void> _replaceAllData({
    required List<Song> songs,
    required List<Setlist> setlists,
    required List<MetronomePreset> presets,
  }) async {
    await _runInTransaction(() async {
      final existingSetlists = await _setlistRepository.getAllSetlists();
      for (final setlist in existingSetlists) {
        await _setlistRepository.deleteSetlist(setlist.id);
      }

      final existingSongs = await _songRepository.getAllSongs();
      for (final song in existingSongs) {
        await _songRepository.deleteSong(song.id);
      }

      final existingPresets = await _presetRepository.getAllPresets();
      for (final preset in existingPresets) {
        await _presetRepository.deletePreset(preset.id);
      }

      for (final song in songs) {
        await _songRepository.saveSong(song);
      }
      for (final setlist in setlists) {
        await _setlistRepository.saveSetlist(setlist);
      }
      for (final preset in presets) {
        await _presetRepository.savePreset(preset);
      }
    });
  }

  void _validateDecodedBackup({
    required List<Song> songs,
    required List<Setlist> setlists,
    required List<MetronomePreset> presets,
  }) {
    for (final song in songs) {
      _songWriteValidator.validate(song);
    }
    for (final setlist in setlists) {
      _setlistWriteValidator.validate(setlist);
    }
    for (final preset in presets) {
      _presetWriteValidator.validate(preset);
    }
  }

  Song _decodeSong(Map<String, Object?> json) {
    final linkedAudioJson = _readOptionalObject(json, 'linkedAudio');
    return Song(
      id: _readString(json, 'id'),
      title: _readString(json, 'title'),
      createdAt: _readDateTime(json, 'createdAt'),
      startBpm: _readInt(json, 'startBpm'),
      beatsPerBar: _readInt(json, 'beatsPerBar'),
      beatUnit: _readInt(json, 'beatUnit'),
      countInBars: _readInt(json, 'countInBars'),
      endBar: _readInt(json, 'endBar'),
      tempoChanges: _readObjectList(
        json,
        'tempoChanges',
      ).map(_decodeTempoChange).toList(growable: false),
      loops: _readObjectList(
        json,
        'loops',
      ).map(_decodeLoop).toList(growable: false),
      songEvents: _readObjectList(
        json,
        'songEvents',
      ).map(_decodeSongEvent).toList(growable: false),
      beatPatterns: _readObjectList(
        json,
        'beatPatterns',
      ).map(_decodeBeatPattern).toList(growable: false),
      linkedAudio:
          linkedAudioJson == null ? null : _decodeLinkedAudio(linkedAudioJson),
    );
  }

  SongTempoChange _decodeTempoChange(Map<String, Object?> json) {
    return SongTempoChange(
      id: _readString(json, 'id'),
      barIndex: _readInt(json, 'barIndex'),
      bpm: _readInt(json, 'bpm'),
      beatsPerBar: _readInt(json, 'beatsPerBar'),
      beatUnit: _readInt(json, 'beatUnit'),
    );
  }

  SongLoop _decodeLoop(Map<String, Object?> json) {
    return SongLoop(
      id: _readString(json, 'id'),
      startBar: _readInt(json, 'startBar'),
      endBar: _readInt(json, 'endBar'),
      repeatCount: _readInt(json, 'repeatCount'),
    );
  }

  SongEvent _decodeSongEvent(Map<String, Object?> json) {
    final audioCueJson = _readOptionalObject(json, 'audioCue');
    return SongEvent(
      id: _readString(json, 'id'),
      barIndex: _readInt(json, 'barIndex'),
      label: _readString(json, 'label'),
      audioCue: audioCueJson == null ? null : _decodeAudioCue(audioCueJson),
      audioCueBarsBefore: _readInt(json, 'audioCueBarsBefore'),
    );
  }

  SongBarBeatPattern _decodeBeatPattern(Map<String, Object?> json) {
    return SongBarBeatPattern(
      id: _readString(json, 'id'),
      barIndex: _readInt(json, 'barIndex'),
      accents: _readStringList(
        json,
        'accents',
      ).map(_decodeAccentLevel).toList(growable: false),
      subdivision: _decodeSubdivision(_readString(json, 'subdivision')),
      repeatPass: _readOptionalInt(json, 'repeatPass'),
    );
  }

  LinkedAudioFile _decodeLinkedAudio(Map<String, Object?> json) {
    return LinkedAudioFile(
      filePath: _readString(json, 'filePath'),
      displayName: _readString(json, 'displayName'),
      offsetMilliseconds: _readInt(json, 'offsetMillis'),
      volumePercent: _readInt(json, 'volumePercent'),
      playInLiveMode: _readBool(json, 'playInLiveMode'),
    );
  }

  Setlist _decodeSetlist(Map<String, Object?> json) {
    return Setlist(
      id: _readString(json, 'id'),
      title: _readString(json, 'title'),
      createdAt: _readDateTime(json, 'createdAt'),
      items: _readObjectList(
        json,
        'items',
      ).map(_decodeSetlistItem).toList(growable: false),
    );
  }

  SetlistItem _decodeSetlistItem(Map<String, Object?> json) {
    return SetlistItem(
      id: _readString(json, 'id'),
      songId: _readString(json, 'songId'),
      songTitle: _readString(json, 'songTitle'),
      playbackEnabled: _readBool(json, 'playbackEnabled'),
      playAttachedAudio: _readBool(json, 'playAttachedAudio'),
      transitionSteps: _readObjectList(
        json,
        'transitionSteps',
      ).map(_decodeTransitionStep).toList(growable: false),
    );
  }

  SetlistTransitionStep _decodeTransitionStep(Map<String, Object?> json) {
    final audioCueJson = _readOptionalObject(json, 'audioCue');
    return SetlistTransitionStep(
      id: _readString(json, 'id'),
      type: _decodeTransitionStepType(_readString(json, 'type')),
      value: _readInt(json, 'value'),
      audioCue: audioCueJson == null ? null : _decodeAudioCue(audioCueJson),
    );
  }

  MetronomePreset _decodePreset(Map<String, Object?> json) {
    final intervalSettingsJson = _readOptionalObject(json, 'intervalSettings');
    return MetronomePreset(
      id: _readString(json, 'id'),
      name: _readString(json, 'name'),
      bpm: _readInt(json, 'bpm'),
      beatsPerBar: _readInt(json, 'beatsPerBar'),
      beatUnit: _readInt(json, 'beatUnit'),
      subdivision: _decodeSubdivision(_readString(json, 'subdivision')),
      clickSoundSet: _decodeClickSoundSet(
        _readOptionalString(json, 'clickSoundSet') ?? ClickSoundSet.tock.name,
      ),
      masterVolumePercent:
          _readOptionalInt(json, 'masterVolumePercent') ??
          MetronomePreset.defaultMasterVolumePercent,
      accentPattern: _readStringList(
        json,
        'accentPattern',
      ).map(_decodeAccentLevel).toList(growable: false),
      intervalSettings: intervalSettingsJson == null
          ? null
          : _decodeIntervalSettings(intervalSettingsJson),
    );
  }

  IntervalSettings _decodeIntervalSettings(Map<String, Object?> json) {
    final maxDurationMillis = _readOptionalInt(json, 'maxDurationMillis');
    return IntervalSettings(
      interval: Duration(milliseconds: _readInt(json, 'intervalMillis')),
      bpmStepEnabled: _readBool(json, 'bpmStepEnabled'),
      bpmStep: _readInt(json, 'bpmStep'),
      maxDuration: maxDurationMillis == null
          ? null
          : Duration(milliseconds: maxDurationMillis),
    );
  }

  AudioCue _decodeAudioCue(Map<String, Object?> json) {
    return AudioCue(
      type: _decodeAudioCueType(_readString(json, 'type')),
      voiceText: _readOptionalString(json, 'voiceText'),
      voiceIdentifier: _readOptionalString(json, 'voiceIdentifier'),
      customFilePath: _readOptionalString(json, 'customFilePath'),
      customFileDisplayName: _readOptionalString(json, 'customFileDisplayName'),
      volumePercent: _readInt(json, 'volumePercent'),
    );
  }

  List<Map<String, Object?>> _readObjectList(
    Map<String, Object?> json,
    String key,
  ) {
    final rawList = json[key];
    if (rawList is! List<Object?>) {
      throw FormatException('$key must be a JSON array.');
    }

    return rawList.map((item) {
      if (item is Map<String, Object?>) {
        return item;
      }

      throw FormatException('$key must contain JSON objects.');
    }).toList(growable: false);
  }

  List<String> _readStringList(Map<String, Object?> json, String key) {
    final rawList = json[key];
    if (rawList is! List<Object?>) {
      throw FormatException('$key must be a JSON array.');
    }

    return rawList.map((item) {
      if (item is String) {
        return item;
      }

      throw FormatException('$key must contain strings.');
    }).toList(growable: false);
  }

  Map<String, Object?>? _readOptionalObject(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is Map<String, Object?>) {
      return value;
    }

    throw FormatException('$key must be a JSON object.');
  }

  String _readString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is String) {
      return value;
    }

    throw FormatException('$key must be a string.');
  }

  String? _readOptionalString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null || value is String) {
      return value as String?;
    }

    throw FormatException('$key must be a string.');
  }

  int _readInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }

    throw FormatException('$key must be an integer.');
  }

  int? _readOptionalInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null || value is int) {
      return value as int?;
    }

    throw FormatException('$key must be an integer.');
  }

  bool _readBool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is bool) {
      return value;
    }

    throw FormatException('$key must be a boolean.');
  }

  DateTime _readDateTime(Map<String, Object?> json, String key) {
    return DateTime.parse(_readString(json, key));
  }

  AccentLevel _decodeAccentLevel(String name) {
    return AccentLevel.values.byName(name);
  }

  AudioCueType _decodeAudioCueType(String name) {
    return AudioCueType.values.byName(name);
  }

  Subdivision _decodeSubdivision(String name) {
    return Subdivision.values.byName(name);
  }

  ClickSoundSet _decodeClickSoundSet(String name) {
    return ClickSoundSet.values.byName(name);
  }

  SetlistTransitionStepType _decodeTransitionStepType(String name) {
    return SetlistTransitionStepType.values.byName(name);
  }
}
