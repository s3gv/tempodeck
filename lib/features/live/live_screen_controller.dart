import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/audio/metronome_click_engine.dart';
import '../../core/audio/i_audio_engine.dart';
import '../../core/domain/audio_cue.dart';
import '../../core/domain/linked_audio_file.dart';
import '../../core/domain/setlist.dart';
import '../../core/domain/song.dart';
import '../../core/domain/song_beatmap.dart';
import '../../core/domain/subdivision.dart';
import '../../core/audio/foreground_playback_service.dart';
import '../../core/providers/audio_mixer_provider.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/service_providers.dart';
import '../metronome/metronome_screen_controller.dart';
import '../metronome/metronome_screen_state.dart';
import 'live_event.dart';
import 'live_event_resolver.dart';
import 'live_metronome_transport.dart';
import 'live_playback_plan.dart';
import 'live_screen_state.dart';
import 'live_view_context.dart';

final liveMetronomeTransportProvider = Provider<LiveMetronomeTransport>(
  (ref) => AudioEngineLiveMetronomeTransport(
    audioEngine: ref.watch(audioEngineProvider),
  ),
);

final liveScreenControllerProvider =
    NotifierProvider<LiveScreenController, LiveScreenState>(
      LiveScreenController.new,
    );

class LiveScreenController extends Notifier<LiveScreenState> {
  static const int _setlistPreloadWindowSize = 15;
  static final Logger _logger = Logger('LiveScreenController');
  static const LiveMetronomeEventResolver _metronomeEventResolver =
      LiveMetronomeEventResolver();

  Setlist? _activeSetlist;
  SetlistPlaybackPlan? _currentSetlistPlaybackPlan;
  int? _currentSetlistSegmentIndex;
  Song? _currentSong;
  SongBeatmap? _currentSongBeatmap;
  bool _isCountInActive = false;
  int? _firstSongPlaybackBarIndex;
  bool _linkedAudioStartedForCurrentSong = false;
  Future<void> Function()? _onFirstSongBarReached;
  bool _shouldPlayCurrentSongLinkedAudio = false;
  bool _isAdvancingManualTransition = false;
  PreparedLinkedAudioHandle? _preparedCurrentSongLinkedAudioHandle;
  final Set<String> _preloadedLinkedAudioPaths = <String>{};
  Completer<void>? _waitTimerCompleter;
  int? _lastSetlistSongIndex;
  bool _setlistTransitionEnabled = true;
  Stopwatch? _intervalStopwatch;
  Timer? _intervalCountdownTimer;
  int _intervalCompletedCount = 0;
  bool _intervalStepPending = false;

  @override
  LiveScreenState build() {
    final transport = ref.read(liveMetronomeTransportProvider);
    ref.listen<LiveViewContext>(liveViewContextProvider, (prev, next) {
      // When the context changes (e.g. user switches from metronome to a
      // song on desktop), update the displayed BPM/time signature and
      // preload linked audio.
      if (prev != next) {
        state = _initialStateFromContext(next);
        if (next is SetlistViewContext) {
          unawaited(_loadSetlistInitialState(next.setlist));
        }
      }
      unawaited(_preloadContextLinkedAudio(next));
    });
    ref.listen<int>(externalAudioStopCounterProvider, (_, __) {
      _handleExternalStop();
    });
    final context = ref.read(liveViewContextProvider);
    unawaited(_preloadContextLinkedAudio(context));
    ref.onDispose(() {
      unawaited(_releasePreparedCurrentSongLinkedAudio());
      unawaited(transport.stopAllAudio());
    });
    if (context is SetlistViewContext) {
      unawaited(_loadSetlistInitialState(context.setlist));
    }
    return _initialStateFromContext(context);
  }

  LiveScreenState _initialStateFromContext(LiveViewContext context) {
    final metronomeState = ref.read(metronomeScreenControllerProvider);
    return switch (context) {
      SongViewContext(:final song) => LiveScreenState.initial().copyWith(
        bpm: song.startBpm,
        beatsPerBar: song.beatsPerBar,
        beatUnit: song.beatUnit,
      ),
      SetlistViewContext() => LiveScreenState.initial(),
      MetronomeViewContext() => LiveScreenState.initial().copyWith(
        bpm: metronomeState.bpm,
        beatsPerBar: metronomeState.beatsPerBar,
        beatUnit: metronomeState.beatUnit,
      ),
    };
  }

  /// Asynchronously loads the first song of a setlist and updates the
  /// displayed BPM / time signature so the user sees the correct values
  /// before pressing play.
  Future<void> _loadSetlistInitialState(Setlist setlist) async {
    final firstItem = setlist.items
        .where((item) => item.playbackEnabled)
        .firstOrNull;
    if (firstItem == null) return;

    final songRepo = ref.read(songRepositoryProvider);
    final song = await songRepo.loadSong(firstItem.songId);
    state = state.copyWith(
      bpm: song.startBpm,
      beatsPerBar: song.beatsPerBar,
      beatUnit: song.beatUnit,
    );
  }

