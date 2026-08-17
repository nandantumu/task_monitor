import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_monitor/widgets/focus_pie_chart.dart';

void main() {
  testWidgets('FocusPieChart renders disabled state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FocusPieChart(
            percentage: null,
            isEnabled: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pie-disabled')), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
  });

  testWidgets('FocusPieChart renders active percentage', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FocusPieChart(
            percentage: 85.0,
            isEnabled: true,
            tooltipReason: 'Working in VS Code',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('85'), findsOneWidget);
  });

  testWidgets('FocusPieChart renders loading state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FocusPieChart(
            percentage: null,
            isEnabled: true,
            isLoading: true,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pie-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
