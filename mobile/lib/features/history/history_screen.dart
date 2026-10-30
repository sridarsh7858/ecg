import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/trend_chart.dart';
import '../../data/models/measurement_session.dart';
import '../../domain/stress/stress_level.dart';
import '../../state/stress_controller.dart';
import '../shell/main_shell.dart';
import 'session_detail_screen.dart';

/// Time windows offered by the filter chips.
enum HistoryRange {
  week(7, '7 Days'),
  month(30, '30 Days'),
  quarter(90, '90 Days');

  const HistoryRange(this.days, this.label);

  final int days;
  final String label;
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  HistoryRange _range = HistoryRange.month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stress = context.watch<StressController>();

    // Oldest first for the charts, newest first for the list.
    final inRange = stress.historyWithin(_range.days);
    final newestFirst = inRange.reversed.toList();

    if (stress.history.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('History')),
        body: EmptyState(
          icon: Icons.insights_outlined,
          title: 'No sessions yet',
          message:
              'Complete a check-in and it will appear here, along with '
              'your trends over time.',
          action: FilledButton.icon(
            onPressed: () => MainShell.goToTab(context, MainShell.measureTab),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('START A CHECK-IN'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RangeSelector(
                    selected: _range,
                    onChanged: (range) => setState(() => _range = range),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SummaryRow(sessions: inRange),
                  const SizedBox(height: AppSpacing.lg),
                  TrendChartCard(
                    title: 'Stress trend',
                    subtitle:
                        'Estimated level over the last '
                        '${_range.days} days',
                    color: theme.colorScheme.primary,
                    minY: 1,
                    maxY: 5,
                    yLabelBuilder: (value) => value.toStringAsFixed(0),
                    points: [
                      for (final session in inRange)
                        TrendPoint(
                          time: session.recordedAt,
                          value: session.prediction.levelNumber.toDouble(),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TrendChartCard(
                    title: 'Heart rate',
                    subtitle: 'Beats per minute at each check-in',
                    color: AppColors.level5,
                    yLabelBuilder: (value) => value.toStringAsFixed(0),
                    points: [
                      for (final session in inRange)
                        TrendPoint(
                          time: session.recordedAt,
                          value: session.prediction.features.hr,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TrendChartCard(
                    title: 'RMSSD',
                    subtitle: 'Short-term variability, in milliseconds',
                    color: AppColors.level1,
                    yLabelBuilder: (value) => value.toStringAsFixed(0),
                    points: [
                      for (final session in inRange)
                        TrendPoint(
                          time: session.recordedAt,
                          value: session.prediction.features.rmssd,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SectionHeader(
                    title: 'Sessions',
                    subtitle: '${newestFirst.length} in this period',
                  ),
                  if (newestFirst.isEmpty)
                    AppCard(
                      child: Text(
                        'No check-ins in the last ${_range.days} days. Try a '
                        'longer period.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final session in newestFirst) ...[
                      _SessionCard(session: session),
                      const SizedBox(height: AppSpacing.md),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.selected, required this.onChanged});

  final HistoryRange selected;
  final ValueChanged<HistoryRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<HistoryRange>(
      segments: [
        for (final range in HistoryRange.values)
          ButtonSegment(value: range, label: Text(range.label)),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.sessions});

  final List<MeasurementSession> sessions;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return const SizedBox.shrink();

    final levels = sessions
        .map((s) => s.prediction.levelNumber)
        .toList(growable: false);
    final average = levels.reduce((a, b) => a + b) / levels.length;
    final lowest = levels.reduce((a, b) => a < b ? a : b);
    final gamesPlayed = sessions.where((s) => s.hasGame).length;

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: MetricTile(
              label: 'Check-ins',
              value: '${sessions.length}',
              icon: Icons.checklist_rounded,
              compact: true,
            ),
          ),
          Expanded(
            child: MetricTile(
              label: 'Average level',
              value: average.toStringAsFixed(1),
              icon: Icons.stacked_line_chart_rounded,
              compact: true,
            ),
          ),
          Expanded(
            child: MetricTile(
              label: 'Calmest',
              value: '$lowest',
              icon: Icons.spa_outlined,
              compact: true,
            ),
          ),
          Expanded(
            child: MetricTile(
              label: 'With a game',
              value: '$gamesPlayed',
              icon: Icons.sports_esports_outlined,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final MeasurementSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = StressLevelConfig.of(session.prediction.level);
    final accent = info.colorOf(context);
    final features = session.prediction.features;

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SessionDetailScreen(session: session),
        ),
      ),
      semanticLabel:
          'Session on ${Formatters.date(session.recordedAt)}, '
          'level ${info.number}, ${info.title}',
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(info.icon, size: 14, color: accent),
                    Text(
                      '${info.number}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: accent,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${Formatters.relativeDay(session.recordedAt)} at '
                      '${Formatters.time(session.recordedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _MiniStat(
                icon: Icons.favorite_rounded,
                value: '${Formatters.number(features.hr, places: 0)} BPM',
              ),
              const SizedBox(width: AppSpacing.md),
              _MiniStat(
                icon: Icons.show_chart_rounded,
                value: '${Formatters.number(features.rmssd)} ms',
              ),
              const SizedBox(width: AppSpacing.md),
              _MiniStat(
                icon: Icons.timer_outlined,
                value: '${session.durationSeconds}s',
              ),
            ],
          ),
          if (session.hasGame) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppChip(
                    label: session.gameName ?? 'Game played',
                    icon: Icons.sports_esports_rounded,
                    color: theme.colorScheme.primary,
                    dense: true,
                  ),
                ),
                if (session.postStressLevel != null)
                  Text(
                    'Level ${session.prediction.levelNumber} to '
                    '${session.postStressLevel}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