  Future<void> togglePlayback() async {
    if (state.isStarting) {
      return;
    }

    if (state.isWaitingForManualAdvance) {
      if (_isAdvancingManualTransition) return;
      _isAdvancingManualTransition = true;
      state = state.copyWith(isWaitingForManualAdvance: false);
      try {
        await advanceSetlistTransition();
      } finally {
        _isAdvancingManualTransition = false;
      }
      return;
    }

    if (state.isPlaying) {
      _stop();
      return;
    }

    final context = ref.read(liveViewContextProvider);
    final metronomeState = ref.read(metronomeScreenControllerProvider);

    // Derive BPM / time signature from the active context.
    final int bpm;
    final int beatsPerBar;
    final int beatUnit;

    switch (context) {
      case SongViewContext(:final song):
        final plan = await ref
            .read(livePlaybackPlanLoaderProvider)
            .load(SongViewContext(song: song)) as SongPlaybackPlan;
        await _startSongPlaybackPlan(
          plan.song,
          metronomeState,
          plan: plan,
        );
        return;
      case SetlistViewContext(:final setlist):
        await _startSetlistPlayback(setlist, metronomeState);
        return;
      case MetronomeViewContext():
        bpm = metronomeState.bpm;
        beatsPerBar = metronomeState.beatsPerBar;
        beatUnit = metronomeState.beatUnit;
    }

    final transport = ref.read(liveMetronomeTransportProvider);
    try {
      state = state.copyWith(
        isStarting: true,
        bpm: bpm,
        beatsPerBar: beatsPerBar,
        beatUnit: beatUnit,
        pulseCount: metronomeState.subdivision.pulseCount,
      );
      await transport.start(
        LiveMetronomeTransportConfig(
          bpm: bpm,
          beatsPerBar: beatsPerBar,
          beatUnit: beatUnit,
          subdivision: metronomeState.subdivision,
          accentPattern: metronomeState.accentPattern,
          clickSoundSet: metronomeState.clickSoundSet,
          masterVolumePercent: metronomeState.masterVolumePercent,
        ),
        onTick: _handleTick,
      );

      // Interval timer is exclusive to metronome mode — song and setlist
      // contexts return before reaching this code path.
      _startIntervalTimerIfNeeded(metronomeState);
      unawaited(_foregroundService.startForeground());

      state = state.copyWith(
        isPlaying: true,
        isStarting: false,
        intervalRemainingSeconds: _intervalRemainingSeconds(metronomeState),
        maxDurationRemainingSeconds: _maxDurationRemainingSeconds(metronomeState),
      );
    } catch (error, stackTrace) {
      _logger.severe('Failed to start live playback.', error, stackTrace);
      _stop();
      state = state.copyWith(
        errorMessage:
            'Audio unavailable. Please check your device audio settings.',
      );
    }
  }

  void _handleTick(MetronomeBeatTick tick) {
    final beatmapEntry = _beatmapEntryForTick(tick);
    final displayBarIndex = beatmapEntry?.displayBarIndex ?? tick.barIndex;
    final barChanged = displayBarIndex != state.barIndex;
    var newState = state.copyWith(
      isPlaying: true,
      barIndex: displayBarIndex,
      barLabel: beatmapEntry?.barLabel,
      beatIndex: tick.beatIndex,
      pulseIndex: tick.pulseIndex,
      pulseCount: tick.pulseCount,
      accentLevel: tick.accentLevel,
      bpm: tick.bpm,
      beatsPerBar: tick.beatsPerBar,
      beatUnit: tick.beatUnit,
    );

    if (_isCountInActive) {
      if (_hasReachedFirstSongBar(tick, beatmapEntry)) {
        _isCountInActive = false;
        _triggerSongEventsForBar(beatmapEntry);
        final resolved = _resolveLiveEventsForTick(
          tick: tick,
          beatmapEntry: beatmapEntry,
        );
        newState = newState.copyWith(
          currentEvents: resolved.current,
          nextEvents: resolved.next,
        );
        state = newState;
        unawaited(_enterSongPlaybackPhase());
        return;
      }

      state = newState;
      if (_isLastPulseOfBar(tick)) {
        final remainingBars = _remainingCountInBars(beatmapEntry);
        if (remainingBars > 0) {
          state = state.copyWith(
            transitionMessage: _countInTransitionMessage(remainingBars),
          );
        }
      }
      return;
    }

    // Only resolve events when bar changes (not on every pulse).
    if (barChanged) {
      _triggerSongEventsForBar(beatmapEntry);
      final resolved = _resolveLiveEventsForTick(
        tick: tick,
        beatmapEntry: beatmapEntry,
      );
      newState = newState.copyWith(
        currentEvents: resolved.current,
        nextEvents: resolved.next,
      );
    }

    if (_currentSong != null &&
        _isLastPulseOfBar(tick) &&
        _hasCompletedSongPlayback(tick)) {
      state = newState;
      if (_activeSetlist != null) {
        unawaited(_advanceSetlistSong());
      } else {
        _stopAfterSongEnd();
      }
      return;
    }

    // In metronome mode, apply pending interval step on beat 1 of a new bar.
    if (_currentSong == null && barChanged && _intervalStepPending) {
      _applyPendingIntervalStep();
    }

    state = newState;
  }

  /// Stops playback after a song reaches its endBar. Only stops the transport
  /// (no new ticks) but lets the audio engine finish playing the last click.
  void _stopAfterSongEnd() {
    ref.read(liveMetronomeTransportProvider).stop();
    unawaited(_foregroundService.stopForeground());
    _cleanupPlaybackState();
    unawaited(_releasePreparedCurrentSongLinkedAudio());
    state = state.copyWith(
      isPlaying: false,
      isStarting: false,
      isTransitioning: false,
      isWaitingForManualAdvance: false,
      clearCurrentSongTitle: true,
      clearCurrentSongIndex: true,
      clearTotalSongs: true,
      clearTransitionMessage: true,
      clearErrorMessage: true,
    );
  }

  ForegroundPlaybackService get _foregroundService =>
      ref.read(foregroundPlaybackServiceProvider);

  /// Called when playback was stopped externally (audio interruption or app
  /// backgrounded). Resets the UI state without re-stopping the engine
  /// (which has already been stopped by the lifecycle observer).
  void _handleExternalStop() {
    if (!state.isPlaying && !state.isStarting) return;
    _logger.info('External audio stop detected — resetting UI state.');
    _cleanupPlaybackState();
    unawaited(_releasePreparedCurrentSongLinkedAudio());
    state = state.copyWith(
      isPlaying: false,
      isStarting: false,
      isTransitioning: false,
      isWaitingForManualAdvance: false,
      clearCurrentSongTitle: true,
      clearCurrentSongIndex: true,
      clearTotalSongs: true,
      clearTransitionMessage: true,
      clearErrorMessage: true,
      clearBarLabel: true,
      clearIntervalRemainingSeconds: true,
      clearMaxDurationRemainingSeconds: true,
    );
  }

