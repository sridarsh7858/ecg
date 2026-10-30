import 'package:flutter/material.dart' hide Baseline;

import '../../data/models/baseline.dart';
import '../../data/models/physiological_features.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import 'app_widgets.dart';

/// The four HRV values, laid out as a responsive 2-column grid.
///
/// Used on Home, the result screen and session details so the numbers are
/// always presented the same way.
class HrvFeatureGrid extends StatelessWidget {
  const HrvFeatureGrid({
    super.key,
    required this.features,
    this.baseline,
    this.compact = false,
  });

  final PhysiologicalFeatures features;

  /// When provided, each tile also shows the delta against the baseline.
  final Baseline? baseline;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final comparison = baseline?.compare(features);

    final tiles = <Widget>[
      MetricTile(
        label: 'Heart Rate',
        value: Formatters.number(features.hr, places: 0),
        unit: 'BPM',
        icon: Icons.favorite_rounded,
        accent: AppColors.level5,
        compact: compact,
        caption: comparison == null
            ? null
            : '${Formatters.signed(comparison.hrDelta, places: 0)} vs baseline',
      ),
      MetricTile(
        label: 'RMSSD',
        value: Formatters.number(features.rmssd),
        unit: 'ms',
        icon: Icons.show_chart_rounded,
        accent: AppColors.level1,
        compact: compact,
        caption: comparison == null
            ? null
            : '${Formatters.signed(comparison.rmssdDelta)} vs baseline',
      ),
      MetricTile(
        label: 'SDNN',
        value: Formatters.number(features.sdnn),
        unit: 'ms',
        icon: Icons.timeline_rounded,
        accent: AppColors.info,
        compact: compact,
        caption: comparison == null
            ? null
            : '${Formatters.signed(comparison.sdnnDelta)} vs baseline',
      ),
      MetricTile(
        label: 'pNN50',
        value: Formatters.number(features.pnn50),
        unit: '%',
        icon: Icons.percent_rounded,
        accent: AppColors.level3,
        compact: compact,
        caption: comparison == null
            ? null
            : '${Formatters.signed(comparison.pnn50Delta)} vs baseline',
      ),
    ];

    // A plain two-column wrap rather than a GridView: it sizes to content, so
    // the optional baseline caption cannot cause an overflow.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - AppSpacing.lg) / 2;
        return Wrap(
          spacing: AppSpacing.lg,
          runSpacing: compact ? AppSpacing.md : AppSpacing.lg,
          children: [
            for (final tile in tiles) SizedBox(width: columnWidth, child: tile),
          ],
        );
      },
    );
  }
}

/// Single-line summary of the mean R-R interval, shown under the grid.
class MeanRrLine extends StatelessWidget {
  const MeanRrLine({super.key, required this.features});

  final PhysiologicalFeatures features;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.straighten_rounded,
          size: 15,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            'Mean R-R  ${Formatters.number(features.meanRR, places: 0)} ms',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
