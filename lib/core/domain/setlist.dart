import 'audio_cue.dart';

enum SetlistTransitionStepType { countInBars, pauseTimer, manual, audio }

class Setlist {
  const Setlist({
    required this.id,
    required this.title,
    required this.createdAt,
    this.items = const [],
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final List<SetlistItem> items;

  Setlist copyWith({
    String? title,
    List<SetlistItem>? items,
  }) {
    return Setlist(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      items: items ?? this.items,
    );
  }
}

class SetlistItem {
  const SetlistItem({
    required this.id,
    required this.songId,
    required this.songTitle,
    this.playbackEnabled = true,
    this.playAttachedAudio = true,
    this.transitionSteps = const [],
  });

  final String id;
  final String songId;
  final String songTitle;
  final bool playbackEnabled;
  final bool playAttachedAudio;
  final List<SetlistTransitionStep> transitionSteps;

  SetlistItem copyWith({
    bool? playbackEnabled,
    bool? playAttachedAudio,
    List<SetlistTransitionStep>? transitionSteps,
  }) {
    return SetlistItem(
      id: id,
      songId: songId,
      songTitle: songTitle,
      playbackEnabled: playbackEnabled ?? this.playbackEnabled,
      playAttachedAudio: playAttachedAudio ?? this.playAttachedAudio,
      transitionSteps: transitionSteps ?? this.transitionSteps,
    );
  }
}

class SetlistTransitionStep {
  const SetlistTransitionStep({
    required this.id,
    required this.type,
    required this.value,
    this.audioCue,
  });

  final String id;
  final SetlistTransitionStepType type;
  final int value;
  final AudioCue? audioCue;
}
