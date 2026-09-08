import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/widgets/td_splash_screen.dart';

void main() {
  testWidgets('renders without an ambient Directionality widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      const TDSplashScreen(
        isReady: false,
        child: SizedBox.shrink(),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps showing the splash until startup is ready', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TDSplashScreen(
          isReady: false,
          child: Text('App Ready'),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 3));

    final hiddenChildOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('App Ready'),
        matching: find.byType(Opacity),
      ).first,
    );
    expect(hiddenChildOpacity.opacity, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('shows the child after the splash cross-fade completes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const TDSplashScreen(
        isReady: true,
        child: Text('App Ready', textDirection: TextDirection.ltr),
      ),
    );

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('App Ready'), findsOneWidget);
  });
}
