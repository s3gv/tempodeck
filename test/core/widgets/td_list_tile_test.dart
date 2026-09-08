import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_colors.dart';
import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_list_tile.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders title and subtitle text', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDListTile(
        title: 'Bohemian Rhapsody',
        subtitle: '138 BPM',
      ),
    ),);

    expect(find.text('Bohemian Rhapsody'), findsOneWidget);
    expect(find.text('138 BPM'), findsOneWidget);
  });

  testWidgets('calls onTap when tapped', (tester) async {
    var tapped = false;

    await tester.pumpWidget(buildTestWidget(
      TDListTile(
        title: 'Song Item',
        onTap: () => tapped = true,
      ),
    ),);

    await tester.tap(find.text('Song Item'));
    expect(tapped, isTrue);
  });

  testWidgets('renders trailing widget', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDListTile(
        title: 'Settings Item',
        trailing: Icon(Icons.chevron_right),
      ),
    ),);

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('shows selected state styling (isSelected: true)',
      (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDListTile(
        title: 'Selected Song',
        isSelected: true,
      ),
    ),);

    // The AnimatedContainer should use the elevated surface color and
    // primary border when selected.
    final animatedContainer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = animatedContainer.decoration! as BoxDecoration;
    expect(decoration.color, AppColors.surface);
    expect(decoration.border, isNotNull);
    final border = decoration.border! as Border;
    expect(border.top.color, AppColors.primary);
  });

  testWidgets('shows default state styling (isSelected: false)',
      (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDListTile(
        title: 'Unselected Song',
      ),
    ),);

    final animatedContainer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = animatedContainer.decoration! as BoxDecoration;
    expect(decoration.color, Colors.transparent);
  });
}
