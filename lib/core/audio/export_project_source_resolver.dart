import 'package:logging/logging.dart';

import '../domain/audio_cue.dart';
import '../domain/click_sound_set.dart';
import '../domain/linked_audio_file.dart';
import '../domain/setlist.dart';
import '../domain/song.dart';
import '../domain/song_beatmap.dart';
import '../files/linked_audio_path_repair_service.dart';
import 'audio_cue_export_augmenter.dart';
import 'beat_duration.dart' as beat_duration_util;
import 'click_sound_set_assets.dart';
import 'click_track_export_augmenter.dart';
import 'export_engine.dart';
import 'i_export_engine.dart';
import 'linked_audio_export_augmenter.dart';
import 'setlist_transition_step_runner.dart';
import 'song_playback_beatmap.dart';
import 'song_playback_timeline_mapper.dart';
import 'tempo_map_evaluator.dart';

final _logger = Logger('ExportProjectSourceResolver');

abstract class SongExportSourceLoader {
  Future<Song> loadSong(String songId);
}

abstract class SetlistExportSourceLoader {
  Future<Setlist> loadSetlist(String setlistId);
}

class ExportProjectSourceResolver implements ExportSourceResolver {
  ExportProjectSourceResolver({
    required SongExportSourceLoader songLoader,
    required SetlistExportSourceLoader setlistLoader,
    LinkedAudioExportAugmenter? linkedAudioExportAugmenter,
    ClickTrackExportAugmenter? clickTrackExportAugmenter,
    AudioCueExportAugmenter? audioCueExportAugmenter,
    SongPlaybackTimelineMapper? songPlaybackTimelineMapper,
    SongPlaybackBeatmapBuilder? beatmapBuilder,
    TempoMapEvaluator? tempoMapEvaluator,
    SetlistTransitionStepRunner? setlistTransitionStepRunner,
    LinkedAudioPathRepairService? linkedAudioPathRepairService,
  })  : _songLoader = songLoader,
        _setlistLoader = setlistLoader,
        _linkedAudioExportAugmenter = linkedAudioExportAugmenter ??
            const LinkedAudioExportAugmenter(
              linkedAudioClipLoader: _UnsupportedLinkedAudioClipLoader(),
            ),
        _clickTrackExportAugmenter = clickTrackExportAugmenter ??
            const ClickTrackExportAugmenter(
              clickSoundClipLoader: _UnsupportedClickSoundClipLoader(),
            ),
        _audioCueExportAugmenter =
            audioCueExportAugmenter ?? const AudioCueExportAugmenter(),
        _songPlaybackTimelineMapper =
            songPlaybackTimelineMapper ?? const SongPlaybackTimelineMapper(),
        _beatmapBuilder =
            beatmapBuilder ?? const SongPlaybackBeatmapBuilder(),
        _tempoMapEvaluator = tempoMapEvaluator ?? const TempoMapEvaluator(),
        _setlistTransitionStepRunner =
            setlistTransitionStepRunner ?? const SetlistTransitionStepRunner(),
        _linkedAudioPathRepairService = linkedAudioPathRepairService;

  final SongExportSourceLoader _songLoader;
  final SetlistExportSourceLoader _setlistLoader;
  final LinkedAudioExportAugmenter _linkedAudioExportAugmenter;
  final ClickTrackExportAugmenter _clickTrackExportAugmenter;
  final AudioCueExportAugmenter _audioCueExportAugmenter;
  final SongPlaybackTimelineMapper _songPlaybackTimelineMapper;
  final SongPlaybackBeatmapBuilder _beatmapBuilder;
  final TempoMapEvaluator _tempoMapEvaluator;
  final SetlistTransitionStepRunner _setlistTransitionStepRunner;
  final LinkedAudioPathRepairService? _linkedAudioPathRepairService;

  @override
  Future<ResolvedExportProject> resolve(
    ExportSource source, {
    ExportContentOptions contentOptions = const ExportContentOptions(),
  }) async {
    final projects = await resolveProjects(
      source,
      contentOptions: contentOptions,
    );
    return projects.single;
  }

