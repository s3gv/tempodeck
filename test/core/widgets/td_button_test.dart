import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_button.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  group('TDButton', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDButton(label: 'Start', onPressed: () {}),
      ),);

      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDButton(
          label: 'Play',
          icon: Icons.play_arrow,
          onPressed: () {},
        ),
      ),);

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('calls onPressed when tapped', (tester) async {
      var pressed = false;

      await tester.pumpWidget(buildTestWidget(
        TDButton(
          label: 'Tap Me',
          onPressed: () => pressed = true,
        ),
      ),);

      await tester.tap(find.text('Tap Me'));
      await tester.pump();

      expect(pressed, isTrue);
    });

    testWidgets('does not call onPressed when disabled', (tester) async {
      var pressed = false;

      await tester.pumpWidget(buildTestWidget(
        const TDButton(
          label: 'Disabled',
          onPressed: null,
        ),
      ),);

      await tester.tap(find.text('Disabled'));
      await tester.pump();

      expect(pressed, isFalse);
    });

    testWidgets('renders secondary variant with OutlinedButton',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDButton(
          label: 'Secondary',
          variant: TDButtonVariant.secondary,
          onPressed: () {},
        ),
      ),);

      expect(find.text('Secondary'), findsOneWidget);
      // Secondary variant uses OutlinedButton, not FilledButton.
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('renders primary variant with FilledButton', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDButton(
          label: 'Primary',
          variant: TDButtonVariant.primary,
          onPressed: () {},
        ),
      ),);

      expect(find.text('Primary'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator when loading',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDButton(
          label: 'Loading',
          isLoading: true,
          onPressed: () {},
        ),
      ),);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
