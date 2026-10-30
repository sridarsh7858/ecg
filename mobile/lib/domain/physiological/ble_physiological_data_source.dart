import 'dart:async';

import '../../data/models/physiological_features.dart';
import '../../data/models/physiological_input_packet.dart';
import '../ble/ble_service.dart';
import 'physiological_data_source.dart';

/// Live physiological data from the wearable, over BLE.
///
/// This source does no parsing and knows nothing about `flutter_blue_plus`. It
/// consumes already-validated [PhysiologicalInputPacket]s from [BleService] and
/// turns a window of them into one measurement.
///
/// The device streams continuously once connected; a "measurement" is simply
/// the window of packets collected between start and finish. Fields are
/// averaged across the window, which is what makes a 30-second reading steadier
/// than any single packet.
///
/// **A sensor that never appeared stays null.** If no packet in the window
/// carried GSR, the resulting packet has no GSR, and the UI shows "Not
/// available". Nothing here substitutes a value for an absent sensor.
class BlePhysiologicalDataSource extends PhysiologicalDataSource {
  BlePhysiologicalDataSource(this._service);

  final BleService _service;

  /// How long to wait for the first packet before giving up.
  ///
  /// A connection can be established and still deliver nothing, if the firmware
  /// has not started sampling or is stuck. Failing with a clear message beats
  /// hanging for the whole window and then reporting an empty result.
  static const Duration firstPacketTimeout = Duration(seconds: 12);

  final List<PhysiologicalInputPacket> _window = [];
  PhysiologicalInputPacket? _aggregate;

  @override
  String get id => 'ble';

  @override
  String get displayName => 'Wearable (Bluetooth)';

  @override
  String get sourceTag => PhysiologicalSource.bluetooth.tag;

  @override
  MeasurementMode get mode => MeasurementMode.bluetooth;

  @override
  DataSourceStatus get status {
    final state = _service.currentStatus.connectionState;
    return switch (state) {
      BleConnectionState.connected => DataSourceStatus.connected,
      BleConnectionState.connecting ||
      BleConnectionState.discovering => DataSourceStatus.connecting,
      BleConnectionState.scanning ||
      BleConnectionState.disconnected => DataSourceStatus.disconnected,
    };
  }

  @override
  bool get isReady => _service.currentStatus.isConnected;

  /// Connection is driven from the Devices screen, not from here.
  ///
  /// A measurement must never silently initiate a connection: which device the
  /// app talks to is the user's choice, made explicitly.
  @override
  Future<void> connect() async {
    if (!isReady) {
      throw StateError(
        'No wearable is connected. Open Devices, scan, and connect first.',
      );
    }
  }

  @override
  Future<void> disconnect() => _service.disconnect();

  @override
  Stream<MeasurementTick> measure(Duration duration) async* {
    if (!isReady) {
      throw StateError(
        'No wearable is connected. Open Devices, scan, and connect first.',
      );
    }

    _window.clear();
    _aggregate = null;

    final started = DateTime.now();
    final queue = StreamController<PhysiologicalInputPacket>();
    final subscription = _service.packets.listen(queue.add, onError: queue.addError);

    try {
      await for (final packet in queue.stream.timeout(
        firstPacketTimeout,
        onTimeout: (sink) => sink.addError(
          StateError(
            'Connected, but the wearable sent no data within '
            '${firstPacketTimeout.inSeconds} seconds. Check that the '
            'electrodes are attached and the firmware is streaming.',
          ),
        ),
      )) {
        if (!packet.isUsable) continue;
        _window.add(packet);

        final elapsed = DateTime.now().difference(started);
        if (elapsed >= duration) break;

        yield MeasurementTick(
          elapsed: elapsed,
          total: duration,
          hr: packet.effectiveHeartRate ?? 0,
          rr: packet.effectiveMeanRR ?? 0,
          signalQuality: _qualityFrom(packet.signalQuality),
          // Raw ECG is a separate characteristic and is not required for a
          // measurement, so the trace stays flat unless the firmware streams
          // it. A fabricated waveform here would be a lie about the hardware.
          waveformSample: 0,
        );
      }
    } finally {
      await subscription.cancel();
      await queue.close();
    }

    if (_window.isEmpty) {
      throw StateError('No usable data was received from the wearable.');
    }

    _aggregate = _aggregateWindow();
  }

  static SignalQuality _qualityFrom(double? quality) {
    if (quality == null) return SignalQuality.good;
    if (quality >= 0.8) return SignalQuality.good;
    if (quality >= 0.5) return SignalQuality.fair;
    return SignalQuality.poor;
  }

  /// Averages the window, field by field, skipping absent values.
  ///
  /// Each field is averaged only over the packets that actually carried it, so
  /// a sensor that appeared halfway through the window is not diluted by the
  /// packets that predate it, and one that never appeared stays null.
  PhysiologicalInputPacket _aggregateWindow() {
    double? mean(double? Function(PhysiologicalInputPacket p) pick) {
      final values = _window.map(pick).whereType<double>().toList();
      if (values.isEmpty) return null;
      return values.reduce((a, b) => a + b) / values.length;
    }

    int? meanInt(int? Function(PhysiologicalInputPacket p) pick) {
      final values = _window.map(pick).whereType<int>().toList();
      if (values.isEmpty) return null;
      return (values.reduce((a, b) => a + b) / values.length).round();
    }

    T? last<T>(T? Function(PhysiologicalInputPacket p) pick) {
      for (final packet in _window.reversed) {
        final value = pick(packet);
        if (value != null) return value;
      }
      return null;
    }

    return PhysiologicalInputPacket(
      timestamp: _window.last.timestamp,
      source: PhysiologicalSource.bluetooth,
      heartRate: mean((p) => p.effectiveHeartRate),
      meanRR: mean((p) => p.effectiveMeanRR),
      rmssd: mean((p) => p.rmssd),
      sdnn: mean((p) => p.sdnn),
      pnn50: mean((p) => p.pnn50),
      gsrValue: mean((p) => p.gsrValue),
      gsrLevel: mean((p) => p.gsrLevel),
      gsrPeaks: meanInt((p) => p.gsrPeaks),
      accelX: mean((p) => p.accelX),
      accelY: mean((p) => p.accelY),
      accelZ: mean((p) => p.accelZ),
      movementIntensity: mean((p) => p.effectiveMovementIntensity),
      gyroX: mean((p) => p.gyroX),
      gyroY: mean((p) => p.gyroY),
      gyroZ: mean((p) => p.gyroZ),
      // Battery and quality describe the device right now, so the most recent
      // reading is the right one - averaging them would be meaningless.
      batteryVoltage: last((p) => p.batteryVoltage),
      batteryCurrent: last((p) => p.batteryCurrent),
      batteryPercentage: last((p) => p.batteryPercentage),
      signalQuality: mean((p) => p.signalQuality),
      rrIntervals: _window
          .expand((p) => p.rrIntervals ?? const <double>[])
          .toList()
          .let((list) => list.isEmpty ? null : list),
    );
  }

  /// Number of packets collected in the last measurement window.
  int get windowSize => _window.length;

  @override
  Future<PhysiologicalInputPacket> readPacket() async {
    final aggregate = _aggregate;
    if (aggregate == null) {
      throw StateError('No completed BLE measurement is available.');
    }
    return aggregate;
  }

  @override
  Future<PhysiologicalFeatures> readFeatures() async =>
      (await readPacket()).toLegacyFeatures();
}

extension _Let<T> on T {
  R let<R>(R Function(T value) transform) => transform(this);
}
