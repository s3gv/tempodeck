import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_slider.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders label and value text', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDSlider(
        value: 0.5,
        onChanged: null,
        label: 'Volume',
        valueLabel: '50%',
      ),
    ),);

    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('contains a Slider widget', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDSlider(
        value: 0.3,
        onChanged: null,
      ),
    ),);

    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('calls onChanged when slider value changes', (tester) async {
    double? changedValue;

    await tester.pumpWidget(buildTestWidget(
      TDSlider(
        value: 0.5,
        min: 0,
        max: 1,
        onChanged: (value) => changedValue = value,
      ),
    ),);

    // Find the inner Slider and invoke its onChanged.
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(0.8);

    expect(changedValue, 0.8);
  });

  testWidgets('hides label row when label is null', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDSlider(
        value: 0.5,
        onChanged: null,
      ),
    ),);

    // Only the Slider should be present, no label text.
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });
}
