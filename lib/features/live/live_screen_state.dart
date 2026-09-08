import '../../core/domain/accent_level.dart';
import 'live_event.dart';

class LiveScreenState {
  const LiveScreenState({
    required this.isPlaying,
    required this.isStarting,
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.barIndex,
    required this.barLabel,
    required this.beatIndex,
    required this.pulseIndex,
    required this.pulseCount,
    required this.accentLevel,
    required this.currentEvents,
    required this.nextEvents,
    required this.currentSongTitle,
    required this.currentSongIndex,
    required this.totalSongs,
    required this.isTransitioning,
    required this.transitionMessage,
    required this.isWaitingForManualAdvance,
    required this.intervalRemainingSeconds,
    required this.maxDurationRemainingSeconds,
    required this.errorMessage,
  });

  factory LiveScreenState.initial() {
    return const LiveScreenState(
      isPlaying: false,
      isStarting: false,
      bpm: _defaultBpm,
      beatsPerBar: _defaultBeatsPerBar,
      beatUnit: _defaultBeatUnit,
      barIndex: 0,
      barLabel: null,
      beatIndex: 0,
      pulseIndex: 0,
      pulseCount: 1,
      accentLevel: AccentLevel.normal,
      currentEvents: [],
      nextEvents: [],
      currentSongTitle: null,
      currentSongIndex: null,
      totalSongs: null,
      isTransitioning: false,
      transitionMessage: null,
      isWaitingForManualAdvance: false,
      intervalRemainingSeconds: null,
      maxDurationRemainingSeconds: null,
      errorMessage: null,
    );
  }

  static const _defaultBpm = 120;
  static const _defaultBeatsPerBar = 4;
  static const _defaultBeatUnit = 4;

  final bool isPlaying;
  final bool isStarting;

  /// Current BPM – sourced from the active [LiveViewContext].
  final int bpm;

  /// Current beats per bar – sourced from the active [LiveViewContext].
  final int beatsPerBar;

  /// Current beat unit – sourced from the active [LiveViewContext].
  final int beatUnit;

  final int barIndex;
  final String? barLabel;
  final int beatIndex;
  final int pulseIndex;
  final int pulseCount;
  final AccentLevel accentLevel;
  final List<LiveEvent> currentEvents;
  final List<LiveEvent> nextEvents;

  /// Title of the currently playing song in setlist mode.
  final String? currentSongTitle;

  /// 1-based index of the current song among playable setlist items.
  final int? currentSongIndex;

  /// Total number of playable songs in the active setlist.
  final int? totalSongs;

  /// Whether a setlist transition step is currently executing.
  final bool isTransitioning;

  /// Human-readable description of the active transition step.
  final String? transitionMessage;

  /// Whether the setlist is waiting for the user to manually advance.
  final bool isWaitingForManualAdvance;

  /// Remaining seconds in the current metronome interval, or null when not
  /// in interval mode.
  final int? intervalRemainingSeconds;

  /// Remaining seconds of the total max duration, or null when not set.
  final int? maxDurationRemainingSeconds;

  /// User-facing error message when audio playback fails.
  final String? errorMessage;

  LiveScreenState copyWith({
    bool? isPlaying,
    bool? isStarting,
    int? bpm,
    int? beatsPerBar,
    int? beatUnit,
    int? barIndex,
    String? barLabel,
    bool clearBarLabel = false,
    int? beatIndex,
    int? pulseIndex,
    int? pulseCount,
    AccentLevel? accentLevel,
    List<LiveEvent>? currentEvents,
    List<LiveEvent>? nextEvents,
    String? currentSongTitle,
    bool clearCurrentSongTitle = false,
    int? currentSongIndex,
    bool clearCurrentSongIndex = false,
    int? totalSongs,
    bool clearTotalSongs = false,
    bool? isTransitioning,
    String? transitionMessage,
    bool clearTransitionMessage = false,
    bool? isWaitingForManualAdvance,
    int? intervalRemainingSeconds,
    bool clearIntervalRemainingSeconds = false,
    int? maxDurationRemainingSeconds,
    bool clearMaxDurationRemainingSeconds = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return LiveScreenState(
      isPlaying: isPlaying ?? this.isPlaying,
      isStarting: isStarting ?? this.isStarting,
      bpm: bpm ?? this.bpm,
      beatsPerBar: beatsPerBar ?? this.beatsPerBar,
      beatUnit: beatUnit ?? this.beatUnit,
      barIndex: barIndex ?? this.barIndex,
      barLabel: clearBarLabel ? null : (barLabel ?? this.barLabel),
      beatIndex: beatIndex ?? this.beatIndex,
      pulseIndex: pulseIndex ?? this.pulseIndex,
      pulseCount: pulseCount ?? this.pulseCount,
      accentLevel: accentLevel ?? this.accentLevel,
      currentEvents: currentEvents ?? this.currentEvents,
      nextEvents: nextEvents ?? this.nextEvents,
      currentSongTitle: clearCurrentSongTitle
          ? null
          : (currentSongTitle ?? this.currentSongTitle),
      currentSongIndex: clearCurrentSongIndex
          ? null
          : (currentSongIndex ?? this.currentSongIndex),
      totalSongs:
          clearTotalSongs ? null : (totalSongs ?? this.totalSongs),
      isTransitioning: isTransitioning ?? this.isTransitioning,
      transitionMessage: clearTransitionMessage
          ? null
          : (transitionMessage ?? this.transitionMessage),
      isWaitingForManualAdvance:
          isWaitingForManualAdvance ?? this.isWaitingForManualAdvance,
      intervalRemainingSeconds: clearIntervalRemainingSeconds
          ? null
          : (intervalRemainingSeconds ?? this.intervalRemainingSeconds),
      maxDurationRemainingSeconds: clearMaxDurationRemainingSeconds
          ? null
          : (maxDurationRemainingSeconds ?? this.maxDurationRemainingSeconds),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}
