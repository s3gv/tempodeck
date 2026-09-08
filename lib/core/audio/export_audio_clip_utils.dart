import 'dart:math' as math;
import 'dart:typed_data';

import 'export_engine.dart';

/// Resamples an [ExportAudioClip] to the given [targetSampleRate] using linear
/// interpolation. Returns the clip unchanged if it already matches.
ExportAudioClip resampleClip(ExportAudioClip clip, int targetSampleRate) {
  if (clip.sampleRate == targetSampleRate) {
    return clip;
  }

  final channels = clip.channelCount;
  final sourceFrames = clip.samples.length ~/ channels;
  final ratio = clip.sampleRate / targetSampleRate;
  final targetFrames = (sourceFrames / ratio).floor();
  final resampled = Float32List(targetFrames * channels);

  for (var frame = 0; frame < targetFrames; frame++) {
    final sourcePosition = frame * ratio;
    final sourceIndex = sourcePosition.floor();
    final fraction = sourcePosition - sourceIndex;
    final nextIndex = math.min(sourceIndex + 1, sourceFrames - 1);

    for (var ch = 0; ch < channels; ch++) {
      final current = clip.samples[sourceIndex * channels + ch];
      final next = clip.samples[nextIndex * channels + ch];
      resampled[frame * channels + ch] = current + (next - current) * fraction;
    }
  }

  return ExportAudioClip(
    samples: resampled,
    sampleRate: targetSampleRate,
    channelCount: channels,
  );
}

/// Converts a mono [ExportAudioClip] to stereo by duplicating each sample
/// into left and right channels. Returns the clip unchanged if it is already
/// stereo.
ExportAudioClip ensureStereo(ExportAudioClip clip) {
  if (clip.channelCount == ExportAudioFormat.defaultChannelCount) {
    return clip;
  }

  if (clip.channelCount != 1) {
    throw ArgumentError.value(
      clip.channelCount,
      'channelCount',
      'Only mono (1) clips can be converted to stereo.',
    );
  }

  final monoSamples = clip.samples;
  final stereoSamples = Float32List(monoSamples.length * 2);

  for (var i = 0; i < monoSamples.length; i++) {
    stereoSamples[i * 2] = monoSamples[i];
    stereoSamples[i * 2 + 1] = monoSamples[i];
  }

  return ExportAudioClip(
    samples: stereoSamples,
    sampleRate: clip.sampleRate,
    channelCount: ExportAudioFormat.defaultChannelCount,
  );
}
