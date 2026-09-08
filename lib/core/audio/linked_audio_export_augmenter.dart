import 'dart:typed_data';

import '../domain/linked_audio_file.dart';
import 'export_engine.dart';

abstract class LinkedAudioClipLoader {
  Future<ExportAudioClip> loadClip(LinkedAudioFile linkedAudioFile);
}

class LinkedAudioExportAugmenter {
  const LinkedAudioExportAugmenter({
    required LinkedAudioClipLoader linkedAudioClipLoader,
  }) : _linkedAudioClipLoader = linkedAudioClipLoader;

  final LinkedAudioClipLoader _linkedAudioClipLoader;

  /// Augments [project] with the linked audio file.
  ///
  /// [linkedAudioFile.offsetMilliseconds] is treated as a seek position within
  /// the audio file — the first [offsetMilliseconds] of audio are skipped.
  /// This matches the live playback behaviour where
  /// [SoLoudAudioEngine.prepareLinkedAudioPlayback] seeks the audio source to
  /// the offset before un-pausing it.
  ///
  /// When [maxDuration] is set, the (already-seeked) clip is trimmed so that it
  /// does not extend beyond [maxDuration] from [timelineOffset]. This prevents
  /// linked audio from one song bleeding into the next in setlist exports.
  Future<ResolvedExportProject> augment({
    required ResolvedExportProject project,
    required LinkedAudioFile? linkedAudioFile,
    Duration timelineOffset = Duration.zero,
    Duration? maxDuration,
  }) async {
    if (linkedAudioFile == null) {
      return project;
    }

    final gain = _normalizedGain(linkedAudioFile.volumePercent);
    var clip = await _linkedAudioClipLoader.loadClip(linkedAudioFile);

    if (linkedAudioFile.offsetMilliseconds > 0) {
      clip = _seekClip(clip, linkedAudioFile.offsetMilliseconds);
    }

    if (maxDuration != null) {
      clip = _trimClipToMaxDuration(clip, maxDuration);
    }

    final audioEvent = ExportAudioEvent(
      offset: timelineOffset,
      clip: clip,
      gain: gain,
    );

    return project.copyWith(
      audioEvents: <ExportAudioEvent>[
        ...project.audioEvents,
        audioEvent,
      ],
    );
  }

  /// Skips the first [offsetMilliseconds] of audio, matching the seek
  /// behaviour of [SoLoudAudioEngine.prepareLinkedAudioPlayback].
  ExportAudioClip _seekClip(ExportAudioClip clip, int offsetMilliseconds) {
    final skipFrames =
        (offsetMilliseconds * clip.sampleRate) ~/
            Duration.millisecondsPerSecond;
    final skipSamples = skipFrames * clip.channelCount;

    if (skipSamples >= clip.samples.length) {
      return ExportAudioClip(
        samples: Float32List(0),
        sampleRate: clip.sampleRate,
        channelCount: clip.channelCount,
      );
    }

    return ExportAudioClip(
      samples: Float32List.sublistView(clip.samples, skipSamples),
      sampleRate: clip.sampleRate,
      channelCount: clip.channelCount,
    );
  }

  /// Trims [clip] so that it does not exceed [maxDuration].
  ExportAudioClip _trimClipToMaxDuration(
    ExportAudioClip clip,
    Duration maxDuration,
  ) {
    if (maxDuration <= Duration.zero) {
      return ExportAudioClip(
        samples: Float32List(0),
        sampleRate: clip.sampleRate,
        channelCount: clip.channelCount,
      );
    }

    final maxFrames =
        (maxDuration.inMicroseconds * clip.sampleRate) ~/
            Duration.microsecondsPerSecond;
    final clipFrames = clip.samples.length ~/ clip.channelCount;

    if (clipFrames <= maxFrames) {
      return clip;
    }

    final maxSamples = maxFrames * clip.channelCount;
    return ExportAudioClip(
      samples: Float32List.sublistView(clip.samples, 0, maxSamples),
      sampleRate: clip.sampleRate,
      channelCount: clip.channelCount,
    );
  }

  double _normalizedGain(int volumePercent) {
    if (volumePercent < 0 || volumePercent > 100) {
      throw ArgumentError.value(
        volumePercent,
        'linkedAudioFile.volumePercent',
        'Linked audio export volume must stay within 0–100 percent.',
      );
    }

    return volumePercent / 100;
  }
}
