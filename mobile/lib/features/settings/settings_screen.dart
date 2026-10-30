import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/app_settings.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/stress_controller.dart';
import 'about_screen.dart';
import 'developer_panel_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final stress = context.watch<StressController>();
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'Appearance'),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('Light'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('Dark'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_outlined),
                              label: Text('System'),
                            ),
                          ],
                          selected: {settings.themeMode},
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) =>
                              settings.setThemeMode(selection.first),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SwitchListTile(
                          value: settings.reduceMotion,
                          onChanged: settings.setReduceMotion,
                          title: const Text('Reduce motion'),
                          subtitle: const Text(
                            'Shortens animations. Also follows your system '
                            'setting.',
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Measurement'),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile(
                          value: settings.demoMode,
                          onChanged: settings.setDemoMode,
                          title: const Text('Demo mode'),
                          subtitle: Text(
                            settings.demoMode
                                ? 'Readings are simulated on this device.'
                                : 'Turning this off needs a paired sensor, '
                                      'which is not available yet.',
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        const Divider(),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Measurement duration',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          children: [
                            for (final seconds in AppSettings.durationOptions)
                              ChoiceChip(
                                label: Text('${seconds}s'),
                                selected:
                                    settings.measurementSeconds == seconds,
                                onSelected: (_) =>
                                    settings.setMeasurementSeconds(seconds),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Feedback'),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: settings.soundEnabled,
                          onChanged: settings.setSoundEnabled,
                          title: const Text('Sound'),
                          secondary: const Icon(Icons.volume_up_outlined),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          value: settings.hapticsEnabled,
                          onChanged: settings.setHapticsEnabled,
                          title: const Text('Haptic feedback'),
                          secondary: const Icon(Icons.vibration_outlined),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Data'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.download_outlined),
                          title: const Text('Export data'),
                          subtitle: const Text(
                            'Copy your sessions as JSON to the clipboard',
                          ),
                          onTap: () => _export(context, stress),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.restart_alt_rounded),
                          title: const Text('Reset baseline'),
                          enabled: stress.hasBaseline,
                          subtitle: Text(
                            stress.hasBaseline
                                ? 'Remove your stored calm reference'
                                : 'No baseline recorded yet',
                          ),
                          onTap: stress.hasBaseline
                              ? () => _resetBaseline(context, stress)
                              : null,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          title: Text(
                            'Clear local history',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          subtitle: Text(
                            '${stress.totalMeasurements} check-ins and '
                            '${stress.totalGamesPlayed} game sessions',
                          ),
                          onTap: () => _clearHistory(context, stress),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Developer'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.developer_mode_rounded),
                      title: const Text('Developer / demo mode'),
                      subtitle: const Text(
                        'Select a stress level and inspect the demo engine',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DeveloperPanelScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'About'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.info_outline_rounded),
                          title: const Text('About NeuroPulse'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AboutScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.privacy_tip_outlined),
                          title: const Text('Privacy and disclaimer'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const AboutScreen(showPrivacy: true),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      await auth.signOut();
                      navigator.popUntil((route) => route.isFirst);
                    },
                    icon: const Icon(Icons.logout_rounded, size: 20),
                    label: const Text('LOG OUT'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, StressController stress) async {
    final payload = {
      'exportedAt': DateTime.now().toIso8601String(),
      'engine': stress.modelVersion,
      'measurements': stress.history.map((s) => s.toJson()).toList(),
      'gameSessions': stress.gameSessions.map((s) => s.toJson()).toList(),
      'baseline': stress.baseline?.toJson(),
    };

    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Copied ${stress.totalMeasurements} check-ins to the clipboard',
        ),
      ),
    );
  }

  Future<void> _resetBaseline(
    BuildContext context,
    StressController stress,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await stress.clearBaseline();
    messenger.showSnackBar(const SnackBar(content: Text('Baseline cleared')));
  }

  Future<void> _clearHistory(
    BuildContext context,
    StressController stress,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear local history?'),
        content: const Text(
          'Every saved check-in and game session on this device will be '
          'deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear everything'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await stress.clearHistory();
    messenger.showSnackBar(
      const SnackBar(content: Text('Local history cleared')),
    );
  }
}
