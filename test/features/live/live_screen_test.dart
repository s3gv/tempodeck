import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/providers/app_variant_provider.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_animated_background.dart';
import 'package:tempodeck/features/live/live_metronome_transport.dart';
import 'package:tempodeck/features/live/live_screen.dart';
import 'package:tempodeck/features/live/live_screen_controller.dart';
import 'package:tempodeck/core/audio/metronome_click_engine.dart';

void main() {
  setUpAll(() {
    TDAnimatedBackground.disableAnimations = true;
  });

  tearDownAll(() {
    TDAnimatedBackground.disableAnimations = false;
  });

  testWidgets('space toggles playback on desktop live view', (tester) async {
    final transport = _FakeLiveMetronomeTransport();
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_LiveScreenHarness(container: container));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('livePlayStopButton')), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.byTooltip('Play'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(transport.startCallCount, 1);
    expect(find.text('Stop'), findsNothing);
    expect(find.byTooltip('Stop'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(transport.stopCallCount, 1);
    expect(find.text('Play'), findsNothing);
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('space still toggles playback after the play button took focus',
      (tester) async {
    final transport = _FakeLiveMetronomeTransport();
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_LiveScreenHarness(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('livePlayStopButton')));
    await tester.pumpAndSettle();

    expect(transport.startCallCount, 1);
    expect(find.text('Stop'), findsNothing);
    expect(find.byTooltip('Stop'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(transport.stopCallCount, 1);
    expect(find.text('Play'), findsNothing);
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('exit button is disabled while playback is active',
      (tester) async {
    final transport = _FakeLiveMetronomeTransport();
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.desktop),
        liveMetronomeTransportProvider.overrideWithValue(transport),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_LiveScreenHarness(container: container));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('liveExitButton')))
          .onPressed,
      isNotNull,
    );
    expect(find.byTooltip('Close live view'), findsOneWidget);

    await tester.tap(find.byKey(const Key('livePlayStopButton')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('liveExitButton')))
          .onPressed,
      isNull,
    );
    expect(find.byTooltip('Stop playback to close live view'), findsOneWidget);
  });

  testWidgets(
      'mobile drag offset springs back when dismiss is disabled mid-gesture',
      (tester) async {
    final transport = _FakeLiveMetronomeTransport();
    final container = ProviderContainer(
      overrides: [
        appVariantProvider.overrideWithValue(AppVariant.mobile),
        liveMetronomeTransportProvider.overrideWithValue(transport),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_LiveScreenHarness(container: container));
    await tester.pumpAndSettle();

    final dismissTransform = find.byKey(const Key('liveDismissTransform'));
    final gesture =
        await tester.startGesture(tester.getCenter(dismissTransform));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();

    final draggedTransform = tester.widget<Transform>(
      dismissTransform,
    );
    expect(draggedTransform.transform.getTranslation().y, lessThan(0));

    await tester.tap(find.byKey(const Key('livePlayStopButton')));
    await tester.pump();

    await gesture.up();
    await tester.pumpAndSettle();

    final settledTransform = tester.widget<Transform>(
      dismissTransform,
    );
    expect(settledTransform.transform.getTranslation().y, 0);
  });
}

class _LiveScreenHarness extends StatelessWidget {
  const _LiveScreenHarness({required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const LiveScreen(),
      ),
    );
  }
}

class _FakeLiveMetronomeTransport implements LiveMetronomeTransport {
  int startCallCount = 0;
  int stopCallCount = 0;
  bool _isRunning = false;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> start(
    LiveMetronomeTransportConfig config, {
    required void Function(MetronomeBeatTick tick) onTick,
    List<MetronomeClickEngineConfig>? beatmapSequence,
  }) async {
    startCallCount++;
    _isRunning = true;
  }

  @override
  void stop() {
    stopCallCount++;
    _isRunning = false;
  }

  @override
  Future<void> stopAllAudio() async {
    stop();
  }
}
