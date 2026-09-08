import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tempodeck/core/audio/audio_limiter_settings.dart';
import 'package:tempodeck/core/audio/tap_tempo_detector.dart';
import 'package:tempodeck/core/audio/click_sound_set_assets.dart';
import 'package:tempodeck/core/audio/i_audio_engine.dart';
import 'package:tempodeck/core/audio/text_to_speech_client.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/domain/interval_settings.dart';
import 'package:tempodeck/core/domain/metronome_preset.dart';
import 'package:tempodeck/core/domain/subdivision.dart';
import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/providers/service_providers.dart';
import 'package:tempodeck/core/repositories/metronome_settings_repository.dart';
import 'package:tempodeck/core/repositories/preset_repository.dart';
import 'package:tempodeck/features/metronome/metronome_screen_controller.dart';
import 'package:tempodeck/features/metronome/metronome_screen_state.dart';

void main() {
  test('initializes with the default metronome state', () {
    final container = _createContainer();
    addTearDown(container.dispose);

    final state = container.read(metronomeScreenControllerProvider);

    expect(state.bpm, 120);
    expect(state.beatsPerBar, 4);
    expect(state.beatUnit, 4);
    expect(state.subdivision, Subdivision.one);
    expect(
      state.masterVolumePercent,
      MetronomeScreenState.defaultMasterVolumePercent,
    );
    expect(state.tapTempoTapCount, 0);
    expect(
      state.accentPattern,
      [
        AccentLevel.high,
        AccentLevel.normal,
        AccentLevel.normal,
        AccentLevel.normal,
      ],
    );
  });

  test('resizes the accent pattern when beats per bar changes', () {
    final container = _createContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    controller.setBeatsPerBar(6);
    final expandedState = container.read(metronomeScreenControllerProvider);

    expect(expandedState.beatsPerBar, 6);
    expect(expandedState.accentPattern.length, 6);
    expect(expandedState.accentPattern[4], AccentLevel.normal);
    expect(expandedState.accentPattern[5], AccentLevel.normal);

    controller.setBeatsPerBar(3);
    final shrunkState = container.read(metronomeScreenControllerProvider);

    expect(shrunkState.beatsPerBar, 3);
    expect(
      shrunkState.accentPattern,
      [
        AccentLevel.high,
        AccentLevel.normal,
        AccentLevel.normal,
      ],
    );
  });

  test('enables interval mode with default settings', () {
    final container = _createContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    controller.setIntervalModeEnabled(true);

    expect(
      container.read(metronomeScreenControllerProvider).intervalSettings,
      const IntervalSettings(interval: Duration(minutes: 1)),
    );
  });

  test('updates interval duration and max duration settings', () {
    final container = _createContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    controller.setIntervalModeEnabled(true);
    controller.setIntervalDurationMinutes(2);
    controller.setIntervalDurationSeconds(30);
    controller.setMaximumDurationEnabled(true);
    controller.setMaximumDurationMinutes(12);
    controller.setMaximumDurationSeconds(15);

    final intervalSettings =
        container.read(metronomeScreenControllerProvider).intervalSettings!;
    expect(intervalSettings.interval, const Duration(minutes: 2, seconds: 30));
    expect(
      intervalSettings.maxDuration,
      const Duration(minutes: 12, seconds: 15),
    );
  });

  test('updates bpm step settings inside interval mode', () {
    final container = _createContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    controller.setIntervalModeEnabled(true);
    controller.setBpmStepEnabled(true);
    controller.incrementBpmStep();
    controller.decrementBpmStep();

    final intervalSettings =
        container.read(metronomeScreenControllerProvider).intervalSettings!;
    expect(intervalSettings.bpmStepEnabled, isTrue);
    expect(intervalSettings.bpmStep, 5);
  });

  test('tracks tap tempo progress and resets it after silence', () {
    final clock = _FakeTapTempoClock(
      DateTime(2026, 3, 13, 9, 0, 0),
    );
    final detector = TapTempoDetector(clock: clock);
    final scheduler = _FakeTapTempoResetScheduler();
    final container = _createContainer(
      overrides: [
        tapTempoDetectorProvider.overrideWithValue(detector),
        tapTempoResetSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    expect(controller.tapTempo(), isNull);
    expect(
      container.read(metronomeScreenControllerProvider).tapTempoTapCount,
      1,
    );

    scheduler.fire();

    expect(
      container.read(metronomeScreenControllerProvider).tapTempoTapCount,
      0,
    );
    expect(detector.tapCount, 0);
  });

  test('setBpm clears tap tempo progress in a single state update', () {
    final clock = _FakeTapTempoClock(
      DateTime(2026, 3, 13, 9, 0, 0),
    );
    final detector = TapTempoDetector(clock: clock);
    final scheduler = _FakeTapTempoResetScheduler();
    final container = _createContainer(
      overrides: [
        tapTempoDetectorProvider.overrideWithValue(detector),
        tapTempoResetSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    controller.tapTempo();

    final updates = <MetronomeScreenState>[];
    final subscription = container.listen(
      metronomeScreenControllerProvider,
      (_, next) => updates.add(next),
    );
    addTearDown(subscription.close);

    controller.setBpm(132);

    expect(updates, hasLength(1));
    expect(updates.single.bpm, 132);
    expect(updates.single.tapTempoTapCount, 0);
  });

  test('ignores interval updates when interval mode is disabled', () {
    final container = _createContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    controller.setIntervalDurationMinutes(5);
    controller.setIntervalDurationSeconds(45);
    controller.setBpmStepEnabled(true);
    controller.incrementBpmStep();
    controller.decrementBpmStep();
    controller.setMaximumDurationEnabled(true);
    controller.setMaximumDurationMinutes(20);
    controller.setMaximumDurationSeconds(30);

    expect(
      container.read(metronomeScreenControllerProvider).intervalSettings,
      isNull,
    );
  });

  test('applies a preset to the current metronome state', () {
    final container = _createContainer(
      overrides: [
        presetRepositoryProvider.overrideWithValue(_MemoryPresetRepository()),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    const preset = MetronomePreset(
      id: 'preset-1',
      name: 'Practice',
      bpm: 96,
      beatsPerBar: 3,
      beatUnit: 8,
      subdivision: Subdivision.two,
      clickSoundSet: ClickSoundSet.mightyKit,
      masterVolumePercent: 64,
      accentPattern: [
        AccentLevel.high,
        AccentLevel.low,
        AccentLevel.normal,
      ],
      intervalSettings: IntervalSettings(interval: Duration(minutes: 2)),
    );

    controller.applyPreset(preset);

    final state = container.read(metronomeScreenControllerProvider);
    expect(state.bpm, 96);
    expect(state.beatsPerBar, 3);
    expect(state.beatUnit, 8);
    expect(state.subdivision, Subdivision.two);
    expect(state.clickSoundSet, ClickSoundSet.mightyKit);
    expect(state.masterVolumePercent, 64);
    expect(state.accentPattern, preset.accentPattern);
    expect(state.intervalSettings, preset.intervalSettings);
    expect(state.appliedPresetId, 'preset-1');
  });

  test('loads and selects a click sound set through the audio engine',
      () async {
    final audioEngine = _RecordingAudioEngine();
    final container = _createContainer(
      overrides: [
        presetRepositoryProvider.overrideWithValue(_MemoryPresetRepository()),
        audioEngineProvider.overrideWithValue(audioEngine),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    await controller.setClickSoundSet(ClickSoundSet.hype);

    expect(audioEngine.loadedSets, [ClickSoundSet.hype]);
    expect(audioEngine.selectedSets, [ClickSoundSet.hype]);
    expect(
      container.read(metronomeScreenControllerProvider).clickSoundSet,
      ClickSoundSet.hype,
    );
  });

  test('updates master volume through the audio engine', () {
    final audioEngine = _RecordingAudioEngine();
    final container = _createContainer(
      overrides: [
        presetRepositoryProvider.overrideWithValue(_MemoryPresetRepository()),
        audioEngineProvider.overrideWithValue(audioEngine),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    controller.setMasterVolumePercent(72);

    expect(audioEngine.masterVolumes, [0.72]);
    expect(
      container.read(metronomeScreenControllerProvider).masterVolumePercent,
      72,
    );
  });

  test(
      'keeps the latest click sound selection when requests resolve out of order',
      () async {
    final audioEngine = _RecordingAudioEngine();
    final firstLoad = Completer<void>();
    final secondLoad = Completer<void>();
    audioEngine.loadCompleters[ClickSoundSet.hype] = firstLoad;
    audioEngine.loadCompleters[ClickSoundSet.metalKit] = secondLoad;
    final container = _createContainer(
      overrides: [
        presetRepositoryProvider.overrideWithValue(_MemoryPresetRepository()),
        audioEngineProvider.overrideWithValue(audioEngine),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    final firstRequest = controller.setClickSoundSet(ClickSoundSet.hype);
    final secondRequest = controller.setClickSoundSet(ClickSoundSet.metalKit);

    secondLoad.complete();
    await secondRequest;
    firstLoad.complete();
    await firstRequest;

    expect(audioEngine.selectedSets, [ClickSoundSet.metalKit]);
    expect(
      container.read(metronomeScreenControllerProvider).clickSoundSet,
      ClickSoundSet.metalKit,
    );
  });

  test('keeps the current click sound when audio loading fails', () async {
    final audioEngine = _RecordingAudioEngine();
    audioEngine.failingSets.add(ClickSoundSet.hype);
    final container = _createContainer(
      overrides: [
        presetRepositoryProvider.overrideWithValue(_MemoryPresetRepository()),
        audioEngineProvider.overrideWithValue(audioEngine),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    await controller.setClickSoundSet(ClickSoundSet.hype);

    expect(audioEngine.selectedSets, isEmpty);
    expect(
      container.read(metronomeScreenControllerProvider).clickSoundSet,
      ClickSoundSet.tock,
    );
  });

  test('saves the current metronome state as a preset', () async {
    final repository = _MemoryPresetRepository();
    final container = _createContainer(
      overrides: [
        presetRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    controller.setBpm(132);
    controller.setBeatsPerBar(5);
    controller.setSubdivision(Subdivision.three);
    await controller.saveCurrentPreset('Stage Tempo');

    expect(repository.savedPresets, hasLength(1));
    final savedPreset = repository.savedPresets.single;
    expect(savedPreset.name, 'Stage Tempo');
    expect(savedPreset.bpm, 132);
    expect(savedPreset.beatsPerBar, 5);
    expect(savedPreset.subdivision, Subdivision.three);
    expect(
      container.read(metronomeScreenControllerProvider).appliedPresetId,
      savedPreset.id,
    );
  });

  test('saving current state creates a new preset even when one is applied',
      () async {
    final repository = _MemoryPresetRepository();
    final container = _createContainer(
      overrides: [
        presetRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    controller.applyPreset(
      const MetronomePreset(
        id: 'preset-1',
        name: 'Practice',
        bpm: 96,
        beatsPerBar: 4,
        beatUnit: 4,
        subdivision: Subdivision.one,
        clickSoundSet: ClickSoundSet.blip,
        masterVolumePercent: 55,
        accentPattern: [
          AccentLevel.high,
          AccentLevel.normal,
          AccentLevel.normal,
          AccentLevel.normal,
        ],
      ),
    );
    controller.setBpm(132);

    await controller.saveCurrentPreset('Stage Tempo');

    expect(repository.savedPresets, hasLength(1));
    expect(repository.savedPresets.single.id, isNot('preset-1'));
    expect(repository.savedPresets.single.name, 'Stage Tempo');
    expect(repository.savedPresets.single.bpm, 132);
    expect(repository.savedPresets.single.clickSoundSet, ClickSoundSet.blip);
    expect(repository.savedPresets.single.masterVolumePercent, 55);
    expect(
      container.read(metronomeScreenControllerProvider).appliedPresetId,
      repository.savedPresets.single.id,
    );
  });

  test('renames a preset while preserving all other fields', () async {
    final repository = _MemoryPresetRepository();
    final container = _createContainer(
      overrides: [
        presetRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    const preset = MetronomePreset(
      id: 'preset-1',
      name: 'Practice',
      bpm: 96,
      beatsPerBar: 3,
      beatUnit: 8,
      subdivision: Subdivision.two,
      clickSoundSet: ClickSoundSet.mightyKit,
      masterVolumePercent: 80,
      accentPattern: [
        AccentLevel.high,
        AccentLevel.low,
        AccentLevel.normal,
      ],
      intervalSettings: IntervalSettings(interval: Duration(minutes: 2)),
    );

    await controller.renamePreset(preset, 'Stage Tempo');

    expect(repository.savedPresets, hasLength(1));
    final renamedPreset = repository.savedPresets.single;
    expect(renamedPreset.id, preset.id);
    expect(renamedPreset.name, 'Stage Tempo');
    expect(renamedPreset.bpm, preset.bpm);
    expect(renamedPreset.beatsPerBar, preset.beatsPerBar);
    expect(renamedPreset.beatUnit, preset.beatUnit);
    expect(renamedPreset.subdivision, preset.subdivision);
    expect(renamedPreset.clickSoundSet, preset.clickSoundSet);
    expect(
      renamedPreset.masterVolumePercent,
      preset.masterVolumePercent,
    );
    expect(renamedPreset.accentPattern, preset.accentPattern);
    expect(renamedPreset.intervalSettings, preset.intervalSettings);
  });

  test('deleting the applied preset clears the applied preset id', () async {
    final repository = _MemoryPresetRepository();
    final container = _createContainer(
      overrides: [
        presetRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      metronomeScreenControllerProvider.notifier,
    );

    controller.applyPreset(
      const MetronomePreset(
        id: 'preset-1',
        name: 'Practice',
        bpm: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        subdivision: Subdivision.one,
        accentPattern: [
          AccentLevel.high,
          AccentLevel.normal,
          AccentLevel.normal,
          AccentLevel.normal,
        ],
      ),
    );

    await controller.deletePreset('preset-1');

    expect(repository.deletedPresetIds, ['preset-1']);
    expect(
      container.read(metronomeScreenControllerProvider).appliedPresetId,
      isNull,
    );
  });

  group('persistence', () {
    test('persists state on every setter call', () async {
      final settingsRepo = _FakeMetronomeSettingsRepository();
      final container = _createContainer(
        overrides: [
          metronomeSettingsRepositoryProvider
              .overrideWithValue(settingsRepo),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        metronomeScreenControllerProvider.notifier,
      );

      controller.setBpm(140);
      controller.setBeatsPerBar(6);
      controller.setSubdivision(Subdivision.two);

      // Let fire-and-forget futures complete.
      await Future<void>.delayed(Duration.zero);

      final persisted = settingsRepo.lastSaved;
      expect(persisted, isNotNull);
      expect(persisted!.bpm, 140);
      expect(persisted.beatsPerBar, 6);
      expect(persisted.subdivision, Subdivision.two);
    });

    test('loadPersistedSettings restores saved state', () async {
      final settingsRepo = _FakeMetronomeSettingsRepository();
      settingsRepo.storedState = MetronomeScreenState(
        bpm: 96,
        beatsPerBar: 3,
        beatUnit: 8,
        subdivision: Subdivision.three,
        clickSoundSet: ClickSoundSet.blip,
        masterVolumePercent: 65,
        tapTempoTapCount: 0,
        accentPattern: const [
          AccentLevel.high,
          AccentLevel.low,
          AccentLevel.normal,
        ],
      );

      final container = _createContainer(
        overrides: [
          metronomeSettingsRepositoryProvider
              .overrideWithValue(settingsRepo),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(metronomeScreenControllerProvider.notifier)
          .loadPersistedSettings();

      final state = container.read(metronomeScreenControllerProvider);
      expect(state.bpm, 96);
      expect(state.beatsPerBar, 3);
      expect(state.beatUnit, 8);
      expect(state.subdivision, Subdivision.three);
      expect(state.clickSoundSet, ClickSoundSet.blip);
      expect(state.masterVolumePercent, 65);
    });

    test('loadPersistedSettings falls back to defaults on failure', () async {
      final settingsRepo = _FakeMetronomeSettingsRepository();
      settingsRepo.shouldFailOnLoad = true;

      final container = _createContainer(
        overrides: [
          metronomeSettingsRepositoryProvider
              .overrideWithValue(settingsRepo),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(metronomeScreenControllerProvider.notifier)
          .loadPersistedSettings();

      final state = container.read(metronomeScreenControllerProvider);
      expect(state.bpm, 120);
      expect(state.beatsPerBar, 4);
    });

    test('rapid edits only persist final state', () async {
      final settingsRepo = _FakeMetronomeSettingsRepository();
      final container = _createContainer(
        overrides: [
          metronomeSettingsRepositoryProvider
              .overrideWithValue(settingsRepo),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        metronomeScreenControllerProvider.notifier,
      );

      for (var bpm = 100; bpm <= 120; bpm++) {
        controller.setBpm(bpm);
      }

      // Let all chained futures complete.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(settingsRepo.lastSaved?.bpm, 120);
    });
  });
}

ProviderContainer _createContainer({
  List<Override> overrides = const [],
}) {
  return ProviderContainer(
    overrides: [
      appVariantProvider.overrideWithValue(AppVariant.desktop),
      metronomeSettingsRepositoryProvider
          .overrideWithValue(_FakeMetronomeSettingsRepository()),
      ...overrides,
    ],
  );
}

class _FakeMetronomeSettingsRepository implements MetronomeSettingsRepository {
  MetronomeScreenState? storedState;
  MetronomeScreenState? lastSaved;
  bool shouldFailOnLoad = false;

  @override
  Future<MetronomeScreenState> load() async {
    if (shouldFailOnLoad) {
      throw Exception('Simulated load failure');
    }
    return storedState ?? MetronomeScreenState.initial();
  }

  @override
  Future<void> save(MetronomeScreenState state) async {
    lastSaved = state;
  }
}

class _MemoryPresetRepository implements PresetRepository {
  final List<MetronomePreset> savedPresets = [];
  final List<String> deletedPresetIds = [];

  @override
  Future<void> deletePreset(String presetId) async {
    deletedPresetIds.add(presetId);
    savedPresets.removeWhere((preset) => preset.id == presetId);
  }

  @override
  Future<List<MetronomePreset>> getAllPresets() async => savedPresets;

  @override
  Future<MetronomePreset?> getPresetById(String presetId) async {
    for (final preset in savedPresets) {
      if (preset.id == presetId) {
        return preset;
      }
    }

    return null;
  }

  @override
  Future<void> savePreset(MetronomePreset preset) async {
    await deletePreset(preset.id);
    savedPresets.add(preset);
  }

  @override
  Stream<List<MetronomePreset>> watchAllPresets() async* {
    yield List<MetronomePreset>.unmodifiable(savedPresets);
  }

  @override
  Stream<MetronomePreset?> watchPresetById(String presetId) async* {
    yield await getPresetById(presetId);
  }
}

class _RecordingAudioEngine implements IAudioEngine {
  final List<ClickSoundSet> loadedSets = [];
  final List<ClickSoundSet> selectedSets = [];
  final List<double> masterVolumes = [];
  final Map<ClickSoundSet, Completer<void>> loadCompleters = {};
  final Set<ClickSoundSet> failingSets = {};

  @override
  bool get isInitialized => true;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadClickSoundSet(ClickSoundSet set) async {
    loadedSets.add(set);
    final completer = loadCompleters[set];
    if (completer != null) {
      await completer.future;
    }
    if (failingSets.contains(set)) {
      throw StateError('Failed to load $set.');
    }
  }

  @override
  Future<void> playCue(AudioCue cue) async {}

  @override
  Future<void> preloadLinkedAudio(String filePath) async {}

  @override
  Future<PreparedLinkedAudioHandle> prepareLinkedAudioPlayback(
    String filePath, {
    required Duration offset,
    required double volume,
  }) async => const PreparedLinkedAudioHandle('metronome-controller-test');

  @override
  Future<void> playPreparedLinkedAudio(PreparedLinkedAudioHandle handle) async {}

  @override
  Future<void> releasePreparedLinkedAudio(
    PreparedLinkedAudioHandle handle,
  ) async {}

  @override
  void playClick(AccentLevel accent) {}

  @override
  void playSubdivisionClick() {}

  @override
  Future<void> playLinkedAudio(
    String filePath, {
    required Duration offset,
    required double volume,
  }) async {}

  @override
  void selectClickSoundSet(ClickSoundSet set) {
    selectedSets.add(set);
  }

  @override
  void setClickChannelVolume(ClickSoundVariant variant, double volume) {}

  @override
  void setLimiter(AudioLimiterSettings settings) {}

  @override
  void setMasterVolume(double volume) {
    masterVolumes.add(volume);
  }

  @override
  Future<List<TextToSpeechVoice>> getAvailableVoices() async => [];

  @override
  Future<void> speakCue(String text, {String? voiceIdentifier}) async {}

  @override
  Future<void> stop() async {}
}

class _FakeTapTempoClock implements TapTempoClock {
  _FakeTapTempoClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

class _FakeTapTempoResetScheduler implements TapTempoResetScheduler {
  _FakeTapTempoResetTask? _task;

  @override
  TapTempoResetTask schedule(Duration duration, void Function() callback) {
    _task = _FakeTapTempoResetTask(callback);
    return _task!;
  }

  void fire() {
    _task?.fire();
  }
}

class _FakeTapTempoResetTask implements TapTempoResetTask {
  _FakeTapTempoResetTask(this._callback);

  final void Function() _callback;
  bool _isCancelled = false;

  @override
  void cancel() {
    _isCancelled = true;
  }

  void fire() {
    if (_isCancelled) {
      return;
    }
    _callback();
  }
}
