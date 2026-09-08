import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/audio/i_export_engine.dart';
import '../../core/audio/setlist_transition_step_runner.dart';
import '../../core/audio/song_playback_beatmap.dart';
import '../../core/audio/song_playback_timeline_mapper.dart';
import '../../core/audio/tempo_map_evaluator.dart';
import '../../core/domain/setlist.dart';
import '../../core/domain/song.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/service_providers.dart';

final _logger = Logger('ExportController');

/// State for a single export operation.
sealed class ExportState {
  const ExportState();
}

class ExportIdle extends ExportState {
  const ExportIdle();
}

class ExportRunning extends ExportState {
  const ExportRunning({required this.progress});
  final double progress;
}

class ExportComplete extends ExportState {
  const ExportComplete({
    required this.filePaths,
    required this.warnings,
  });
  final List<String> filePaths;
  final List<String> warnings;
}

class ExportFailed extends ExportState {
  const ExportFailed({required this.message});
  final String message;
}

final exportControllerProvider =
    NotifierProvider<ExportController, ExportState>(ExportController.new);

class ExportController extends Notifier<ExportState> {
  static const SetlistTransitionStepRunner _transitionStepRunner =
      SetlistTransitionStepRunner();
  static const TempoMapEvaluator _tempoMapEvaluator = TempoMapEvaluator();
  StreamSubscription<double>? _exportSubscription;

  @override
  ExportState build() => const ExportIdle();

  /// Estimates total playback duration for file size display.
  Future<Duration> estimateDuration(
    ExportSource source, {
    bool includeCountIn = true,
  }) async {
    const mapper = SongPlaybackTimelineMapper();
    const beatmapBuilder = SongPlaybackBeatmapBuilder();
    switch (source) {
      case SongExportSource(:final songId):
        final song =
            await ref.read(songRepositoryProvider).loadSong(songId);
        final exportSong = includeCountIn
            ? song
            : song.copyWith(countInBars: 0);
        final beatmap = beatmapBuilder.build(exportSong);
        return mapper.calculateBeatmapDuration(beatmap);
      case SetlistExportSource(:final setlistId):
        final setlist =
            await ref.read(setlistRepositoryProvider).loadSetlist(setlistId);
        var total = Duration.zero;
        for (final item in setlist.items.where((i) => i.playbackEnabled)) {
          final song =
              await ref.read(songRepositoryProvider).loadSong(item.songId);
          if (includeCountIn) {
            total += _calculateTransitionDuration(song, item.transitionSteps);
          }
          // Always strip the song's own count-in in setlist mode — only
          // transition count-ins contribute to the timeline.
          final beatmap = beatmapBuilder.build(song.copyWith(countInBars: 0));
          total += mapper.calculateBeatmapDuration(beatmap);
        }
        return total;
    }
  }

  Duration _calculateTransitionDuration(
    Song targetSong,
    List<SetlistTransitionStep> steps,
  ) {
    var duration = Duration.zero;
    for (final step in steps) {
      final action = _transitionStepRunner.resolveAction(step);
      switch (action) {
        case CountInBarsAction():
          final barDuration = _barDurationForSongStart(targetSong);
          duration += Duration(
            microseconds: barDuration.inMicroseconds * action.barCount,
          );
        case PauseTimerAction():
          duration += action.duration;
        case ManualWaitAction():
          continue;
        case AudioCueAction():
          continue;
      }
    }
    return duration;
  }

  Duration _barDurationForSongStart(Song song) {
    final tempoState = _tempoMapEvaluator.resolveAtBar(song, 1);
    const quarterNotesPerWholeNote = 4;
    final quarterNoteDuration =
        Duration.microsecondsPerMinute / tempoState.bpm;
    final beatDurationMicros =
        quarterNoteDuration * (quarterNotesPerWholeNote / tempoState.beatUnit);
    final beatDuration = Duration(microseconds: beatDurationMicros.round());
    return Duration(
      microseconds: beatDuration.inMicroseconds * tempoState.beatsPerBar,
    );
  }

  /// Starts the export pipeline.
  Future<void> startExport({
    required ExportSource source,
    required String title,
    ExportMp3Layout layout = ExportMp3Layout.singleFile,
    ExportContentOptions contentOptions = const ExportContentOptions(),
  }) async {
    await _exportSubscription?.cancel();

    final tempDir = await getTemporaryDirectory();
    final sanitized = title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final outputPath = '${tempDir.path}/${sanitized}_$timestamp.mp3';

    state = const ExportRunning(progress: 0);

    final engine = ref.read(exportEngineProvider);
    final completer = Completer<void>();
    final warnings = <String>[];

    _exportSubscription = engine
        .exportToMp3(
          source: source,
          outputPath: outputPath,
          layout: layout,
          contentOptions: contentOptions,
          onWarnings: (resolvedWarnings) => warnings.addAll(resolvedWarnings),
        )
        .listen(
      (progress) {
        state = ExportRunning(progress: progress);
      },
      onDone: () async {
        // Collect output files — for cutOnManual, multiple part files exist.
        final outputFiles = <String>[];
        if (layout == ExportMp3Layout.cutOnManual) {
          final dir = Directory(tempDir.path);
          final prefix = '${sanitized}_$timestamp';
          for (final entity in dir.listSync()) {
            if (entity is File && entity.path.contains(prefix)) {
              outputFiles.add(entity.path);
            }
          }
          outputFiles.sort();
        }
        if (outputFiles.isEmpty) {
          outputFiles.add(outputPath);
        }

        // Verify all output files actually exist before declaring success.
        final missingFiles = <String>[];
        for (final path in outputFiles) {
          final file = File(path);
          if (!file.existsSync()) {
            missingFiles.add(path);
          } else {
            _logger.info(
              'Output file verified: $path '
              '(${file.lengthSync()} bytes)',
            );
          }
        }

        if (missingFiles.isNotEmpty) {
          _logger.severe(
            'Export stream completed but output files are missing: '
            '${missingFiles.join(", ")}',
          );
          state = const ExportFailed(
            message: 'Export completed but the output file was not created. '
                'This may indicate an issue with the audio encoder.',
          );
          if (!completer.isCompleted) {
            completer.complete();
          }
          return;
        }

        _logger.info(
          'Export complete: ${outputFiles.length} file(s), '
          '${warnings.length} warning(s)',
        );
        state = ExportComplete(filePaths: outputFiles, warnings: warnings);
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _logger.severe('Export failed.', error, stackTrace);
        state = ExportFailed(message: '$error');
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    await completer.future;
  }

  /// Saves/shares the exported files via the platform service.
  Future<void> saveExportedFiles() async {
    final currentState = state;
    if (currentState is! ExportComplete) return;

    final service = ref.read(exportFileServiceProvider);
    for (final path in currentState.filePaths) {
      final file = File(path);
      if (!await file.exists()) {
        _logger.warning('Export file not found: $path');
        state = ExportFailed(
          message: 'Export file not found at $path',
        );
        return;
      }

      final fileSize = await file.length();
      _logger.info(
        'Sharing export file: $path ($fileSize bytes)',
      );

      final fileName = path.split('/').last;
      await service.saveExportedFile(path, fileName);
    }
  }

  /// Cancels an in-progress export.
  void cancelExport() {
    _exportSubscription?.cancel();
    _exportSubscription = null;
    state = const ExportIdle();
  }

  /// Resets state back to idle.
  void reset() {
    _exportSubscription?.cancel();
    _exportSubscription = null;
    state = const ExportIdle();
  }
}
