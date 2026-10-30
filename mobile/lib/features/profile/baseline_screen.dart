import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/dependencies.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/hrv_feature_grid.dart';
import '../../data/models/physiological_features.dart';
import '../../domain/physiological/physiological_data_source.dart';
import '../../state/stress_controller.dart';

/// Records a calm reference point.
///
/// It runs the same capture as a check-in but skips the estimate: the baseline
/// is stored for comparison only and is deliberately not fed to the prediction
/// engine.
class BaselineScreen extends StatefulWidget {
  const BaselineScreen({super.key});

  @override
  State<BaselineScreen> createState() => _BaselineScreenState();
}

class _BaselineScreenState extends State<BaselineScreen> {
  PhysiologicalDataSource? _source;
  PhysiologicalFeatures? _captured;
  double _progress = 0;
  bool _running = false;
  bool _saved = false;

  /// A baseline is a short recording; a full check-in length is not needed.
  static const Duration _captureDuration = Duration(seconds: 20);

  Future<void> _capture() async {
    final source = _source ??= context.read<AppDependencies>().activeDataSource;

    setState(() {
      _running = true;
      _saved = false;
      _captured = null;
      _progress = 0;
    });

    await for (final tick in source.measure(_captureDuration)) {
      if (!mounted) return;
      setState(() => _progress = tick.progress);
    }

    final features = await source.readFeatures();
    if (!mounted) return;
    setState(() {
      _captured = features;
      _running = false;
      _progress = 1;
    });
  }

  Future<void> _save() async {
    final features = _captured;
    if (features == null) return;

    await context.read<StressController>().setBaselineFromFeatures(features);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Baseline saved')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stress = context.watch<StressController>();
    final captured = _captured;

    return Scaffold(
      appBar: AppBar(title: const Text('Set my calm baseline')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          child: PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Find a quiet moment',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Sit still and breathe normally for '
                  '${_captureDuration.inSeconds} seconds. What we record '
                  'becomes the reference your later readings are compared '
                  'against.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (stress.hasBaseline && captured == null)
                  AppCard(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Recording a new baseline replaces the one you '
                            'already have.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_running) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    child: Column(
                      children: [
                        Text(
                          'Recording',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 10,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          '${(_progress * 100).round()}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (captured != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Captured baseline',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (captured.isDemo) const DemoBadge(),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        HrvFeatureGrid(features: captured),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                if (captured == null)
                  FilledButton.icon(
                    onPressed: _running ? null : _capture,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      _running ? 'RECORDING...' : 'START BASELINE RECORDING',
                    ),
                  )
                else ...[
                  FilledButton.icon(
                    onPressed: _saved ? null : _save,
                    icon: Icon(
                      _saved
                          ? Icons.check_circle_rounded
                          : Icons.bookmark_add_outlined,
                    ),
                    label: Text(_saved ? 'BASELINE SAVED' : 'SAVE BASELINE'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: _running ? null : _capture,
                    child: const Text('RECORD AGAIN'),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Demo mode is on, so this ${_captureDuration.inSeconds} '
                  'second recording is simulated. Your baseline is used for '
                  'comparison only and does not change your estimated level.',
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
