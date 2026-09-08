import '../domain/audio_cue.dart';
import '../domain/setlist.dart';

sealed class SetlistTransitionAction {
  const SetlistTransitionAction();
}

final class CountInBarsAction extends SetlistTransitionAction {
  const CountInBarsAction({required this.barCount});

  final int barCount;
}

final class PauseTimerAction extends SetlistTransitionAction {
  const PauseTimerAction({required this.duration});

  final Duration duration;
}

final class ManualWaitAction extends SetlistTransitionAction {
  const ManualWaitAction();
}

final class AudioCueAction extends SetlistTransitionAction {
  const AudioCueAction({required this.audioCue});

  final AudioCue audioCue;
}

class SetlistTransitionStepRunner {
  const SetlistTransitionStepRunner();

  SetlistTransitionAction resolveAction(SetlistTransitionStep step) {
    return switch (step.type) {
      SetlistTransitionStepType.countInBars => _buildCountInBarsAction(step),
      SetlistTransitionStepType.pauseTimer => _buildPauseTimerAction(step),
      SetlistTransitionStepType.manual => const ManualWaitAction(),
      SetlistTransitionStepType.audio => _buildAudioCueAction(step),
    };
  }

  CountInBarsAction _buildCountInBarsAction(SetlistTransitionStep step) {
    if (step.value < 1) {
      throw ArgumentError.value(
        step.value,
        'step.value',
        'count-in bars must be at least 1',
      );
    }

    return CountInBarsAction(barCount: step.value);
  }

  PauseTimerAction _buildPauseTimerAction(SetlistTransitionStep step) {
    if (step.value < 0) {
      throw ArgumentError.value(
        step.value,
        'step.value',
        'pause timer must not be negative',
      );
    }

    return PauseTimerAction(duration: Duration(seconds: step.value));
  }

  AudioCueAction _buildAudioCueAction(SetlistTransitionStep step) {
    final audioCue = step.audioCue;
    if (audioCue == null) {
      throw ArgumentError.value(
        step.id,
        'step.audioCue',
        'audio transition steps require an audio cue',
      );
    }

    return AudioCueAction(audioCue: audioCue);
  }
}
