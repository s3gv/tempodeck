import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/export_engine.dart';
import 'package:tempodeck/core/audio/export_project_source_resolver.dart';
import 'package:tempodeck/core/audio/i_export_engine.dart';
import 'package:tempodeck/core/audio/linked_audio_export_augmenter.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song.dart';

void main() {
  group('ExportProjectSourceResolver', () {
    late _FakeSongLoader songLoader;
    late _FakeSetlistLoader setlistLoader;
    late _FakeLinkedAudioClipLoader linkedAudioClipLoader;
    late ExportProjectSourceResolver resolver;

    setUp(() {
      songLoader = _FakeSongLoader();
      setlistLoader = _FakeSetlistLoader();
      linkedAudioClipLoader = _FakeLinkedAudioClipLoader();
      resolver = ExportProjectSourceResolver(
        songLoader: songLoader,
        setlistLoader: setlistLoader,
        linkedAudioExportAugmenter: LinkedAudioExportAugmenter(
          linkedAudioClipLoader: linkedAudioClipLoader,
        ),
      );
    });

    test('resolves song exports with count-in, linked audio and voice warnings',
        () async {
      final song = Song(
        id: 'song-1',
        title: 'Song',
        createdAt: _createdAt,
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 2,
        endBar: 4,
        linkedAudio: const LinkedAudioFile(
          filePath: '/tmp/backing.wav',
          displayName: 'Backing',
          offsetMilliseconds: 500,
          volumePercent: 80,
        ),
        songEvents: [
          const SongEvent(
            id: 'event-1',
            barIndex: 3,
            label: 'Voice',
            audioCue: AudioCue(type: AudioCueType.voice, voiceText: 'Go'),
          ),
        ],
      );
      songLoader.songsById[song.id] = song;

      final project = await resolver.resolve(
        SongExportSource(song.id),
        contentOptions: const ExportContentOptions(
          includeClickTrack: false,
          includeAudioCues: false,
        ),
      );

      expect(songLoader.loadedSongIds, [song.id]);
      expect(project.duration, const Duration(seconds: 12));
      expect(project.audioEvents, hasLength(1));
      // Linked audio starts at countInDuration (2 bars at 120bpm 4/4 = 4s).
      // offsetMilliseconds (500) is a seek into the file, not a timeline delay.
      expect(
        project.audioEvents.single.offset,
        const Duration(milliseconds: 4000),
      );
      expect(project.audioEvents.single.gain, 0.8);
      expect(project.warnings, [voiceCueExportWarning]);
    });

    test('resolves setlist exports across playable items and transitions',
        () async {
      final introSong = Song(
        id: 'song-1',
        title: 'Intro',
        createdAt: _createdAt,
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 1,
        endBar: 4,
        linkedAudio: const LinkedAudioFile(
          filePath: '/tmp/intro.wav',
          displayName: 'Intro',
          offsetMilliseconds: 250,
        ),
      );
      final finaleSong = Song(
        id: 'song-2',
        title: 'Finale',
        createdAt: _createdAt,
        startBpm: 60,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 1,
        endBar: 2,
        linkedAudio: const LinkedAudioFile(
          filePath: '/tmp/finale.wav',
          displayName: 'Finale',
          offsetMilliseconds: 500,
        ),
        songEvents: [
          const SongEvent(
            id: 'event-2',
            barIndex: 1,
            label: 'Voice',
            audioCue: AudioCue(type: AudioCueType.voice, voiceText: 'Ready'),
          ),
        ],
      );
      final setlist = Setlist(
        id: 'setlist-1',
        title: 'Set',
        createdAt: _createdAt,
        items: [
          const SetlistItem(
            id: 'item-1',
            songId: 'song-1',
            songTitle: 'Intro',
          ),
          const SetlistItem(
            id: 'item-disabled',
            songId: 'song-disabled',
            songTitle: 'Disabled',
            playbackEnabled: false,
          ),
          const SetlistItem(
            id: 'item-2',
            songId: 'song-2',
            songTitle: 'Finale',
            transitionSteps: [
              SetlistTransitionStep(
                id: 'step-1',
                type: SetlistTransitionStepType.countInBars,
                value: 2,
              ),
              SetlistTransitionStep(
                id: 'step-2',
                type: SetlistTransitionStepType.pauseTimer,
                value: 3,
              ),
              SetlistTransitionStep(
                id: 'step-3',
                type: SetlistTransitionStepType.audio,
                value: 0,
                audioCue: AudioCue(type: AudioCueType.voice, voiceText: 'Next'),
              ),
            ],
          ),
        ],
      );
      songLoader.songsById.addAll({
        introSong.id: introSong,
        finaleSong.id: finaleSong,
      });
      setlistLoader.setlistsById[setlist.id] = setlist;

      final project = await resolver.resolve(
        SetlistExportSource(setlist.id),
        contentOptions: const ExportContentOptions(
          includeClickTrack: false,
          includeAudioCues: false,
        ),
      );

      expect(setlistLoader.loadedSetlistIds, [setlist.id]);
      expect(songLoader.loadedSongIds, ['song-1', 'song-2']);
      expect(project.duration, const Duration(seconds: 27));
      expect(project.audioEvents, hasLength(2));
      // Intro: no transition steps → currentOffset 0, no count-in → offset 0.
      // offsetMilliseconds (250) is a seek, not a timeline delay.
      expect(
        project.audioEvents.first.offset,
        Duration.zero,
      );
      // Finale: transition countIn(2) + pause(3) → currentOffset 8+11=19s.
      // offsetMilliseconds (500) is a seek, not a timeline delay.
      expect(
        project.audioEvents.last.offset,
        const Duration(milliseconds: 19000),
      );
      expect(project.warnings, [voiceCueExportWarning]);
    });

    test('ignores manual setlist transition steps during export', () async {
      final song = Song(
        id: 'song-1',
        title: 'Song',
        createdAt: _createdAt,
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 1,
        endBar: 4,
      );
      final setlist = Setlist(
        id: 'setlist-1',
        title: 'Set',
        createdAt: _createdAt,
        items: [
          const SetlistItem(
            id: 'item-1',
            songId: 'song-1',
            songTitle: 'Song',
            transitionSteps: [
              SetlistTransitionStep(
                id: 'step-1',
                type: SetlistTransitionStepType.manual,
                value: 0,
              ),
            ],
          ),
        ],
      );
      songLoader.songsById[song.id] = song;
      setlistLoader.setlistsById[setlist.id] = setlist;

      final project = await resolver.resolve(
        SetlistExportSource(setlist.id),
        contentOptions: const ExportContentOptions(
          includeClickTrack: false,
          includeAudioCues: false,
        ),
      );

      expect(project.duration, const Duration(seconds: 8));
      expect(project.audioEvents, isEmpty);
      expect(project.warnings, [manualStepExportWarning]);
    });

    test('cuts setlist exports into multiple projects at manual transitions',
        () async {
      final firstSong = Song(
        id: 'song-1',
        title: 'First',
        createdAt: _createdAt,
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 1,
        endBar: 4,
      );
      final secondSong = Song(
        id: 'song-2',
        title: 'Second',
        createdAt: _createdAt,
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 1,
        endBar: 2,
      );
      final setlist = Setlist(
        id: 'setlist-1',
        title: 'Set',
        createdAt: _createdAt,
        items: const [
          SetlistItem(
            id: 'item-1',
            songId: 'song-1',
            songTitle: 'First',
          ),
          SetlistItem(
            id: 'item-2',
            songId: 'song-2',
            songTitle: 'Second',
            transitionSteps: [
              SetlistTransitionStep(
                id: 'step-1',
                type: SetlistTransitionStepType.pauseTimer,
                value: 3,
              ),
              SetlistTransitionStep(
                id: 'step-2',
                type: SetlistTransitionStepType.manual,
                value: 0,
              ),
              SetlistTransitionStep(
                id: 'step-3',
                type: SetlistTransitionStepType.countInBars,
                value: 2,
              ),
            ],
          ),
        ],
      );
      songLoader.songsById.addAll({
        firstSong.id: firstSong,
        secondSong.id: secondSong,
      });
      setlistLoader.setlistsById[setlist.id] = setlist;

      final projects = await resolver.resolveProjects(
        SetlistExportSource(setlist.id),
        layout: ExportMp3Layout.cutOnManual,
        contentOptions: const ExportContentOptions(
          includeClickTrack: false,
          includeAudioCues: false,
        ),
      );

      expect(projects, hasLength(2));
      expect(projects.first.duration, const Duration(seconds: 11));
      expect(projects[1].duration, const Duration(seconds: 8));
      expect(projects.first.warnings, isEmpty);
      expect(projects[1].warnings, isEmpty);
    });

    test('does not add warnings from disabled setlist items', () async {
      final song = Song(
        id: 'song-1',
        title: 'Song',
        createdAt: _createdAt,
        startBpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 1,
        endBar: 4,
      );
      final setlist = Setlist(
        id: 'setlist-1',
        title: 'Set',
        createdAt: _createdAt,
        items: [
          const SetlistItem(
            id: 'item-disabled',
            songId: 'song-1',
            songTitle: 'Song',
            playbackEnabled: false,
            transitionSteps: [
              SetlistTransitionStep(
                id: 'step-1',
                type: SetlistTransitionStepType.audio,
                value: 0,
                audioCue: AudioCue(type: AudioCueType.voice, voiceText: 'Skip'),
              ),
            ],
          ),
        ],
      );
      songLoader.songsById[song.id] = song;
      setlistLoader.setlistsById[setlist.id] = setlist;

      final project = await resolver.resolve(
        SetlistExportSource(setlist.id),
        contentOptions: const ExportContentOptions(
          includeClickTrack: false,
          includeAudioCues: false,
        ),
      );

      expect(project.warnings, isEmpty);
    });

    test('throws when song start BPM is not greater than zero', () async {
      final song = Song(
        id: 'song-1',
        title: 'Broken Tempo',
        createdAt: _createdAt,
        startBpm: 0,
        beatsPerBar: 4,
        beatUnit: 4,
        countInBars: 1,
        endBar: 4,
      );
      songLoader.songsById[song.id] = song;

      await expectLater(
        () => resolver.resolve(
          SongExportSource(song.id),
          contentOptions: const ExportContentOptions(
            includeClickTrack: false,
            includeAudioCues: false,
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('BPM must be greater than zero.'),
          ),
        ),
      );
    });
  });
}