  void _stop() {
    // Remember which song we were on so we can resume from its transition.
    _lastSetlistSongIndex = _currentSetlistSongIndex;
    unawaited(ref.read(liveMetronomeTransportProvider).stopAllAudio());
    unawaited(_foregroundService.stopForeground());
    _cleanupPlaybackState();
    unawaited(_releasePreparedCurrentSongLinkedAudio());
    state = state.copyWith(
      isPlaying: false,
      isStarting: false,
      isTransitioning: false,
      isWaitingForManualAdvance: false,
      clearCurrentSongTitle: true,
      clearCurrentSongIndex: true,
      clearTotalSongs: true,
      clearTransitionMessage: true,
      clearErrorMessage: true,
      clearBarLabel: true,
      clearIntervalRemainingSeconds: true,
      clearMaxDurationRemainingSeconds: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Interval timer
  // ---------------------------------------------------------------------------

  void _startIntervalTimerIfNeeded(MetronomeScreenState metronomeState) {
    _stopIntervalTimer();
    // Use effectiveIntervalSettings which respects the Pro entitlement.
    // On mobile, free users always get null here even if interval mode
    // was previously enabled in persisted state.
    final controller = ref.read(metronomeScreenControllerProvider.notifier);
    final interval = controller.effectiveIntervalSettings;
    if (interval == null) return;

    _intervalStopwatch = Stopwatch()..start();
    _intervalCompletedCount = 0;

    _intervalCountdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateIntervalCountdown(),
    );
  }

  void _updateIntervalCountdown() {
    final metronomeState = ref.read(metronomeScreenControllerProvider);
    final interval = metronomeState.intervalSettings;
    if (interval == null || _intervalStopwatch == null) return;

    final elapsed = _intervalStopwatch!.elapsed;
    final intervalDuration = interval.interval;
    final completedIntervals =
        elapsed.inMilliseconds ~/ intervalDuration.inMilliseconds;

    // When the interval expires, play the signal immediately and mark
    // that a BPM step is pending (applied on beat 1 of the next bar).
    if (completedIntervals > _intervalCompletedCount) {
      _intervalCompletedCount = completedIntervals;
      _intervalStepPending = true;

      final cueVolumeFactor =
          ref.read(audioMixerControllerProvider.notifier).cueVolumeFactor();
      unawaited(
        ref.read(audioEngineProvider).playCue(
              _scaledAudioCue(
                const AudioCue(type: AudioCueType.intervalSignal),
                globalVolumeFactor: cueVolumeFactor,
              ),
            ),
      );
    }

    // Check max duration.
    final maxDuration = interval.maxDuration;
    if (maxDuration != null && elapsed >= maxDuration) {
      _intervalStepPending = true;
    }

    // Update countdown displays.
    final remaining = _intervalRemainingSeconds(metronomeState);
    final maxRemaining = _maxDurationRemainingSeconds(metronomeState);
    state = state.copyWith(
      intervalRemainingSeconds: remaining,
      maxDurationRemainingSeconds: maxRemaining,
    );
  }

  /// Called from `_handleTick` on beat 1 of a new bar. When an interval
  /// step is pending, applies the BPM change and restarts the transport.
  /// The acoustic signal was already played in [_updateIntervalCountdown].
  void _applyPendingIntervalStep() {
    if (!_intervalStepPending) return;
    _intervalStepPending = false;

    final metronomeState = ref.read(metronomeScreenControllerProvider);
    final interval = metronomeState.intervalSettings;
    if (interval == null || _intervalStopwatch == null) return;

    // Check max duration — stop entirely if exceeded.
    final maxDuration = interval.maxDuration;
    if (maxDuration != null &&
        _intervalStopwatch!.elapsed >= maxDuration) {
      _stop();
      return;
    }

    if (!interval.bpmStepEnabled) return;

    // Apply BPM step and restart transport at the new tempo, clamped to
    // the validated metronome range.
    final newBpm = (state.bpm + interval.bpmStep).clamp(
      MetronomeScreenController.minimumBpm,
      MetronomeScreenController.maximumBpm,
    );
    final transport = ref.read(liveMetronomeTransportProvider);
    transport.stop();
    final config = LiveMetronomeTransportConfig(
      bpm: newBpm,
      beatsPerBar: state.beatsPerBar,
      beatUnit: state.beatUnit,
      subdivision: metronomeState.subdivision,
      accentPattern: metronomeState.accentPattern,
      clickSoundSet: metronomeState.clickSoundSet,
      masterVolumePercent: metronomeState.masterVolumePercent,
    );
    unawaited(transport.start(config, onTick: _handleTick));
    state = state.copyWith(bpm: newBpm);
  }

  int? _intervalRemainingSeconds(MetronomeScreenState metronomeState) {
    final interval = metronomeState.intervalSettings;
    if (interval == null || _intervalStopwatch == null) return null;

    final elapsed = _intervalStopwatch!.elapsed;
    final intervalDuration = interval.interval;
    final elapsedInCurrentInterval = Duration(
      milliseconds: elapsed.inMilliseconds % intervalDuration.inMilliseconds,
    );
    final remaining = intervalDuration - elapsedInCurrentInterval;
    return remaining.inSeconds;
  }

  int? _maxDurationRemainingSeconds(MetronomeScreenState metronomeState) {
    final interval = metronomeState.intervalSettings;
    if (interval == null ||
        interval.maxDuration == null ||
        _intervalStopwatch == null) {
      return null;
    }
    final remaining = interval.maxDuration! - _intervalStopwatch!.elapsed;
    final seconds = remaining.inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  void _stopIntervalTimer() {
    _intervalCountdownTimer?.cancel();
    _intervalCountdownTimer = null;
    _intervalStopwatch?.stop();
    _intervalStopwatch = null;
    _intervalCompletedCount = 0;
    _intervalStepPending = false;
  }

  /// Returns the 1-based song index of the currently playing segment, or null.
  int? get _currentSetlistSongIndex {
    final plan = _currentSetlistPlaybackPlan;
    final idx = _currentSetlistSegmentIndex;
    if (plan == null || idx == null || idx >= plan.segments.length) return null;
    final segment = plan.segments[idx];
    return switch (segment) {
      SetlistSongSegment(:final songIndex) => songIndex,
      SetlistCountInSegment(:final songIndex) => songIndex,
      SetlistWaitSegment(:final songIndex) => songIndex,
      SetlistManualSegment(:final songIndex) => songIndex,
      SetlistAudioCueSegment(:final songIndex) => songIndex,
    };
  }

  void _cleanupPlaybackState() {
    _cancelWaitTimer();
    _stopIntervalTimer();
    _isCountInActive = false;
    _firstSongPlaybackBarIndex = null;
    _linkedAudioStartedForCurrentSong = false;
    _onFirstSongBarReached = null;
    _activeSetlist = null;
    // Keep _currentSetlistPlaybackPlan so prev/next navigation works while
    // paused. It is overwritten on the next _startSetlistPlayback call.
    _currentSetlistSegmentIndex = null;
    _currentSong = null;
    _currentSongBeatmap = null;
    _shouldPlayCurrentSongLinkedAudio = false;
  }

  void _cancelWaitTimer() {
    final completer = _waitTimerCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _waitTimerCompleter = null;
  }

  /// Waits for [totalSeconds] with a visible mm:ss countdown in
  /// [state.transitionMessage]. Completes early if [_stop] is called.
  Future<bool> _waitWithCountdown(int totalSeconds) async {
    final completer = Completer<void>();
    _waitTimerCompleter = completer;
    var remaining = totalSeconds;

    final ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      remaining -= 1;
      if (remaining <= 0) {
        if (!completer.isCompleted) completer.complete();
      } else {
        state = state.copyWith(
          transitionMessage: _formatPauseCountdown(remaining),
        );
      }
    });

    await completer.future;
    ticker.cancel();
    final wasCancelled = _activeSetlist == null;
    _waitTimerCompleter = null;
    return wasCancelled;
  }

