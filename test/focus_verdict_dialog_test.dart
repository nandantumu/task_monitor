import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_monitor/services/focus_verifier_service.dart';
import 'package:task_monitor/widgets/focus_verdict_dialog.dart';

void main() {
  testWidgets('FocusVerdictDialog renders positive verdict details accurately', (tester) async {
    final result = FocusVerificationResult(
      matchPercentage: 85.0,
      reason: 'User is actively developing code in IDE',
      activeWindowTitle: 'main.dart - Visual Studio Code [Code Editor / IDE]',
      openWindowTitles: [
        'main.dart [Code Editor / IDE]',
        'Terminal [Terminal]',
      ],
      timestamp: DateTime.now(),
    );

    var reauditCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusVerdictDialog(
            currentFocus: 'Develop Flutter application',
            result: result,
            isAuditing: false,
            onReaudit: () {
              reauditCalled = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Gemma AI Focus Audit'), findsOneWidget);
    expect(find.text('85%'), findsOneWidget);
    expect(find.text('ON TASK'), findsOneWidget);
    expect(find.text('Develop Flutter application'), findsOneWidget);
    expect(find.text('User is actively developing code in IDE'), findsOneWidget);
    expect(find.text('main.dart - Visual Studio Code [Code Editor / IDE]'), findsOneWidget);
    expect(find.text('main.dart [Code Editor / IDE]'), findsOneWidget);

    await tester.tap(find.text('Re-audit Now'));
    expect(reauditCalled, isTrue);
  });

  testWidgets('FocusVerdictDialog renders off-task verdict accurately', (tester) async {
    final result = FocusVerificationResult(
      matchPercentage: 10.0,
      reason: 'Screen shows social media instead of target objective',
      activeWindowTitle: 'Slack [Communication]',
      openWindowTitles: ['Slack [Communication]'],
      timestamp: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusVerdictDialog(
            currentFocus: 'Working through proof',
            result: result,
            isAuditing: false,
            onReaudit: () {},
          ),
        ),
      ),
    );

    expect(find.text('10%'), findsOneWidget);
    expect(find.text('OFF TASK / DISTRACTED'), findsOneWidget);
    expect(find.text('Screen shows social media instead of target objective'), findsOneWidget);
  });
}