  @override
  Future<List<ResolvedExportProject>> resolveProjects(
    ExportSource source, {
    ExportMp3Layout layout = ExportMp3Layout.singleFile,
    ExportContentOptions contentOptions = const ExportContentOptions(),
  }) {
    return switch (source) {
      SongExportSource() => _resolveSongProjects(source, contentOptions),
      SetlistExportSource() =>
        _resolveSetlistProjects(source, layout: layout, contentOptions: contentOptions),
    };
  }

  Future<List<ResolvedExportProject>> _resolveSongProjects(
    SongExportSource source,
    ExportContentOptions contentOptions,
  ) async {
    final song = await _songLoader.loadSong(source.songId);
    _validateSongBpm(song);
    final exportSong = contentOptions.includeCountIn
        ? song
        : song.copyWith(countInBars: 0);
    final beatmap = _beatmapBuilder.build(exportSong);
    final songDuration =
        _songPlaybackTimelineMapper.calculateBeatmapDuration(beatmap);

    var project = ResolvedExportProject(
      source: source,
      duration: songDuration,
      warnings: _warningsForSong(song),
    );

    if (contentOptions.includeLinkedAudio) {
      final countInDuration = _countInDurationFromBeatmap(beatmap);
      project = await _augmentWithLinkedAudio(
        project: project,
        linkedAudioFile: await _liveLinkedAudio(song.linkedAudio),
        timelineOffset: countInDuration,
      );
    }

    if (contentOptions.includeClickTrack) {
      project = await _clickTrackExportAugmenter.augment(
        project: project,
        beatmap: beatmap,
        clickSoundSet: contentOptions.clickSoundSet,
        metronomeGain: contentOptions.metronomeGain,
      );
    }

    if (contentOptions.includeAudioCues) {
      project = await _audioCueExportAugmenter.augment(
        project: project,
        beatmap: beatmap,
        cueGain: contentOptions.cueGain,
      );
    }

    _logBeatmapSummary(beatmap);
    _logger.info(
      'Resolved song export: duration=${project.duration.inMilliseconds}ms, '
      'audioEvents=${project.audioEvents.length}, '
      'clickTrack=${contentOptions.includeClickTrack}, '
      'linkedAudio=${contentOptions.includeLinkedAudio}, '
      'cues=${contentOptions.includeAudioCues}, '
      'countIn=${contentOptions.includeCountIn}',
    );

    return [project];
  }

  Future<List<ResolvedExportProject>> _resolveSetlistProjects(
    SetlistExportSource source, {
    required ExportMp3Layout layout,
    required ExportContentOptions contentOptions,
  }) async {
    if (layout == ExportMp3Layout.cutOnManual) {
      return _resolveSetlistProjectsCutOnManual(source, contentOptions);
    }

    return [await _resolveSetlistSingleProject(source, contentOptions)];
  }

