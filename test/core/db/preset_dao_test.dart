import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/db/app_database.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/domain/interval_settings.dart';
import 'package:tempodeck/core/domain/metronome_preset.dart';
import 'package:tempodeck/core/domain/subdivision.dart';

void main() {
  late AppDatabase database;
  late PresetDao dao;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    dao = database.presetDao;
  });

  tearDown(() async {
    await database.close();
  });

  test('saves and reloads a preset with interval settings', () async {
    final preset = const MetronomePreset(
      id: 'preset-1',
      name: 'Arena Intro',
      bpm: 128,
      beatsPerBar: 4,
      beatUnit: 4,
      subdivision: Subdivision.four,
      clickSoundSet: ClickSoundSet.hype,
      masterVolumePercent: 67,
      accentPattern: [
        AccentLevel.high,
        AccentLevel.normal,
        AccentLevel.low,
        AccentLevel.normal,
      ],
      intervalSettings: IntervalSettings(
        interval: Duration(minutes: 1, seconds: 30),
        bpmStepEnabled: true,
        bpmStep: 3,
        maxDuration: Duration(minutes: 10),
      ),
    );

    await dao.savePreset(preset);

    final loadedPreset = await dao.getPresetById(preset.id);

    expect(loadedPreset, isNotNull);
    _expectPresetsEqual(loadedPreset!, preset);
  });

  test('updates presets and clears interval settings on overwrite', () async {
    final originalPreset = const MetronomePreset(
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
      ),
    );
    final updatedPreset = const MetronomePreset(
      id: 'preset-1',
      name: 'Arena Intro v2',
      bpm: 140,
      beatsPerBar: 7,
      beatUnit: 8,
      subdivision: Subdivision.three,
      clickSoundSet: ClickSoundSet.mightyKit,
      masterVolumePercent: 42,
      accentPattern: [
        AccentLevel.high,
        AccentLevel.low,
        AccentLevel.normal,
      ],
    );

    await dao.savePreset(originalPreset);
    await dao.savePreset(updatedPreset);

    final loadedPreset = await dao.getPresetById(updatedPreset.id);

    expect(loadedPreset, isNotNull);
    _expectPresetsEqual(loadedPreset!, updatedPreset);
  });

  test('lists presets ordered by name', () async {
    final zebraPreset = const MetronomePreset(
      id: 'preset-1',
      name: 'Zebra',
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      subdivision: Subdivision.one,
      accentPattern: [AccentLevel.high],
    );
    final alphaPreset = const MetronomePreset(
      id: 'preset-2',
      name: 'Alpha',
      bpm: 140,
      beatsPerBar: 3,
      beatUnit: 8,
      subdivision: Subdivision.three,
      accentPattern: [
        AccentLevel.high,
        AccentLevel.low,
        AccentLevel.normal,
      ],
    );

    await dao.savePreset(zebraPreset);
    await dao.savePreset(alphaPreset);

    final presets = await dao.getAllPresets();

    expect(
      presets.map((preset) => preset.id).toList(),
      ['preset-2', 'preset-1'],
    );
  });

  test('deletes presets', () async {
    final preset = const MetronomePreset(
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
    );

    await dao.savePreset(preset);
    await dao.deletePreset(preset.id);

    final loadedPreset = await dao.getPresetById(preset.id);

    expect(loadedPreset, isNull);
  });

  test('watchPresetById emits preset updates and null after deletion',
      () async {
    final emittedPresets = <MetronomePreset?>[];
    final preset = const MetronomePreset(
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
    );
    final subscription =
        dao.watchPresetById(preset.id).listen(emittedPresets.add);

    await Future<void>.delayed(Duration.zero);
    await dao.savePreset(preset);
    await Future<void>.delayed(Duration.zero);
    await dao.deletePreset(preset.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emittedPresets.first, isNull);
    expect(emittedPresets[1], isNotNull);
    _expectPresetsEqual(emittedPresets[1]!, preset);
    expect(emittedPresets.last, isNull);
  });

  test('watchAllPresets emits on insert and delete', () async {
    final emittedPresets = <List<MetronomePreset>>[];
    final preset = const MetronomePreset(
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
    );
    final subscription = dao.watchAllPresets().listen(emittedPresets.add);

    await Future<void>.delayed(Duration.zero);
    await dao.savePreset(preset);
    await Future<void>.delayed(Duration.zero);
    await dao.deletePreset(preset.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emittedPresets.first, isEmpty);
    expect(emittedPresets[1].map((item) => item.id).toList(), ['preset-1']);
    expect(emittedPresets.last, isEmpty);
  });
}

void _expectPresetsEqual(MetronomePreset actual, MetronomePreset expected) {
  expect(actual.id, expected.id);
  expect(actual.name, expected.name);
  expect(actual.bpm, expected.bpm);
  expect(actual.beatsPerBar, expected.beatsPerBar);
  expect(actual.beatUnit, expected.beatUnit);
  expect(actual.subdivision, expected.subdivision);
  expect(actual.clickSoundSet, expected.clickSoundSet);
  expect(actual.masterVolumePercent, expected.masterVolumePercent);
  expect(actual.accentPattern, expected.accentPattern);

  final actualIntervalSettings = actual.intervalSettings;
  final expectedIntervalSettings = expected.intervalSettings;
  expect(actualIntervalSettings == null, expectedIntervalSettings == null);
  if (actualIntervalSettings == null || expectedIntervalSettings == null) {
    return;
  }

  expect(actualIntervalSettings.interval, expectedIntervalSettings.interval);
  expect(
    actualIntervalSettings.bpmStepEnabled,
    expectedIntervalSettings.bpmStepEnabled,
  );
  expect(actualIntervalSettings.bpmStep, expectedIntervalSettings.bpmStep);
  expect(
    actualIntervalSettings.maxDuration,
    expectedIntervalSettings.maxDuration,
  );
}
