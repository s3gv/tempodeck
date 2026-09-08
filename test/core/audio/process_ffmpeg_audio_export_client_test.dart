import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/process_ffmpeg_audio_export_client.dart';

void main() {
  group('ProcessFfmpegAudioExportClient argument parsing', () {
    test('splits simple flags', () {
      final args =
          ProcessFfmpegAudioExportClient.parseCommandToArgs('-y -vn -ac 2');
      expect(args, ['-y', '-vn', '-ac', '2']);
    });

    test('handles double-quoted paths with spaces', () {
      final args = ProcessFfmpegAudioExportClient.parseCommandToArgs(
        '-i "/path/to my/file.mp3" -vn output.wav',
      );
      expect(args, ['-i', '/path/to my/file.mp3', '-vn', 'output.wav']);
    });

    test('preserves backslashes in Windows paths', () {
      final args = ProcessFfmpegAudioExportClient.parseCommandToArgs(
        r'-i "C:\Users\Alice\Music\my song.mp3" -vn output.wav',
      );
      expect(args, [
        '-i',
        r'C:\Users\Alice\Music\my song.mp3',
        '-vn',
        'output.wav',
      ]);
    });

    test('preserves backslashes in unquoted Windows paths', () {
      final args = ProcessFfmpegAudioExportClient.parseCommandToArgs(
        r'-i C:\Users\Alice\file.mp3 -vn output.wav',
      );
      expect(args, [
        '-i',
        r'C:\Users\Alice\file.mp3',
        '-vn',
        'output.wav',
      ]);
    });

    test('handles multiple quoted arguments', () {
      final args = ProcessFfmpegAudioExportClient.parseCommandToArgs(
        '-y -i "/input path/file.wav" -vn -codec:a libmp3lame '
        '"/output path/result.mp3"',
      );
      expect(args, [
        '-y',
        '-i',
        '/input path/file.wav',
        '-vn',
        '-codec:a',
        'libmp3lame',
        '/output path/result.mp3',
      ]);
    });

    test('handles empty command', () {
      final args = ProcessFfmpegAudioExportClient.parseCommandToArgs('');
      expect(args, isEmpty);
    });

    test('handles consecutive spaces', () {
      final args =
          ProcessFfmpegAudioExportClient.parseCommandToArgs('-y   -vn   -ac 2');
      expect(args, ['-y', '-vn', '-ac', '2']);
    });

    test('handles typical waveform decode command', () {
      final args = ProcessFfmpegAudioExportClient.parseCommandToArgs(
        '-y -i "/Users/test/Music/my song.mp3" '
        '-vn -acodec pcm_s16le -ar 44100 -ac 2 '
        '"/tmp/tempodeck/output.wav"',
      );
      expect(args, [
        '-y',
        '-i',
        '/Users/test/Music/my song.mp3',
        '-vn',
        '-acodec',
        'pcm_s16le',
        '-ar',
        '44100',
        '-ac',
        '2',
        '/tmp/tempodeck/output.wav',
      ]);
    });

    test('handles typical mp3 export command', () {
      final args = ProcessFfmpegAudioExportClient.parseCommandToArgs(
        '-y -i "/tmp/tempodeck_export_abc/input.wav" '
        '-vn -codec:a libmp3lame -b:a 192000 '
        '"/Users/test/Desktop/export.mp3"',
      );
      expect(args, [
        '-y',
        '-i',
        '/tmp/tempodeck_export_abc/input.wav',
        '-vn',
        '-codec:a',
        'libmp3lame',
        '-b:a',
        '192000',
        '/Users/test/Desktop/export.mp3',
      ]);
    });
  });
}
