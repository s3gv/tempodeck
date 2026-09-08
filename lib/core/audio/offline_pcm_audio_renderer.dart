import 'dart:typed_data';

import 'export_engine.dart';

class OfflinePcmAudioRenderer implements OfflineAudioRenderer {
  const OfflinePcmAudioRenderer();

  @override
  Future<RenderedAudioBuffer> render(ResolvedExportProject project) async {
    final format = project.outputFormat;
    final totalFrames = _frameCountForDuration(project.duration, format.sampleRate);
    final mixedSamples = Float32List(totalFrames * format.channelCount);

    for (final event in project.audioEvents) {
      _validateClipFormat(event.clip, format);
    }

    for (final event in project.audioEvents) {
      _mixEvent(
        targetSamples: mixedSamples,
        event: event,
        outputFormat: format,
        totalFrames: totalFrames,
      );
    }

    return RenderedAudioBuffer(
      samples: mixedSamples,
      sampleRate: format.sampleRate,
      channelCount: format.channelCount,
      duration: project.duration,
    );
  }

  void _mixEvent({
    required Float32List targetSamples,
    required ExportAudioEvent event,
    required ExportAudioFormat outputFormat,
    required int totalFrames,
  }) {
    final clip = event.clip;

    final startFrame = _frameCountForDuration(
      event.offset.isNegative ? Duration.zero : event.offset,
      outputFormat.sampleRate,
    );
    if (startFrame >= totalFrames) {
      return;
    }

    final availableFrames = totalFrames - startFrame;
    final clipFrames = clip.samples.length ~/ clip.channelCount;
    final framesToMix = clipFrames < availableFrames ? clipFrames : availableFrames;

    for (var frameIndex = 0; frameIndex < framesToMix; frameIndex += 1) {
      final targetFrameIndex = startFrame + frameIndex;
      final targetBaseIndex = targetFrameIndex * outputFormat.channelCount;
      final clipBaseIndex = frameIndex * clip.channelCount;

      for (var channelIndex = 0; channelIndex < outputFormat.channelCount; channelIndex += 1) {
        final mixedValue =
            targetSamples[targetBaseIndex + channelIndex] +
            clip.samples[clipBaseIndex + channelIndex] * event.gain;
        targetSamples[targetBaseIndex + channelIndex] = mixedValue.clamp(-1.0, 1.0);
      }
    }
  }

  void _validateClipFormat(ExportAudioClip clip, ExportAudioFormat outputFormat) {
    if (clip.sampleRate != outputFormat.sampleRate) {
      throw ArgumentError.value(
        clip.sampleRate,
        'clip.sampleRate',
        'Export audio clips must match the renderer sample rate.',
      );
    }

    if (clip.channelCount != outputFormat.channelCount) {
      throw ArgumentError.value(
        clip.channelCount,
        'clip.channelCount',
        'Export audio clips must match the renderer channel count.',
      );
    }
  }

  int _frameCountForDuration(Duration duration, int sampleRate) {
    return (duration.inMicroseconds * sampleRate) ~/ Duration.microsecondsPerSecond;
  }
}
