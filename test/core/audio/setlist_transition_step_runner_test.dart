import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/setlist_transition_step_runner.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/setlist.dart';

void main() {
  group('SetlistTransitionStepRunner.resolveAction', () {
    const runner = SetlistTransitionStepRunner();

    test('resolves count-in steps to bar-count actions', () {
      final action = runner.resolveAction(
        const SetlistTransitionStep(
          id: 'step-1',
          type: SetlistTransitionStepType.countInBars,
          value: 2,
        ),
      );

      expect(action, isA<CountInBarsAction>());
      expect((action as CountInBarsAction).barCount, 2);
    });

    test('resolves pause steps to timer actions', () {
      final action = runner.resolveAction(
        const SetlistTransitionStep(
          id: 'step-1',
          type: SetlistTransitionStepType.pauseTimer,
          value: 5,
        ),
      );

      expect(action, isA<PauseTimerAction>());
      expect((action as PauseTimerAction).duration, const Duration(seconds: 5));
    });

    test('resolves manual steps to wait actions', () {
      final action = runner.resolveAction(
        const SetlistTransitionStep(
          id: 'step-1',
          type: SetlistTransitionStepType.manual,
          value: 0,
        ),
      );

      expect(action, isA<ManualWaitAction>());
    });

    test('resolves audio steps to cue actions', () {
      final cue = const AudioCue(type: AudioCueType.voice, voiceText: 'Go');

      final action = runner.resolveAction(
        SetlistTransitionStep(
          id: 'step-1',
          type: SetlistTransitionStepType.audio,
          value: 0,
          audioCue: cue,
        ),
      );

      expect(action, isA<AudioCueAction>());
      expect((action as AudioCueAction).audioCue, cue);
    });

    test('throws for invalid count-in bar values', () {
      expect(
        () => runner.resolveAction(
          const SetlistTransitionStep(
            id: 'step-1',
            type: SetlistTransitionStepType.countInBars,
            value: 0,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws for negative pause durations', () {
      expect(
        () => runner.resolveAction(
          const SetlistTransitionStep(
            id: 'step-1',
            type: SetlistTransitionStepType.pauseTimer,
            value: -1,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when audio step has no cue', () {
      expect(
        () => runner.resolveAction(
          const SetlistTransitionStep(
            id: 'step-1',
            type: SetlistTransitionStepType.audio,
            value: 0,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