class _FakeSongLoader implements SongExportSourceLoader {
  final Map<String, Song> songsById = {};
  final List<String> loadedSongIds = [];

  @override
  Future<Song> loadSong(String songId) async {
    loadedSongIds.add(songId);
    final song = songsById[songId];
    if (song == null) {
      throw StateError('Missing test song for $songId');
    }

    return song;
  }
}

class _FakeSetlistLoader implements SetlistExportSourceLoader {
  final Map<String, Setlist> setlistsById = {};
  final List<String> loadedSetlistIds = [];

  @override
  Future<Setlist> loadSetlist(String setlistId) async {
    loadedSetlistIds.add(setlistId);
    final setlist = setlistsById[setlistId];
    if (setlist == null) {
      throw StateError('Missing test setlist for $setlistId');
    }

    return setlist;
  }
}

class _FakeLinkedAudioClipLoader implements LinkedAudioClipLoader {
  @override
  Future<ExportAudioClip> loadClip(LinkedAudioFile linkedAudioFile) async {
    return ExportAudioClip(
      samples: Float32List.fromList(const [0.25, -0.25, 0.5, -0.5]),
      sampleRate: ExportAudioFormat.defaultSampleRate,
      channelCount: ExportAudioFormat.defaultChannelCount,
    );
  }
}

final _createdAt = DateTime(2026, 3, 1);
