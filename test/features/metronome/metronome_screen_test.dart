import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tempodeck/core/audio/audio_limiter_settings.dart';
import 'package:tempodeck/core/audio/click_sound_set_assets.dart';
import 'package:tempodeck/core/audio/i_audio_engine.dart';
import 'package:tempodeck/core/audio/text_to_speech_client.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/audio_cue.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/domain/metronome_preset.dart';
import 'package:tempodeck/core/domain/subdivision.dart';
import 'package:tempodeck/core/providers/repository_providers.dart';
import 'package:tempodeck/core/providers/service_providers.dart';
import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/repositories/preset_repository.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_animated_background.dart';
import 'package:tempodeck/features/metronome/metronome_screen.dart';
import 'package:tempodeck/features/metronome/metronome_screen_controller.dart';

void main() {
  setUpAll(() {
    TDAnimatedBackground.disableAnimations = true;
  });

  tearDownAll(() {
    TDAnimatedBackground.disableAnimations = false;
  });

  testWidgets('renders the metronome controls and updates bpm', (tester) async {
    final container = _createTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _MetronomeScreenHarness(),
      ),
    );

    expect(find.text('Metronome'), findsOneWidget);
    // BPM display shows number and label separately.
    expect(find.text('120'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('Tap 4x to detect tempo'), findsOneWidget);
    // Rhythm section is expanded by default.
    expect(find.text('Accent Pattern'), findsOneWidget);

    // TDSlider wraps a Slider – find the inner widget.
    final slider = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(const Key('bpm-slider')),
        matching: find.byType(Slider),
      ),
    );
    slider.onChanged?.call(132);
    await tester.pump();

    expect(find.text('132'), findsOneWidget);
  });

  testWidgets('bpm increment and decrement buttons adjust by one',
      (tester) async {
    final container = _createTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _MetronomeScreenHarness(),
      ),
    );

    expect(find.text('120'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bpm-increment')));
    await tester.pump();
    expect(find.text('121'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bpm-decrement')));
    await tester.pump();
    expect(find.text('120'), findsOneWidget);
  });

  testWidgets('tap tempo shows how many taps are left', (tester) async {
    final container = _createTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _MetronomeScreenHarness(),
      ),
    );

    expect(find.text('Tap 4x to detect tempo'), findsOneWidget);

    await tester.tap(find.text('TAP'));
    await tester.pump();

    expect(find.text('3 taps left'), findsOneWidget);

    final scheduler = container.read(tapTempoResetSchedulerProvider)
        as _TestTapTempoResetScheduler;
    scheduler.fire();
    await tester.pump();

    expect(find.text('Tap 4x to detect tempo'), findsOneWidget);
  });

  testWidgets('updates subdivision selection through the segmented control',
      (tester) async {
    final container = _createTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _MetronomeScreenHarness(),
      ),
    );

    // Rhythm section is expanded by default so subdivision dropdown is visible.
    // Tap the dropdown to open the options sheet, then select the option.
    await tester.tap(find.text('Subdivision'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+3'));
    await tester.pumpAndSettle();

    expect(
      container.read(metronomeScreenControllerProvider).subdivision,
      Subdivision.four,
    );
  });

  testWidgets('shows interval controls when interval mode is enabled',
      (tester) async {
    final container = _createTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _MetronomeScreenHarness(),
      ),
    );
    await tester.pumpAndSettle();

    // Interval section is collapsed – expand it.
    await _expandSection(tester, 'INTERVAL MODE');

    expect(find.text('Enable Interval Mode'), findsOneWidget);
    expect(find.text('Interval Duration'), findsNothing);

    container
        .read(metronomeScreenControllerProvider.notifier)
        .setIntervalModeEnabled(true);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Interval Duration'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Interval Duration'), findsOneWidget);
    expect(find.text('BPM Step'), findsOneWidget);
    expect(find.text('Max Duration'), findsOneWidget);
  });

  testWidgets('shows the interval preview when interval mode is enabled',
      (tester) async {
    final container = _createTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _MetronomeScreenHarness(),
      ),
    );

    // Expand interval section then enable interval mode.
    await _expandSection(tester, 'INTERVAL MODE');

    container
        .read(metronomeScreenControllerProvider.notifier)
        .setIntervalModeEnabled(true);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Interval Preview'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Interval Preview'), findsOneWidget);
    expect(find.text('Interval 1'), findsOneWidget);
  });

  testWidgets('renders saved presets and preset actions through the screen',
      (tester) async {
    const repository = _FakePresetRepository(
      presets: [
        MetronomePreset(
          id: 'preset-1',
          name: 'Warmup',
          bpm: 88,
          beatsPerBar: 3,
          beatUnit: 4,
          subdivision: Subdivision.two,
          accentPattern: [
            AccentLevel.high,
            AccentLevel.normal,
            AccentLevel.low,
          ],
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.mobile),
        presetRepositoryProvider.overrideWithValue(repository),
        audioEngineProvider.overrideWithValue(_FakeAudioEngine()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _MetronomeScreenHarness(),
      ),
    );
    await tester.pumpAndSettle();

    // Presets section is collapsed – expand it.
    await _expandSection(tester, 'PRESETS');

    expect(find.text('Warmup'), findsOneWidget);
    expect(find.text('88 BPM \u00B7 3/4 \u00B7 2 pulses'), findsOneWidget);
    expect(find.text('Save Current as Preset'), findsOneWidget);
  });
}

