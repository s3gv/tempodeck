import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_spacing.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_card.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders child content', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDCard(child: Text('Card Content')),
    ),);

    expect(find.text('Card Content'), findsOneWidget);
  });

  testWidgets('has onTap callback when provided', (tester) async {
    var tapped = false;

    await tester.pumpWidget(buildTestWidget(
      TDCard(
        onTap: () => tapped = true,
        child: const Text('Tappable'),
      ),
    ),);

    await tester.tap(find.text('Tappable'));
    expect(tapped, isTrue);
  });

  testWidgets('shows default padding (AppSpacing.lg)', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDCard(child: Text('Padded')),
    ),);

    final animatedContainer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(
      animatedContainer.padding,
      const EdgeInsets.all(AppSpacing.lg),
    );
  });

  testWidgets('accepts custom padding', (tester) async {
    const customPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);

    await tester.pumpWidget(buildTestWidget(
      const TDCard(
        padding: customPadding,
        child: Text('Custom Padding'),
      ),
    ),);

    final animatedContainer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(animatedContainer.padding, customPadding);
  });
}
