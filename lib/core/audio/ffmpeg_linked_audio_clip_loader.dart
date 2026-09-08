import 'dart:io';

import '../domain/linked_audio_file.dart';
import 'export_engine.dart';
import 'ffmpeg_audio_export_transcoder.dart';
import 'ffmpeg_helpers.dart';
import 'linked_audio_export_augmenter.dart';
import 'wave_file_decoder.dart';

class FfmpegLinkedAudioClipLoader implements LinkedAudioClipLoader {
  FfmpegLinkedAudioClipLoader({
    FfmpegAudioExportClient? ffmpegAudioExportClient,
    WaveFileDecoder? waveFileDecoder,
  })  : _ffmpegAudioExportClient =
            ffmpegAudioExportClient ?? const FfmpegKitAudioExportClient(),
        _waveFileDecoder = waveFileDecoder ?? const WaveFileDecoder();

  static const String _temporaryDirectoryPrefix = 'tempodeck_linked_audio_';
  static const String _temporaryWaveFileName = 'linked_audio.wav';
  static const int _targetSampleRate = 44100;
  static const int _targetChannelCount = 2;

  final FfmpegAudioExportClient _ffmpegAudioExportClient;
  final WaveFileDecoder _waveFileDecoder;

  @override
  Future<ExportAudioClip> loadClip(LinkedAudioFile linkedAudioFile) async {
    Directory? temporaryDirectory;

    try {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        _temporaryDirectoryPrefix,
      );
      final outputPath =
          '${temporaryDirectory.path}${Platform.pathSeparator}$_temporaryWaveFileName';
      final result = await _ffmpegAudioExportClient.execute(
        command: _buildCommand(
          inputPath: linkedAudioFile.filePath,
          outputPath: outputPath,
        ),
      );

      switch (result) {
        case FfmpegTranscodeSuccess():
          return _waveFileDecoder.decode(await File(outputPath).readAsBytes());
        case FfmpegTranscodeCancelled():
          throw StateError('Linked audio clip decode was cancelled.');
        case FfmpegTranscodeFailure():
          throw StateError(
            ffmpegFailureMessage(
              result,
              operationLabel: 'FFmpeg linked audio decode',
            ),
          );
      }
    } finally {
      if (temporaryDirectory != null && await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }

  String _buildCommand({
    required String inputPath,
    required String outputPath,
  }) {
    return '-y '
        '-i ${ffmpegQuotedPath(inputPath)} '
        '-vn '
        '-acodec pcm_s16le '
        '-ar $_targetSampleRate '
        '-ac $_targetChannelCount '
        '${ffmpegQuotedPath(outputPath)}';
  }

}
