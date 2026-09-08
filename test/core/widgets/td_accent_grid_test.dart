import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/domain/accent_level.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_accent_grid.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  group('TDAccentGrid', () {
    testWidgets('renders correct number of rows for 4 beats', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          TDAccentGrid(
            accentPattern: const [
              AccentLevel.high,
              AccentLevel.normal,
              AccentLevel.normal,
              AccentLevel.normal,
            ],
            onAccentChanged: (_, __) {},
          ),
        ),
      );

      // Each beat row shows its 1-based beat number.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsNothing);
    });

    testWidgets('renders correct number of rows for 3 beats', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          TDAccentGrid(
            accentPattern: const [
              AccentLevel.high,
              AccentLevel.normal,
              AccentLevel.low,
            ],
            onAccentChanged: (_, __) {},
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsNothing);
    });

    testWidgets('renders accent segment labels (H, N, L, M)', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          TDAccentGrid(
            accentPattern: const [
              AccentLevel.high,
              AccentLevel.normal,
              AccentLevel.low,
              AccentLevel.mute,
            ],
            onAccentChanged: (_, __) {},
          ),
        ),
      );

      // Each row has all four segment labels, so we find them for each beat.
      expect(find.text('H'), findsWidgets);
      expect(find.text('N'), findsWidgets);
      expect(find.text('L'), findsWidgets);
      expect(find.text('M'), findsWidgets);
    });

    testWidgets(
      'calls onAccentChanged with correct index and level when a segment is tapped',
      (tester) async {
        int? changedIndex;
        AccentLevel? changedLevel;

        await tester.pumpWidget(
          buildTestWidget(
            TDAccentGrid(
              accentPattern: const [
                AccentLevel.high,
                AccentLevel.normal,
                AccentLevel.normal,
                AccentLevel.normal,
              ],
              onAccentChanged: (index, level) {
                changedIndex = index;
                changedLevel = level;
              },
            ),
          ),
        );

        // Find all 'L' labels (one per row = 4) and tap the second one
        // (row index 1 = beat 2).
        final lowSegments = find.text('L');
        expect(lowSegments, findsNWidgets(4));

        await tester.tap(lowSegments.at(1));
        await tester.pump();

        expect(changedIndex, 1);
        expect(changedLevel, AccentLevel.low);
      },
    );
  });
}
