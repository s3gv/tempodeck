import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/backup/json_backup_exporter.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/domain/interval_settings.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';
import 'package:tempodeck/core/domain/metronome_preset.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/domain/subdivision.dart';
import 'package:tempodeck/core/repositories/preset_repository.dart';
import 'package:tempodeck/core/repositories/setlist_repository.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';

void main() {
  test('exports songs, setlists, and presets into a single json payload',
      () async {
    final exporter = JsonBackupExporter(
      songRepository: _FakeSongRepository(
        songs: [
          Song(
            id: 'song-1',
            title: 'Intro',
            createdAt: DateTime.utc(2026, 3, 10, 12),
            startBpm: 128,
            beatsPerBar: 4,
            beatUnit: 4,
            countInBars: 2,
            endBar: 32,
            tempoChanges: const [
              SongTempoChange(
                id: 'tempo-1',
                barIndex: 8,
                bpm: 132,
                beatsPerBar: 4,
                beatUnit: 4,
              ),
            ],
            loops: const [
              SongLoop(
                id: 'loop-1',
                startBar: 9,
                endBar: 12,
                repeatCount: 2,
              ),
            ],
            songEvents: const [
              SongEvent(
                id: 'event-1',
                barIndex: 16,
                label: 'Verse',
                audioCue: AudioCue(
                  type: AudioCueType.voice,
                  voiceText: 'Verse',
                  volumePercent: 80,
                ),
                audioCueBarsBefore: 2,
              ),
            ],
            beatPatterns: const [
              SongBarBeatPattern(
                id: 'pattern-1',
                barIndex: 20,
                accents: [
                  AccentLevel.high,
                  AccentLevel.normal,
                  AccentLevel.low,
                  AccentLevel.normal,
                ],
                subdivision: Subdivision.four,
                repeatPass: 2,
              ),
            ],
            linkedAudio: const LinkedAudioFile(
              filePath: '/tmp/intro.wav',
              displayName: 'Intro Track',
              offsetMilliseconds: 3000,
              volumePercent: 72,
            ),
          ),
        ],
      ),
      setlistRepository: _FakeSetlistRepository(
        setlists: [
          Setlist(
            id: 'setlist-1',
            title: 'Evening Set',
            createdAt: DateTime.utc(2026, 3, 10, 13),
            items: const [
              SetlistItem(
                id: 'item-1',
                songId: 'song-1',
                songTitle: 'Intro',
                transitionSteps: [
                  SetlistTransitionStep(
                    id: 'step-1',
                    type: SetlistTransitionStepType.countInBars,
                    value: 2,
                  ),
                  SetlistTransitionStep(
                    id: 'step-2',
                    type: SetlistTransitionStepType.audio,
                    value: 0,
                    audioCue: AudioCue(
                      type: AudioCueType.highPulse,
                      volumePercent: 65,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      presetRepository: _FakePresetRepository(
        presets: const [
          MetronomePreset(
            id: 'preset-1',
            name: 'Arena Intro',
            bpm: 128,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.four,
            clickSoundSet: ClickSoundSet.hype,
            masterVolumePercent: 67,
            accentPattern: [
              AccentLevel.high,
              AccentLevel.normal,
              AccentLevel.low,
              AccentLevel.normal,
            ],
            intervalSettings: IntervalSettings(
              interval: Duration(minutes: 1),
              bpmStepEnabled: true,
              bpmStep: 3,
              maxDuration: Duration(minutes: 5),
            ),
          ),
        ],
      ),
      now: () => DateTime.utc(2026, 3, 10, 14, 30),
    );

    final jsonString = await exporter.exportJson();
    final decoded = jsonDecode(jsonString) as Map<String, Object?>;

    expect(decoded['schemaVersion'], JsonBackupExporter.schemaVersion);
    expect(decoded['exportedAt'], '2026-03-10T14:30:00.000Z');

    final songs = decoded['songs'] as List<Object?>;
    expect(songs, hasLength(1));
    final song = songs.single as Map<String, Object?>;
    expect(song['id'], 'song-1');
    expect(song['startBpm'], 128);
    expect(song['linkedAudio'], isA<Map<String, Object?>>());

    final linkedAudio = song['linkedAudio'] as Map<String, Object?>;
    expect(linkedAudio['offsetMillis'], 3000);
    expect(linkedAudio['volumePercent'], 72);

    final songEvents = song['songEvents'] as List<Object?>;
    final songEvent = songEvents.single as Map<String, Object?>;
    final songEventCue = songEvent['audioCue'] as Map<String, Object?>;
    expect(songEventCue['type'], 'voice');
    expect(songEventCue['voiceText'], 'Verse');

    final setlists = decoded['setlists'] as List<Object?>;
    final setlist = setlists.single as Map<String, Object?>;
    final items = setlist['items'] as List<Object?>;
    final item = items.single as Map<String, Object?>;
    final transitionSteps = item['transitionSteps'] as List<Object?>;
    final transitionStep = transitionSteps[1] as Map<String, Object?>;
    final transitionCue = transitionStep['audioCue'] as Map<String, Object?>;
    expect(transitionStep['type'], 'audio');
    expect(transitionCue['type'], 'highPulse');

    final presets = decoded['presets'] as List<Object?>;
    final preset = presets.single as Map<String, Object?>;
    expect(preset['subdivision'], 'four');
    expect(preset['clickSoundSet'], 'hype');
    expect(preset['masterVolumePercent'], 67);
    expect(preset['accentPattern'], ['high', 'normal', 'low', 'normal']);

    final intervalSettings = preset['intervalSettings'] as Map<String, Object?>;
    expect(intervalSettings['intervalMillis'], 60000);
    expect(intervalSettings['maxDurationMillis'], 300000);
  });

  test('exports empty repository state as empty arrays', () async {
    final exporter = JsonBackupExporter(
      songRepository: _FakeSongRepository(),
      setlistRepository: _FakeSetlistRepository(),
      presetRepository: _FakePresetRepository(),
      now: () => DateTime.utc(2026, 3, 10, 14, 30),
    );

    final jsonString = await exporter.exportJson();
    final decoded = jsonDecode(jsonString) as Map<String, Object?>;

    expect(decoded['songs'], isEmpty);
    expect(decoded['setlists'], isEmpty);
    expect(decoded['presets'], isEmpty);
  });

  test('exports nullable backup fields as null', () async {
    final exporter = JsonBackupExporter(
      songRepository: _FakeSongRepository(
        songs: [
          Song(
            id: 'song-2',
            title: 'Minimal Song',
            createdAt: DateTime.utc(2026, 3, 10, 15),
            startBpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            countInBars: 0,
            endBar: 8,
            songEvents: const [
              SongEvent(
                id: 'event-1',
                barIndex: 4,
                label: 'Marker',
              ),
            ],
          ),
        ],
      ),
      setlistRepository: _FakeSetlistRepository(),
      presetRepository: _FakePresetRepository(
        presets: const [
          MetronomePreset(
            id: 'preset-2',
            name: 'Dry Preset',
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [],
          ),
          MetronomePreset(
            id: 'preset-3',
            name: 'Interval Preset',
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [],
            intervalSettings: IntervalSettings(
              interval: Duration(minutes: 1),
            ),
          ),
        ],
      ),
      now: () => DateTime.utc(2026, 3, 10, 14, 30),
    );

    final jsonString = await exporter.exportJson();
    final decoded = jsonDecode(jsonString) as Map<String, Object?>;

    final songs = decoded['songs'] as List<Object?>;
    final song = songs.single as Map<String, Object?>;
    expect(song['linkedAudio'], isNull);

    final songEvents = song['songEvents'] as List<Object?>;
    final songEvent = songEvents.single as Map<String, Object?>;
    expect(songEvent['audioCue'], isNull);

    final presets = decoded['presets'] as List<Object?>;
    final dryPreset = presets[0] as Map<String, Object?>;
    expect(dryPreset['intervalSettings'], isNull);

    final intervalPreset = presets[1] as Map<String, Object?>;
    final intervalSettings =
        intervalPreset['intervalSettings'] as Map<String, Object?>;
    expect(intervalSettings['maxDurationMillis'], isNull);
  });
}

class _FakeSongRepository implements SongRepository {
  _FakeSongRepository({this.songs = const []});

  final List<Song> songs;

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) => throw UnimplementedError();

  @override
  Future<void> deleteSong(String songId) async {}

  @override
  Future<List<Song>> getAllSongs() async => songs;

  @override
  Future<Song?> getSongById(String songId) async => null;

  @override
  Future<Song> loadSong(String songId) {
    throw UnimplementedError();
  }

  @override
  Future<void> saveSong(Song song) async {}

  @override
  Future<void> regenerateBeatmap(String songId) async {}

  @override
  Stream<List<Song>> watchAllSongs() => const Stream.empty();

  @override
  Stream<Song?> watchSongById(String songId) => const Stream.empty();
}

class _FakeSetlistRepository implements SetlistRepository {
  _FakeSetlistRepository({this.setlists = const []});

  final List<Setlist> setlists;

  @override
  Future<void> deleteSetlist(String setlistId) async {}

  @override
  Future<List<Setlist>> getAllSetlists() async => setlists;

  @override
  Future<Setlist?> getSetlistById(String setlistId) async => null;

  @override
  Future<Setlist> loadSetlist(String setlistId) {
    throw UnimplementedError();
  }

  @override
  Future<void> saveSetlist(Setlist setlist) async {}

  @override
  Stream<List<Setlist>> watchAllSetlists() => const Stream.empty();

  @override
  Stream<Setlist?> watchSetlistById(String setlistId) => const Stream.empty();
}

class _FakePresetRepository implements PresetRepository {
  _FakePresetRepository({this.presets = const []});

  final List<MetronomePreset> presets;

  @override
  Future<void> deletePreset(String presetId) async {}

  @override
  Future<List<MetronomePreset>> getAllPresets() async => presets;

  @override
  Future<MetronomePreset?> getPresetById(String presetId) async => null;

  @override
  Future<void> savePreset(MetronomePreset preset) async {}

  @override
  Stream<List<MetronomePreset>> watchAllPresets() => const Stream.empty();

  @override
  Stream<MetronomePreset?> watchPresetById(String presetId) =>
      const Stream.empty();
}
