import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/hrv_feature_grid.dart';
import '../../core/widgets/stress_gauge.dart';
import '../../data/models/measurement_session.dart';
import '../../domain/stress/stress_level.dart';
import '../../state/stress_controller.dart';

/// Everything recorded for one check-in.
class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.session});

  final MeasurementSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stress = context.watch<StressController>();
    final prediction = session.prediction;
    final info = StressLevelConfig.of(prediction.level);

    return Scaffold(
      appBar: AppBar(title: const Text('Session detail')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          child: PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: StressGauge(
                    level: prediction.level,
                    confidence: prediction.confidence,
                    size: 190,
                    reduceMotion: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  Formatters.dateTime(session.recordedAt),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                StressLevelBar(level: prediction.level),
                const SizedBox(height: AppSpacing.xl),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Readings',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (prediction.isDemo) const DemoBadge(),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      HrvFeatureGrid(
                        features: prediction.features,
                        baseline: stress.baseline,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      MeanRrLine(features: prediction.features),
                    ],
                  ),
                ),
                if (session.hasGame) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Activity',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: [
                            Expanded(
                              child: MetricTile(
                                label: 'Game played',
                                value: session.gameName ?? '-',
                                icon: Icons.sports_esports_rounded,
                                compact: true,
                              ),
                            ),
                            Expanded(
                              child: MetricTile(
                                label: 'Game score',
                                value: '${session.gameScore ?? 0}',
                                icon: Icons.star_outline_rounded,
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                        if (session.postStressLevel != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const Divider(),
                          const SizedBox(height: AppSpacing.md),
                          _BeforeAfterRow(
                            before: prediction.level,
                            after: StressLevel.fromNumber(
                              session.postStressLevel!,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Record',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _Row(
                        label: 'Estimated level',
                        value: '${info.number} - ${info.title}',
                      ),
                      _Row(
                        label: 'Confidence',
                        value: '${prediction.confidencePercent}%',
                      ),
                      _Row(
                        label: 'Measurement length',
                        value: '${session.durationSeconds} seconds',
                      ),
                      _Row(
                        label: 'Data source',
                        value: prediction.isDemo
                            ? 'Demo (simulated)'
                            : prediction.source,
                      ),
                      _Row(label: 'Engine', value: prediction.modelVersion),
                      _Row(
                        label: 'Timestamp',
                        value: session.recordedAt.toIso8601String(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Estimated stress level from a student research prototype. '
                  'Not a medical assessment.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BeforeAfterRow extends StatelessWidget {
  const _BeforeAfterRow({required this.before, required this.after});

  final StressLevel before;
  final StressLevel after;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final beforeInfo = StressLevelConfig.of(before);
    final afterInfo = StressLevelConfig.of(after);

    return Row(
      children: [
        Expanded(
          child: MetricTile(
            label: 'Before',
            value: '${beforeInfo.number} - ${beforeInfo.title}',
            icon: beforeInfo.icon,
            accent: beforeInfo.colorOf(context),
            compact: true,
          ),
        ),
        Icon(
          Icons.arrow_forward_rounded,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        Expanded(
          child: MetricTile(
            label: 'After',
            value: '${afterInfo.number} - ${afterInfo.title}',
            icon: afterInfo.icon,
            accent: afterInfo.colorOf(context),
            compact: true,
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
