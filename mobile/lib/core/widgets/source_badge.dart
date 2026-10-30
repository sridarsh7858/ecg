import 'package:flutter/material.dart';

import '../../data/models/physiological_input_packet.dart';
import '../../domain/ble/ble_service.dart';
import '../../domain/ble/device_capabilities.dart';
import '../theme/app_spacing.dart';
import 'app_widgets.dart';

/// Says where a reading came from. Shown next to every result and history row.
///
/// This is the app's central honesty affordance. A number produced from typed
/// input or simulated values must never look like a measurement, so the badge
/// is deliberately not decorative - it names the source in words.
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.source, this.dense = true});

  final PhysiologicalSource source;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, Color color, String semantic) = switch (source) {
      PhysiologicalSource.demo => (
        Icons.science_outlined,
        scheme.tertiary,
        'Simulated demonstration data, not a measurement',
      ),
      PhysiologicalSource.manual => (
        Icons.edit_outlined,
        scheme.secondary,
        'Values entered by hand, not measured by this app',
      ),
      PhysiologicalSource.bluetooth => (
        Icons.bluetooth_connected,
        scheme.primary,
        'Measured by the connected wearable',
      ),
    };

    return Semantics(
      label: semantic,
      child: AppChip(
        label: source.label,
        icon: icon,
        color: color,
        dense: dense,
      ),
    );
  }
}

/// The wearable's current state: connection, battery, signal and stream.
///
/// Renders honestly in every state. A field the device does not report shows
/// as unavailable rather than as a zero, and a connection that is up but
/// silent is reported as connected-but-not-streaming, because those are
/// genuinely different situations when bringing up firmware.
class DeviceStatusCard extends StatelessWidget {
  const DeviceStatusCard({
    super.key,
    required this.status,
    this.onTap,
    this.showCapabilities = true,
  });

  final BleLinkStatus status;
  final VoidCallback? onTap;
  final bool showCapabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connected = status.isConnected;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                connected ? Icons.watch : Icons.watch_off_outlined,
                color: connected ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wearable', style: theme.textTheme.titleMedium),
                    Text(
                      connected
                          ? (status.device?.name ?? 'Connected')
                          : status.connectionState.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (connected)
                Icon(Icons.check_circle, color: scheme.primary, size: 20)
              else if (onTap != null)
                Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ),
          if (connected) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _StatusPill(
                  icon: Icons.battery_full,
                  label: status.batteryPercentage != null
                      ? '${status.batteryPercentage}%'
                      : 'Battery unavailable',
                  muted: status.batteryPercentage == null,
                ),
                _StatusPill(
                  icon: Icons.signal_cellular_alt,
                  label: status.signalQuality != null
                      ? 'Signal ${(status.signalQuality! * 100).round()}%'
                      : (status.rssi != null
                            ? '${status.rssi} dBm'
                            : 'Signal unavailable'),
                  muted:
                      status.signalQuality == null && status.rssi == null,
                ),
                _StatusPill(
                  icon: status.isStreaming
                      ? Icons.stream
                      : Icons.pause_circle_outline,
                  label: status.isStreaming
                      ? 'Streaming'
                      : 'No data yet',
                  muted: !status.isStreaming,
                ),
              ],
            ),
            if (status.packetsReceived > 0 || status.packetsRejected > 0) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                '${status.packetsReceived} packets received'
                '${status.packetsRejected > 0 ? ', ${status.packetsRejected} rejected' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (showCapabilities && !status.capabilities.isEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              SensorCapabilityList(capabilities: status.capabilities),
            ],
          ],
          if (status.lastError != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: scheme.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    status.lastError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
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

/// Which sensors the connected device actually has (§30 capability detection).
class SensorCapabilityList extends StatelessWidget {
  const SensorCapabilityList({super.key, required this.capabilities});

  final DeviceCapabilities capabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sensors',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final row in capabilities.summary)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  row.seen
                      ? Icons.check_circle_outline
                      : (row.present
                            ? Icons.pending_outlined
                            : Icons.remove_circle_outline),
                  size: 16,
                  color: row.seen
                      ? scheme.primary
                      : (row.present ? scheme.tertiary : scheme.outline),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(row.sensor.label, style: theme.textTheme.bodySmall),
                const Spacer(),
                Text(
                  row.seen
                      ? 'Active'
                      : (row.present ? 'Declared' : 'Not present'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppChip(
      label: label,
      icon: icon,
      color: muted ? scheme.outline : scheme.primary,
      dense: true,
    );
  }
}