  Future<ResolvedExportProject> _resolveSetlistSingleProject(
    SetlistExportSource source,
    ExportContentOptions contentOptions,
  ) async {
    final setlist = await _setlistLoader.loadSetlist(source.setlistId);
    var currentOffset = Duration.zero;
    var project = ResolvedExportProject(
      source: source,
      duration: Duration.zero,
      warnings: _warningsForSetlist(setlist),
    );

    for (final item in setlist.items) {
      if (!item.playbackEnabled) {
        continue;
      }

      final song = await _songLoader.loadSong(item.songId);
      _validateSongBpm(song);
      currentOffset += _calculateTransitionDuration(
        steps: item.transitionSteps,
        targetSong: song,
      );

      final transitionCountIn = _countInFromTransitionSteps(
        steps: item.transitionSteps,
        targetSong: song,
      );
      final exportSong = contentOptions.includeCountIn
          ? song.copyWith(countInBars: transitionCountIn.barCount)
          : song.copyWith(countInBars: 0);
      final beatmap = _beatmapBuilder.build(exportSong);
      final countInDuration = _countInDurationFromBeatmap(beatmap);
      final songDuration =
          _songPlaybackTimelineMapper.calculateBeatmapDuration(beatmap);
      final songPlayableDuration = songDuration - countInDuration;

      if (contentOptions.includeLinkedAudio) {
        project = await _augmentWithLinkedAudio(
          project: project,
          linkedAudioFile: item.playAttachedAudio
              ? await _liveLinkedAudio(song.linkedAudio)
              : null,
          timelineOffset: currentOffset,
          maxDuration: songPlayableDuration,
        );
      }

      if (contentOptions.includeClickTrack) {
        project = await _clickTrackExportAugmenter.augment(
          project: project,
          beatmap: beatmap,
          clickSoundSet: contentOptions.clickSoundSet,
          metronomeGain: contentOptions.metronomeGain,
          timelineOffset: currentOffset - countInDuration,
        );
      }

      if (contentOptions.includeAudioCues) {
        project = await _audioCueExportAugmenter.augment(
          project: project,
          beatmap: beatmap,
          cueGain: contentOptions.cueGain,
          timelineOffset: currentOffset - countInDuration,
        );
      }

      currentOffset += songPlayableDuration;
      project = project.copyWith(
        duration: currentOffset,
        warnings: _mergeWarnings(project.warnings, _warningsForSong(song)),
      );
    }

    return project;
  }

  Future<List<ResolvedExportProject>> _resolveSetlistProjectsCutOnManual(
    SetlistExportSource source,
    ExportContentOptions contentOptions,
  ) async {
    final setlist = await _setlistLoader.loadSetlist(source.setlistId);
    final projects = <ResolvedExportProject>[];
    var currentProject = ResolvedExportProject(
      source: source,
      duration: Duration.zero,
      warnings: const [],
    );
    var currentOffset = Duration.zero;

    for (final item in setlist.items) {
      if (!item.playbackEnabled) {
        continue;
      }

      final song = await _songLoader.loadSong(item.songId);
      _validateSongBpm(song);

      for (final step in item.transitionSteps) {
        currentProject = currentProject.copyWith(
          warnings: _mergeWarnings(
            currentProject.warnings,
            _warningsForTransitionStep(step, includeManualWarning: false),
          ),
        );
        final action = _setlistTransitionStepRunner.resolveAction(step);
        switch (action) {
          case CountInBarsAction():
            final barDuration = _barDurationForSongStart(song);
            currentOffset += Duration(
              microseconds: barDuration.inMicroseconds * action.barCount,
            );
          case PauseTimerAction():
            currentOffset += action.duration;
          case ManualWaitAction():
            currentProject = currentProject.copyWith(duration: currentOffset);
            _appendProjectIfNotEmpty(projects, currentProject);
            currentProject = ResolvedExportProject(
              source: source,
              duration: Duration.zero,
              warnings: const [],
            );
            currentOffset = Duration.zero;
          case AudioCueAction():
            continue;
        }
      }

      final transitionCountIn = _countInFromTransitionSteps(
        steps: item.transitionSteps,
        targetSong: song,
      );
      final exportSong = contentOptions.includeCountIn
          ? song.copyWith(countInBars: transitionCountIn.barCount)
          : song.copyWith(countInBars: 0);
      final beatmap = _beatmapBuilder.build(exportSong);
      final countInDuration = _countInDurationFromBeatmap(beatmap);
      final songDuration =
          _songPlaybackTimelineMapper.calculateBeatmapDuration(beatmap);
      final songPlayableDuration = songDuration - countInDuration;

      if (contentOptions.includeLinkedAudio) {
        currentProject = await _augmentWithLinkedAudio(
          project: currentProject,
          linkedAudioFile:
              item.playAttachedAudio
                  ? await _liveLinkedAudio(song.linkedAudio)
                  : null,
          timelineOffset: currentOffset,
          maxDuration: songPlayableDuration,
        );
      }

      if (contentOptions.includeClickTrack) {
        currentProject = await _clickTrackExportAugmenter.augment(
          project: currentProject,
          beatmap: beatmap,
          clickSoundSet: contentOptions.clickSoundSet,
          metronomeGain: contentOptions.metronomeGain,
          timelineOffset: currentOffset - countInDuration,
        );
      }

      if (contentOptions.includeAudioCues) {
        currentProject = await _audioCueExportAugmenter.augment(
          project: currentProject,
          beatmap: beatmap,
          cueGain: contentOptions.cueGain,
          timelineOffset: currentOffset - countInDuration,
        );
      }

      currentOffset += songPlayableDuration;
      currentProject = currentProject.copyWith(
        duration: currentOffset,
        warnings:
            _mergeWarnings(currentProject.warnings, _warningsForSong(song)),
      );
    }

    _appendProjectIfNotEmpty(projects, currentProject);
    return projects;
  }

