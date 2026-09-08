import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/db/app_database.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/domain/metronome_preset.dart';
import 'package:tempodeck/core/domain/subdivision.dart';
import 'package:tempodeck/core/repositories/drift_preset_repository.dart';

void main() {
  late AppDatabase database;
  late DriftPresetRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftPresetRepository(presetDao: database.presetDao);
  });

  tearDown(() async {
    await database.close();
  });

  test('persists and reloads presets through the repository contract',
      () async {
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
    );

    await repository.savePreset(preset);

    final loadedPreset = await repository.getPresetById(preset.id);
    final allPresets = await repository.getAllPresets();

    expect(loadedPreset, isNotNull);
    expect(loadedPreset!.id, preset.id);
    expect(loadedPreset.name, preset.name);
    expect(loadedPreset.clickSoundSet, preset.clickSoundSet);
    expect(loadedPreset.masterVolumePercent, preset.masterVolumePercent);
    expect(allPresets.map((item) => item.id).toList(), ['preset-1']);
  });

  test('watchAllPresets emits repository updates', () async {
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
    final subscription =
        repository.watchAllPresets().listen(emittedPresets.add);

    await Future<void>.delayed(Duration.zero);
    await repository.savePreset(preset);
    await Future<void>.delayed(Duration.zero);
    await repository.deletePreset(preset.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emittedPresets.first, isEmpty);
    expect(emittedPresets[1].map((item) => item.id).toList(), ['preset-1']);
    expect(emittedPresets.last, isEmpty);
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
        repository.watchPresetById(preset.id).listen(emittedPresets.add);

    await Future<void>.delayed(Duration.zero);
    await repository.savePreset(preset);
    await Future<void>.delayed(Duration.zero);
    await repository.deletePreset(preset.id);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emittedPresets.first, isNull);
    expect(emittedPresets[1], isNotNull);
    expect(emittedPresets[1]!.id, preset.id);
    expect(emittedPresets.last, isNull);
  });

  test('savePreset rejects invalid preset data before writing', () {
    const invalidPreset = MetronomePreset(
      id: 'preset-1',
      name: 'Arena Intro',
      bpm: 128,
      beatsPerBar: 2,
      beatUnit: 4,
      subdivision: Subdivision.one,
      accentPattern: [
        AccentLevel.high,
        AccentLevel.normal,
        AccentLevel.low,
      ],
    );

    expect(
      () => repository.savePreset(invalidPreset),
      throwsA(isA<ArgumentError>()),
    );
  });
}
