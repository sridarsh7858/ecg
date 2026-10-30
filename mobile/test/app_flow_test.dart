import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/domain/stress/stress_level.dart';
import 'package:neuropulse/features/auth/login_screen.dart';
import 'package:neuropulse/features/games/games_screen.dart';
import 'package:neuropulse/features/history/history_screen.dart';
import 'package:neuropulse/features/home/home_screen.dart';
import 'package:neuropulse/features/measure/measure_screen.dart';
import 'package:neuropulse/features/onboarding/onboarding_screen.dart';
import 'package:neuropulse/features/profile/profile_screen.dart';
import 'package:neuropulse/features/settings/developer_panel_screen.dart';

import 'support/test_harness.dart';

void main() {
  group('onboarding and auth', () {
    testWidgets('a first run starts at onboarding', (tester) async {
      await TestHarness.pumpApp(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Welcome to NeuroPulse'), findsOneWidget);
    });

    testWidgets('skipping onboarding lands on sign in', (tester) async {
      await TestHarness.pumpApp(tester);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('registering signs the user in and opens Home', (tester) async {
      await TestHarness.pumpApp(
        tester,
        initialPrefs: {'onboarding_seen': true},
      );

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
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. 21'),
        '21',
      );
      await tester.enterText(find.byType(TextFormField).last, 'hunter22');

      await tester.tap(find.text('CREATE ACCOUNT'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.textContaining('Asha'), findsWidgets);
    });

    testWidgets('signing in with a wrong password shows an error', (
      tester,
    ) async {
      await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs()..remove('current_user_id'),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'you@example.com'),
        'asha@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'wrongpass');
      await tester.tap(find.text('SIGN IN'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.textContaining('password'), findsWidgets);
    });

    testWidgets('a signed-in user goes straight to Home', (tester) async {
      await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('CURRENT STRESS'), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('the bottom bar reaches all five sections', (tester) async {
      await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );

      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(NavigationDestination, 'Measure'));
      await tester.pumpAndSettle();
      expect(find.byType(MeasureScreen), findsOneWidget);
      expect(find.text('Ready to check in?'), findsOneWidget);

      await tester.tap(find.widgetWithText(NavigationDestination, 'Games'));
      await tester.pumpAndSettle();
      expect(find.byType(GamesScreen), findsOneWidget);
      expect(find.text('Choose an activity'), findsOneWidget);

      await tester.tap(find.widgetWithText(NavigationDestination, 'History'));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(NavigationDestination, 'Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });

  group('home dashboard', () {
    testWidgets('shows the greeting, estimate and the four HRV values', (
      tester,
    ) async {
      await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );

      expect(find.textContaining('Asha'), findsWidgets);
      expect(find.text('CURRENT STRESS'), findsOneWidget);
      expect(find.text('Heart Rate'), findsWidgets);
      expect(find.text('RMSSD'), findsWidgets);
      expect(find.text('SDNN'), findsWidgets);
      expect(find.text('pNN50'), findsWidgets);
      expect(find.text('Recommended for you'), findsOneWidget);
      expect(find.text('PLAY NOW'), findsOneWidget);
    });

    testWidgets('labels the readings as demo data', (tester) async {
      await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );
      expect(find.text('Demo data'), findsWidgets);
    });
  });

  group('demo mode drives the whole app', () {
    testWidgets('every level renders on Home with its own recommendation', (
      tester,
    ) async {
      final deps = await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );
      final stress = deps.stressController;

      for (final level in StressLevel.values) {
        await stress.setDemoLevel(level);
        await tester.pumpAndSettle();

        final info = StressLevelConfig.of(level);
        expect(
          stress.currentLevel,
          level,
          reason: 'controller should hold level ${level.number}',
        );
        expect(find.text('${info.number}'), findsWidgets);
        expect(find.text(info.upperTitle), findsWidgets);
        expect(
          find.text(stress.recommendation.primary.name),
          findsWidgets,
          reason: 'recommendation for level ${level.number}',
        );
      }
    });

    testWidgets('the developer panel switches level and the app follows', (
      tester,
    ) async {
      final deps = await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );

      await tester.tap(find.byTooltip('Settings').first);
      await tester.pumpAndSettle();
      // ensureVisible scrolls the widget's own Scrollable. scrollUntilVisible
      // would pick the first Scrollable in the tree, which is a tab still
      // mounted behind the pushed route.
      await tester.ensureVisible(find.text('Developer / demo mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Developer / demo mode'));
      await tester.pumpAndSettle();

      expect(find.byType(DeveloperPanelScreen), findsOneWidget);
      expect(find.text('DEMO INPUT'), findsOneWidget);

      // The panel now carries the data-source, engine and live-packet
      // sections above the level list, so the option has to be scrolled to.
      await tester.ensureVisible(find.text('Very High'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Very High'));
      await tester.pumpAndSettle();

      expect(deps.stressController.demoLevel, StressLevel.veryHigh);
      expect(deps.stressController.currentLevel, StressLevel.veryHigh);
      expect(deps.stressController.recommendation.primary.id, 'calm_breathing');
    });
  });

  group('history', () {
    testWidgets('shows an empty state before any check-in', (tester) async {
      await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );

      await tester.tap(find.widgetWithText(NavigationDestination, 'History'));
      await tester.pumpAndSettle();

      expect(find.text('No sessions yet'), findsOneWidget);
    });

    testWidgets('lists saved sessions and the trend charts', (tester) async {
      final deps = await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );

      final prediction = await deps.stressController.refreshCurrent();
      await deps.stressController.saveMeasurement(
        prediction,
        durationSeconds: 30,
      );

      await tester.tap(find.widgetWithText(NavigationDestination, 'History'));
      await tester.pumpAndSettle();

      expect(find.text('No sessions yet'), findsNothing);
      expect(find.text('Stress trend'), findsOneWidget);
      expect(find.text('Heart rate'), findsOneWidget);
      expect(find.text('RMSSD'), findsOneWidget);
      expect(find.text('7 Days'), findsOneWidget);
      expect(find.text('30 Days'), findsOneWidget);
      expect(find.text('90 Days'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      expect(find.textContaining('Today at'), findsOneWidget);
    });
  });

  group('profile', () {
    testWidgets('reports the account, engine and device state', (tester) async {
      await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );

      await tester.tap(find.widgetWithText(NavigationDestination, 'Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Asha Ramesh'), findsOneWidget);
      expect(find.text('asha@example.com'), findsOneWidget);
      expect(find.text('Age 21'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Demo Mode'), findsOneWidget);
      expect(find.textContaining('Demo Stress Engine'), findsOneWidget);
      expect(find.text('SET MY CALM BASELINE'), findsOneWidget);
    });

    testWidgets('a saved baseline appears with a comparison', (tester) async {
      final deps = await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );

      await deps.stressController.setBaselineFromFeatures(
        deps.stressController.generateDemoFeatures(),
      );

      await tester.tap(find.widgetWithText(NavigationDestination, 'Profile'));
      await tester.pumpAndSettle();

      expect(find.text('SET MY CALM BASELINE'), findsNothing);
      expect(find.text('Baseline'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Diff'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('switching to dark theme repaints the app', (tester) async {
      final deps = await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );

      await tester.tap(find.byTooltip('Settings').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(deps.settingsController.themeMode, ThemeMode.dark);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
    });

    testWidgets('measurement duration is configurable', (tester) async {
      final deps = await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );

      await tester.tap(find.byTooltip('Settings').first);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('45s'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('45s'));
      await tester.pumpAndSettle();

      expect(deps.settingsController.measurementSeconds, 45);
    });
  });
}
