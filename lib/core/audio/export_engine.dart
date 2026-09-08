import 'dart:io';
import 'dart:typed_data';

import 'i_export_engine.dart';

const String voiceCueExportWarning =
    'Voice cues cannot be exported – system TTS does not support audio capture.';
const String manualStepExportWarning =
    'Manual wait steps are skipped during export – transitions will be shorter than live.';

class ExportAudioFormat {
  const ExportAudioFormat({
    this.sampleRate = defaultSampleRate,
    this.channelCount = defaultChannelCount,
  });

  static const int defaultSampleRate = 44100;
  static const int defaultChannelCount = 2;

  final int sampleRate;
  final int channelCount;
}

class ExportAudioClip {
  const ExportAudioClip({
    required this.samples,
    required this.sampleRate,
    required this.channelCount,
  });

  final Float32List samples;
  final int sampleRate;
  final int channelCount;
}

class ExportAudioEvent {
  const ExportAudioEvent({
    required this.offset,
    required this.clip,
    this.gain = 1.0,
  });

  final Duration offset;
  final ExportAudioClip clip;
  final double gain;
}

class ResolvedExportProject {
  const ResolvedExportProject({
    required this.source,
    required this.duration,
    this.outputFormat = const ExportAudioFormat(),
    this.audioEvents = const [],
    this.warnings = const [],
  });

  final ExportSource source;
  final Duration duration;
  final ExportAudioFormat outputFormat;
  final List<ExportAudioEvent> audioEvents;
  final List<String> warnings;

  ResolvedExportProject copyWith({
    ExportSource? source,
    Duration? duration,
    ExportAudioFormat? outputFormat,
    List<ExportAudioEvent>? audioEvents,
    List<String>? warnings,
  }) {
    return ResolvedExportProject(
      source: source ?? this.source,
      duration: duration ?? this.duration,
      outputFormat: outputFormat ?? this.outputFormat,
      audioEvents: audioEvents ?? this.audioEvents,
      warnings: warnings ?? this.warnings,
    );
  }
}

class RenderedAudioBuffer {
  const RenderedAudioBuffer({
    required this.samples,
    required this.sampleRate,
    required this.channelCount,
    required this.duration,
  });

  final Float32List samples;
  final int sampleRate;
  final int channelCount;
  final Duration duration;
}

abstract class ExportSourceResolver {
  Future<ResolvedExportProject> resolve(
    ExportSource source, {
    ExportContentOptions contentOptions = const ExportContentOptions(),
  });

  Future<List<ResolvedExportProject>> resolveProjects(
    ExportSource source, {
    ExportMp3Layout layout = ExportMp3Layout.singleFile,
    ExportContentOptions contentOptions = const ExportContentOptions(),
  }) async {
    return [await resolve(source, contentOptions: contentOptions)];
  }
}

abstract class OfflineAudioRenderer {
  Future<RenderedAudioBuffer> render(ResolvedExportProject project);
}

abstract class AudioExportTranscoder {
  Stream<double> transcodeToMp3({
    required RenderedAudioBuffer audioBuffer,
    required String outputPath,
    required int bitrateBps,
  });
}

class ExportEngine implements IExportEngine {
  ExportEngine({
    required ExportSourceResolver sourceResolver,
    required OfflineAudioRenderer offlineAudioRenderer,
    required AudioExportTranscoder audioExportTranscoder,
  })  : _sourceResolver = sourceResolver,
        _offlineAudioRenderer = offlineAudioRenderer,
        _audioExportTranscoder = audioExportTranscoder;

  static const double _resolvedStageProgress = 0.15;
  static const double _renderedStageProgress = 0.45;
  static const int _bitsPerByte = 8;
  static const String _segmentFileSuffix = '_part';
  static const int _minimumSegmentPadding = 2;

  final ExportSourceResolver _sourceResolver;
  final OfflineAudioRenderer _offlineAudioRenderer;
  final AudioExportTranscoder _audioExportTranscoder;

