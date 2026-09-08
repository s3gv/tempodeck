import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/domain/interval_settings.dart';
import 'package:tempodeck/features/metronome/metronome_interval_preview_builder.dart';

void main() {
  const builder = MetronomeIntervalPreviewBuilder();

  test('builds repeating preview items without bpm changes', () {
    final items = builder.build(
      bpm: 120,
      intervalSettings: const IntervalSettings(
        interval: Duration(minutes: 1),
      ),
    );

    expect(items, hasLength(MetronomeIntervalPreviewBuilder.previewItemCount));
    expect(items.first.title, 'Interval 1');
    expect(items.first.subtitle, 'After 01:00 • Keep 120 BPM');
    expect(items[1].subtitle, 'After 02:00 • Keep 120 BPM');
  });

  test('builds bpm step preview items when interval stepping is enabled', () {
    final items = builder.build(
      bpm: 120,
      intervalSettings: const IntervalSettings(
        interval: Duration(seconds: 30),
        bpmStepEnabled: true,
        bpmStep: 5,
      ),
    );

    expect(items.first.subtitle, 'After 00:30 • Change to 125 BPM');
    expect(items[1].subtitle, 'After 01:00 • Change to 130 BPM');
  });

  test('clamps stepped bpm preview items to the supported preset range', () {
    final items = builder.build(
      bpm: 318,
      intervalSettings: const IntervalSettings(
        interval: Duration(seconds: 30),
        bpmStepEnabled: true,
        bpmStep: 5,
      ),
    );

    expect(items.first.subtitle, 'After 00:30 • Change to 320 BPM');
    expect(items[1].subtitle, 'After 01:00 • Change to 320 BPM');
  });

  test('shows the boundary interval and then the stop event at max duration',
      () {
    final items = builder.build(
      bpm: 100,
      intervalSettings: const IntervalSettings(
        interval: Duration(minutes: 1),
        maxDuration: Duration(minutes: 3),
      ),
    );

    expect(items, hasLength(4));
    expect(items[0].title, 'Interval 1');
    expect(items[1].title, 'Interval 2');
    expect(items[2].title, 'Interval 3');
    expect(items[2].subtitle, 'After 03:00 • Keep 100 BPM');
    expect(items[3].title, 'Stop playback');
    expect(items[3].subtitle, 'After 03:00');
  });
}
