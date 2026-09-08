import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/export_engine.dart';
import 'package:tempodeck/core/audio/ffmpeg_audio_export_transcoder.dart';

void main() {
  group('FfmpegAudioExportTranscoder', () {
    late _FakeFfmpegAudioExportClient client;
    late FfmpegAudioExportTranscoder transcoder;
    late Directory temporaryOutputDirectory;

    setUp(() async {
      client = _FakeFfmpegAudioExportClient();
      transcoder = FfmpegAudioExportTranscoder(
        ffmpegAudioExportClient: client,
      );
      temporaryOutputDirectory = await Directory.systemTemp.createTemp(
        'tempodeck_ffmpeg_test_',
      );
    });

    tearDown(() async {
      if (await temporaryOutputDirectory.exists()) {
        await temporaryOutputDirectory.delete(recursive: true);
      }
    });

    test('writes a temporary wave file and invokes ffmpeg mp3 encoding',
        () async {
      client.result = const FfmpegTranscodeSuccess();

      await expectLater(
        transcoder.transcodeToMp3(
          audioBuffer: _audioBuffer(duration: const Duration(seconds: 2)),
          outputPath:
              '${temporaryOutputDirectory.path}${Platform.pathSeparator}song.mp3',
          bitrateBps: 192000,
        ),
        emitsInOrder([1.0, emitsDone]),
      );

      expect(client.commands, hasLength(1));
      expect(client.commands.single, contains('-codec:a libmp3lame'));
      expect(client.commands.single, contains('-b:a 192000'));
      expect(
        client.commands.single,
        contains(
          '"${temporaryOutputDirectory.path}${Platform.pathSeparator}song.mp3"',
        ),
      );
      expect(client.inputWaveHeaders, ['RIFF']);
    });

    test('emits monotonic progress updates from ffmpeg statistics', () async {
      client.result = const FfmpegTranscodeSuccess();
      client.statisticsMoments = const [
        Duration(milliseconds: 500),
        Duration(milliseconds: 1500),
        Duration(milliseconds: 2500),
      ];

      await expectLater(
        transcoder.transcodeToMp3(
          audioBuffer: _audioBuffer(duration: const Duration(seconds: 2)),
          outputPath:
              '${temporaryOutputDirectory.path}${Platform.pathSeparator}song.mp3',
          bitrateBps: 192000,
        ),
        emitsInOrder([0.25, 0.75, 1.0, emitsDone]),
      );
    });

    test('surfaces ffmpeg failures as stream errors', () async {
      client.result = const FfmpegTranscodeFailure(
        output: 'encoder failed',
        failStackTrace: 'stack',
      );

      await expectLater(
        transcoder.transcodeToMp3(
          audioBuffer: _audioBuffer(duration: const Duration(seconds: 2)),
          outputPath:
              '${temporaryOutputDirectory.path}${Platform.pathSeparator}song.mp3',
          bitrateBps: 192000,
        ),
        emitsError(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('encoder failed'),
          ),
        ),
      );
    });

    test('surfaces ffmpeg cancellation as a stream error', () async {
      client.result = const FfmpegTranscodeCancelled();

      await expectLater(
        transcoder.transcodeToMp3(
          audioBuffer: _audioBuffer(duration: const Duration(seconds: 2)),
          outputPath:
              '${temporaryOutputDirectory.path}${Platform.pathSeparator}song.mp3',
          bitrateBps: 192000,
        ),
        emitsError(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('cancelled'),
          ),
        ),
      );
    });
  });
}

class _FakeFfmpegAudioExportClient implements FfmpegAudioExportClient {
  final List<String> commands = [];
  final List<String> inputWaveHeaders = [];
  List<Duration> statisticsMoments = const [];
  FfmpegTranscodeResult result = const FfmpegTranscodeSuccess();

  @override
  Future<FfmpegTranscodeResult> execute({
    required String command,
    FfmpegStatisticsCallback? onStatistics,
  }) async {
    commands.add(command);

    final inputPath = _extractQuotedPath(command, marker: '-i ');
    final inputBytes = await File(inputPath).readAsBytes();
    inputWaveHeaders.add(String.fromCharCodes(inputBytes.sublist(0, 4)));

    for (final statisticsMoment in statisticsMoments) {
      onStatistics?.call(statisticsMoment);
    }

    // Simulate FFmpeg writing an output file on success.
    if (result is FfmpegTranscodeSuccess) {
      final outputPath = _extractOutputPath(command);
      await File(outputPath).writeAsBytes([0xFF, 0xFB, 0x90, 0x00]);
    }

    return result;
  }

  String _extractOutputPath(String command) {
    // Output path is the last quoted string in the command.
    final lastQuoteEnd = command.lastIndexOf('"');
    final lastQuoteStart = command.lastIndexOf('"', lastQuoteEnd - 1);
    return command.substring(lastQuoteStart + 1, lastQuoteEnd);
  }

  String _extractQuotedPath(String command, {required String marker}) {
    final markerIndex = command.indexOf(marker);
    final startQuoteIndex = command.indexOf('"', markerIndex);
    final endQuoteIndex = command.indexOf('"', startQuoteIndex + 1);
    return command.substring(startQuoteIndex + 1, endQuoteIndex);
  }
}

RenderedAudioBuffer _audioBuffer({required Duration duration}) {
  return RenderedAudioBuffer(
    samples: Float32List.fromList(const [0.0, 0.5, -0.5, 0.0]),
    sampleRate: ExportAudioFormat.defaultSampleRate,
    channelCount: ExportAudioFormat.defaultChannelCount,
    duration: duration,
  );
}
