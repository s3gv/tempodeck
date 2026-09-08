import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/theme/app_theme.dart';
import 'package:tempodeck/core/widgets/td_text_field.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders with hint text', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDTextField(hint: 'Enter song name'),
    ),);

    expect(find.text('Enter song name'), findsOneWidget);
  });

  testWidgets('accepts text input', (tester) async {
    String? changedText;

    await tester.pumpWidget(buildTestWidget(
      TDTextField(
        hint: 'Type here',
        onChanged: (value) => changedText = value,
      ),
    ),);

    await tester.enterText(find.byType(TextField), 'Hello World');
    expect(changedText, 'Hello World');
  });

  testWidgets('renders with custom label', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDTextField(label: 'Song Title'),
    ),);

    expect(find.text('Song Title'), findsOneWidget);
  });

  testWidgets('renders error text when provided', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      const TDTextField(
        hint: 'Enter BPM',
        errorText: 'Invalid value',
      ),
    ),);

    expect(find.text('Invalid value'), findsOneWidget);
  });
}
