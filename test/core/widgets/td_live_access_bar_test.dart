import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_live_access_bar.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    // TDLiveAccessBar returns a Positioned widget, so it needs a Stack parent.
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Stack(children: [child]),
      ),
    );
  }

  group('TDLiveAccessBar', () {
    testWidgets('renders the play icon', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDLiveAccessBar(onPlay: () async {}),
      ),);

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('renders with "Open live view" semantics label',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        TDLiveAccessBar(onPlay: () async {}),
      ),);

      expect(
        find.bySemanticsLabel('Open live view'),
        findsOneWidget,
      );
    });

    testWidgets('calls onPlay when tapped', (tester) async {
      var played = false;

      await tester.pumpWidget(buildTestWidget(
        TDLiveAccessBar(onPlay: () async {
          played = true;
        },),
      ),);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      expect(played, isTrue);
    });

    testWidgets('shows spinner while onPlay is running', (tester) async {
      final completer = Completer<void>();

      await tester.pumpWidget(buildTestWidget(
        TDLiveAccessBar(onPlay: () => completer.future),
      ),);

      // Tap to start loading.
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      // Play icon should be replaced by a spinner.
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the future → spinner should disappear.
      completer.complete();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });
  });
}
