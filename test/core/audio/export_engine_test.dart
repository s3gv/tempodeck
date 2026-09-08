import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/export_engine.dart';
import 'package:tempodeck/core/audio/i_export_engine.dart';

void main() {
  group('ExportEngine', () {
    late _FakeExportSourceResolver sourceResolver;
    late _FakeOfflineAudioRenderer offlineAudioRenderer;
    late _FakeAudioExportTranscoder audioExportTranscoder;
    late ExportEngine engine;

    setUp(() {
      sourceResolver = _FakeExportSourceResolver();
      offlineAudioRenderer = _FakeOfflineAudioRenderer();
      audioExportTranscoder = _FakeAudioExportTranscoder();
      engine = ExportEngine(
        sourceResolver: sourceResolver,
        offlineAudioRenderer: offlineAudioRenderer,
        audioExportTranscoder: audioExportTranscoder,
      );
    });

    test('estimates file size using bitrate and precise duration', () {
      final bytes = engine.estimateFileSizeBytes(
        duration: const Duration(milliseconds: 3500),
        bitrateBps: 192000,
      );

      expect(bytes, 84000);
    });

    test('throws for a non-positive bitrate estimate', () {
      expect(
        () => engine.estimateFileSizeBytes(
          duration: const Duration(seconds: 1),
          bitrateBps: 0,
        ),
        throwsArgumentError,
      );
    });

    test('exports a song source through resolve, render, and transcode',
        () async {
      sourceResolver.project = ResolvedExportProject(
        source: SongExportSource('song-1'),
        duration: const Duration(minutes: 3),
      );
      audioExportTranscoder.progressValues = [0.25, 1.0];

      final progress = engine.exportToMp3(
        source: SongExportSource('song-1'),
        outputPath: '/tmp/song.mp3',
      );

      await expectLater(
        progress,
        emitsInOrder([
          0.15,
          closeTo(0.45, 0.0001),
          closeTo(0.5875, 0.0001),
          1.0,
          emitsDone,
        ]),
      );
      expect(sourceResolver.resolvedSources, [isA<SongExportSource>()]);
      expect(offlineAudioRenderer.renderedProjects, [sourceResolver.project]);
      expect(audioExportTranscoder.outputPaths, ['/tmp/song.mp3']);
      expect(audioExportTranscoder.bitrates, [192000]);
    });

    test('exports multiple setlist files when cut-on-manual mode is enabled',
        () async {
      sourceResolver.projects = [
        ResolvedExportProject(
          source: SetlistExportSource('setlist-1'),
          duration: const Duration(minutes: 2),
        ),
        ResolvedExportProject(
          source: SetlistExportSource('setlist-1'),
          duration: const Duration(minutes: 3),
        ),
      ];
      audioExportTranscoder.progressValues = [1.0];

      await expectLater(
        engine.exportToMp3(
          source: SetlistExportSource('setlist-1'),
          outputPath: '/tmp/setlist.mp3',
          layout: ExportMp3Layout.cutOnManual,
        ),
        emitsInOrder([
          0.15,
          closeTo(0.3, 0.0001),
          0.575,
          closeTo(0.725, 0.0001),
          1.0,
          emitsDone,
        ]),
      );

      expect(audioExportTranscoder.outputPaths, [
        '/tmp/setlist_part01.mp3',
        '/tmp/setlist_part02.mp3',
      ]);
    });

    test('exports a setlist source through the same pipeline', () async {
      sourceResolver.project = ResolvedExportProject(
        source: SetlistExportSource('setlist-1'),
        duration: const Duration(minutes: 8),
        warnings: const [voiceCueExportWarning],
      );

      await expectLater(
        engine.exportToMp3(
          source: SetlistExportSource('setlist-1'),
          outputPath: '/tmp/setlist.mp3',
          bitrateBps: 256000,
        ),
        emitsThrough(1.0),
      );

      expect(sourceResolver.resolvedSources, [isA<SetlistExportSource>()]);
      expect(audioExportTranscoder.bitrates, [256000]);
    });

    test('throws for a non-positive export bitrate', () async {
      await expectLater(
        engine.exportToMp3(
          source: SongExportSource('song-1'),
          outputPath: '/tmp/song.mp3',
          bitrateBps: 0,
        ),
        emitsError(isA<ArgumentError>()),
      );
    });
  });

  test('voice cue export warning string stays stable', () {
    expect(
      voiceCueExportWarning,
      'Voice cues cannot be exported – system TTS does not support audio capture.',
    );
  });
}

class _FakeExportSourceResolver implements ExportSourceResolver {
  final List<ExportSource> resolvedSources = [];
  ResolvedExportProject project = ResolvedExportProject(
    source: SongExportSource('song-1'),
    duration: const Duration(minutes: 1),
  );
  List<ResolvedExportProject>? projects;

  @override
  Future<ResolvedExportProject> resolve(
    ExportSource source, {
    ExportContentOptions contentOptions = const ExportContentOptions(),
  }) async {
    resolvedSources.add(source);
    return project;
  }

  @override
  Future<List<ResolvedExportProject>> resolveProjects(
    ExportSource source, {
    ExportMp3Layout layout = ExportMp3Layout.singleFile,
    ExportContentOptions contentOptions = const ExportContentOptions(),
  }) async {
    resolvedSources.add(source);
    return projects ?? [project];
  }
}

class _FakeOfflineAudioRenderer implements OfflineAudioRenderer {
  final List<ResolvedExportProject> renderedProjects = [];

  @override
  Future<RenderedAudioBuffer> render(ResolvedExportProject project) async {
    renderedProjects.add(project);
    return RenderedAudioBuffer(
      samples: Float32List.fromList(const [0.0, 0.5, -0.5, 0.0]),
      sampleRate: 44100,
      channelCount: 2,
      duration: project.duration,
    );
  }
}

class _FakeAudioExportTranscoder implements AudioExportTranscoder {
  final List<String> outputPaths = [];
  final List<int> bitrates = [];
  List<double> progressValues = const [1.0];

  @override
  Stream<double> transcodeToMp3({
    required RenderedAudioBuffer audioBuffer,
    required String outputPath,
    required int bitrateBps,
  }) async* {
    outputPaths.add(outputPath);
    bitrates.add(bitrateBps);

    for (final progress in progressValues) {
      yield progress;
    }
  }
}