  static String _formatPauseCountdown(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return 'Pause: $mm:$ss';
  }

  // ---------------------------------------------------------------------------
  // Setlist transport
  // ---------------------------------------------------------------------------

  Future<void> _startSetlistPlayback(
    Setlist setlist,
    MetronomeScreenState metronomeState,
  ) async {
    _activeSetlist = setlist;
    final plan = await ref
        .read(livePlaybackPlanLoaderProvider)
        .load(SetlistViewContext(setlist: setlist)) as SetlistPlaybackPlan;
    _currentSetlistPlaybackPlan = plan;
    if (plan.segments.isEmpty) {
      state = state.copyWith(
        transitionMessage: 'No playable songs in setlist',
        isTransitioning: true,
      );
      return;
    }

    // Resume from the last song's transition if we were previously stopped
    // mid-setlist, otherwise start from the beginning.
    final resumeSongIndex = _lastSetlistSongIndex;
    _lastSetlistSongIndex = null;
    int startSegmentIndex = 0;
    if (resumeSongIndex != null) {
      final idx = plan.segments.indexWhere((s) => switch (s) {
        SetlistSongSegment(:final songIndex) => songIndex == resumeSongIndex,
        SetlistCountInSegment(:final songIndex) => songIndex == resumeSongIndex,
        SetlistWaitSegment(:final songIndex) => songIndex == resumeSongIndex,
        SetlistManualSegment(:final songIndex) => songIndex == resumeSongIndex,
        SetlistAudioCueSegment(:final songIndex) => songIndex == resumeSongIndex,
      },);
      if (idx >= 0) startSegmentIndex = idx;
    }
    _currentSetlistSegmentIndex = startSegmentIndex;

    await _startCurrentSetlistSegment(metronomeState);
  }

  Future<void> _startSongPlaybackPlan(
    Song song,
    MetronomeScreenState metronomeState, {
    required SongPlaybackPlan plan,
    String? currentSongTitle,
    int? currentSongIndex,
    int? totalSongs,
  }) async {
    _currentSong = song;
    _currentSongBeatmap = plan.beatmap;
    _shouldPlayCurrentSongLinkedAudio = plan.shouldPlayLinkedAudio;
    _linkedAudioStartedForCurrentSong = false;
    await _preloadSongAssets(
      song,
      shouldPreloadLinkedAudio: plan.shouldPlayLinkedAudio,
    );
    await _prepareCurrentSongLinkedAudio(song);

    final beatmap = _currentSongBeatmap;
    if (beatmap == null) {
      throw StateError('Song playback plan is not available.');
    }
    _firstSongPlaybackBarIndex = beatmap.firstSongEntry.playbackBarIndex;
    final hasCountIn = beatmap.countInBarCount > 0;
    _isCountInActive = hasCountIn;
    _onFirstSongBarReached = () async {
      await _playCurrentSongLinkedAudioIfEnabled();
      state = state.copyWith(
        isTransitioning: false,
        clearTransitionMessage: true,
      );
    };

    await _startActualSongPlayback(
      metronomeState,
      currentSongTitle: currentSongTitle ?? song.title,
      currentSongIndex: currentSongIndex,
      totalSongs: totalSongs,
      startPlaybackBarIndex: hasCountIn
          ? 1
          : beatmap.firstSongEntry.playbackBarIndex,
      transitionMessage: hasCountIn
          ? _countInTransitionMessage(beatmap.countInBarCount)
          : null,
    );
  }

  Future<void> _preloadContextLinkedAudio(LiveViewContext context) async {
    switch (context) {
      case SongViewContext(:final song):
        await _preloadSongAssets(song, shouldPreloadLinkedAudio: true);
      case SetlistViewContext(:final setlist):
        await _preloadSetlistWindow(setlist, startItemIndex: 0);
      case MetronomeViewContext():
        return;
    }
  }

  Future<void> _preloadSongAssets(
    Song song, {
    required bool shouldPreloadLinkedAudio,
  }) async {
    if (shouldPreloadLinkedAudio) {
      await _preloadSongLinkedAudio(song);
    }
    await _preloadSongEventCueFiles(song);
  }

