import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_monitor/main.dart';

void main() {
  testWidgets('Focus bar renders with prompt', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FocusBar(autoStartTimer: false),
        ),
      ),
    );

    expect(find.textContaining('CF:'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
