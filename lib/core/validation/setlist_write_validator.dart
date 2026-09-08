import '../domain/audio_cue.dart';
import '../domain/setlist.dart';
import 'validation_helpers.dart';

class SetlistWriteValidator with ValidationHelpers {
  const SetlistWriteValidator();

  static const int minimumTitleLength = 1;
  static const int minimumCountInBars = 1;
  static const int minimumPauseSeconds = 0;
  static const int minimumVolumePercent = 0;
  static const int maximumVolumePercent = 100;

  void validate(Setlist setlist) {
    requireText(
      value: setlist.title,
      label: 'Setlist.title',
      message:
          'Setlist.title must contain at least $minimumTitleLength non-whitespace character.',
    );

    for (final item in setlist.items) {
      for (final step in item.transitionSteps) {
        _validateStep(step);
      }
    }
  }

  void _validateStep(SetlistTransitionStep step) {
    switch (step.type) {
      case SetlistTransitionStepType.countInBars:
        requireMinimum(
          value: step.value,
          minimum: minimumCountInBars,
          label: 'SetlistTransitionStep.value',
          message: 'count-in bars must be at least 1.',
        );
      case SetlistTransitionStepType.pauseTimer:
        requireMinimum(
          value: step.value,
          minimum: minimumPauseSeconds,
          label: 'SetlistTransitionStep.value',
          message: 'pause timer must not be negative.',
        );
      case SetlistTransitionStepType.manual:
      case SetlistTransitionStepType.audio:
        break;
    }

    final audioCue = step.audioCue;
    if (step.type == SetlistTransitionStepType.audio) {
      if (audioCue == null) {
        throw ArgumentError.value(
          step.id,
          'SetlistTransitionStep.audioCue',
          'audio transition steps require an audio cue.',
        );
      }

      _validateAudioCue(audioCue);
      return;
    }

    if (audioCue != null) {
      throw ArgumentError.value(
        step.id,
        'SetlistTransitionStep.audioCue',
        'Only audio transition steps may define an audio cue.',
      );
    }
  }

  void _validateAudioCue(AudioCue audioCue) {
    requireInRange(
      value: audioCue.volumePercent,
      minimum: minimumVolumePercent,
      maximum: maximumVolumePercent,
      label: 'AudioCue.volumePercent',
    );

    switch (audioCue.type) {
      case AudioCueType.voice:
        requireText(
          value: audioCue.voiceText,
          label: 'AudioCue.voiceText',
          message: 'voice cues require voice text.',
        );
      case AudioCueType.customFile:
        requireText(
          value: audioCue.customFilePath,
          label: 'AudioCue.customFilePath',
          message: 'custom file cues require a file path.',
        );
      case AudioCueType.intervalSignal:
      case AudioCueType.maxSignal:
      case AudioCueType.lowPulse:
      case AudioCueType.midPulse:
      case AudioCueType.highPulse:
        break;
    }
  }
}
