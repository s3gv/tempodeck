import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/audio_engine_config.dart';
import 'package:tempodeck/core/audio/metronome_click_engine.dart';
import 'package:tempodeck/core/audio/soloud_audio_engine.dart';
import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/domain/click_sound_set.dart';
import 'package:tempodeck/core/domain/subdivision.dart';
import 'package:tempodeck/features/live/live_metronome_transport.dart';

import '../../core/audio/audio_playback_session_test_support.dart';
import '../../core/audio/metronome_click_engine_test.dart';
import '../../core/audio/soloud_audio_engine_test.dart';

/// Contract tests for [AudioEngineLiveMetronomeTransport] proving the real
/// transport -> click engine -> audio engine chain works end-to-end.
///
/// Uses a real [SoLoudAudioEngine] with [FakeSoLoudClient] and a real
/// [MetronomeClickEngine] with [FakeMetronomeScheduler]/[FakeMetronomeRunClock]
/// so we can drive the scheduler manually.
void main() {
  group('AudioEngineLiveMetronomeTransport contract', () {
    late FakeSoLoudClient client;
    late FakeTextToSpeechClient textToSpeechClient;
    late FakeAudioPlaybackSession playbackSession;
    late SoLoudAudioEngine audioEngine;
    late FakeMetronomeScheduler scheduler;
    late FakeMetronomeRunClock runClock;
    late MetronomeClickEngine clickEngine;
    late AudioEngineLiveMetronomeTransport transport;

    setUp(() {
      client = FakeSoLoudClient();
      textToSpeechClient = FakeTextToSpeechClient();
      playbackSession = FakeAudioPlaybackSession();
      audioEngine = SoLoudAudioEngine(
        soLoudClient: client,
        textToSpeechClient: textToSpeechClient,
        playbackSession: playbackSession,
        config: const AudioEngineConfig(),
      );

      scheduler = FakeMetronomeScheduler();
      runClock = FakeMetronomeRunClock();
      clickEngine = MetronomeClickEngine(
        output: _AudioEngineClickOutput(audioEngine),
        scheduler: scheduler,
        runClock: runClock,
      );

      transport = AudioEngineLiveMetronomeTransport(
        audioEngine: audioEngine,
        clickEngine: clickEngine,
      );
    });

    group('start transport -> verify clicks played through engine', () {
      test('start plays the first click immediately via the audio engine',
          () async {
        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [AccentLevel.high],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );

        // The first beat is emitted synchronously on start.
        expect(
          client.playedAssetPaths,
          contains('assets/audio/click_kits/tock/tock_accent_high.wav'),
        );
        expect(transport.isRunning, isTrue);
      });

      test('subsequent beats play clicks via the audio engine', () async {
        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [AccentLevel.high, AccentLevel.low],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );

        final beatDuration = const Duration(milliseconds: 500);
        runClock.elapsedValue = beatDuration;
        scheduler.runNext(); // beat 2

        expect(
          client.playedAssetPaths,
          [
            'assets/audio/click_kits/tock/tock_accent_high.wav',
            'assets/audio/click_kits/tock/tock_accent_low.wav',
          ],
        );
      });

      test('start applies the requested master volume', () async {
        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [AccentLevel.high],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 65,
          ),
          onTick: (_) {},
        );

        expect(client.globalVolume, 0.65);
      });

      test('start loads and selects the requested click sound set', () async {
        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [AccentLevel.high],
            clickSoundSet: ClickSoundSet.hype,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );

        expect(
          client.playedAssetPaths,
          contains('assets/audio/click_kits/hype/hype_accent_high.wav'),
        );
      });
    });

    group('stop transport -> verify engine gets stop calls', () {
      test('stop halts the click engine and transport reports not running',
          () async {
        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [AccentLevel.high],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );

        transport.stop();

        expect(transport.isRunning, isFalse);
        expect(clickEngine.isRunning, isFalse);
      });

      test('stopAllAudio stops the click engine and the audio engine',
          () async {
        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [AccentLevel.high],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );

        await transport.stopAllAudio();

        expect(transport.isRunning, isFalse);
        // Audio engine stop is called which clears active playback.
        expect(client.stoppedAssetPaths, isNotEmpty);
        expect(textToSpeechClient.stopCallCount, 1);
      });
    });

    group('config changes propagate to click engine', () {
      test('BPM affects the scheduled beat interval', () async {
        // 120 BPM in 4/4 => 500ms per quarter note.
        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );

        expect(
          scheduler.scheduledDelays.last,
          const Duration(milliseconds: 500),
        );
      });

      test('time signature affects the scheduled beat interval', () async {
        // 120 BPM in 3/8 => 250ms per eighth note.
        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 3,
            beatUnit: 8,
            subdivision: Subdivision.one,
            accentPattern: [],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );

        expect(
          scheduler.scheduledDelays.last,
          const Duration(milliseconds: 250),
        );
      });

      test('subdivision affects the scheduled pulse interval', () async {
        // 120 BPM in 4/4 with subdivision 4 => 500ms / 4 = 125ms per pulse.
        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.four,
            accentPattern: [],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );

        expect(
          scheduler.scheduledDelays.last,
          const Duration(milliseconds: 125),
        );
      });
    });

    group('beatmap sequence advances configs correctly', () {
      test('transitions from 4/4 at 120 BPM to 3/8 at 90 BPM on bar 2',
          () async {
        final ticks = <MetronomeBeatTick>[];
        const bar1Config = MetronomeClickEngineConfig(
          bpm: 120,
          beatsPerBar: 4,
          beatUnit: 4,
          subdivision: Subdivision.one,
          accentPattern: [AccentLevel.high],
        );
        const bar2Config = MetronomeClickEngineConfig(
          bpm: 90,
          beatsPerBar: 3,
          beatUnit: 8,
          subdivision: Subdivision.one,
          accentPattern: [AccentLevel.low],
        );

        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [AccentLevel.high],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: ticks.add,
          beatmapSequence: const [bar1Config, bar2Config],
        );

        // Advance through bar 1 (4 beats).
        const bar1Interval = Duration(milliseconds: 500);
        for (var i = 1; i <= 3; i++) {
          runClock.elapsedValue = bar1Interval * i;
          scheduler.runNext();
        }

        // Bar 1 complete, beat 1 of bar 2 scheduled at bar 1 timing.
        runClock.elapsedValue = bar1Interval * 4;
        scheduler.runNext();

        final bar2Beat1 = ticks.last;
        expect(bar2Beat1.barIndex, 2);
        expect(bar2Beat1.beatIndex, 1);
        expect(bar2Beat1.bpm, 90);
        expect(bar2Beat1.beatsPerBar, 3);
        expect(bar2Beat1.beatUnit, 8);
        expect(bar2Beat1.accentLevel, AccentLevel.low);
      });
    });

    group('onTick callback fires with correct bar/beat/pulse data', () {
      test('fires correct tick data for every beat in bar 1', () async {
        final ticks = <MetronomeBeatTick>[];

        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [AccentLevel.high, AccentLevel.low],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: ticks.add,
        );

        const interval = Duration(milliseconds: 500);
        for (var i = 1; i <= 3; i++) {
          runClock.elapsedValue = interval * i;
          scheduler.runNext();
        }

        expect(ticks, hasLength(4));
        expect(
          ticks.map((t) => (t.barIndex, t.beatIndex, t.accentLevel)).toList(),
          [
            (1, 1, AccentLevel.high),
            (1, 2, AccentLevel.low),
            (1, 3, AccentLevel.normal),
            (1, 4, AccentLevel.normal),
          ],
        );
      });

      test('fires correct pulse data with subdivisions', () async {
        final ticks = <MetronomeBeatTick>[];

        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 2,
            beatUnit: 4,
            subdivision: Subdivision.two,
            accentPattern: [AccentLevel.high],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: ticks.add,
        );

        const pulseInterval = Duration(milliseconds: 250);
        runClock.elapsedValue = pulseInterval;
        scheduler.runNext(); // beat 1, pulse 2

        expect(ticks, hasLength(2));
        expect(ticks[0].pulseIndex, 1);
        expect(ticks[0].pulseCount, 2);
        expect(ticks[1].pulseIndex, 2);
        expect(ticks[1].pulseCount, 2);
      });
    });

    group('concurrent transport start throws StateError', () {
      test('throws when starting a transport that is already running',
          () async {
        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );

        expect(
          () => transport.start(
            const LiveMetronomeTransportConfig(
              bpm: 120,
              beatsPerBar: 4,
              beatUnit: 4,
              subdivision: Subdivision.one,
              accentPattern: [],
              clickSoundSet: ClickSoundSet.tock,
              masterVolumePercent: 100,
            ),
            onTick: (_) {},
          ),
          throwsStateError,
        );
      });
    });

    group('transport restart after stop works', () {
      test('stop then start again plays clicks normally', () async {
        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [AccentLevel.high],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );

        transport.stop();
        expect(transport.isRunning, isFalse);

        client.playedAssetPaths.clear();

        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 90,
            beatsPerBar: 3,
            beatUnit: 8,
            subdivision: Subdivision.one,
            accentPattern: [AccentLevel.low],
            clickSoundSet: ClickSoundSet.hype,
            masterVolumePercent: 80,
          ),
          onTick: (_) {},
        );

        expect(transport.isRunning, isTrue);
        expect(
          client.playedAssetPaths,
          contains('assets/audio/click_kits/hype/hype_accent_low.wav'),
        );
        expect(client.globalVolume, 0.8);
      });
    });

    group('audio engine initialization', () {
      test('transport initializes the audio engine on first start', () async {
        expect(client.initCallCount, 0);

        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );

        expect(client.initCallCount, 1);
      });

      test('transport does not reinitialize on subsequent starts', () async {
        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );
        transport.stop();

        await transport.start(
          const LiveMetronomeTransportConfig(
            bpm: 120,
            beatsPerBar: 4,
            beatUnit: 4,
            subdivision: Subdivision.one,
            accentPattern: [],
            clickSoundSet: ClickSoundSet.tock,
            masterVolumePercent: 100,
          ),
          onTick: (_) {},
        );

        // init was called once, then isInitialized returns true so no reinit.
        expect(client.initCallCount, 1);
      });
    });
  });
}

/// Bridges the [MetronomeClickOutput] interface to the real [SoLoudAudioEngine].
///
/// This is functionally identical to the private
/// `_AudioEngineMetronomeClickOutput` in [AudioEngineLiveMetronomeTransport]
/// but accessible in tests.
class _AudioEngineClickOutput implements MetronomeClickOutput {
  const _AudioEngineClickOutput(this._engine);

  final SoLoudAudioEngine _engine;

  @override
  void playHighBeat() => _engine.playClick(AccentLevel.high);

  @override
  void playLowBeat() => _engine.playClick(AccentLevel.low);

  @override
  void playNormalBeat() => _engine.playClick(AccentLevel.normal);

  @override
  void playSubdivisionPulse() => _engine.playSubdivisionClick();
}
