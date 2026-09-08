import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_animated_background.dart';
import 'package:tempodeck/core/widgets/td_dropdown_card.dart';

void main() {
  setUpAll(() {
    TDAnimatedBackground.disableAnimations = true;
  });

  tearDownAll(() {
    TDAnimatedBackground.disableAnimations = false;
  });

  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  group('TDDropdownCard', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDDropdownCard<String>(
          label: 'Time Signature',
          value: '4/4',
          options: const ['3/4', '4/4', '5/4'],
          itemLabel: (v) => v,
          onChanged: (_) {},
        ),
      ),);

      expect(find.text('Time Signature'), findsOneWidget);
    });

    testWidgets('renders currently selected value label', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDDropdownCard<String>(
          label: 'Subdivision',
          value: 'Eighth',
          options: const ['Quarter', 'Eighth', 'Sixteenth'],
          itemLabel: (v) => v,
          onChanged: (_) {},
        ),
      ),);

      expect(find.text('Eighth'), findsOneWidget);
    });

    testWidgets('renders trailing chevron icon', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDDropdownCard<String>(
          label: 'Sound',
          value: 'Click',
          options: const ['Click', 'Beep', 'Woodblock'],
          itemLabel: (v) => v,
          onChanged: (_) {},
        ),
      ),);

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('opens bottom sheet on tap', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDDropdownCard<String>(
          label: 'Sound',
          value: 'Click',
          options: const ['Click', 'Beep', 'Woodblock'],
          itemLabel: (v) => v,
          onChanged: (_) {},
        ),
      ),);

      await tester.tap(find.byType(TDDropdownCard<String>));
      await tester.pumpAndSettle();

      // All options should be visible in the bottom sheet.
      expect(find.text('Beep'), findsOneWidget);
      expect(find.text('Woodblock'), findsOneWidget);
    });

    testWidgets('shows check icon next to selected option in sheet',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDDropdownCard<String>(
          label: 'Sound',
          value: 'Click',
          options: const ['Click', 'Beep', 'Woodblock'],
          itemLabel: (v) => v,
          onChanged: (_) {},
        ),
      ),);

      await tester.tap(find.byType(TDDropdownCard<String>));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('calls onChanged when an option is selected', (tester) async {
      String? selectedValue;

      await tester.pumpWidget(buildTestWidget(
        TDDropdownCard<String>(
          label: 'Sound',
          value: 'Click',
          options: const ['Click', 'Beep', 'Woodblock'],
          itemLabel: (v) => v,
          onChanged: (v) => selectedValue = v,
        ),
      ),);

      await tester.tap(find.byType(TDDropdownCard<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Beep'));
      await tester.pumpAndSettle();

      expect(selectedValue, 'Beep');
    });
  });
}
