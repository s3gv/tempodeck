import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/domain/interval_settings.dart';
import 'package:tempodeck/features/live/live_event.dart';
import 'package:tempodeck/features/live/live_event_resolver.dart';

void main() {
  const resolver = LiveMetronomeEventResolver();

  test('returns empty events when interval settings are null', () {
    final result = resolver.resolve(
      intervalSettings: null,
      currentBpm: 120,
    );

    expect(result.current, isEmpty);
    expect(result.next, isEmpty);
  });

  test('returns empty events when bpmStepEnabled is false', () {
    final result = resolver.resolve(
      intervalSettings: const IntervalSettings(
        interval: Duration(minutes: 1),
        bpmStepEnabled: false,
        bpmStep: 5,
      ),
      currentBpm: 120,
    );

    expect(result.current, isEmpty);
    expect(result.next, isEmpty);
  });

  test('returns interval step event when bpmStepEnabled is true', () {
    final result = resolver.resolve(
      intervalSettings: const IntervalSettings(
        interval: Duration(minutes: 1),
        bpmStepEnabled: true,
        bpmStep: 5,
      ),
      currentBpm: 120,
    );

    expect(result.current, isEmpty);
    expect(result.next, hasLength(1));
    expect(result.next.first, isA<IntervalStepEvent>());

    final event = result.next.first as IntervalStepEvent;
    expect(event.fromBpm, 120);
    expect(event.toBpm, 125);
  });

  test('returns empty events when currentBpm is null', () {
    final result = resolver.resolve(
      intervalSettings: const IntervalSettings(
        interval: Duration(minutes: 1),
        bpmStepEnabled: true,
        bpmStep: 5,
      ),
      currentBpm: null,
    );

    expect(result.current, isEmpty);
    expect(result.next, isEmpty);
  });
}
