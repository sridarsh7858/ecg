import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/dependencies.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/source_badge.dart';
import '../../data/models/physiological_input_packet.dart';
import '../../domain/physiological/physiological_data_source.dart';
import '../../state/device_controller.dart';
import '../../state/measurement_mode_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/stress_controller.dart';
import '../devices/devices_screen.dart';
import 'manual_input_screen.dart';
import 'measure_controller.dart';
import 'stress_result_screen.dart';
import 'widgets/live_trace.dart';

/// The check-in screen: START -> MEASURING -> PROCESSING -> RESULT.
class MeasureScreen extends StatefulWidget {
  const MeasureScreen({super.key});

  @override
  State<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends State<MeasureScreen> {
  MeasureController? _controller;
  MeasurementMode? _builtForMode;

  /// Builds the controller for the currently selected mode.
  ///
  /// The controller binds one data source for its lifetime, so switching mode
  /// replaces it. That is cheaper and clearer than making the controller
  /// itself mode-aware, and it guarantees a half-finished measurement in one
  /// mode can never complete against another mode's source.
  MeasureController _ensureController() {
    final dependencies = context.read<AppDependencies>();
    final mode = context.read<MeasurementModeController>().mode;

    final existing = _controller;
    if (existing != null && _builtForMode == mode) return existing;

    existing?.dispose();

    final created = MeasureController(
      dataSource: dependencies.modeController.sourceFor(mode),
      predictionService: dependencies.predictionService,
    );
    _controller = created;
    _builtForMode = mode;
    return created;
  }

  /// Opens the manual form and installs whatever the user entered.
  Future<void> _openManualInput() async {
    final dependencies = context.read<AppDependencies>();
    final packet = await Navigator.of(context).push<PhysiologicalInputPacket>(
      MaterialPageRoute(builder: (_) => const ManualInputScreen()),
    );
    if (packet == null || !mounted) return;

    dependencies.manualDataSource.submit(packet);
    dependencies.modeController.refresh();
    setState(() {});
  }

  Future<void> _openDevices() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DevicesScreen()),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start(MeasureController controller) async {
    final settings = context.read<SettingsController>();
    if (settings.hapticsEnabled) HapticFeedback.mediumImpact();

    await controller.start(settings.measurementDuration);

    if (!mounted) return;
    final prediction = controller.prediction;
    if (prediction == null) return;

    if (settings.hapticsEnabled) HapticFeedback.lightImpact();
    await context.read<StressController>().applyPrediction(
      prediction,
      packet: controller.packet,
    );

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StressResultScreen(
          prediction: prediction,
          durationSeconds: controller.duration.inSeconds,
        ),
      ),
    );

    if (mounted) controller.reset();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the controller when the mode changes underneath us.
    context.watch<MeasurementModeController>();

    return ChangeNotifierProvider<MeasureController>.value(
      value: _ensureController(),
      child: Consumer<MeasureController>(
        builder: (context, controller, _) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Check in'),
              actions: [
                if (controller.phase == MeasurePhase.measuring)
                  TextButton(
                    onPressed: controller.cancel,
                    child: const Text('Cancel'),
                  ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                child: PageBody(
                  child: switch (controller.phase) {
                    MeasurePhase.idle => _ReadyView(
                      controller: controller,
                      onStart: () => _start(controller),
                      onOpenManualInput: _openManualInput,
                      onOpenDevices: _openDevices,
                    ),
                    MeasurePhase.measuring ||
                    MeasurePhase.processing ||
                    MeasurePhase.complete => _RunningView(
                      controller: controller,
                    ),
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({
    required this.controller,
    required this.onStart,
    required this.onOpenManualInput,
    required this.onOpenDevices,
  });

  final MeasureController controller;
  final VoidCallback onStart;
  final VoidCallback onOpenManualInput;
  final VoidCallback onOpenDevices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();
    final modeController = context.watch<MeasurementModeController>();
    final mode = modeController.mode;
    final blocked = modeController.blockedReason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        _ModeSelector(
          mode: mode,
          onChanged: (next) => modeController.setMode(next),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
            ),
            child: Icon(
              Icons.monitor_heart_outlined,
              size: 58,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Ready to check in?',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Sit comfortably and breathe normally. Keep still for the whole '
          'measurement.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppCard(
          child: Column(
            children: [
              _StatusRow(
                icon: switch (mode) {
                  MeasurementMode.demo => Icons.science_outlined,
                  MeasurementMode.manual => Icons.edit_outlined,
                  MeasurementMode.bluetooth => Icons.bluetooth_rounded,
                },
                label: 'Source',
                value: controller.deviceName,
                trailing: SourceBadge(source: mode.source),
              ),
              const Divider(height: AppSpacing.xl),
              _StatusRow(
                icon: Icons.signal_cellular_alt_rounded,
                label: 'Status',
                value: controller.deviceReady ? 'Ready' : 'Not ready',
                valueColor: controller.deviceReady
                    ? AppColors.positive
                    : theme.colorScheme.error,
              ),
              const Divider(height: AppSpacing.xl),
              _StatusRow(
                icon: Icons.timer_outlined,
                label: 'Duration',
                value: mode == MeasurementMode.manual
                    ? 'Not timed'
                    : '${settings.measurementSeconds} seconds',
              ),
            ],
          ),
        ),
        if (mode == MeasurementMode.manual) ...[
          const SizedBox(height: AppSpacing.lg),
          FilledButton.tonalIcon(
            onPressed: onOpenManualInput,
            icon: const Icon(Icons.edit_outlined),
            label: Text(
              controller.deviceReady ? 'Edit values' : 'Enter values',
            ),
          ),
        ],
        if (mode == MeasurementMode.bluetooth && !controller.deviceReady) ...[
          const SizedBox(height: AppSpacing.lg),
          FilledButton.tonalIcon(
            onPressed: onOpenDevices,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('Open Devices'),
          ),
        ],
        if (blocked != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            blocked,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (controller.error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            color: theme.colorScheme.errorContainer,
            child: Text(
              controller.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: controller.deviceReady ? onStart : null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('START MEASUREMENT'),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          switch (mode) {
            MeasurementMode.demo =>
              'Demo mode - values are simulated for demonstration, not '
                  'measured from a sensor.',
            MeasurementMode.manual =>
              'Manual mode - the app analyses the values you entered. It did '
                  'not measure them.',
            MeasurementMode.bluetooth =>
              'Bluetooth mode - values come from the connected wearable.',
          },
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({required this.controller});

  final MeasureController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tick = controller.tick;
    final isProcessing = controller.phase != MeasurePhase.measuring;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: AppChip(
            label: isProcessing ? 'PROCESSING' : 'MEASURING',
            icon: isProcessing
                ? Icons.hourglass_top_rounded
                : Icons.graphic_eq_rounded,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Center(
          child: Text(
            isProcessing
                ? 'Estimating'
                : Formatters.duration(tick?.remaining ?? Duration.zero),
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Center(
          child: Text(
            isProcessing ? 'Running the demo stress engine' : 'remaining',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: controller.progress),
            duration: const Duration(milliseconds: 200),
            builder: (context, value, _) => LinearProgressIndicator(
              value: isProcessing ? null : value,
              minHeight: 10,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppCard(
          child: Column(
            children: [
              LiveTrace(
                samples: controller.waveform,
                color: theme.colorScheme.primary,
                windowSize: MeasureController.waveformWindow,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'Heart Rate',
                      value: tick == null
                          ? '--'
                          : Formatters.number(tick.hr, places: 0),
                      unit: 'BPM',
                      icon: Icons.favorite_rounded,
                      accent: AppColors.level5,
                    ),
                  ),
                  Expanded(
                    child: MetricTile(
                      label: 'R-R interval',
                      value: tick == null
                          ? '--'
                          : Formatters.number(tick.rr, places: 0),
                      unit: 'ms',
                      icon: Icons.straighten_rounded,
                      accent: AppColors.info,
                    ),
                  ),
                  Expanded(
                    child: MetricTile(
                      label: 'Signal',
                      value: tick?.signalQuality.label ?? '--',
                      icon: Icons.signal_cellular_alt_rounded,
                      accent: AppColors.positive,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: SourceBadge(
            source: context.watch<MeasurementModeController>().mode.source,
            dense: false,
          ),
        ),
      ],
    );
  }
}


/// Chooses between the three interchangeable data sources (section 20).
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final MeasurementMode mode;
  final ValueChanged<MeasurementMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = context.watch<DeviceController>().isConnected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<MeasurementMode>(
          segments: [
            for (final option in MeasurementMode.values)
              ButtonSegment<MeasurementMode>(
                value: option,
                label: Text(option.label),
                icon: Icon(
                  switch (option) {
                    MeasurementMode.demo => Icons.science_outlined,
                    MeasurementMode.manual => Icons.edit_outlined,
                    MeasurementMode.bluetooth => connected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth,
                  },
                  size: 18,
                ),
              ),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          mode.description,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
