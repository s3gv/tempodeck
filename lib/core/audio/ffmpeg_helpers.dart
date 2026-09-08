import 'ffmpeg_audio_export_transcoder.dart';

/// Wraps [path] in double quotes, escaping any embedded double quotes.
///
/// FFmpeg commands require paths with spaces or special characters to be
/// quoted. This helper ensures the path is safe for use in an FFmpeg
/// command string.
String ffmpegQuotedPath(String path) {
  final escapedPath = path.replaceAll('"', r'\"');
  return '"$escapedPath"';
}

/// Builds a human-readable failure message from an [FfmpegTranscodeFailure].
///
/// [operationLabel] identifies the operation that failed (e.g.
/// `'FFmpeg MP3 export'` or `'FFmpeg linked audio decode'`).
String ffmpegFailureMessage(
  FfmpegTranscodeFailure result, {
  required String operationLabel,
}) {
  final output = result.output;
  final failStackTrace = result.failStackTrace;
  final details = <String>[
    if (output != null && output.trim().isNotEmpty) output.trim(),
    if (failStackTrace != null && failStackTrace.trim().isNotEmpty)
      failStackTrace.trim(),
  ];
  if (details.isEmpty) {
    return '$operationLabel failed.';
  }

  return '$operationLabel failed: ${details.join(' | ')}';
}
