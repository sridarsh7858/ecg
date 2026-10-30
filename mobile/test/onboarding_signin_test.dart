import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/features/home/home_screen.dart';

import 'support/test_harness.dart';

void main() {
  testWidgets('signing in after onboarding reaches Home', (tester) async {
    // No prefs at all: this is a genuinely fresh install, so the app starts
    // on onboarding exactly as it does on a real device.
    await TestHarness.pumpApp(tester);

    // Skip through onboarding.
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Register an account.
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Your name'),
      'Asha Ramesh',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'you@example.com'),
      'asha@example.com',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. 21'), '21');
    await tester.enterText(find.byType(TextFormField).last, 'hunter22');

    await tester.tap(find.text('CREATE ACCOUNT'));
    await tester.pumpAndSettle();

    expect(
      find.byType(HomeScreen),
      findsOneWidget,
      reason: 'registering after onboarding should land on Home',
    );
  });
}
