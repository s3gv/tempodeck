import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_audio_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_audio_flutter/return_code.dart';
import 'package:ffmpeg_kit_audio_flutter/session.dart';
import 'package:logging/logging.dart';

import 'export_engine.dart';
import 'ffmpeg_helpers.dart';
import 'wave_file_encoder.dart';

final _logger = Logger('FfmpegAudioExportTranscoder');

typedef FfmpegStatisticsCallback = void Function(Duration processedDuration);

sealed class FfmpegTranscodeResult {
  const FfmpegTranscodeResult();
}

final class FfmpegTranscodeSuccess extends FfmpegTranscodeResult {
  const FfmpegTranscodeSuccess();
}

final class FfmpegTranscodeCancelled extends FfmpegTranscodeResult {
  const FfmpegTranscodeCancelled();
}

final class FfmpegTranscodeFailure extends FfmpegTranscodeResult {
  const FfmpegTranscodeFailure({
    required this.output,
    required this.failStackTrace,
  });

  final String? output;
  final String? failStackTrace;
}

abstract class FfmpegAudioExportClient {
  Future<FfmpegTranscodeResult> execute({
    required String command,
    FfmpegStatisticsCallback? onStatistics,
  });
}

class FfmpegKitAudioExportClient implements FfmpegAudioExportClient {
  const FfmpegKitAudioExportClient();

  @override
  Future<FfmpegTranscodeResult> execute({
    required String command,
    FfmpegStatisticsCallback? onStatistics,
  }) async {
    final completedSession = Completer<Session>();

    await FFmpegKit.executeAsync(
      command,
      (session) {
        if (!completedSession.isCompleted) {
          completedSession.complete(session);
        }
      },
      null,
      (statistics) {
        if (onStatistics != null) {
          onStatistics(
            Duration(milliseconds: statistics.getTime().round()),
          );
        }
      },
    );

    final session = await completedSession.future;
    final output = await session.getOutput();
    final returnCode = await session.getReturnCode();
    _logger.info(
      'FFmpeg session complete: returnCode=${returnCode?.getValue()}, '
      'output=${output?.substring(0, output.length.clamp(0, 500))}',
    );
    return _resultForSession(session);
  }

  Future<FfmpegTranscodeResult> _resultForSession(Session session) async {
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      return const FfmpegTranscodeSuccess();
    }

    if (ReturnCode.isCancel(returnCode)) {
      return const FfmpegTranscodeCancelled();
    }

    return FfmpegTranscodeFailure(
      output: await session.getOutput(),
      failStackTrace: await session.getFailStackTrace(),
    );
  }
}

class FfmpegAudioExportTranscoder implements AudioExportTranscoder {
  FfmpegAudioExportTranscoder({
    FfmpegAudioExportClient? ffmpegAudioExportClient,
    WaveFileEncoder? waveFileEncoder,
  })  : _ffmpegAudioExportClient =
            ffmpegAudioExportClient ?? const FfmpegKitAudioExportClient(),
        _waveFileEncoder = waveFileEncoder ?? const WaveFileEncoder();

  static const String _temporaryDirectoryPrefix = 'tempodeck_export_';
  static const String _temporaryWaveFileName = 'input.wav';

  final FfmpegAudioExportClient _ffmpegAudioExportClient;
  final WaveFileEncoder _waveFileEncoder;

  @override
  Stream<double> transcodeToMp3({
    required RenderedAudioBuffer audioBuffer,
    required String outputPath,
    required int bitrateBps,
  }) {
    return Stream.multi((controller) {
      unawaited(
        _runTranscode(
          controller: controller,
          audioBuffer: audioBuffer,
          outputPath: outputPath,
          bitrateBps: bitrateBps,
        ),
      );
    });
  }

  Future<void> _runTranscode({
    required MultiStreamController<double> controller,
    required RenderedAudioBuffer audioBuffer,
    required String outputPath,
    required int bitrateBps,
  }) async {
    Directory? temporaryDirectory;

    try {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        _temporaryDirectoryPrefix,
      );
      final inputFile = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}$_temporaryWaveFileName',
      );
      final outputFile = File(outputPath);

      await outputFile.parent.create(recursive: true);
      final wavBytes = _waveFileEncoder.encode(
        samples: audioBuffer.samples,
        sampleRate: audioBuffer.sampleRate,
        channelCount: audioBuffer.channelCount,
      );
      await inputFile.writeAsBytes(wavBytes);
      _logger.info(
        'WAV written: ${inputFile.path} '
        '(${wavBytes.length} bytes, '
        'duration=${audioBuffer.duration.inMilliseconds}ms, '
        'samples=${audioBuffer.samples.length})',
      );

      final command = _buildCommand(
        inputPath: inputFile.path,
        outputPath: outputPath,
        bitrateBps: bitrateBps,
      );
      _logger.info('FFmpeg command: $command');

      var emittedProgress = 0.0;
      final result = await _ffmpegAudioExportClient.execute(
        command: command,
        onStatistics: (processedDuration) {
          if (audioBuffer.duration <= Duration.zero) {
            return;
          }

          final progress = processedDuration.inMicroseconds /
              audioBuffer.duration.inMicroseconds;
          final normalizedProgress = progress.clamp(0.0, 1.0);
          if (normalizedProgress > emittedProgress &&
              normalizedProgress < 1.0) {
            emittedProgress = normalizedProgress;
            controller.add(normalizedProgress);
          }
        },
      );

      switch (result) {
        case FfmpegTranscodeSuccess():
          final outputExists = await outputFile.exists();
          final outputSize =
              outputExists ? await outputFile.length() : 0;
          _logger.info(
            'FFmpeg success: output exists=$outputExists, '
            'size=$outputSize bytes',
          );
          if (!outputExists || outputSize == 0) {
            throw StateError(
              'FFmpeg reported success but output file is '
              '${outputExists ? "empty" : "missing"} at $outputPath',
            );
          }
          controller.add(1.0);
        case FfmpegTranscodeCancelled():
          throw StateError('MP3 export was cancelled.');
        case FfmpegTranscodeFailure():
          throw StateError(
            ffmpegFailureMessage(
              result,
              operationLabel: 'FFmpeg MP3 export',
            ),
          );
      }
    } catch (error, stackTrace) {
      controller.addError(error, stackTrace);
    } finally {
      if (temporaryDirectory != null && await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
      await controller.close();
    }
  }

  String _buildCommand({
    required String inputPath,
    required String outputPath,
    required int bitrateBps,
  }) {
    return '-y '
        '-i ${ffmpegQuotedPath(inputPath)} '
        '-vn '
        '-codec:a libmp3lame '
        '-b:a $bitrateBps '
        '${ffmpegQuotedPath(outputPath)}';
  }

}