  Future<void> _preloadSetlistWindow(
    Setlist setlist, {
    required int startItemIndex,
  }) async {
    var preloadedSongs = 0;
    for (var itemIndex = startItemIndex;
        itemIndex < setlist.items.length &&
            preloadedSongs < _setlistPreloadWindowSize;
        itemIndex += 1) {
      final item = setlist.items[itemIndex];
      await _preloadTransitionCueFiles(item.transitionSteps);
      if (!item.playbackEnabled) {
        continue;
      }

      try {
        final song = await ref.read(songRepositoryProvider).loadSong(item.songId);
        await _preloadSongAssets(
          song,
          shouldPreloadLinkedAudio: item.playAttachedAudio,
        );
        preloadedSongs += 1;
      } catch (error, stackTrace) {
        _logger.warning('Failed to preload setlist song assets.', error, stackTrace);
      }
    }
  }

  Future<void> _preloadSongLinkedAudio(Song song) async {
    final linkedAudio = song.linkedAudio;
    if (linkedAudio == null || !linkedAudio.playInLiveMode) {
      return;
    }

    String? filePath;
    try {
      final resolvedLinkedAudio = await ref
          .read(linkedAudioPathRepairServiceProvider)
          .repairIfNeeded(linkedAudio);
      filePath = resolvedLinkedAudio.filePath;
      if (_preloadedLinkedAudioPaths.contains(filePath)) {
        return;
      }
      _preloadedLinkedAudioPaths.add(filePath);
      final audioEngine = ref.read(audioEngineProvider);
      await audioEngine.initialize();
      await audioEngine.preloadLinkedAudio(filePath);
    } catch (error, stackTrace) {
      if (filePath != null) {
        _preloadedLinkedAudioPaths.remove(filePath);
      }
      _logger.warning('Failed to preload linked audio for live playback.', error, stackTrace);
    }
  }

  Future<void> _preloadSongEventCueFiles(Song song) async {
    for (final songEvent in song.songEvents) {
      final audioCue = songEvent.audioCue;
      if (audioCue == null) {
        continue;
      }
      await _preloadAudioCueFile(audioCue);
    }
  }

  Future<void> _preloadTransitionCueFiles(
    List<SetlistTransitionStep> transitionSteps,
  ) async {
    for (final step in transitionSteps) {
      final audioCue = step.audioCue;
      if (audioCue == null) {
        continue;
      }
      await _preloadAudioCueFile(audioCue);
    }
  }

  Future<void> _preloadAudioCueFile(AudioCue audioCue) async {
    if (audioCue.type != AudioCueType.customFile) {
      return;
    }
    final filePath = audioCue.customFilePath;
    if (filePath == null || filePath.isEmpty) {
      return;
    }
    if (_preloadedLinkedAudioPaths.contains(filePath)) {
      return;
    }
    _preloadedLinkedAudioPaths.add(filePath);
    try {
      final audioEngine = ref.read(audioEngineProvider);
      await audioEngine.initialize();
      await audioEngine.preloadLinkedAudio(filePath);
    } catch (error, stackTrace) {
      _preloadedLinkedAudioPaths.remove(filePath);
      _logger.warning('Failed to preload custom audio cue file.', error, stackTrace);
    }
  }

  Future<void> _startActualSongPlayback(
    MetronomeScreenState metronomeState, {
    required String currentSongTitle,
    int? currentSongIndex,
    int? totalSongs,
    required int startPlaybackBarIndex,
    String? transitionMessage,
  }) async {
    final transport = ref.read(liveMetronomeTransportProvider);
    if (transport.isRunning) {
      transport.stop();
    }

    final firstPlaybackStep = _requiredBeatmapEntry(startPlaybackBarIndex);
    final initialEvents = _resolveSongPlaybackEvents(
      playbackBarIndex: firstPlaybackStep.playbackBarIndex,
    );
    final config = _transportConfigForBeatmapEntry(firstPlaybackStep);
    state = state.copyWith(
      isStarting: true,
      isTransitioning: _isCountInActive,
      isWaitingForManualAdvance: false,
      clearTransitionMessage: transitionMessage == null,
      bpm: config.bpm,
      beatsPerBar: config.beatsPerBar,
      beatUnit: config.beatUnit,
      pulseCount: config.subdivision.pulseCount,
      barIndex: firstPlaybackStep.displayBarIndex,
      barLabel: firstPlaybackStep.barLabel,
      beatIndex: 0,
      pulseIndex: 0,
      currentSongTitle: currentSongTitle,
      currentSongIndex: currentSongIndex,
      totalSongs: totalSongs,
      currentEvents: initialEvents.current,
      nextEvents: initialEvents.next,
      transitionMessage: transitionMessage,
    );

    await transport.start(
      config,
      onTick: _handleTick,
      beatmapSequence: _beatmapTransportSequence(
        startPlaybackBarIndex: startPlaybackBarIndex,
      ),
    );
    unawaited(_foregroundService.startForeground());

    if (!_isCountInActive) {
      await _playCurrentSongLinkedAudioIfEnabled();
      _linkedAudioStartedForCurrentSong = true;
      // Trigger audio cues for bar 1 immediately — the first tick won't
      // fire them because barChanged is false (state already shows bar 1).
      final firstEntry = _currentSongBeatmap?.entryForPlaybackBar(
        startPlaybackBarIndex,
      );
      _triggerSongEventsForBar(firstEntry);
    }

    state = state.copyWith(
      isPlaying: true,
      isStarting: false,
      isTransitioning: _isCountInActive,
      clearTransitionMessage: !_isCountInActive,
    );
  }

  Future<void> _advanceToNextSetlistSegment(
    MetronomeScreenState metronomeState,
  ) async {
    final plan = _currentSetlistPlaybackPlan;
    final currentSegmentIndex = _currentSetlistSegmentIndex;
    if (plan == null || currentSegmentIndex == null) {
      return;
    }
    final nextSegmentIndex = currentSegmentIndex + 1;
    if (nextSegmentIndex >= plan.segments.length) {
      _stop();
      state = state.copyWith(
        transitionMessage: 'Setlist complete',
        isTransitioning: true,
        clearCurrentSongTitle: true,
        clearCurrentSongIndex: true,
      );
      return;
    }
    _currentSetlistSegmentIndex = nextSegmentIndex;
    await _startCurrentSetlistSegment(metronomeState);
  }

