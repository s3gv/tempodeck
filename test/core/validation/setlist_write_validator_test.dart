import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/setlist.dart';
import 'package:tempodeck/core/validation/setlist_write_validator.dart';

void main() {
  const validator = SetlistWriteValidator();

  test('accepts a valid setlist aggregate', () {
    final setlist = Setlist(
      id: 'setlist-1',
      title: 'Live Set',
      createdAt: DateTime.utc(2026, 3, 10, 12),
      items: const [
        SetlistItem(
          id: 'item-1',
          songId: 'song-1',
          songTitle: 'Intro',
          transitionSteps: [
            SetlistTransitionStep(
              id: 'step-1',
              type: SetlistTransitionStepType.countInBars,
              value: 2,
            ),
            SetlistTransitionStep(
              id: 'step-2',
              type: SetlistTransitionStepType.audio,
              value: 0,
              audioCue: AudioCue(
                type: AudioCueType.voice,
                voiceText: 'Next song',
                volumePercent: 80,
              ),
            ),
          ],
        ),
      ],
    );

    expect(() => validator.validate(setlist), returnsNormally);
  });

  test('rejects blank setlist titles', () {
    final setlist = Setlist(
      id: 'setlist-1',
      title: '   ',
      createdAt: DateTime.utc(2026, 3, 10, 12),
    );

    expect(() => validator.validate(setlist), throwsA(isA<ArgumentError>()));
  });

  test('rejects count-in steps below one bar', () {
    final setlist = _buildSetlistWithStep(
      const SetlistTransitionStep(
        id: 'step-1',
        type: SetlistTransitionStepType.countInBars,
        value: 0,
      ),
    );

    expect(() => validator.validate(setlist), throwsA(isA<ArgumentError>()));
  });

  test('rejects negative pause timers', () {
    final setlist = _buildSetlistWithStep(
      const SetlistTransitionStep(
        id: 'step-1',
        type: SetlistTransitionStepType.pauseTimer,
        value: -1,
      ),
    );

    expect(() => validator.validate(setlist), throwsA(isA<ArgumentError>()));
  });

  test('rejects audio steps without an audio cue', () {
    final setlist = _buildSetlistWithStep(
      const SetlistTransitionStep(
        id: 'step-1',
        type: SetlistTransitionStepType.audio,
        value: 0,
      ),
    );

    expect(() => validator.validate(setlist), throwsA(isA<ArgumentError>()));
  });

  test('rejects non-audio steps that still carry an audio cue', () {
    final setlist = _buildSetlistWithStep(
      const SetlistTransitionStep(
        id: 'step-1',
        type: SetlistTransitionStepType.manual,
        value: 0,
        audioCue: AudioCue(type: AudioCueType.highPulse),
      ),
    );

    expect(() => validator.validate(setlist), throwsA(isA<ArgumentError>()));
  });

  test('rejects invalid voice cues', () {
    final setlist = _buildSetlistWithStep(
      const SetlistTransitionStep(
        id: 'step-1',
        type: SetlistTransitionStepType.audio,
        value: 0,
        audioCue: AudioCue(
          type: AudioCueType.voice,
          voiceText: '   ',
        ),
      ),
    );

    expect(() => validator.validate(setlist), throwsA(isA<ArgumentError>()));
  });

  test('rejects invalid custom file cues', () {
    final setlist = _buildSetlistWithStep(
      const SetlistTransitionStep(
        id: 'step-1',
        type: SetlistTransitionStepType.audio,
        value: 0,
        audioCue: AudioCue(
          type: AudioCueType.customFile,
          customFilePath: '',
        ),
      ),
    );

    expect(() => validator.validate(setlist), throwsA(isA<ArgumentError>()));
  });

  test('rejects audio cues outside the supported volume range', () {
    final setlist = _buildSetlistWithStep(
      const SetlistTransitionStep(
        id: 'step-1',
        type: SetlistTransitionStepType.audio,
        value: 0,
        audioCue: AudioCue(
          type: AudioCueType.highPulse,
          volumePercent: 120,
        ),
      ),
    );

    expect(() => validator.validate(setlist), throwsA(isA<ArgumentError>()));
  });
}

Setlist _buildSetlistWithStep(SetlistTransitionStep step) {
  return Setlist(
    id: 'setlist-1',
    title: 'Live Set',
    createdAt: DateTime.utc(2026, 3, 10, 12),
    items: [
      SetlistItem(
        id: 'item-1',
        songId: 'song-1',
        songTitle: 'Intro',
        transitionSteps: [step],
      ),
    ],
  );
}
