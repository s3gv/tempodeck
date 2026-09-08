import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/export_engine.dart';
import 'package:tempodeck/core/audio/ffmpeg_audio_export_transcoder.dart';
import 'package:tempodeck/core/audio/ffmpeg_linked_audio_clip_loader.dart';
import 'package:tempodeck/core/audio/wave_file_encoder.dart';
import 'package:tempodeck/core/domain/linked_audio_file.dart';

void main() {
  test('decodes linked audio files through ffmpeg into export clips', () async {
    final ffmpegClient = _FakeFfmpegAudioExportClient();
    final loader = FfmpegLinkedAudioClipLoader(
      ffmpegAudioExportClient: ffmpegClient,
    );

    final clip = await loader.loadClip(
      const LinkedAudioFile(
        filePath: '/tmp/source.wav',
        displayName: 'Source',
        offsetMilliseconds: 0,
        volumePercent: 80,
      ),
    );

    expect(ffmpegClient.executedCommands, hasLength(1));
    expect(ffmpegClient.executedCommands.single, contains('-ar 44100'));
    expect(ffmpegClient.executedCommands.single, contains('-ac 2'));
    expect(clip.sampleRate, ExportAudioFormat.defaultSampleRate);
    expect(clip.channelCount, ExportAudioFormat.defaultChannelCount);
    expect(clip.samples, hasLength(4));
  });

  test('surfaces ffmpeg decode failures', () async {
    final loader = FfmpegLinkedAudioClipLoader(
      ffmpegAudioExportClient: _FailingFfmpegAudioExportClient(),
    );

    await expectLater(
      loader.loadClip(
        const LinkedAudioFile(
          filePath: '/tmp/source.wav',
          displayName: 'Source',
          offsetMilliseconds: 0,
          volumePercent: 80,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('surfaces cancelled ffmpeg decodes', () async {
    final loader = FfmpegLinkedAudioClipLoader(
      ffmpegAudioExportClient: _CancelledFfmpegAudioExportClient(),
    );

    await expectLater(
      loader.loadClip(
        const LinkedAudioFile(
          filePath: '/tmp/source.wav',
          displayName: 'Source',
          offsetMilliseconds: 0,
          volumePercent: 80,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}

class _FakeFfmpegAudioExportClient implements FfmpegAudioExportClient {
  final List<String> executedCommands = [];
  static const WaveFileEncoder _waveFileEncoder = WaveFileEncoder();

  @override
  Future<FfmpegTranscodeResult> execute({
    required String command,
    FfmpegStatisticsCallback? onStatistics,
  }) async {
    executedCommands.add(command);
    final outputPath = _extractLastQuotedPath(command);
    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsBytes(
      _waveFileEncoder.encode(
        samples: Float32List.fromList(const [0.0, 0.25, -0.25, 0.5]),
        sampleRate: ExportAudioFormat.defaultSampleRate,
        channelCount: ExportAudioFormat.defaultChannelCount,
      ),
    );
    return const FfmpegTranscodeSuccess();
  }

  String _extractLastQuotedPath(String command) {
    final matches = RegExp(r'"([^"]+)"').allMatches(command).toList();
    if (matches.isEmpty) {
      throw StateError('Expected a quoted output path in the ffmpeg command.');
    }

    return matches.last.group(1)!;
  }
}

class _FailingFfmpegAudioExportClient implements FfmpegAudioExportClient {
  @override
  Future<FfmpegTranscodeResult> execute({
    required String command,
    FfmpegStatisticsCallback? onStatistics,
  }) async {
    return const FfmpegTranscodeFailure(
      output: 'decode failed',
      failStackTrace: null,
    );
  }
}

class _CancelledFfmpegAudioExportClient implements FfmpegAudioExportClient {
  @override
  Future<FfmpegTranscodeResult> execute({
    required String command,
    FfmpegStatisticsCallback? onStatistics,
  }) async {
    return const FfmpegTranscodeCancelled();
  }
}