  Future<void> _startCurrentSetlistSegment(
    MetronomeScreenState metronomeState,
  ) async {
    final plan = _currentSetlistPlaybackPlan;
    final segmentIndex = _currentSetlistSegmentIndex;
    if (plan == null || segmentIndex == null) {
      return;
    }
    final segment = plan.segments[segmentIndex];

    // When transitions are disabled, skip non-song segments.
    if (!_setlistTransitionEnabled && segment is! SetlistSongSegment) {
      await _advanceToNextSetlistSegment(metronomeState);
      return;
    }

    switch (segment) {
      case SetlistSongSegment():
        await _startSongPlaybackPlan(
          segment.song,
          metronomeState,
          plan: SongPlaybackPlan(
            song: segment.song,
            beatmap: segment.beatmap,
            shouldPlayLinkedAudio: segment.shouldPlayLinkedAudio,
          ),
          currentSongTitle: segment.songTitle,
          currentSongIndex: segment.songIndex,
          totalSongs: plan.totalPlayableSongs,
        );
      case SetlistCountInSegment():
        _currentSongBeatmap = segment.beatmap;
        _shouldPlayCurrentSongLinkedAudio = false;
        _linkedAudioStartedForCurrentSong = false;
        _firstSongPlaybackBarIndex = segment.beatmap.firstSongEntry.playbackBarIndex;
        _isCountInActive = true;
        _onFirstSongBarReached = () async {
          ref.read(liveMetronomeTransportProvider).stop();
          state = state.copyWith(
            isPlaying: false,
            isTransitioning: false,
            clearTransitionMessage: true,
          );
          await _advanceToNextSetlistSegment(metronomeState);
        };
        await _startActualSongPlayback(
          metronomeState,
          currentSongTitle: segment.songTitle,
          currentSongIndex: segment.songIndex,
          totalSongs: plan.totalPlayableSongs,
          startPlaybackBarIndex: 1,
          transitionMessage: _countInTransitionMessage(
            segment.beatmap.countInBarCount,
          ),
        );
      case SetlistWaitSegment():
        state = state.copyWith(
          isPlaying: true,
          isTransitioning: true,
          transitionMessage: _formatPauseCountdown(segment.durationSeconds),
          currentSongTitle: segment.songTitle,
          currentSongIndex: segment.songIndex,
          totalSongs: plan.totalPlayableSongs,
        );
        final wasCancelled = await _waitWithCountdown(
          segment.durationSeconds,
        );
        if (wasCancelled) return;
        await _advanceToNextSetlistSegment(metronomeState);
      case SetlistManualSegment():
        ref.read(liveMetronomeTransportProvider).stop();
        state = state.copyWith(
          isPlaying: false,
          isTransitioning: true,
          isWaitingForManualAdvance: true,
          transitionMessage: 'Press Play to continue',
          currentSongTitle: segment.songTitle,
          currentSongIndex: segment.songIndex,
          totalSongs: plan.totalPlayableSongs,
        );
      case SetlistAudioCueSegment():
        state = state.copyWith(
          isTransitioning: true,
          transitionMessage: 'Playing audio cue',
          currentSongTitle: segment.songTitle,
          currentSongIndex: segment.songIndex,
          totalSongs: plan.totalPlayableSongs,
        );
        try {
          await ref.read(audioEngineProvider).playCue(
                _scaledAudioCue(
                  segment.audioCue,
                  globalVolumeFactor: ref
                      .read(audioMixerControllerProvider.notifier)
                      .transitionVolumeFactor(),
                ),
              );
        } catch (error, stackTrace) {
          _logger.warning(
            'Failed to play setlist transition audio cue.',
            error,
            stackTrace,
          );
        }
        await _advanceToNextSetlistSegment(metronomeState);
    }
  }

  /// Called by the UI when the user taps "continue" during a manual
  /// transition step.
  Future<void> advanceSetlistTransition() async {
    if (_currentSetlistPlaybackPlan == null || _currentSetlistSegmentIndex == null) {
      return;
    }

    final metronomeState = ref.read(metronomeScreenControllerProvider);
    await _advanceToNextSetlistSegment(metronomeState);
  }

  /// Whether setlist transitions are enabled. When disabled, jumping to a
  /// song skips its transition steps.
  bool get isTransitionEnabled => _setlistTransitionEnabled;

  void setTransitionEnabled(bool enabled) {
    _setlistTransitionEnabled = enabled;
  }

  /// Jumps to the next song in the setlist. Only works when not currently
  /// playing (i.e. the setlist is paused).
  Future<void> jumpToNextSetlistSong() async {
    if (state.isPlaying || state.isTransitioning) return;
    final plan = _currentSetlistPlaybackPlan;
    if (plan == null) return;

    final currentSongIdx = _lastSetlistSongIndex ?? 1;
    final nextSongIdx = currentSongIdx + 1;
    if (nextSongIdx > plan.totalPlayableSongs) return;
    _lastSetlistSongIndex = nextSongIdx;
    _updateStoppedSongDisplay(plan, nextSongIdx);
  }

  /// Jumps to the previous song in the setlist. Only works when not currently
  /// playing (i.e. the setlist is paused).
  Future<void> jumpToPreviousSetlistSong() async {
    if (state.isPlaying || state.isTransitioning) return;
    final plan = _currentSetlistPlaybackPlan;
    if (plan == null) return;

    final currentSongIdx = _lastSetlistSongIndex ?? 1;
    final prevSongIdx = currentSongIdx - 1;
    if (prevSongIdx < 1) return;
    _lastSetlistSongIndex = prevSongIdx;
    _updateStoppedSongDisplay(plan, prevSongIdx);
  }

