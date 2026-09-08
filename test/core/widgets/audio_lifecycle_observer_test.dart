import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/audio_playback_session.dart';
import 'package:tempodeck/core/widgets/audio_lifecycle_observer.dart';

import '../audio/audio_playback_session_test_support.dart';
import '../audio/foreground_playback_service_test_support.dart';
import 'package:tempodeck/core/audio/stub_audio_engine.dart';

void main() {
  late _StubAudioEngine engine;
  late FakeAudioPlaybackSession session;
  late FakeForegroundPlaybackService foregroundService;

  setUp(() {
    engine = _StubAudioEngine();
    session = FakeAudioPlaybackSession();
    foregroundService = FakeForegroundPlaybackService();
  });

  Widget buildWidget() {
    return AudioLifecycleObserver(
      audioEngine: engine,
      playbackSession: session,
      foregroundService: foregroundService,
      child: const SizedBox.shrink(),
    );
  }

  testWidgets('registers interruption handler on init', (tester) async {
    await tester.pumpWidget(buildWidget());

    // Simulate an interruption — the callback should be registered.
    session.simulateInterruption(
      true,
      AudioInterruptionReason.externalInterruption,
    );

    expect(engine.stopCallCount, 1);
  });

  testWidgets(
    'stops audio and foreground service when interruption begins',
    (tester) async {
      await tester.pumpWidget(buildWidget());

      session.simulateInterruption(
        true,
        AudioInterruptionReason.externalInterruption,
      );
      await tester.pump();

      expect(engine.stopCallCount, 1);
      expect(foregroundService.stopCallCount, 1);
    },
  );

  testWidgets(
    'does not auto-resume when interruption ends',
    (tester) async {
      await tester.pumpWidget(buildWidget());

      // First begin an interruption…
      session.simulateInterruption(
        true,
        AudioInterruptionReason.externalInterruption,
      );
      await tester.pump();
      engine.stopCallCount = 0; // Reset.

      // …then end it.
      session.simulateInterruption(
        false,
        AudioInterruptionReason.externalInterruption,
      );
      await tester.pump();

      // Should NOT try to start playback again.
      expect(engine.stopCallCount, 0);
    },
  );

  testWidgets(
    'stops audio on transient focus loss',
    (tester) async {
      await tester.pumpWidget(buildWidget());

      session.simulateInterruption(
        true,
        AudioInterruptionReason.transientFocusLoss,
      );
      await tester.pump();

      expect(engine.stopCallCount, 1);
    },
  );

  testWidgets(
    'stops audio on duck interruption instead of lowering volume',
    (tester) async {
      await tester.pumpWidget(buildWidget());

      session.simulateInterruption(true, AudioInterruptionReason.duck);
      await tester.pump();

      // A metronome should stop, not duck — a quieter click is useless.
      expect(engine.stopCallCount, 1);
    },
  );

  testWidgets(
    'unregisters interruption handler on dispose',
    (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pumpWidget(const SizedBox.shrink());

      // After dispose, interruption should not call stop again.
      engine.stopCallCount = 0;
      session.simulateInterruption(
        true,
        AudioInterruptionReason.externalInterruption,
      );

      expect(engine.stopCallCount, 0);
    },
  );
}

/// Minimal audio engine stub that tracks stop/dispose calls.
class _StubAudioEngine extends StubAudioEngine {
  int stopCallCount = 0;
  int disposeCallCount = 0;

  @override
  Future<void> stop() async {
    stopCallCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCallCount += 1;
  }
}
