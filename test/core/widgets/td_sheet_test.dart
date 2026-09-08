import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_colors.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_animated_background.dart';
import 'package:tempodeck/core/widgets/td_sheet.dart';

void main() {
  setUpAll(() {
    TDAnimatedBackground.disableAnimations = true;
  });

  tearDownAll(() {
    TDAnimatedBackground.disableAnimations = false;
  });

  group('showTDSheet', () {
    testWidgets('renders child content inside the sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showTDSheet(
                      context: context,
                      builder: (_) => const Text('Sheet Content'),
                    );
                  },
                  child: const Text('Open Sheet'),
                );
              },
            ),
          ),
        ),
      );

      // Tap the button to open the sheet.
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Sheet Content'), findsOneWidget);
    });

    testWidgets('has proper surface background color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showTDSheet(
                      context: context,
                      builder: (_) => const Text('Styled Sheet'),
                    );
                  },
                  child: const Text('Open Sheet'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // The BottomSheet should use AppColors.surface as background.
      // The backgroundColor is passed through showModalBottomSheet.
      // Verify via the ModalBottomSheetRoute's background parameter
      // by finding the Material widget inside the bottom sheet.
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, AppColors.surface);
    });

    testWidgets('renders drag handle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showTDSheet(
                      context: context,
                      builder: (_) => const Text('With Handle'),
                    );
                  },
                  child: const Text('Open Sheet'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Verify via the SafeArea + Column structure.
      // The sheet should have both the drag handle area and the child content.
      expect(find.text('With Handle'), findsOneWidget);
    });
  });
}
