import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_section_header.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders label as uppercase', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDSectionHeader(
        icon: Icons.tune,
        label: 'rhythm',
      ),
    ),);

    expect(find.text('RHYTHM'), findsOneWidget);
  });

  testWidgets('renders icon', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDSectionHeader(
        icon: Icons.tune,
        label: 'Settings',
      ),
    ),);

    expect(find.byIcon(Icons.tune), findsOneWidget);
  });

  testWidgets('shows chevron when onToggle is provided', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      TDSectionHeader(
        icon: Icons.tune,
        label: 'Collapsible',
        onToggle: () {},
      ),
    ),);

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('hides chevron when onToggle is null', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDSectionHeader(
        icon: Icons.tune,
        label: 'Non-collapsible',
      ),
    ),);

    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('calls onToggle when tapped', (tester) async {
    var toggleCalled = false;

    await tester.pumpWidget(buildTestWidget(
      TDSectionHeader(
        icon: Icons.tune,
        label: 'Tap Me',
        onToggle: () => toggleCalled = true,
      ),
    ),);

    await tester.tap(find.text('TAP ME'));
    expect(toggleCalled, isTrue);
  });
}
