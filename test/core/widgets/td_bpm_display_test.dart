import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_bpm_display.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  group('TDBpmDisplay', () {
    testWidgets('renders BPM value as text', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TDBpmDisplay(bpm: 120),
      ),);

      expect(find.text('120'), findsOneWidget);
    });

    testWidgets('renders "BPM" label by default', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TDBpmDisplay(bpm: 90),
      ),);

      expect(find.text('BPM'), findsOneWidget);
    });

    testWidgets('renders custom label when provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TDBpmDisplay(bpm: 140, label: 'TEMPO'),
      ),);

      expect(find.text('TEMPO'), findsOneWidget);
      expect(find.text('BPM'), findsNothing);
    });

    testWidgets('pulse() can be called on the state via GlobalKey',
        (tester) async {
      final key = GlobalKey<TDBpmDisplayState>();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: TDBpmDisplay(key: key, bpm: 100),
          ),
        ),
      );

      // Calling pulse should not throw.
      key.currentState!.pulse();
      await tester.pump();
    });
  });
}