  void _updateStoppedSongDisplay(SetlistPlaybackPlan plan, int songIndex) {
    final segment = plan.segments.whereType<SetlistSongSegment>().where(
      (s) => s.songIndex == songIndex,
    ).firstOrNull;
    if (segment == null) return;
    state = state.copyWith(
      bpm: segment.song.startBpm,
      beatsPerBar: segment.song.beatsPerBar,
      beatUnit: segment.song.beatUnit,
      currentSongTitle: segment.songTitle,
      currentSongIndex: songIndex,
      totalSongs: plan.totalPlayableSongs,
    );
  }

  /// Advances the setlist when the current song reaches its endBar.
  Future<void> _advanceSetlistSong() async {
    final setlist = _activeSetlist;
    if (setlist == null) {
      return;
    }

    unawaited(ref.read(liveMetronomeTransportProvider).stopAllAudio());

    final metronomeState = ref.read(metronomeScreenControllerProvider);
    await _advanceToNextSetlistSegment(metronomeState);
  }

  AudioCue _scaledAudioCue(
    AudioCue audioCue, {
    required double globalVolumeFactor,
  }) {
    final scaledVolume = (audioCue.volumePercent * globalVolumeFactor)
        .round()
        .clamp(0, 100);
    return AudioCue(
      type: audioCue.type,
      voiceText: audioCue.voiceText,
      voiceIdentifier: audioCue.voiceIdentifier,
      customFilePath: audioCue.customFilePath,
      customFileDisplayName: audioCue.customFileDisplayName,

      volumePercent: scaledVolume,
    );
  }

  LiveMetronomeTransportConfig _transportConfigForBeatmapEntry(
    SongBeatmapEntry entry,
  ) {
    return LiveMetronomeTransportConfig(
      bpm: entry.bpm,
      beatsPerBar: entry.beatsPerBar,
      beatUnit: entry.beatUnit,
      subdivision: entry.subdivision,
      accentPattern: entry.accentPattern,
      clickSoundSet:
          ref.read(metronomeScreenControllerProvider).clickSoundSet,
      masterVolumePercent:
          ref.read(metronomeScreenControllerProvider).masterVolumePercent,
    );
  }

  MetronomeClickEngineConfig _metronomeClickEngineConfigForPlaybackBar(
    int playbackBarIndex,
  ) {
    final entry = _requiredBeatmapEntry(playbackBarIndex);
    return MetronomeClickEngineConfig(
      bpm: entry.bpm,
      beatsPerBar: entry.beatsPerBar,
      beatUnit: entry.beatUnit,
      subdivision: entry.subdivision,
      accentPattern: entry.accentPattern,
    );
  }

