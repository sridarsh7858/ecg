import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/hrv_feature_grid.dart';
import '../../app/dependencies.dart';
import '../../core/widgets/source_badge.dart';
import '../../data/models/stress_prediction.dart';
import '../../domain/physiological/physiological_data_source.dart';
import '../../domain/stress/ml_stress_prediction_service.dart';
import '../../domain/stress/stress_feature_vector.dart';
import '../../domain/stress/stress_level.dart';
import '../../domain/stress/stress_scoring.dart';
import '../../state/device_controller.dart';
import '../../state/measurement_mode_controller.dart';
import '../../state/stress_controller.dart';
import '../devices/devices_screen.dart';
import '../games/game_launcher.dart';

/// Developer and demo controls.
///
/// Selecting a level here changes the level the demo data source simulates,
/// which the whole app then reflects: dashboard, recommendation, measurement,
/// result screen and saved history. Nothing in this screen is intended for end
/// users - it exists for development and for demonstrating the project.
class DeveloperPanelScreen extends StatefulWidget {
  const DeveloperPanelScreen({super.key});

  @override
  State<DeveloperPanelScreen> createState() => _DeveloperPanelScreenState();
}

class _DeveloperPanelScreenState extends State<DeveloperPanelScreen> {
  StressPrediction? _preview;
  bool _busy = false;

  Future<void> _selectLevel(StressLevel level) async {
    setState(() => _busy = true);
    final stress = context.read<StressController>();
    await stress.setDemoLevel(level);
    if (!mounted) return;
    setState(() {
      _preview = stress.current;
      _busy = false;
    });
  }

  /// Generates a fresh feature vector and shows what the engine makes of it,
  /// without disturbing the stored state.
  Future<void> _previewVector() async {
    final stress = context.read<StressController>();
    final features = stress.generateDemoFeatures();
    final prediction = await stress.predictOnly(features);
    if (!mounted) return;
    setState(() => _preview = prediction);
  }

