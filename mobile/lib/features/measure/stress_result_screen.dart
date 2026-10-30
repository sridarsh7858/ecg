import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/motion.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/hrv_feature_grid.dart';
import '../../core/widgets/stress_gauge.dart';
import '../../data/models/measurement_session.dart';
import '../../data/models/stress_prediction.dart';
import '../../domain/stress/stress_level.dart';
import '../../state/settings_controller.dart';
import '../../state/stress_controller.dart';
import '../games/game_launcher.dart';
import '../games/widgets/game_card.dart';

/// Shown straight after a check-in completes.
class StressResultScreen extends StatefulWidget {
  const StressResultScreen({
    super.key,
    required this.prediction,
    required this.durationSeconds,
  });

  final StressPrediction prediction;
  final int durationSeconds;

  @override
  State<StressResultScreen> createState() => _StressResultScreenState();
}

class _StressResultScreenState extends State<StressResultScreen> {
  MeasurementSession? _saved;
  bool _saving = false;
  bool _showDetails = false;

  bool get _isSaved => _saved != null;

  Future<MeasurementSession?> _save() async {
    if (_isSaved) return _saved;
    setState(() => _saving = true);

    final session = await context.read<StressController>().saveMeasurement(
      widget.prediction,
      durationSeconds: widget.durationSeconds,
    );

    if (!mounted) return session;
    setState(() {
      _saved = session;
      _saving = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Session saved to History')));
    return session;
  }

  /// Saving first means the play-through can be linked to this check-in, which
  /// is what produces the before/after pair in History.
  Future<void> _playRecommended() async {
    final session = await _save();
    if (!mounted) return;

    final recommendation = context.read<StressController>().recommendation;
    await GameLauncher.play(
      context,
      recommendation.primary,
      measurementId: session?.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stress = context.watch<StressController>();
    final settings = context.watch<SettingsController>();
    final prediction = widget.prediction;
    final info = StressLevelConfig.of(prediction.level);
    final recommendation = stress.recommendationService.recommendFor(
      prediction.level,
    );
    final reduceMotion =
        settings.reduceMotion ||
        AppMotion.platformPrefersReducedMotion(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your result'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          child: PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'YOUR CURRENT STRESS',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: StressGauge(
                    level: prediction.level,
                    confidence: prediction.confidence,
                    reduceMotion: reduceMotion,
                    size: 232,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: AppChip(
                    label: 'Estimated stress level',
                    icon: Icons.insights_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                    dense: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Readings from this session',
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
                      if (_showDetails) ...[
                        const SizedBox(height: AppSpacing.lg),
                        const Divider(),
                        const SizedBox(height: AppSpacing.md),
                        _DetailRows(prediction: prediction),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _showDetails = !_showDetails),
                          icon: Icon(
                            _showDetails
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 20,
                          ),
                          label: Text(
                            _showDetails ? 'HIDE DETAILS' : 'VIEW DETAILS',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  color: info.colorOf(context).withValues(alpha: 0.10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(info.icon, color: info.colorOf(context)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info.recommendation,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              info.motivation,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RecommendedGameCard(
                  game: recommendation.primary,
                  reason: recommendation.reason,
                  buttonLabel: 'PLAY RECOMMENDED GAME',
                  onPlay: _playRecommended,
                ),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton.icon(
                  onPressed: _isSaved || _saving ? null : _save,
                  icon: Icon(
                    _isSaved
                        ? Icons.check_circle_rounded
                        : Icons.bookmark_add_outlined,
                    size: 20,
                  ),
                  label: Text(_isSaved ? 'SESSION SAVED' : 'SAVE SESSION'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Estimated by ${stress.engineName} '
                  '(${prediction.modelVersion}). Not a medical assessment.',
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

/// The extra rows revealed by "View details".
class _DetailRows extends StatelessWidget {
  const _DetailRows({required this.prediction});

  final StressPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final features = prediction.features;
    return Column(
      children: [
        _DetailRow(
          label: 'Mean R-R interval',
          value: '${Formatters.number(features.meanRR, places: 0)} ms',
        ),
        _DetailRow(
          label: 'Confidence',
          value: '${prediction.confidencePercent}%',
        ),
        _DetailRow(label: 'Engine', value: prediction.modelVersion),
        _DetailRow(
          label: 'Data source',
          value: prediction.isDemo ? 'Demo (simulated)' : prediction.source,
        ),
        _DetailRow(
          label: 'Recorded',
          value: Formatters.dateTime(prediction.timestamp),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

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
          Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