  Future<void> _playCurrentSongLinkedAudioIfEnabled() async {
    if (!_shouldPlayCurrentSongLinkedAudio) {
      return;
    }

    final handle = _preparedCurrentSongLinkedAudioHandle;
    if (handle == null) {
      return;
    }

    try {
      await ref.read(audioEngineProvider).playPreparedLinkedAudio(handle);
      _preparedCurrentSongLinkedAudioHandle = null;
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to start linked audio for live song playback.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _prepareCurrentSongLinkedAudio(Song song) async {
    await _releasePreparedCurrentSongLinkedAudio();

    final linkedAudio = song.linkedAudio;
    if (!_shouldPlayCurrentSongLinkedAudio || linkedAudio == null) {
      return;
    }

    final resolvedLinkedAudio = await ref
        .read(linkedAudioPathRepairServiceProvider)
        .repairIfNeeded(linkedAudio);
    if (!resolvedLinkedAudio.playInLiveMode) {
      return;
    }

    try {
      _preparedCurrentSongLinkedAudioHandle = await ref
          .read(audioEngineProvider)
          .prepareLinkedAudioPlayback(
            resolvedLinkedAudio.filePath,
            offset: Duration(
              milliseconds: resolvedLinkedAudio.offsetMilliseconds,
            ),
            volume: _linkedAudioPlaybackVolume(resolvedLinkedAudio),
          );
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to prepare linked audio for live song playback.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _releasePreparedCurrentSongLinkedAudio() async {
    final handle = _preparedCurrentSongLinkedAudioHandle;
    _preparedCurrentSongLinkedAudioHandle = null;
    if (handle == null) {
      return;
    }
    try {
      await ref.read(audioEngineProvider).releasePreparedLinkedAudio(handle);
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to release prepared linked audio.',
        error,
        stackTrace,
      );
    }
  }

  double _linkedAudioPlaybackVolume(LinkedAudioFile linkedAudio) {
    final mixerFactor =
        ref.read(audioMixerControllerProvider.notifier).songVolumeFactor();
    final linkedAudioFactor = linkedAudio.volumePercent / 100;
    return (mixerFactor * linkedAudioFactor).clamp(0.0, 1.0);
  }

  String _countInTransitionMessage(int barCount) {
    final noun = barCount == 1 ? 'bar' : 'bars';
    return 'Count-in: $barCount $noun';
  }

  bool _isLastPulseOfBar(MetronomeBeatTick tick) {
    return tick.beatIndex == tick.beatsPerBar && tick.pulseIndex == tick.pulseCount;
  }

  bool _hasCompletedSongPlayback(MetronomeBeatTick tick) {
    final beatmap = _currentSongBeatmap;
    if (beatmap == null) {
      return false;
    }

    return tick.barIndex >= beatmap.totalPlaybackBars &&
        _isLastPulseOfBar(tick);
  }

  SongBeatmapEntry? _beatmapEntryForTick(MetronomeBeatTick tick) {
    final beatmap = _currentSongBeatmap;
    if (beatmap == null) {
      return null;
    }
    final playbackBarIndex = tick.barIndex.clamp(
      1,
      beatmap.totalPlaybackBars,
    );
    return beatmap.entryForPlaybackBar(playbackBarIndex);
  }

  SongBeatmapEntry _requiredBeatmapEntry(int playbackBarIndex) {
    final beatmap = _currentSongBeatmap;
    if (beatmap == null) {
      throw StateError('Song playback plan is not available.');
    }

    final clampedPlaybackBarIndex = playbackBarIndex.clamp(
      1,
      beatmap.totalPlaybackBars,
    );
    return beatmap.entryForPlaybackBar(clampedPlaybackBarIndex);
  }

  Future<void> _enterSongPlaybackPhase() async {
    _isCountInActive = false;
    if (_linkedAudioStartedForCurrentSong) {
      return;
    }
    _linkedAudioStartedForCurrentSong = true;
    final onFirstSongBarReached = _onFirstSongBarReached;
    _onFirstSongBarReached = null;
    if (onFirstSongBarReached != null) {
      await onFirstSongBarReached();
    }
  }

  bool _hasReachedFirstSongBar(
    MetronomeBeatTick tick,
    SongBeatmapEntry? beatmapEntry,
  ) {
    return beatmapEntry != null &&
        beatmapEntry.playbackBarIndex == _firstSongPlaybackBarIndex &&
        tick.beatIndex == 1 &&
        tick.pulseIndex == 1;
  }

  int _remainingCountInBars(SongBeatmapEntry? beatmapEntry) {
    final firstSongPlaybackBarIndex = _firstSongPlaybackBarIndex;
    if (beatmapEntry == null || firstSongPlaybackBarIndex == null) {
      return 0;
    }
    return firstSongPlaybackBarIndex - beatmapEntry.playbackBarIndex - 1;
  }

  List<MetronomeClickEngineConfig> _beatmapTransportSequence({
    required int startPlaybackBarIndex,
  }) {
    final beatmap = _currentSongBeatmap;
    if (beatmap == null) {
      throw StateError('Song playback plan is not available.');
    }
    return [
      for (var playbackBarIndex = startPlaybackBarIndex;
          playbackBarIndex <= beatmap.totalPlaybackBars;
          playbackBarIndex += 1)
        _metronomeClickEngineConfigForPlaybackBar(playbackBarIndex),
    ];
  }

  ({List<LiveEvent> current, List<LiveEvent> next}) _resolveLiveEventsForTick({
    required MetronomeBeatTick tick,
    required SongBeatmapEntry? beatmapEntry,
  }) {
    // Song/setlist playback: events come exclusively from the beatmap.
    if (beatmapEntry != null) {
      return _resolveSongPlaybackEvents(
        playbackBarIndex: beatmapEntry.playbackBarIndex,
      );
    }

    // Metronome-only mode: no beatmap, resolve interval stepping events.
    final metronomeState = ref.read(metronomeScreenControllerProvider);
    return _metronomeEventResolver.resolve(
      intervalSettings: metronomeState.intervalSettings,
      currentBpm: state.bpm,
    );
  }

  ({List<LiveEvent> current, List<LiveEvent> next}) _resolveSongPlaybackEvents({
    required int playbackBarIndex,
  }) {
    final currentEvents = _currentSongPlaybackEvents(
      playbackBarIndex: playbackBarIndex,
    );

    final beatmap = _currentSongBeatmap!;
    for (var nextPlaybackBarIndex = playbackBarIndex + 1;
        nextPlaybackBarIndex <= beatmap.totalPlaybackBars;
        nextPlaybackBarIndex += 1) {
      final nextStep = _requiredBeatmapEntry(nextPlaybackBarIndex);
      final nextEvents = _songPlaybackEventsAtStep(nextStep);
      if (nextEvents.isNotEmpty) {
        return (current: currentEvents, next: nextEvents);
      }
    }

    return (current: currentEvents, next: const []);
  }

  List<LiveEvent> _currentSongPlaybackEvents({
    required int playbackBarIndex,
  }) {
    for (var candidatePlaybackBarIndex = playbackBarIndex;
        candidatePlaybackBarIndex >= 1;
        candidatePlaybackBarIndex -= 1) {
      final candidateStep = _requiredBeatmapEntry(candidatePlaybackBarIndex);
      final events = _songPlaybackEventsAtStep(candidateStep);
      if (events.isNotEmpty) {
        return events;
      }
    }

    return const [];
  }

  List<LiveEvent> _songPlaybackEventsAtStep(SongBeatmapEntry step) {
    final events = <LiveEvent>[];

    for (final event in step.events) {
      switch (event.kind) {
        case SongBeatmapEventKind.tempoChange:
          events.add(
            TempoChangeEvent(
              bpm: event.bpm!,
              beatsPerBar: event.beatsPerBar!,
              beatUnit: event.beatUnit!,
              barIndex: event.sourceBarIndex ?? step.displayBarIndex,
              displayBarLabel: step.barLabel,
            ),
          );
        case SongBeatmapEventKind.loopStart:
          events.add(
            LoopEvent(
              startBar: event.loopStartBar!,
              endBar: event.loopEndBar!,
              iteration: event.loopIteration!,
              totalIterations: event.loopTotalIterations!,
              isStart: true,
              displayBarLabel: step.barLabel,
            ),
          );
        case SongBeatmapEventKind.loopEnd:
          events.add(
            LoopEvent(
              startBar: event.loopStartBar!,
              endBar: event.loopEndBar!,
              iteration: event.loopIteration!,
              totalIterations: event.loopTotalIterations!,
              isStart: false,
              displayBarLabel: step.barLabel,
            ),
          );
        case SongBeatmapEventKind.songMarker:
          events.add(
            SongMarkerEvent(
              eventLabel: event.label,
              barIndex: event.sourceBarIndex ?? step.displayBarIndex,
              displayBarLabel: step.barLabel,
            ),
          );
      }
    }

    return List<LiveEvent>.unmodifiable(events);
  }

  void _triggerSongEventsForBar(SongBeatmapEntry? beatmapEntry) {
    if (beatmapEntry == null || _isCountInActive) {
      return;
    }

    final cueVolumeFactor =
        ref.read(audioMixerControllerProvider.notifier).cueVolumeFactor();
    for (final trigger in beatmapEntry.audioCueTriggers) {
      unawaited(
        ref.read(audioEngineProvider).playCue(
              _scaledAudioCue(
                trigger.audioCue,
                globalVolumeFactor: cueVolumeFactor,
              ),
            ),
      );
    }
  }
}