/// Scrolls to and taps a [TDSectionHeader] to expand it.
///
/// The [uppercaseLabel] must be the all-caps label shown by TDSectionHeader.
Future<void> _expandSection(
  WidgetTester tester,
  String uppercaseLabel,
) async {
  final textFinder = find.text(uppercaseLabel);
  await tester.scrollUntilVisible(textFinder, 200);
  await tester.pumpAndSettle();
  await tester.tap(textFinder);
  await tester.pumpAndSettle();
}

ProviderContainer _createTestContainer({
  PresetRepository presetRepository = const _FakePresetRepository(),
  IAudioEngine? audioEngine,
}) {
  return ProviderContainer(
    overrides: [
      appVariantProvider.overrideWithValue(AppVariant.mobile),
      presetRepositoryProvider.overrideWithValue(presetRepository),
      audioEngineProvider.overrideWithValue(audioEngine ?? _FakeAudioEngine()),
      tapTempoResetSchedulerProvider.overrideWithValue(
        _TestTapTempoResetScheduler(),
      ),
    ],
  );
}

class _MetronomeScreenHarness extends StatelessWidget {
  const _MetronomeScreenHarness();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: const MetronomeScreen(),
    );
  }
}

class _FakePresetRepository implements PresetRepository {
  const _FakePresetRepository({this.presets = const []});

  final List<MetronomePreset> presets;

  @override
  Future<void> deletePreset(String presetId) async {}

  @override
  Future<List<MetronomePreset>> getAllPresets() async => presets;

  @override
  Future<MetronomePreset?> getPresetById(String presetId) async => null;

  @override
  Future<void> savePreset(MetronomePreset preset) async {}

  @override
  Stream<List<MetronomePreset>> watchAllPresets() async* {
    yield presets;
  }

  @override
  Stream<MetronomePreset?> watchPresetById(String presetId) async* {
    yield null;
  }
}

class _FakeAudioEngine implements IAudioEngine {
  _FakeAudioEngine();

  final List<ClickSoundSet> loadedSets = [];
  final List<ClickSoundSet> selectedSets = [];
  final List<double> masterVolumes = [];

  @override
  bool get isInitialized => true;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadClickSoundSet(ClickSoundSet set) async {
    loadedSets.add(set);
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
  }) async => const PreparedLinkedAudioHandle('metronome-test');

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

class _TestTapTempoResetScheduler implements TapTempoResetScheduler {
  _TestTapTempoResetTask? _task;

  @override
  TapTempoResetTask schedule(Duration duration, void Function() callback) {
    _task = _TestTapTempoResetTask(callback);
    return _task!;
  }

  void fire() {
    _task?.fire();
  }
}

class _TestTapTempoResetTask implements TapTempoResetTask {
  _TestTapTempoResetTask(this._callback);

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
