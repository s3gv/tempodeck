import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_nav_bar.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  const destinations = [
    TDNavDestination(icon: Icons.timer, label: 'Metronome'),
    TDNavDestination(icon: Icons.music_note, label: 'Songs'),
    TDNavDestination(icon: Icons.list, label: 'Setlists'),
    TDNavDestination(icon: Icons.settings, label: 'Settings'),
  ];

  group('TDNavBar', () {
    testWidgets('renders all destination labels', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDNavBar(
          destinations: destinations,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
      ),);

      expect(find.text('Metronome'), findsOneWidget);
      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Setlists'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('calls onDestinationSelected when a destination is tapped',
        (tester) async {
      int? selectedIndex;

      await tester.pumpWidget(buildTestWidget(
        TDNavBar(
          destinations: destinations,
          selectedIndex: 0,
          onDestinationSelected: (index) => selectedIndex = index,
        ),
      ),);

      await tester.tap(find.text('Songs'));
      await tester.pump();

      expect(selectedIndex, 1);
    });

    testWidgets('shows selected icon for the current index', (tester) async {
      const destinationsWithSelected = [
        TDNavDestination(
          icon: Icons.timer_outlined,
          label: 'Metronome',
          selectedIcon: Icons.timer,
        ),
        TDNavDestination(
          icon: Icons.music_note_outlined,
          label: 'Songs',
          selectedIcon: Icons.music_note,
        ),
      ];

      await tester.pumpWidget(buildTestWidget(
        TDNavBar(
          destinations: destinationsWithSelected,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
      ),);

      // The selected tab (index 0) uses selectedIcon (Icons.timer).
      expect(find.byIcon(Icons.timer), findsOneWidget);
      // The unselected tab (index 1) uses the regular icon.
      expect(find.byIcon(Icons.music_note_outlined), findsOneWidget);
    });

    testWidgets('renders all destination icons', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDNavBar(
          destinations: destinations,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
      ),);

      expect(find.byIcon(Icons.timer), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
      expect(find.byIcon(Icons.list), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });
  });
}
