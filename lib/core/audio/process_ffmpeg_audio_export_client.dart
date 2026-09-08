import 'dart:io';

import 'package:logging/logging.dart';

import 'ffmpeg_audio_export_transcoder.dart';

/// Desktop implementation of [FfmpegAudioExportClient] that shells out to the
/// system `ffmpeg` binary via [Process.run].
///
/// On macOS, `ffmpeg` is typically installed via Homebrew. On Windows it must
/// be on PATH. Falls back to well-known macOS paths if the bare `ffmpeg`
/// command is not found.
class ProcessFfmpegAudioExportClient implements FfmpegAudioExportClient {
  const ProcessFfmpegAudioExportClient();

  static final Logger _logger = Logger('ProcessFfmpegAudioExportClient');

  /// Well-known locations for ffmpeg on macOS (Homebrew).
  static const List<String> _macOsFallbackPaths = [
    '/opt/homebrew/bin/ffmpeg',
    '/usr/local/bin/ffmpeg',
  ];

  @override
  Future<FfmpegTranscodeResult> execute({
    required String command,
    FfmpegStatisticsCallback? onStatistics,
  }) async {
    final ffmpegPath = await _resolveFfmpegPath();
    if (ffmpegPath == null) {
      return const FfmpegTranscodeFailure(
        output: 'ffmpeg binary not found. '
            'Please install ffmpeg (e.g. "brew install ffmpeg" on macOS '
            'or add ffmpeg to PATH on Windows).',
        failStackTrace: null,
      );
    }

    final args = _parseCommandToArgs(command);
    _logger.info('Executing: $ffmpegPath ${args.join(' ')}');

    try {
      final result = await Process.run(
        ffmpegPath,
        args,
        stderrEncoding: const SystemEncoding(),
        stdoutEncoding: const SystemEncoding(),
      );

      final stderr = result.stderr as String;
      final stdout = result.stdout as String;
      final combinedOutput = [stdout, stderr]
          .where((s) => s.trim().isNotEmpty)
          .join('\n');

      _logger.info(
        'ffmpeg exited with code ${result.exitCode}. '
        'Output: ${combinedOutput.substring(0, combinedOutput.length.clamp(0, 500))}',
      );

      if (result.exitCode == 0) {
        return const FfmpegTranscodeSuccess();
      }

      return FfmpegTranscodeFailure(
        output: combinedOutput.isEmpty ? null : combinedOutput,
        failStackTrace: null,
      );
    } on ProcessException catch (error) {
      _logger.severe('Failed to run ffmpeg process.', error);
      return FfmpegTranscodeFailure(
        output: 'Failed to execute ffmpeg: ${error.message}',
        failStackTrace: null,
      );
    }
  }

  /// Resolves the ffmpeg binary path. Tries `ffmpeg` on PATH first, then
  /// falls back to well-known macOS locations.
  Future<String?> _resolveFfmpegPath() async {
    // Try bare `ffmpeg` on PATH.
    if (await _isFfmpegAvailable('ffmpeg')) {
      return 'ffmpeg';
    }

    // On macOS, try Homebrew paths.
    if (Platform.isMacOS) {
      for (final path in _macOsFallbackPaths) {
        if (await File(path).exists()) {
          return path;
        }
      }
    }

    _logger.warning('ffmpeg not found on PATH or at known locations.');
    return null;
  }

  /// Checks whether [executable] is available by running `which` (Unix) or
  /// `where` (Windows).
  Future<bool> _isFfmpegAvailable(String executable) async {
    try {
      final whichCommand = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(whichCommand, [executable]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Parses an FFmpeg command string into a list of arguments, respecting
  /// double-quoted paths that may contain spaces.
  ///
  /// Example: `-y -i "/path/to my/file.mp3" -vn output.wav`
  /// → `['-y', '-i', '/path/to my/file.mp3', '-vn', 'output.wav']`
  static List<String> parseCommandToArgs(String command) =>
      _parseCommandToArgs(command);

  static List<String> _parseCommandToArgs(String command) {
    final args = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < command.length; i++) {
      final char = command[i];

      if (char == '"') {
        inQuotes = !inQuotes;
        continue;
      }

      if (char == ' ' && !inQuotes) {
        if (buffer.isNotEmpty) {
          args.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }

      buffer.write(char);
    }

    if (buffer.isNotEmpty) {
      args.add(buffer.toString());
    }

    return args;
  }
}
