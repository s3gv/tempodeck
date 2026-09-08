import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_empty_state.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders icon, title, and subtitle', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDEmptyState(
        icon: Icons.music_note,
        title: 'No Songs',
        subtitle: 'Add your first song to get started',
      ),
    ),);

    expect(find.byIcon(Icons.music_note), findsOneWidget);
    expect(find.text('No Songs'), findsOneWidget);
    expect(find.text('Add your first song to get started'), findsOneWidget);
  });

  testWidgets('renders action button when actionLabel is provided',
      (tester) async {
    await tester.pumpWidget(buildTestWidget(
      TDEmptyState(
        icon: Icons.library_music,
        title: 'No Setlists',
        actionLabel: 'Create Setlist',
        onAction: () {},
      ),
    ),);

    expect(find.text('Create Setlist'), findsOneWidget);
  });

  testWidgets('calls onAction when action button is tapped', (tester) async {
    var actionCalled = false;

    await tester.pumpWidget(buildTestWidget(
      TDEmptyState(
        icon: Icons.library_music,
        title: 'No Setlists',
        actionLabel: 'Create Setlist',
        onAction: () => actionCalled = true,
      ),
    ),);

    await tester.tap(find.text('Create Setlist'));
    expect(actionCalled, isTrue);
  });

  testWidgets('does not render action button when actionLabel is null',
      (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDEmptyState(
        icon: Icons.music_note,
        title: 'No Songs',
      ),
    ),);

    // Only the icon and title should be present; no button text.
    expect(find.text('No Songs'), findsOneWidget);
    // FilledButton is used internally by TDButton for primary variant.
    expect(find.byType(FilledButton), findsNothing);
  });
}
