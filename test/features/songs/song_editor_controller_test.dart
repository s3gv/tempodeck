import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';
import 'package:tempodeck/core/domain/subdivision.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/domain/song.dart';
import 'package:tempodeck/core/domain/song_beatmap.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/repositories/song_repository.dart';
import 'package:tempodeck/features/songs/song_editor_controller.dart';

void main() {
  test('saveSongDetails persists updated basic song fields', () async {
    final repository = _CapturingSongRepository();
    final container = ProviderContainer(
      overrides: [
        songRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(songEditorControllerProvider).saveSongDetails(
          song: _testSong,
          title: 'Updated Song',
          startBpm: 144,
          beatsPerBar: 3,
          beatUnit: 8,
          countInBars: 2,
          endBar: 48,
          tempoChanges: const [
            SongTempoChange(
              id: 'tempo-1',
              barIndex: 8,
              bpm: 150,
              beatsPerBar: 5,
              beatUnit: 4,
            ),
          ],
          loops: const [
            SongLoop(
              id: 'loop-1',
              startBar: 10,
              endBar: 12,
              repeatCount: 2,
            ),
          ],
          songEvents: const [
            SongEvent(
              id: 'event-1',
              barIndex: 16,
              label: 'Verse',
              audioCue: AudioCue(type: AudioCueType.highPulse),
              audioCueBarsBefore: 2,
            ),
          ],
          beatPatterns: const [
            SongBarBeatPattern(
              id: 'pattern-1',
              barIndex: 18,
              accents: [AccentLevel.high, AccentLevel.normal, AccentLevel.low],
              subdivision: Subdivision.two,
            ),
          ],
          linkedAudio: const LinkedAudioFile(
            filePath: '/tmp/backing.mp3',
            displayName: 'Backing Track',
            offsetMilliseconds: 1200,
            volumePercent: 75,
            playInLiveMode: false,
          ),
        );

    expect(repository.savedSongs, hasLength(1));
    final saved = repository.savedSongs.single;
    expect(saved.id, _testSong.id);
    expect(saved.createdAt, _testSong.createdAt);
    expect(saved.title, 'Updated Song');
    expect(saved.startBpm, 144);
    expect(saved.beatsPerBar, 3);
    expect(saved.beatUnit, 8);
    expect(saved.countInBars, 2);
    expect(saved.endBar, 48);
    expect(saved.tempoChanges, hasLength(1));
    expect(saved.loops, hasLength(1));
    expect(saved.songEvents, hasLength(1));
    expect(saved.beatPatterns, hasLength(1));
    expect(saved.linkedAudio, isNotNull);
  });

  test('saveSongDetails trims whitespace from the title', () async {
    final repository = _CapturingSongRepository();
    final container = ProviderContainer(
      overrides: [
        songRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(songEditorControllerProvider).saveSongDetails(
          song: _testSong,
          title: '  Trimmed Title  ',
          startBpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
          countInBars: 1,
          endBar: 32,
          tempoChanges: const [],
          loops: const [],
          songEvents: const [],
          beatPatterns: const [],
          linkedAudio: null,
        );

    expect(repository.savedSongs, hasLength(1));
    expect(repository.savedSongs.single.title, 'Trimmed Title');
  });

  test('createTempoChange creates a change with a generated id', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final tempoChange = container.read(songEditorControllerProvider).createTempoChange(
          barIndex: 6,
          bpm: 144,
          beatsPerBar: 3,
          beatUnit: 8,
        );

    expect(tempoChange.id, isNotEmpty);
    expect(tempoChange.barIndex, 6);
    expect(tempoChange.bpm, 144);
    expect(tempoChange.beatsPerBar, 3);
    expect(tempoChange.beatUnit, 8);
  });

  test('createTempoChange assigns a unique id each time', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(songEditorControllerProvider);
    final first = controller.createTempoChange(
      barIndex: 1,
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
    );
    final second = controller.createTempoChange(
      barIndex: 1,
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
    );

    expect(first.id, isNot(second.id));
  });

  test('createLoop assigns a unique id each time', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(songEditorControllerProvider);
    final first = controller.createLoop(
      startBar: 8,
      endBar: 12,
      repeatCount: 2,
    );
    final second = controller.createLoop(
      startBar: 8,
      endBar: 12,
      repeatCount: 2,
    );

    expect(first.id, isNot(second.id));
  });

  test('createSongEvent trims the label and keeps audio cue details', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final songEvent = container.read(songEditorControllerProvider).createSongEvent(
          barIndex: 12,
          label: '  Chorus  ',
          audioCue: const AudioCue(
            type: AudioCueType.voice,
            voiceText: 'Go',
            volumePercent: 80,
          ),
          audioCueBarsBefore: 2,
        );

    expect(songEvent.id, isNotEmpty);
    expect(songEvent.label, 'Chorus');
    expect(songEvent.audioCue!.type, AudioCueType.voice);
    expect(songEvent.audioCue!.volumePercent, 80);
    expect(songEvent.audioCueBarsBefore, 2);
  });

  test('createSongEvent assigns a unique id each time', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(songEditorControllerProvider);
    final first = controller.createSongEvent(
      barIndex: 1,
      label: 'A',
      audioCue: null,
      audioCueBarsBefore: 0,
    );
    final second = controller.createSongEvent(
      barIndex: 1,
      label: 'A',
      audioCue: null,
      audioCueBarsBefore: 0,
    );

    expect(first.id, isNot(second.id));
  });

  test('regenerateBeatmap delegates to repository', () async {
    final repository = _CapturingSongRepository();
    final container = ProviderContainer(
      overrides: [
        songRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(songEditorControllerProvider)
        .regenerateBeatmap('song-42');

    expect(repository.regeneratedBeatmapSongIds, ['song-42']);
  });

  test('createBeatPattern assigns a unique id and keeps values', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(songEditorControllerProvider);
    final first = controller.createBeatPattern(
      barIndex: 9,
      accents: const [AccentLevel.high, AccentLevel.low],
      subdivision: Subdivision.three,
      repeatPass: 2,
    );
    final second = controller.createBeatPattern(
      barIndex: 9,
      accents: const [AccentLevel.high, AccentLevel.low],
      subdivision: Subdivision.three,
      repeatPass: 2,
    );

    expect(first.id, isNot(second.id));
    expect(first.barIndex, 9);
    expect(first.accents, const [AccentLevel.high, AccentLevel.low]);
    expect(first.subdivision, Subdivision.three);
    expect(first.repeatPass, 2);
  });
}

final _testSong = Song(
  id: 'song-1',
  title: 'Original Song',
  createdAt: DateTime(2024, 1, 1),
  startBpm: 120,
  beatsPerBar: 4,
  beatUnit: 4,
  countInBars: 1,
  endBar: 32,
);

class _CapturingSongRepository implements SongRepository {
  final List<Song> savedSongs = [];
  final List<String> regeneratedBeatmapSongIds = [];

  @override
  Future<SongBeatmap> loadSongBeatmap(String songId) => throw UnimplementedError();

  @override
  Future<void> saveSong(Song song) async => savedSongs.add(song);

  @override
  Future<void> regenerateBeatmap(String songId) async =>
      regeneratedBeatmapSongIds.add(songId);

  @override
  Future<void> deleteSong(String songId) => throw UnimplementedError();

  @override
  Future<List<Song>> getAllSongs() => throw UnimplementedError();

  @override
  Future<Song?> getSongById(String songId) => throw UnimplementedError();

  @override
  Future<Song> loadSong(String songId) => throw UnimplementedError();

  @override
  Stream<List<Song>> watchAllSongs() => throw UnimplementedError();

  @override
  Stream<Song?> watchSongById(String songId) => throw UnimplementedError();
}
