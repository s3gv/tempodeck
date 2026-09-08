import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../domain/linked_audio_file.dart';
import 'audio_duration_reader.dart';
import 'export_engine.dart';
import 'linked_audio_export_augmenter.dart';
import 'soloud_client.dart';

/// Desktop implementation of [LinkedAudioClipLoader] that reads audio samples
/// directly from SoLoud's built-in decoders (MP3, WAV, OGG, FLAC).
///
/// This avoids the FFmpeg dependency entirely — no external binary needed.
///
/// On macOS, file paths from the file picker may become inaccessible after
/// app restart due to sandbox restrictions. To handle this, we read the file
/// bytes into memory first (which works with sandbox-granted access), then
/// use [SoLoudClient.readSamplesFromMem] to decode in-memory.
class SoLoudLinkedAudioClipLoader implements LinkedAudioClipLoader {
  SoLoudLinkedAudioClipLoader({
    required SoLoudClient soLoudClient,
    AudioDurationReader? durationReader,
  })  : _soLoudClient = soLoudClient,
        _durationReader = durationReader ?? const AudioDurationReader();

  static final Logger _logger = Logger('SoLoudLinkedAudioClipLoader');

  /// Number of equally-spaced samples to request from SoLoud.
  /// `fromClip` will bucket these down to 4800 peaks.
  /// Higher = smoother waveform but more memory/CPU.
  static const int _sampleCount = 48000;

  final SoLoudClient _soLoudClient;
  final AudioDurationReader _durationReader;

  @override
  Future<ExportAudioClip> loadClip(LinkedAudioFile linkedAudioFile) async {
    _logger.info(
      'Loading waveform samples from: ${linkedAudioFile.filePath}',
    );

    final file = File(linkedAudioFile.filePath);
    if (!file.existsSync()) {
      _logger.warning('Audio file not found: ${linkedAudioFile.filePath}');
      return ExportAudioClip(
        samples: Float32List(0),
        sampleRate: 44100,
        channelCount: 1,
      );
    }

    // Read file bytes into memory first. This works even in the macOS
    // sandbox because the main isolate still has file-access permission
    // from the original file picker grant. The compute() isolate used by
    // readSamplesFromFile would lose that sandbox scope.
    final bytes = await file.readAsBytes();

    final rawSamples = await _soLoudClient.readSamplesFromMem(
      bytes,
      _sampleCount,
      average: true,
    );

    // SoLoud returns an unmodifiable Float32List — copy to mutable.
    final samples = Float32List(rawSamples.length);
    for (var i = 0; i < rawSamples.length; i++) {
      samples[i] = rawSamples[i];
    }

    // Read duration from file header (no SoLoud loadFile needed).
    final duration = await _durationReader.readDuration(
      linkedAudioFile.filePath,
    );
    final durationMs = duration?.inMilliseconds ?? 0;

    if (durationMs <= 0) {
      _logger.warning(
        'Could not determine audio duration for '
        '${linkedAudioFile.filePath}. Waveform offset will be limited.',
      );
      // Fallback: present samples at 44100 Hz — duration will be
      // samples.length / 44100 ≈ 1.09s which is wrong but non-crashing.
      return ExportAudioClip(
        samples: samples,
        sampleRate: 44100,
        channelCount: 1,
      );
    }

    // Encode the real duration into sampleRate so that fromClip computes:
    //   totalMs = frameCount * 1000 / sampleRate == durationMs
    // With channelCount=1, frameCount = samples.length.
    final syntheticSampleRate =
        (samples.length * 1000 / durationMs).round().clamp(1, 1000000);

    _logger.info(
      'Loaded ${samples.length} waveform samples '
      '(${(durationMs / 1000).toStringAsFixed(1)}s) '
      'from ${linkedAudioFile.filePath}.',
    );

    return ExportAudioClip(
      samples: samples,
      sampleRate: syntheticSampleRate,
      channelCount: 1,
    );
  }
}
