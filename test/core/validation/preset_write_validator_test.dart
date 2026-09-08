import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/domain/interval_settings.dart';
import 'package:tempodeck/core/domain/metronome_preset.dart';
import 'package:tempodeck/core/domain/subdivision.dart';
import 'package:tempodeck/core/validation/preset_write_validator.dart';

void main() {
  const validator = PresetWriteValidator();

  test('accepts a valid metronome preset', () {
    const preset = MetronomePreset(
      id: 'preset-1',
      name: 'Arena Intro',
      bpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      subdivision: Subdivision.four,
      accentPattern: [
        AccentLevel.high,
        AccentLevel.normal,
        AccentLevel.low,
        AccentLevel.normal,
      ],
      intervalSettings: IntervalSettings(
        interval: Duration(minutes: 1),
        bpmStepEnabled: true,
        bpmStep: 3,
        maxDuration: Duration(minutes: 5),
      ),
    );

    expect(() => validator.validate(preset), returnsNormally);
  });

  test('rejects invalid top-level timing values', () {
    const invalidNamePreset = MetronomePreset(
      id: 'preset-0',
      name: '  ',
      bpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      subdivision: Subdivision.one,
      accentPattern: [],
    );
    const invalidBpmPreset = MetronomePreset(
      id: 'preset-1',
      name: 'Arena Intro',
      bpm: 10,
      beatsPerBar: 4,
      beatUnit: 4,
      subdivision: Subdivision.one,
      accentPattern: [],
    );
    const invalidBeatUnitPreset = MetronomePreset(
      id: 'preset-2',
      name: 'Arena Intro',
      bpm: 128,
      beatsPerBar: 4,
      beatUnit: 3,
      subdivision: Subdivision.one,
      accentPattern: [],
    );
    const invalidBeatsPerBarPreset = MetronomePreset(
      id: 'preset-3',
      name: 'Arena Intro',
      bpm: 128,
      beatsPerBar: 0,
      beatUnit: 4,
      subdivision: Subdivision.one,
      accentPattern: [],
    );

    expect(
      () => validator.validate(invalidNamePreset),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validator.validate(invalidBpmPreset),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validator.validate(invalidBeatUnitPreset),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validator.validate(invalidBeatsPerBarPreset),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects accent patterns longer than beats per bar', () {
    const preset = MetronomePreset(
      id: 'preset-1',
      name: 'Arena Intro',
      bpm: 128,
      beatsPerBar: 3,
      beatUnit: 4,
      subdivision: Subdivision.one,
      accentPattern: [
        AccentLevel.high,
        AccentLevel.normal,
        AccentLevel.low,
        AccentLevel.normal,
      ],
    );

    expect(() => validator.validate(preset), throwsA(isA<ArgumentError>()));
  });

  test('rejects master volume outside the supported range', () {
    const preset = MetronomePreset(
      id: 'preset-1',
      name: 'Arena Intro',
      bpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      subdivision: Subdivision.one,
      clickSoundSet: ClickSoundSet.hype,
      masterVolumePercent: 120,
      accentPattern: [],
    );

    expect(() => validator.validate(preset), throwsA(isA<ArgumentError>()));
  });

  test('rejects non-positive interval durations', () {
    const preset = MetronomePreset(
      id: 'preset-1',
      name: 'Arena Intro',
      bpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      subdivision: Subdivision.one,
      accentPattern: [],
      intervalSettings: IntervalSettings(
        interval: Duration.zero,
      ),
    );

    expect(() => validator.validate(preset), throwsA(isA<ArgumentError>()));
  });

  test('rejects enabled interval bpm steps below one', () {
    const preset = MetronomePreset(
      id: 'preset-1',
      name: 'Arena Intro',
      bpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      subdivision: Subdivision.one,
      accentPattern: [],
      intervalSettings: IntervalSettings(
        interval: Duration(minutes: 1),
        bpmStepEnabled: true,
        bpmStep: 0,
      ),
    );

    expect(() => validator.validate(preset), throwsA(isA<ArgumentError>()));
  });

  test('rejects max durations shorter than the interval', () {
    const preset = MetronomePreset(
      id: 'preset-1',
      name: 'Arena Intro',
      bpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      subdivision: Subdivision.one,
      accentPattern: [],
      intervalSettings: IntervalSettings(
        interval: Duration(minutes: 2),
        maxDuration: Duration(minutes: 1),
      ),
    );

    expect(() => validator.validate(preset), throwsA(isA<ArgumentError>()));
  });

  test('rejects non-positive max durations', () {
    const preset = MetronomePreset(
      id: 'preset-1',
      name: 'Arena Intro',
      bpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      subdivision: Subdivision.one,
      accentPattern: [],
      intervalSettings: IntervalSettings(
        interval: Duration(minutes: 1),
        maxDuration: Duration.zero,
      ),
    );

    expect(() => validator.validate(preset), throwsA(isA<ArgumentError>()));
  });
}