  Future<ResolvedExportProject> _augmentWithLinkedAudio({
    required ResolvedExportProject project,
    required LinkedAudioFile? linkedAudioFile,
    required Duration timelineOffset,
    Duration? maxDuration,
  }) {
    return _linkedAudioExportAugmenter.augment(
      project: project,
      linkedAudioFile: linkedAudioFile,
      timelineOffset: timelineOffset,
      maxDuration: maxDuration,
    );
  }

  Future<LinkedAudioFile?> _liveLinkedAudio(
    LinkedAudioFile? linkedAudioFile,
  ) async {
    if (linkedAudioFile == null || !linkedAudioFile.playInLiveMode) {
      return null;
    }

    final repairService = _linkedAudioPathRepairService;
    if (repairService != null) {
      final repaired = await repairService.repairIfNeeded(linkedAudioFile);
      if (repaired.filePath != linkedAudioFile.filePath) {
        _logger.info(
          'Repaired linked audio path: ${linkedAudioFile.filePath} → ${repaired.filePath}',
        );
      }
      return repaired;
    }

    return linkedAudioFile;
  }

  Duration _countInDurationFromBeatmap(SongBeatmap beatmap) {
    var duration = Duration.zero;
    for (final entry in beatmap.entries) {
      if (entry.barKind != SongBeatmapBarKind.countIn) {
        break;
      }
      final bd = beat_duration_util.beatDuration(bpm: entry.bpm, beatUnit: entry.beatUnit);
      duration += Duration(
        microseconds: bd.inMicroseconds * entry.beatsPerBar,
      );
    }
    return duration;
  }

  ({Duration duration, int barCount}) _countInFromTransitionSteps({
    required List<SetlistTransitionStep> steps,
    required Song targetSong,
  }) {
    var barCount = 0;
    for (final step in steps) {
      final action = _setlistTransitionStepRunner.resolveAction(step);
      if (action is CountInBarsAction) {
        barCount += action.barCount;
      }
    }
    if (barCount == 0) {
      return (duration: Duration.zero, barCount: 0);
    }
    final barDuration = _barDurationForSongStart(targetSong);
    return (
      duration: Duration(
        microseconds: barDuration.inMicroseconds * barCount,
      ),
      barCount: barCount,
    );
  }

