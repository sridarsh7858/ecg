import 'package:flutter/foundation.dart';

import '../data/local/local_store.dart';
import '../domain/physiological/ble_physiological_data_source.dart';
import '../domain/physiological/demo_physiological_data_source.dart';
import '../domain/physiological/manual_physiological_data_source.dart';
import '../domain/physiological/physiological_data_source.dart';

/// Holds the three data sources and which one is currently selected.
///
/// This is the switch that makes Demo, Manual and Bluetooth interchangeable.
/// Everything downstream asks for [activeSource] and gets a
/// [PhysiologicalDataSource]; nothing else in the app branches on the mode
/// except the screens that must *show* which mode is active.
class MeasurementModeController extends ChangeNotifier {
  MeasurementModeController({
    required this.demoSource,
    required this.manualSource,
    required this.bleSource,
    LocalStore? store,
    MeasurementMode initialMode = MeasurementMode.demo,
  }) : _store = store,
       _mode = initialMode;

  static const String _storeKey = 'measurement_mode';

  final DemoPhysiologicalDataSource demoSource;
  final ManualPhysiologicalDataSource manualSource;
  final BlePhysiologicalDataSource bleSource;

  final LocalStore? _store;

  MeasurementMode _mode;

  MeasurementMode get mode => _mode;

  /// The data source for the selected mode.
  PhysiologicalDataSource get activeSource => sourceFor(_mode);

  PhysiologicalDataSource sourceFor(MeasurementMode mode) => switch (mode) {
    MeasurementMode.demo => demoSource,
    MeasurementMode.manual => manualSource,
    MeasurementMode.bluetooth => bleSource,
  };

  /// True when the selected mode can actually produce a measurement now.
  ///
  /// Manual needs values entered; Bluetooth needs a connected device. Demo is
  /// always ready.
  bool get isReady => activeSource.isReady;

  /// Why the active mode is not ready, or null when it is.
  String? get blockedReason {
    if (isReady) return null;
    return switch (_mode) {
      MeasurementMode.demo => null,
      MeasurementMode.manual =>
        'Enter your values first, then run the analysis.',
      MeasurementMode.bluetooth =>
        'No wearable connected. Open Devices to scan and connect.',
    };
  }

  Future<void> setMode(MeasurementMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _store?.setString(_storeKey, mode.id);
  }

  /// Re-notifies listeners after something changed a source's readiness,
  /// such as the manual form being submitted or a device connecting.
  void refresh() => notifyListeners();

  Future<void> restore() async {
    final saved = _store?.getString(_storeKey);
    if (saved == null) return;
    final restored = MeasurementMode.fromId(saved);

    // Bluetooth is never restored as the active mode on launch: the wearable
    // will not be connected yet, and starting in a mode that cannot produce a
    // reading is a worse first impression than starting in Demo.
    _mode = restored == MeasurementMode.bluetooth
        ? MeasurementMode.demo
        : restored;
    notifyListeners();
  }
}
