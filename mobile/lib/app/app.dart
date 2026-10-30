import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../data/local/local_store.dart';
import '../features/auth/login_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/shell/main_shell.dart';
import '../state/auth_controller.dart';
import '../state/device_controller.dart';
import '../state/measurement_mode_controller.dart';
import '../state/settings_controller.dart';
import '../state/stress_controller.dart';
import 'dependencies.dart';

/// Root widget: provides the controllers and applies the theme.
class NeuroPulseApp extends StatelessWidget {
  const NeuroPulseApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDependencies>.value(value: dependencies),
        Provider<LocalStore>.value(value: dependencies.store),
        ChangeNotifierProvider<SettingsController>.value(
          value: dependencies.settingsController,
        ),
        ChangeNotifierProvider<AuthController>.value(
          value: dependencies.authController,
        ),
        ChangeNotifierProvider<StressController>.value(
          value: dependencies.stressController,
        ),
        ChangeNotifierProvider<DeviceController>.value(
          value: dependencies.deviceController,
        ),
        ChangeNotifierProvider<MeasurementModeController>.value(
          value: dependencies.modeController,
        ),
      ],
      child: Consumer<SettingsController>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'NeuroPulse',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            home: const RootGate(),
          );
        },
      ),
    );
  }
}

/// Decides the first screen: onboarding, then sign-in, then the app shell.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (auth.status == AuthStatus.unknown) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!auth.hasSeenOnboarding) return const OnboardingScreen();
    if (!auth.isSignedIn) return const LoginScreen();
    return const MainShell();
  }
}
