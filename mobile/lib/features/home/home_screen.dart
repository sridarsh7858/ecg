import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/motion.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/hrv_feature_grid.dart';
import '../../core/widgets/source_badge.dart';
import '../../core/widgets/stress_gauge.dart';
import '../../data/models/physiological_input_packet.dart';
import '../../domain/stress/stress_level.dart';
import '../../state/auth_controller.dart';
import '../../state/device_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/stress_controller.dart';
import '../devices/devices_screen.dart';
import '../games/game_launcher.dart';
import '../games/widgets/game_card.dart';
import '../profile/baseline_screen.dart';
import '../settings/settings_screen.dart';
import '../shell/main_shell.dart';

/// The dashboard: current estimate, the numbers behind it, and what to do next.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stress = context.watch<StressController>();
    final settings = context.watch<SettingsController>();
    final user = context.watch<AuthController>().user;

    final prediction = stress.current;
    final info = stress.currentInfo;
    final recommendation = stress.recommendation;
    final reduceMotion =
        settings.reduceMotion ||
        AppMotion.platformPrefersReducedMotion(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => stress.refreshCurrent(persist: true),
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              PageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    _Greeting(name: user?.firstName ?? 'there'),
                    const SizedBox(height: AppSpacing.xl),
                    _CurrentStressCard(
                      info: info,
                      confidence: prediction?.confidence,
                      isDemo: prediction?.isDemo ?? true,
                      reduceMotion: reduceMotion,
                      onMeasure: () =>
                          MainShell.goToTab(context, MainShell.measureTab),
                    ),
                    if (prediction != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _VitalsCard(
                        stress: stress,
                        onSetBaseline: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const BaselineScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _OptionalSignalsCard(packet: stress.currentPacket),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    DeviceStatusCard(
                      status: context.watch<DeviceController>().status,
                      showCapabilities: false,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DevicesScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const SectionHeader(
                      title: 'Recommended for you',
                      subtitle: 'Chosen for your current estimate',
                    ),
                    RecommendedGameCard(
                      game: recommendation.primary,
                      reason: recommendation.reason,
                      onPlay: () =>
                          GameLauncher.play(context, recommendation.primary),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _QuickActions(stress: stress),
                    const SizedBox(height: AppSpacing.xl),
                    _DisclaimerNote(theme: theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${Formatters.greeting()}, $name',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 2),
              Text(
                Formatters.weekdayDate(DateTime.now()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }
}

class _CurrentStressCard extends StatelessWidget {
  const _CurrentStressCard({
    required this.info,
    required this.confidence,
    required this.isDemo,
    required this.reduceMotion,
    required this.onMeasure,
  });

  final StressLevelInfo info;
  final double? confidence;
  final bool isDemo;
  final bool reduceMotion;
  final VoidCallback onMeasure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'CURRENT STRESS',
                  style: theme.textTheme.labelMedium?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (isDemo) const DemoBadge(),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          StressGauge(
            level: info.level,
            confidence: confidence,
            reduceMotion: reduceMotion,
            size: 210,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            info.description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            info.recommendation,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onMeasure,
              icon: const Icon(Icons.monitor_heart_outlined, size: 20),
              label: const Text('NEW CHECK-IN'),
            ),
          ),
        ],
      ),
    );
  }
}

class _VitalsCard extends StatelessWidget {
  const _VitalsCard({required this.stress, required this.onSetBaseline});

  final StressController stress;
  final VoidCallback onSetBaseline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prediction = stress.current!;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Your readings',
            subtitle: stress.hasBaseline
                ? 'Compared with your calm baseline'
                : 'Heart rate variability features',
            action: stress.hasBaseline
                ? null
                : TextButton(
                    onPressed: onSetBaseline,
                    child: const Text('Set baseline'),
                  ),
          ),
          HrvFeatureGrid(
            features: prediction.features,
            baseline: stress.baseline,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          // A Wrap rather than a Row: on a narrow phone the source label
          // moves onto its own line instead of overflowing.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              MeanRrLine(features: prediction.features),
              Text(
                prediction.isDemo ? 'Demo / simulated data' : 'Sensor data',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.stress});

  final StressController stress;

  @override
  Widget build(BuildContext context) {
    final average = stress.averageLevel();

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.local_fire_department_rounded,
            label: 'Day streak',
            value: '${stress.currentStreak}',
            onTap: () => MainShell.goToTab(context, MainShell.historyTab),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatCard(
            icon: Icons.checklist_rounded,
            label: 'Check-ins',
            value: '${stress.totalMeasurements}',
            onTap: () => MainShell.goToTab(context, MainShell.historyTab),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatCard(
            icon: Icons.trending_down_rounded,
            label: '7-day avg',
            value: average == null ? '-' : average.toStringAsFixed(1),
            onTap: () => MainShell.goToTab(context, MainShell.historyTab),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      semanticLabel: '$label $value',
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerNote extends StatelessWidget {
  const _DisclaimerNote({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      'NeuroPulse gives an estimated stress level for a student research '
      'prototype. It is not a medical device.',
      textAlign: TextAlign.center,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
      ),
    );
  }
}


/// GSR and movement for the current reading.
///
/// Both are optional sensors, so this card's real job is to distinguish
/// "measured and here is the value" from "this sensor was not present". It
/// never shows a number for a sensor that did not report one.
///
/// Movement is labelled as context, not as stress. High movement means the
/// reading may contain motion artefact and that the user was active - it is
/// never presented as evidence of being stressed.
class _OptionalSignalsCard extends StatelessWidget {
  const _OptionalSignalsCard({required this.packet});

  final PhysiologicalInputPacket? packet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final gsr = packet?.gsrLevel ?? packet?.gsrValue;
    final gsrPeaks = packet?.gsrPeaks;
    final movement = packet?.effectiveMovementIntensity;
    final movementLabel = packet?.movementLabel;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Other signals',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (packet != null) SourceBadge(source: packet!.source),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SignalRow(
            icon: Icons.water_drop_outlined,
            label: 'GSR / EDA',
            value: gsr == null
                ? 'Not available'
                : '${gsr.toStringAsFixed(2)} uS'
                      '${gsrPeaks != null ? '  ·  $gsrPeaks peaks' : ''}',
            available: gsr != null,
          ),
          const SizedBox(height: AppSpacing.sm),
          _SignalRow(
            icon: Icons.directions_walk_outlined,
            label: 'Movement',
            value: movement == null
                ? 'Not available'
                : '$movementLabel  ·  ${(movement * 100).round()}%',
            available: movement != null,
          ),
          if (packet?.hasMotionArtefactRisk ?? false) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: scheme.tertiary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'You were moving during this reading, so the signal may '
                    'contain artefact. This is about data quality - it does '
                    'not mean you were stressed.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.available,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: available ? scheme.primary : scheme.outline,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: available ? scheme.onSurface : scheme.onSurfaceVariant,
            fontStyle: available ? FontStyle.normal : FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
