import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/core_export_engine_factory.dart';
import 'package:tempodeck/core/audio/export_engine.dart';
import 'package:tempodeck/core/audio/export_project_source_resolver.dart';
import 'package:tempodeck/core/audio/ffmpeg_audio_export_transcoder.dart';
import 'package:tempodeck/core/audio/i_export_engine.dart';
import 'package:tempodeck/core/audio/linked_audio_export_augmenter.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/domain/song.dart';

void main() {
  group('CoreExportEngineFactory', () {
    late _FakeSongLoader songLoader;
    late _FakeSetlistLoader setlistLoader;
    late _FakeLinkedAudioClipLoader linkedAudioClipLoader;
    late _FakeFfmpegAudioExportClient ffmpegClient;
    late ExportEngine engine;
    late Directory temporaryOutputDirectory;

    setUp(() async {
      songLoader = _FakeSongLoader();
      setlistLoader = _FakeSetlistLoader();
      linkedAudioClipLoader = _FakeLinkedAudioClipLoader();
      ffmpegClient = _FakeFfmpegAudioExportClient();
      engine = const CoreExportEngineFactory().create(
        songLoader: songLoader,
        setlistLoader: setlistLoader,
        linkedAudioClipLoader: linkedAudioClipLoader,
        ffmpegAudioExportClient: ffmpegClient,
      );
      temporaryOutputDirectory = await Directory.systemTemp.createTemp(
        'tempodeck_export_engine_factory_',
      );
    });

    tearDown(() async {
      if (await temporaryOutputDirectory.exists()) {
        await temporaryOutputDirectory.delete(recursive: true);
      }
    });

    test('exports a single song through the composed core pipeline', () async {
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
        ),
      );
      songLoader.songsById[song.id] = song;
      ffmpegClient.statisticsMoments = const [Duration(seconds: 6)];

      await expectLater(
        engine.exportToMp3(
          source: SongExportSource(song.id),
          outputPath:
              '${temporaryOutputDirectory.path}${Platform.pathSeparator}song.mp3',
          contentOptions: const ExportContentOptions(
            includeClickTrack: false,
            includeAudioCues: false,
          ),
        ),
        emitsInOrder([
          0.15,
          closeTo(0.45, 0.0001),
          closeTo(0.725, 0.0001),
          1.0,
          emitsDone,
        ]),
      );

      expect(songLoader.loadedSongIds, [song.id]);
      expect(linkedAudioClipLoader.loadedFiles, [song.linkedAudio]);
      expect(ffmpegClient.commands.single, contains('-codec:a libmp3lame'));
      expect(ffmpegClient.inputWaveHeaders, ['RIFF']);
    });

    test('exports a full setlist through the composed core pipeline', () async {
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
          offsetMilliseconds: 250,
        ),
      );
      final setlist = Setlist(
        id: 'setlist-1',
        title: 'Set',
        createdAt: _createdAt,
        items: const [
          SetlistItem(
            id: 'item-1',
            songId: 'song-1',
            songTitle: 'Intro',
          ),
          SetlistItem(
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
            ],
          ),
        ],
      );
      songLoader.songsById.addAll({
        introSong.id: introSong,
        finaleSong.id: finaleSong,
      });
      setlistLoader.setlistsById[setlist.id] = setlist;
      ffmpegClient.statisticsMoments = const [Duration(seconds: 9)];

      await expectLater(
        engine.exportToMp3(
          source: SetlistExportSource(setlist.id),
          outputPath:
              '${temporaryOutputDirectory.path}${Platform.pathSeparator}setlist.mp3',
          contentOptions: const ExportContentOptions(
            includeClickTrack: false,
            includeAudioCues: false,
          ),
        ),
        emitsInOrder([
          0.15,
          closeTo(0.45, 0.0001),
          closeTo(0.633333, 0.0001),
          1.0,
          emitsDone,
        ]),
      );

      expect(setlistLoader.loadedSetlistIds, [setlist.id]);
      expect(songLoader.loadedSongIds, ['song-1', 'song-2']);
      expect(linkedAudioClipLoader.loadedFiles, [
        introSong.linkedAudio,
        finaleSong.linkedAudio,
      ]);
      expect(ffmpegClient.inputWaveHeaders, ['RIFF']);
    });

    test('cuts setlist exports into multiple mp3 files at manual transitions',
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
                type: SetlistTransitionStepType.manual,
                value: 0,
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

      await expectLater(
        engine.exportToMp3(
          source: SetlistExportSource(setlist.id),
          outputPath:
              '${temporaryOutputDirectory.path}${Platform.pathSeparator}setlist.mp3',
          layout: ExportMp3Layout.cutOnManual,
          contentOptions: const ExportContentOptions(
            includeClickTrack: false,
            includeAudioCues: false,
          ),
        ),
        emitsThrough(1.0),
      );

      expect(ffmpegClient.outputPaths, [
        '${temporaryOutputDirectory.path}${Platform.pathSeparator}setlist_part01.mp3',
        '${temporaryOutputDirectory.path}${Platform.pathSeparator}setlist_part02.mp3',
      ]);
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
  final List<LinkedAudioFile> loadedFiles = [];

  @override
  Future<ExportAudioClip> loadClip(LinkedAudioFile linkedAudioFile) async {
    loadedFiles.add(linkedAudioFile);
    return ExportAudioClip(
      samples: Float32List.fromList(const [0.25, -0.25, 0.5, -0.5]),
      sampleRate: ExportAudioFormat.defaultSampleRate,
      channelCount: ExportAudioFormat.defaultChannelCount,
    );
  }
}

class _FakeFfmpegAudioExportClient implements FfmpegAudioExportClient {
  final List<String> commands = [];
  final List<String> inputWaveHeaders = [];
  final List<String> outputPaths = [];
  List<Duration> statisticsMoments = const [];

  @override
  Future<FfmpegTranscodeResult> execute({
    required String command,
    FfmpegStatisticsCallback? onStatistics,
  }) async {
    commands.add(command);
    outputPaths.add(_extractOutputPath(command));

    final inputPath = _extractQuotedPath(command, marker: '-i ');
    final inputBytes = await File(inputPath).readAsBytes();
    inputWaveHeaders.add(String.fromCharCodes(inputBytes.sublist(0, 4)));

    for (final statisticsMoment in statisticsMoments) {
      onStatistics?.call(statisticsMoment);
    }

    // Simulate FFmpeg writing an output file.
    final outputPath = _extractOutputPath(command);
    await File(outputPath).writeAsBytes([0xFF, 0xFB, 0x90, 0x00]);

    return const FfmpegTranscodeSuccess();
  }

  String _extractQuotedPath(String command, {required String marker}) {
    final markerIndex = command.indexOf(marker);
    final startQuoteIndex = command.indexOf('"', markerIndex);
    final endQuoteIndex = command.indexOf('"', startQuoteIndex + 1);
    return command.substring(startQuoteIndex + 1, endQuoteIndex);
  }

  String _extractOutputPath(String command) {
    final endQuoteIndex = command.lastIndexOf('"');
    final startQuoteIndex = command.lastIndexOf('"', endQuoteIndex - 1);
    return command.substring(startQuoteIndex + 1, endQuoteIndex);
  }
}

final _createdAt = DateTime(2026, 3, 1);
