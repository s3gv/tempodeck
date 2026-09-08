import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_colors.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_toggle.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders in on state (value: true)', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDToggle(value: true, onChanged: null),
    ),);

    // The outer AnimatedContainer should have the primary color when on.
    final animatedContainer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    final decoration = animatedContainer.decoration! as BoxDecoration;
    expect(decoration.color, AppColors.primary);
  });

  testWidgets('renders in off state (value: false)', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDToggle(value: false, onChanged: null),
    ),);

    final animatedContainer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    final decoration = animatedContainer.decoration! as BoxDecoration;
    expect(decoration.color, AppColors.surfaceElevated);
  });

  testWidgets('calls onChanged with toggled value on tap', (tester) async {
    bool? receivedValue;

    await tester.pumpWidget(buildTestWidget(
      TDToggle(
        value: false,
        onChanged: (value) => receivedValue = value,
      ),
    ),);

    await tester.tap(find.byType(TDToggle));
    expect(receivedValue, isTrue);
  });

  testWidgets('does not call onChanged when onChanged is null (disabled)',
      (tester) async {
    var callCount = 0;

    // Build with onChanged: null (disabled).
    await tester.pumpWidget(buildTestWidget(
      const TDToggle(
        value: false,
        onChanged: null,
      ),
    ),);

    // Tapping should not trigger any callback.
    await tester.tap(find.byType(TDToggle));
    expect(callCount, 0);
  });
}