  Future<void> _generateMeasurement() async {
    final stress = context.read<StressController>();
    final messenger = ScaffoldMessenger.of(context);
    final prediction = await stress.refreshCurrent(persist: true);
    await stress.saveMeasurement(prediction, durationSeconds: 30);
    if (!mounted) return;
    setState(() => _preview = prediction);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Saved a level ${prediction.levelNumber} check-in'),
      ),
    );
  }

  Future<void> _seedHistory() async {
    setState(() => _busy = true);
    final stress = context.read<StressController>();
    final messenger = ScaffoldMessenger.of(context);
    await stress.seedDemoHistory();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text('History now has ${stress.totalMeasurements} sessions'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stress = context.watch<StressController>();
    final preview = _preview ?? stress.current;
    final recommendation = stress.recommendation;

    return Scaffold(
      appBar: AppBar(title: const Text('Developer / demo')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    color: theme.colorScheme.tertiaryContainer,
                    child: Row(
                      children: [
                        Icon(
                          Icons.developer_mode_rounded,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'DEVELOPER / DEMO MODE. These controls drive the '
                            'simulated data and are not part of the user '
                            'experience.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _DataSourcePanel(),
                  const SizedBox(height: AppSpacing.xl),
                  const _EnginePanel(),
                  const SizedBox(height: AppSpacing.xl),
                  const _LivePacketPanel(),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(
                    title: 'Select stress level',
                    subtitle: 'The whole app follows this selection',
                  ),
                  for (final info in StressLevelConfig.all) ...[
                    _LevelOption(
                      info: info,
                      selected: stress.demoLevel == info.level,
                      enabled: !_busy,
                      onTap: () => _selectLevel(info.level),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(title: 'Current demo feature vector'),
                  if (preview == null)
                    const AppCard(child: Text('No prediction generated yet.'))
                  else
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'DEMO INPUT',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    letterSpacing: 1.4,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const DemoBadge(),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          HrvFeatureGrid(
                            features: preview.features,
                            compact: true,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const Divider(),
                          const SizedBox(height: AppSpacing.md),
                          _KeyValue(
                            label: 'Arousal score',
                            value: StressScoring.score(
                              preview.features,
                            ).toStringAsFixed(3),
                          ),
                          _KeyValue(
                            label: 'Predicted',
                            value:
                                'Level ${preview.levelNumber} - '
                                '${preview.label}',
                          ),
                          _KeyValue(
                            label: 'Confidence',
                            value: '${preview.confidencePercent}%',
                          ),
                          _KeyValue(
                            label: 'Engine',
                            value: preview.modelVersion,
                          ),
                          _KeyValue(label: 'Source', value: preview.source),
                          _KeyValue(
                            label: 'Timestamp',
                            value: Formatters.time(preview.timestamp),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(title: 'Actions'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.refresh_rounded),
                          title: const Text('View current dummy vector'),
                          subtitle: const Text(
                            'Regenerate features and re-run the engine',
                          ),
                          onTap: _busy ? null : _previewVector,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.add_chart_rounded),
                          title: const Text('Generate demo measurement'),
                          subtitle: const Text('Saves a check-in to History'),
                          onTap: _busy ? null : _generateMeasurement,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.auto_graph_rounded),
                          title: const Text('Seed 60 days of history'),
                          subtitle: const Text(
                            'Fills the charts with generated sessions',
                          ),
                          onTap: _busy ? null : _seedHistory,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.sports_esports_rounded),
                          title: const Text('Test recommended game'),
                          subtitle: Text(
                            'Currently ${recommendation.primary.name}',
                          ),
                          onTap: _busy
                              ? null
                              : () => GameLauncher.play(
                                  context,
                                  recommendation.primary,
                                ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.restart_alt_rounded),
                          title: const Text('Reset baseline'),
                          enabled: stress.hasBaseline,
                          onTap: stress.hasBaseline
                              ? () => stress.clearBaseline()
                              : null,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            'Clear history',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          onTap: _busy ? null : () => stress.clearHistory(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelOption extends StatelessWidget {
  const _LevelOption({
    required this.info,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final StressLevelInfo info;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = info.colorOf(context);

    return AppCard(
      onTap: enabled ? onTap : null,
      semanticLabel: 'Set demo level ${info.number}, ${info.title}',
      border: selected ? BorderSide(color: accent, width: 1.8) : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${info.number}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: accent,
              ),
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
                  info.suggestedGameIds.isEmpty
                      ? 'No suggestion'
                      : 'Suggests ${info.suggestedGameIds.first}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? accent : theme.colorScheme.outlineVariant,
          ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}


/// Data source switch (section 35). Mirrors the Measure screen's selector so
/// the mode can be changed without leaving the panel.
class _DataSourcePanel extends StatelessWidget {
  const _DataSourcePanel();

  @override
  Widget build(BuildContext context) {
    final modeController = context.watch<MeasurementModeController>();
    final device = context.watch<DeviceController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Data source',
          subtitle: 'Demo, Manual and Bluetooth are interchangeable',
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<MeasurementMode>(
                segments: [
                  for (final mode in MeasurementMode.values)
                    ButtonSegment<MeasurementMode>(
                      value: mode,
                      label: Text(mode.label),
                    ),
                ],
                selected: {modeController.mode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    modeController.setMode(selection.first),
              ),
              const SizedBox(height: AppSpacing.md),
              _KeyValue(
                label: 'Active source',
                value: modeController.activeSource.displayName,
              ),
              _KeyValue(
                label: 'Ready',
                value: modeController.isReady ? 'yes' : 'no',
              ),
              _KeyValue(
                label: 'BLE link',
                value: device.status.connectionState.label,
              ),
              _KeyValue(
                label: 'BLE adapter',
                value: device.status.adapterState.label,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DevicesScreen()),
                ),
                icon: const Icon(Icons.bluetooth_searching, size: 18),
                label: const Text('Open Devices'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Which engine is installed, and what it consumes.
class _EnginePanel extends StatelessWidget {
  const _EnginePanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = context.read<AppDependencies>().predictionService;
    final registry = service.featureRegistry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Prediction engine',
          subtitle: 'Swapped at the composition root',
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KeyValue(label: 'Engine', value: service.displayName),
              _KeyValue(label: 'Version', value: service.modelVersion),
              _KeyValue(
                label: 'Trained model',
                value: service.isDemo ? 'no - heuristic' : 'yes',
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Feature registry', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                registry.featureKeys.join(', '),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                service.isDemo
                    ? 'The demo engine is a documented weighted heuristic, not '
                          'a machine-learning model. No accuracy is claimed for '
                          'it because none has been measured.'
                    : 'The trained model takes the raw feature vector and '
                          'returns one calibrated probability, which is banded '
                          'into the five levels. Measured metrics are in '
                          'assets/models/model_card.md.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              // A model that failed to load is the one thing this panel must
              // never hide: the app keeps working on the heuristic, and the
              // reason it fell back belongs on screen rather than only in the
              // log.
              if (service is MLStressPredictionService &&
                  service.loadError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Model not loaded: ${service.loadError}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The last packet received over BLE, plus rejected-packet diagnostics.
class _LivePacketPanel extends StatelessWidget {
  const _LivePacketPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = context.watch<DeviceController>();
    final packet = device.latestPacket;
    final service = context.read<AppDependencies>().predictionService;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Last BLE packet',
          subtitle: 'Raw view of what the wearable sent',
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (packet == null)
                Text(
                  'No packet received. Connect a wearable, or use the '
                  'simulated device, to see live data here.',
                  style: theme.textTheme.bodySmall,
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Received ${Formatters.time(packet.timestamp)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    SourceBadge(source: packet.source),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Feature vector',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Builder(
                  builder: (context) {
                    final vector = StressFeatureVector.from(
                      packet,
                      registry: service.featureRegistry,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in vector.toMap().entries)
                          _KeyValue(
                            label: entry.key,
                            value: entry.value?.toStringAsFixed(2) ??
                                'not available',
                          ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${(vector.completeness * 100).round()}% complete',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Full packet', style: theme.textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  packet.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              if (device.rejections.isNotEmpty) ...[
                const Divider(height: AppSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Rejected packets (${device.rejections.length})',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: device.clearRejections,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                for (final rejection in device.rejections.take(5))
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      rejection.reason,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
