import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/features/auth/login_screen.dart';
import 'package:neuropulse/features/home/home_screen.dart';

import 'support/test_harness.dart';

void main() {
  testWidgets('register, sign out, then sign in again reaches Home', (
    tester,
  ) async {
    final deps = await TestHarness.pumpApp(
      tester,
      initialPrefs: {'onboarding_seen': true},
    );

    // --- Register -----------------------------------------------------------
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

    expect(find.byType(HomeScreen), findsOneWidget, reason: 'register failed');

    // --- Sign out -----------------------------------------------------------
    await deps.authController.signOut();
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget, reason: 'sign out failed');

    // --- Sign back in with the SAME credentials -----------------------------
    await tester.enterText(
      find.widgetWithText(TextFormField, 'you@example.com'),
      'asha@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'hunter22');

    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();

    final auth = deps.authController;
    expect(
      find.byType(HomeScreen),
      findsOneWidget,
      reason:
          'sign in did nothing. status=${auth.status} '
          'busy=${auth.isBusy} error=${auth.error}',
    );
  });
}
