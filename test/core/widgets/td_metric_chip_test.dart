import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_metric_chip.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  group('TDMetricChip', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TDMetricChip(label: '120 BPM'),
      ),);

      expect(find.text('120 BPM'), findsOneWidget);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TDMetricChip(
          label: '4/4',
          icon: Icons.music_note,
        ),
      ),);

      expect(find.byIcon(Icons.music_note), findsOneWidget);
      expect(find.text('4/4'), findsOneWidget);
    });

    testWidgets('renders without icon when not provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TDMetricChip(label: '3 songs'),
      ),);

      expect(find.text('3 songs'), findsOneWidget);
      // No Icon widget should be present.
      expect(find.byType(Icon), findsNothing);
    });
  });
}