  Duration _calculateTransitionDuration({
    required List<SetlistTransitionStep> steps,
    required Song targetSong,
  }) {
    var duration = Duration.zero;

    for (final step in steps) {
      final action = _setlistTransitionStepRunner.resolveAction(step);
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
    final initialTempoState = _tempoMapEvaluator.resolveAtBar(song, 1);
    return _barDuration(
      bpm: initialTempoState.bpm,
      beatsPerBar: initialTempoState.beatsPerBar,
      beatUnit: initialTempoState.beatUnit,
    );
  }

  Duration _barDuration({
    required int bpm,
    required int beatsPerBar,
    required int beatUnit,
  }) {
    if (bpm <= 0) {
      throw ArgumentError.value(bpm, 'bpm', 'BPM must be greater than zero.');
    }

    final bd = beat_duration_util.beatDuration(bpm: bpm, beatUnit: beatUnit);
    return Duration(microseconds: bd.inMicroseconds * beatsPerBar);
  }

  List<String> _warningsForSong(Song song) {
    final warnings = <String>[];

    for (final event in song.songEvents) {
      if (event.audioCue?.type == AudioCueType.voice) {
        warnings.add(voiceCueExportWarning);
      }
    }

    return _deduplicateWarnings(warnings);
  }

  List<String> _warningsForSetlist(Setlist setlist) {
    final warnings = <String>[];

    for (final item in setlist.items) {
      if (!item.playbackEnabled) {
        continue;
      }

      for (final step in item.transitionSteps) {
        if (step.audioCue?.type == AudioCueType.voice) {
          warnings.add(voiceCueExportWarning);
        }

        if (step.type == SetlistTransitionStepType.manual) {
          warnings.add(manualStepExportWarning);
        }
      }
    }

    return _deduplicateWarnings(warnings);
  }

  List<String> _mergeWarnings(List<String> first, List<String> second) {
    return _deduplicateWarnings([...first, ...second]);
  }

  List<String> _warningsForTransitionStep(
    SetlistTransitionStep step, {
    required bool includeManualWarning,
  }) {
    final warnings = <String>[];
    if (step.audioCue?.type == AudioCueType.voice) {
      warnings.add(voiceCueExportWarning);
    }
    if (includeManualWarning && step.type == SetlistTransitionStepType.manual) {
      warnings.add(manualStepExportWarning);
    }

    return _deduplicateWarnings(warnings);
  }

  List<String> _deduplicateWarnings(List<String> warnings) {
    return warnings.toSet().toList(growable: false);
  }

  void _logBeatmapSummary(SongBeatmap beatmap) {
    final bpmChanges = <String>[];
    int? lastBpm;
    int? lastBeatsPerBar;
    int? lastBeatUnit;
    for (final entry in beatmap.entries) {
      if (entry.bpm != lastBpm ||
          entry.beatsPerBar != lastBeatsPerBar ||
          entry.beatUnit != lastBeatUnit) {
        bpmChanges.add(
          'bar ${entry.barLabel}: ${entry.bpm}bpm ${entry.beatsPerBar}/${entry.beatUnit}',
        );
        lastBpm = entry.bpm;
        lastBeatsPerBar = entry.beatsPerBar;
        lastBeatUnit = entry.beatUnit;
      }
    }
    _logger.info(
      'Beatmap: ${beatmap.totalPlaybackBars} bars, '
      'tempo map: [${bpmChanges.join(', ')}]',
    );
  }

  void _validateSongBpm(Song song) {
    if (song.startBpm <= 0) {
      throw ArgumentError.value(
        song.startBpm,
        'startBpm',
        'BPM must be greater than zero.',
      );
    }
  }

  void _appendProjectIfNotEmpty(
    List<ResolvedExportProject> projects,
    ResolvedExportProject project,
  ) {
    if (project.duration <= Duration.zero && project.audioEvents.isEmpty) {
      return;
    }

    projects.add(project);
  }
}

class _UnsupportedLinkedAudioClipLoader implements LinkedAudioClipLoader {
  const _UnsupportedLinkedAudioClipLoader();

  @override
  Future<ExportAudioClip> loadClip(LinkedAudioFile linkedAudioFile) {
    throw UnsupportedError(
      'A linked audio clip loader must be provided when export sources include linked audio.',
    );
  }
}

class _UnsupportedClickSoundClipLoader implements ClickSoundClipLoader {
  const _UnsupportedClickSoundClipLoader();

  @override
  Future<ExportAudioClip> loadClip(ClickSoundSet soundSet, ClickSoundVariant variant) {
    throw UnsupportedError(
      'A click sound clip loader must be provided when export includes click track.',
    );
  }
}
