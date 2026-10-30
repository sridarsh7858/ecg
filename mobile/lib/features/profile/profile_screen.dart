import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../state/auth_controller.dart';
import '../../state/stress_controller.dart';
import '../settings/settings_screen.dart';
import 'baseline_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthController>();
    final stress = context.watch<StressController>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    child: Row(
                      children: [
                        InitialsAvatar(
                          initials: user?.initials ?? '?',
                          seed: user?.email,
                          size: 62,
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.name ?? 'Guest',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user?.email ?? '-',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (user != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                AppChip(
                                  label: 'Age ${user.age}',
                                  icon: Icons.cake_outlined,
                                  dense: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Your activity'),
                  AppCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: MetricTile(
                            label: 'Check-ins',
                            value: '${stress.totalMeasurements}',
                            icon: Icons.checklist_rounded,
                            compact: true,
                          ),
                        ),
                        Expanded(
                          child: MetricTile(
                            label: 'Games',
                            value: '${stress.totalGamesPlayed}',
                            icon: Icons.sports_esports_outlined,
                            compact: true,
                          ),
                        ),
                        Expanded(
                          child: MetricTile(
                            label: 'Calming',
                            value: '${stress.calmingSessionsPlayed}',
                            icon: Icons.spa_outlined,
                            compact: true,
                          ),
                        ),
                        Expanded(
                          child: MetricTile(
                            label: 'Streak',
                            value: '${stress.currentStreak}',
                            icon: Icons.local_fire_department_rounded,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(
                    title: 'Your baseline',
                    subtitle: 'A calm reference point, for context only',
                  ),
                  _BaselineCard(stress: stress),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'System'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _SystemRow(
                          icon: Icons.bluetooth_disabled_rounded,
                          label: 'Device',
                          value: 'Not connected',
                        ),
                        const Divider(height: 1),
                        _SystemRow(
                          icon: Icons.science_outlined,
                          label: 'Data source',
                          value: stress.dataSourceName,
                        ),
                        const Divider(height: 1),
                        _SystemRow(
                          icon: Icons.psychology_outlined,
                          label: 'Model',
                          value:
                              '${stress.engineName} (${stress.modelVersion})',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  OutlinedButton.icon(
                    onPressed: () => _confirmSignOut(context, auth),
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

  Future<void> _confirmSignOut(
    BuildContext context,
    AuthController auth,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Your sessions stay on this device and will be here when you sign '
          'back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await auth.signOut();
  }
}

class _BaselineCard extends StatelessWidget {
  const _BaselineCard({required this.stress});

  final StressController stress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseline = stress.baseline;

    if (baseline == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'You have not set a baseline yet.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'A short calm recording gives your other readings something to '
              'be compared against.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.tonal(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const BaselineScreen())),
              child: const Text('SET MY CALM BASELINE'),
            ),
          ],
        ),
      );
    }

    final current = stress.current?.features;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recorded ${Formatters.relativeDay(baseline.recordedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BaselineScreen()),
                ),
                child: const Text('Update'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _ComparisonHeader(theme: theme),
          const Divider(),
          _ComparisonRow(
            label: 'Heart rate',
            baseline: baseline.hr,
            current: current?.hr,
            unit: 'BPM',
            places: 0,
          ),
          _ComparisonRow(
            label: 'RMSSD',
            baseline: baseline.rmssd,
            current: current?.rmssd,
            unit: 'ms',
          ),
          _ComparisonRow(
            label: 'SDNN',
            baseline: baseline.sdnn,
            current: current?.sdnn,
            unit: 'ms',
          ),
          _ComparisonRow(
            label: 'pNN50',
            baseline: baseline.pnn50,
            current: current?.pnn50,
            unit: '%',
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Shown for context. Your baseline does not change the estimate.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonHeader extends StatelessWidget {
  const _ComparisonHeader({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    return Row(
      children: [
        Expanded(flex: 3, child: Text('', style: style)),
        Expanded(
          flex: 2,
          child: Text('Baseline', textAlign: TextAlign.right, style: style),
        ),
        Expanded(
          flex: 2,
          child: Text('Current', textAlign: TextAlign.right, style: style),
        ),
        Expanded(
          flex: 2,
          child: Text('Diff', textAlign: TextAlign.right, style: style),
        ),
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.label,
    required this.baseline,
    required this.current,
    required this.unit,
    this.places = 1,
  });

  final String label;
  final double baseline;
  final double? current;
  final String unit;
  final int places;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = current;
    final difference = value == null ? null : value - baseline;

    final labelStyle = theme.textTheme.bodySmall;
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label, style: labelStyle)),
          Expanded(
            flex: 2,
            child: Text(
              Formatters.number(baseline, places: places),
              textAlign: TextAlign.right,
              style: valueStyle,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value == null ? '-' : Formatters.number(value, places: places),
              textAlign: TextAlign.right,
              style: valueStyle,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              difference == null
                  ? '-'
                  : Formatters.signed(difference, places: places),
              textAlign: TextAlign.right,
              style: valueStyle?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemRow extends StatelessWidget {
  const _SystemRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(label, style: theme.textTheme.bodyMedium),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
