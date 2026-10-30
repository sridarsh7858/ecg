import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/source_badge.dart';
import '../../domain/ble/ble_service.dart';
import '../../state/device_controller.dart';

/// Scan for, connect to, and monitor the wearable.
///
/// The whole screen works with no hardware present: with Bluetooth off or
/// unsupported it explains why rather than showing an empty list, and the
/// developer panel can point the app at a simulated device so the entire
/// flow - scan, connect, capabilities, streaming - can be walked through.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  @override
  void initState() {
    super.initState();
    // Ask for permissions on arrival so the first Scan tap is not the thing
    // that triggers a system dialog the user did not expect.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DeviceController>().requestPermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DeviceController>();
    final status = controller.status;

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          _BluetoothStateCard(controller: controller),
          const SizedBox(height: AppSpacing.lg),

          if (status.isConnected) ...[
            const SectionHeader(title: 'Connected device'),
            DeviceStatusCard(status: status),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.tonalIcon(
              onPressed: controller.disconnect,
              icon: const Icon(Icons.bluetooth_disabled),
              label: const Text('Disconnect'),
            ),
          ] else ...[
            SectionHeader(
              title: 'Available devices',
              subtitle: controller.isScanning
                  ? 'Scanning...'
                  : 'Scan to find your wearable',
              action: controller.isScanning
                  ? TextButton(
                      onPressed: controller.stopScan,
                      child: const Text('Stop'),
                    )
                  : FilledButton.icon(
                      onPressed: controller.canScan ? controller.scan : null,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Scan'),
                    ),
            ),
            if (controller.isScanning && controller.devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (controller.devices.isEmpty)
              const EmptyState(
                icon: Icons.bluetooth_searching,
                title: 'No devices yet',
                message:
                    'Turn the wearable on and tap Scan. The app works fully '
                    'in Demo and Manual mode while you wait for hardware.',
              )
            else
              for (final device in controller.devices)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _DeviceRow(
                    device: device,
                    busy: status.connectionState.isBusy,
                    onConnect: () => controller.connect(device),
                  ),
                ),
          ],

          if (status.lastError != null && !status.isConnected) ...[
            const SizedBox(height: AppSpacing.lg),
            _ErrorCard(message: status.lastError!),
          ],
        ],
      ),
    );
  }
}

class _BluetoothStateCard extends StatelessWidget {
  const _BluetoothStateCard({required this.controller});

  final DeviceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = controller.status.adapterState;

    final (IconData icon, Color color) = switch (state) {
      BleAdapterState.on => (Icons.bluetooth, scheme.primary),
      BleAdapterState.off => (Icons.bluetooth_disabled, scheme.error),
      BleAdapterState.unauthorized => (Icons.lock_outline, scheme.error),
      BleAdapterState.unsupported => (Icons.block, scheme.outline),
      BleAdapterState.unknown => (Icons.bluetooth_searching, scheme.outline),
    };

    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bluetooth', style: theme.textTheme.titleMedium),
                Text(
                  state.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (state == BleAdapterState.unsupported)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'Demo and Manual modes still work normally.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (state == BleAdapterState.off)
            TextButton(
              onPressed: controller.enableBluetooth,
              child: const Text('Turn on'),
            )
          else if (state == BleAdapterState.unauthorized)
            TextButton(
              onPressed: controller.requestPermissions,
              child: const Text('Allow'),
            ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.busy,
    required this.onConnect,
  });

  final DiscoveredDevice device;
  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      border: device.isNeuroPulse
          ? BorderSide(color: scheme.primary.withValues(alpha: 0.5))
          : null,
      child: Row(
        children: [
          Icon(
            device.isNeuroPulse ? Icons.watch : Icons.bluetooth,
            color: device.isNeuroPulse ? scheme.primary : scheme.outline,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'Signal: ${device.rssi} dBm  ·  ${device.signalLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: busy ? null : onConnect,
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.errorContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