  @override
  int estimateFileSizeBytes({
    required Duration duration,
    int bitrateBps = 192000,
  }) {
    _validateBitrate(bitrateBps);

    final totalBits =
        bitrateBps * duration.inMicroseconds / Duration.microsecondsPerSecond;
    return totalBits ~/ _bitsPerByte;
  }

  @override
  Stream<double> exportToMp3({
    required ExportSource source,
    required String outputPath,
    int bitrateBps = 192000,
    ExportMp3Layout layout = ExportMp3Layout.singleFile,
    ExportContentOptions contentOptions = const ExportContentOptions(),
    void Function(List<String> warnings)? onWarnings,
  }) async* {
    _validateBitrate(bitrateBps);

    final projects = await _sourceResolver.resolveProjects(
      source,
      layout: layout,
      contentOptions: contentOptions,
    );
    if (projects.isEmpty) {
      throw StateError('Export source did not resolve to any export projects.');
    }

    if (onWarnings != null) {
      final allWarnings = projects
          .expand((p) => p.warnings)
          .toSet()
          .toList(growable: false);
      if (allWarnings.isNotEmpty) {
        onWarnings(allWarnings);
      }
    }

    yield _resolvedStageProgress;

    final projectWeight = (1 - _resolvedStageProgress) / projects.length;
    for (var index = 0; index < projects.length; index++) {
      final project = projects[index];
      final audioBuffer = await _offlineAudioRenderer.render(project);
      yield _renderProgressForProject(index, projectWeight);

      await for (final progress in _audioExportTranscoder.transcodeToMp3(
        audioBuffer: audioBuffer,
        outputPath: _outputPathForProject(
          outputPath,
          layout: layout,
          segmentIndex: index,
          segmentCount: projects.length,
        ),
        bitrateBps: bitrateBps,
      )) {
        yield _mapTranscodeProgressForProject(
          index: index,
          projectWeight: projectWeight,
          progress: progress,
        );
      }
    }
  }

  void _validateBitrate(int bitrateBps) {
    if (bitrateBps <= 0) {
      throw ArgumentError.value(
        bitrateBps,
        'bitrateBps',
        'Export bitrate must be greater than zero.',
      );
    }
  }

  double _renderProgressForProject(int index, double projectWeight) {
    return _resolvedStageProgress +
        index * projectWeight +
        projectWeight * _postResolveRenderFraction;
  }

  double _mapTranscodeProgressForProject({
    required int index,
    required double projectWeight,
    required double progress,
  }) {
    final normalizedProgress = progress.clamp(0.0, 1.0);
    final projectBaseProgress = _resolvedStageProgress + index * projectWeight;
    final transcodeFraction = 1 - _postResolveRenderFraction;
    return (projectBaseProgress +
            projectWeight *
                (_postResolveRenderFraction +
                    normalizedProgress * transcodeFraction))
        .clamp(0.0, 1.0);
  }

  String _outputPathForProject(
    String outputPath, {
    required ExportMp3Layout layout,
    required int segmentIndex,
    required int segmentCount,
  }) {
    if (layout == ExportMp3Layout.singleFile || segmentCount == 1) {
      return outputPath;
    }

    final extensionIndex = outputPath.lastIndexOf('.');
    final separatorIndex = outputPath.lastIndexOf(Platform.pathSeparator);
    final hasExtension = extensionIndex > separatorIndex;
    final fileStem =
        hasExtension ? outputPath.substring(0, extensionIndex) : outputPath;
    final fileExtension =
        hasExtension ? outputPath.substring(extensionIndex) : '.mp3';
    final digitCount = segmentCount.toString().length;
    final paddingWidth = digitCount < _minimumSegmentPadding
        ? _minimumSegmentPadding
        : digitCount;
    final segmentNumber =
        (segmentIndex + 1).toString().padLeft(paddingWidth, '0');

    return '$fileStem$_segmentFileSuffix$segmentNumber$fileExtension';
  }

  double get _postResolveRenderFraction =>
      (_renderedStageProgress - _resolvedStageProgress) /
      (1 - _resolvedStageProgress);
}
