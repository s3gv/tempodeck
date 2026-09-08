import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_stepper.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  group('TDStepper', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TDStepper(label: 'BPM Step', value: 5),
      ),);

      expect(find.text('BPM Step'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('calls onIncrement when + button is tapped', (tester) async {
      var incremented = false;

      await tester.pumpWidget(buildTestWidget(
        TDStepper(
          label: 'Step',
          value: 1,
          onIncrement: () => incremented = true,
          onDecrement: () {},
        ),
      ),);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();

      expect(incremented, isTrue);
    });

    testWidgets('calls onDecrement when - button is tapped', (tester) async {
      var decremented = false;

      await tester.pumpWidget(buildTestWidget(
        TDStepper(
          label: 'Step',
          value: 3,
          onIncrement: () {},
          onDecrement: () => decremented = true,
        ),
      ),);

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();

      expect(decremented, isTrue);
    });

    testWidgets('disables increment button when onIncrement is null',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDStepper(
          label: 'Step',
          value: 10,
          onIncrement: null,
          onDecrement: () {},
        ),
      ),);

      final incrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add_circle_outline),
      );
      expect(incrementButton.onPressed, isNull);
    });

    testWidgets('disables decrement button when onDecrement is null',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDStepper(
          label: 'Step',
          value: 1,
          onIncrement: () {},
          onDecrement: null,
        ),
      ),);

      final decrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove_circle_outline),
      );
      expect(decrementButton.onPressed, isNull);
    });
  });
}
