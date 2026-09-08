import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_beat_indicator.dart';

void main() {
  Widget buildHarness({required int beatsPerBar}) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: TDBeatIndicator(beatsPerBar: beatsPerBar),
      ),
    );
  }

  testWidgets('renders correct number of beat dots', (tester) async {
    await tester.pumpWidget(buildHarness(beatsPerBar: 4));

    // 4 beat dots rendered as Containers with circular BoxDecoration.
    final containers = find.byType(Container);
    // Filter to only the circle-shaped beat dots.
    var circleCount = 0;
    for (final element in containers.evaluate()) {
      final widget = element.widget as Container;
      final decoration = widget.decoration;
      if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
        circleCount++;
      }
    }
    expect(circleCount, 4);
  });

  testWidgets('renders different count when beatsPerBar changes',
      (tester) async {
    await tester.pumpWidget(buildHarness(beatsPerBar: 3));

    final containers = find.byType(Container);
    var circleCount = 0;
    for (final element in containers.evaluate()) {
      final widget = element.widget as Container;
      final decoration = widget.decoration;
      if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
        circleCount++;
      }
    }
    expect(circleCount, 3);
  });

  testWidgets('activateBeat does not crash for valid index', (tester) async {
    final key = GlobalKey<TDBeatIndicatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: TDBeatIndicator(key: key, beatsPerBar: 4),
        ),
      ),
    );

    // Should not throw.
    key.currentState!.activateBeat(1, AccentLevel.high);
    await tester.pump();
    key.currentState!.activateBeat(2, AccentLevel.normal);
    await tester.pump();
  });

  testWidgets('activateBeat ignores out-of-range index', (tester) async {
    final key = GlobalKey<TDBeatIndicatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: TDBeatIndicator(key: key, beatsPerBar: 4),
        ),
      ),
    );

    // Out of range – should not throw.
    key.currentState!.activateBeat(0, AccentLevel.normal);
    key.currentState!.activateBeat(5, AccentLevel.normal);
    await tester.pump();
  });

  testWidgets('wraps dots into multiple rows when beatsPerBar exceeds 8',
      (tester) async {
    await tester.pumpWidget(buildHarness(beatsPerBar: 9));

    expect(_countCircles(tester), 9);

    // Should have 2 Rows inside the Column (8 + 1).
    final column = tester.widget<Column>(find.byType(Column).first);
    final rows = column.children.whereType<Row>().toList();
    expect(rows.length, 2);
  });

  testWidgets('caps dots at maxDots when beatsPerBar exceeds 32',
      (tester) async {
    await tester.pumpWidget(buildHarness(beatsPerBar: 40));

    expect(_countCircles(tester), TDBeatIndicatorState.maxDots);
  });

  testWidgets('renders single row for 8 or fewer beats', (tester) async {
    await tester.pumpWidget(buildHarness(beatsPerBar: 8));

    expect(_countCircles(tester), 8);

    final column = tester.widget<Column>(find.byType(Column).first);
    final rows = column.children.whereType<Row>().toList();
    expect(rows.length, 1);
  });

  testWidgets('rebuilds when beatsPerBar changes', (tester) async {
    var beatsPerBar = 4;
    late StateSetter setStateRef;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: StatefulBuilder(
          builder: (context, setState) {
            setStateRef = setState;
            return Scaffold(
              body: TDBeatIndicator(beatsPerBar: beatsPerBar),
            );
          },
        ),
      ),
    );

    // Count initial circles.
    var circleCount = _countCircles(tester);
    expect(circleCount, 4);

    // Update to 6 beats.
    setStateRef(() => beatsPerBar = 6);
    await tester.pump();

    circleCount = _countCircles(tester);
    expect(circleCount, 6);
  });
}

int _countCircles(WidgetTester tester) {
  var count = 0;
  for (final element in find.byType(Container).evaluate()) {
    final widget = element.widget as Container;
    final decoration = widget.decoration;
    if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
      count++;
    }
  }
  return count;
}
