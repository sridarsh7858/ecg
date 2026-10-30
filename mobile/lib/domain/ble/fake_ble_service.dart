import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../../data/models/physiological_input_packet.dart';
import '../../data/models/raw_ecg_packet.dart';
import '../stress/stress_level.dart';
import 'ble_protocol.dart';
import 'ble_service.dart';
import 'device_capabilities.dart';

/// A [BleService] that behaves like a wearable without any wearable.
///
/// This exists for two reasons, and both matter:
///
/// 1. **Tests.** The whole Bluetooth path - scan, connect, discover, subscribe,
///    parse, update UI - can be driven in a widget test with no BLE stack.
/// 2. **Development.** The developer panel can point the app at this service,
///    so the Bluetooth mode can be demonstrated before the ESP32 exists.
///
/// It deliberately emits packets **through [BleProtocol]** as encoded JSON
/// rather than constructing [PhysiologicalInputPacket] objects directly. That
/// way the parser and its validation are exercised on every simulated packet,
/// and the JSON shape stays honest: if the real firmware sends what this fake
/// sends, it will parse.
///
/// Everything it produces is tagged [PhysiologicalSource.bluetooth], because
/// from the app's point of view it *is* the Bluetooth path. Whether the fake or
/// the real service is installed is a composition-root decision, surfaced in
/// the developer panel - it is never hidden from the user.
class FakeBleService implements BleService {
  FakeBleService({
    this.packetInterval = const Duration(seconds: 1),
    this.simulatedLevel,
    this.includeGsr = true,
    this.includeMovement = true,
    this.includeBattery = true,
    this.autoStream = true,
    math.Random? random,
  }) : _random = random ?? math.Random(7);

  /// How often a simulated packet is emitted once connected.
  final Duration packetInterval;

  /// Supplies the stress level the simulated values should look like.
  /// When null, a mid-range resting profile is produced.
  final StressLevel Function()? simulatedLevel;

  final bool includeGsr;
  final bool includeMovement;
  final bool includeBattery;

  /// When false, no packets are emitted until [emitPacket] is called by hand.
  /// Tests use this to control timing precisely.
  final bool autoStream;

  final math.Random _random;

  final _statusController = StreamController<BleLinkStatus>.broadcast();
  final _scanController = StreamController<List<DiscoveredDevice>>.broadcast();
  final _packetController =
      StreamController<PhysiologicalInputPacket>.broadcast();
  final _ecgController = StreamController<RawEcgPacket>.broadcast();
  final _rejectController = StreamController<InvalidPacketResult>.broadcast();

  Timer? _streamTimer;
  BleLinkStatus _status = const BleLinkStatus(
    adapterState: BleAdapterState.on,
  );
  bool _disposed = false;
  int _battery = 87;

  /// The device this fake advertises.
  static const DiscoveredDevice simulatedDevice = DiscoveredDevice(
    id: 'FA:KE:00:00:00:01',
    name: 'NeuroPulse-ESP32 (Simulated)',
    rssi: -58,
    isNeuroPulse: true,
  );

  @override
  Stream<BleLinkStatus> get status => _statusController.stream;

  @override
  BleLinkStatus get currentStatus => _status;

  @override
  Stream<List<DiscoveredDevice>> get scanResults => _scanController.stream;

  @override
  Stream<PhysiologicalInputPacket> get packets => _packetController.stream;

  @override
  Stream<RawEcgPacket> get ecgPackets => _ecgController.stream;

  @override
  Stream<InvalidPacketResult> get rejectedPackets => _rejectController.stream;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> requestEnableBluetooth() async {
    _emit(_status.copyWith(adapterState: BleAdapterState.on));
  }

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    _emit(
      _status.copyWith(
        connectionState: BleConnectionState.scanning,
        clearError: true,
      ),
    );
    _scanController.add(const []);

    // A short delay so the scanning state is actually observable in the UI
    // and in tests, rather than completing within the same frame.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_disposed) return;

    _scanController.add(const [simulatedDevice]);
    _emit(_status.copyWith(connectionState: BleConnectionState.disconnected));
  }

  @override
  Future<void> stopScan() async {
    if (_status.connectionState == BleConnectionState.scanning) {
      _emit(_status.copyWith(connectionState: BleConnectionState.disconnected));
    }
  }

  @override
  Future<void> connect(DiscoveredDevice device) async {
    _emit(
      _status.copyWith(
        connectionState: BleConnectionState.connecting,
        device: device,
        packetsReceived: 0,
        packetsRejected: 0,
        clearError: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (_disposed) return;

    _emit(_status.copyWith(connectionState: BleConnectionState.discovering));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (_disposed) return;

    _emit(
      _status.copyWith(
        connectionState: BleConnectionState.connected,
        rssi: device.rssi,
        capabilities: DeviceCapabilities.fromDeviceInfo({
          'fw': '0.0.0-simulated',
          'hw': 'none',
          'sensors': [
            'ecg',
            if (includeGsr) 'gsr',
            if (includeMovement) ...['accel', 'gyro'],
            if (includeBattery) 'battery',
          ],
        }),
      ),
    );

    if (autoStream) {
      _streamTimer = Timer.periodic(packetInterval, (_) => emitPacket());
      emitPacket();
    }
  }

  @override
  Future<void> disconnect() async {
    _streamTimer?.cancel();
    _streamTimer = null;
    _emit(
      _status.copyWith(
        connectionState: BleConnectionState.disconnected,
        clearDevice: true,
        capabilities: DeviceCapabilities.unknown,
        clearError: true,
      ),
    );
  }

  /// Emits one simulated packet, routed through the real parser.
  void emitPacket({StressLevel? level}) {
    if (_disposed || !_status.isConnected) return;
    emitRaw(jsonEncode(buildPayload(level: level)));
  }

  /// Feeds an arbitrary payload through the real parsing and validation path.
  ///
  /// Tests use this to prove that malformed firmware output is rejected
  /// without disturbing the connection.
  void emitRaw(String payload) {
    final result = BleProtocol.parse(payload);
    switch (result) {
      case PhysiologyPacketResult(:final packet, :final warnings):
        _packetController.add(packet);
        _emit(
          _status.copyWith(
            lastPacketAt: packet.timestamp,
            batteryPercentage: packet.batteryPercentage,
            signalQuality: packet.signalQuality,
            capabilities: _status.capabilities.observing(packet),
            packetsReceived: _status.packetsReceived + 1,
          ),
        );
        for (final warning in warnings) {
          _rejectController.add(InvalidPacketResult('field dropped: $warning'));
        }
      case EcgPacketResult(:final packet):
        _ecgController.add(packet);
        _emit(
          _status.copyWith(
            lastPacketAt: packet.timestamp,
            capabilities: _status.capabilities.observingRawEcg(),
            packetsReceived: _status.packetsReceived + 1,
          ),
        );
      case InvalidPacketResult():
        _rejectController.add(result);
        _emit(_status.copyWith(packetsRejected: _status.packetsRejected + 1));
    }
  }

  /// Builds a plausible firmware payload.
  ///
  /// The numbers are shaped to look like the requested stress level, but they
  /// are invented. They demonstrate the data path; they are not measurements
  /// and nothing about them is validated against physiology.
  Map<String, dynamic> buildPayload({StressLevel? level}) {
    final target = level ?? simulatedLevel?.call() ?? StressLevel.moderate;
    final t = (target.number - 1) / 4; // 0 at level 1, 1 at level 5

    double jitter(double scale) => (_random.nextDouble() * 2 - 1) * scale;

    final hr = 62 + 32 * t + jitter(3);
    final meanRR = 60000 / hr;
    final rmssd = 58 - 42 * t + jitter(4);
    final sdnn = 68 - 44 * t + jitter(5);
    final pnn50 = 26 - 23 * t + jitter(3);

    if (includeBattery && _random.nextInt(20) == 0 && _battery > 1) {
      _battery--;
    }

    return {
      'type': 'physiology',
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'hr': double.parse(hr.toStringAsFixed(1)),
      'mean_rr': double.parse(meanRR.toStringAsFixed(1)),
      'rmssd': double.parse(math.max(3, rmssd).toStringAsFixed(1)),
      'sdnn': double.parse(math.max(5, sdnn).toStringAsFixed(1)),
      'pnn50': double.parse(math.max(0, pnn50).toStringAsFixed(1)),
      if (includeGsr) ...{
        'gsr': double.parse((1.8 + 3.4 * t + jitter(0.2)).toStringAsFixed(2)),
        'gsr_peaks': (1 + 6 * t + _random.nextInt(2)).round(),
      },
      if (includeMovement) ...{
        'accel_x': double.parse(jitter(0.05).toStringAsFixed(3)),
        'accel_y': double.parse((0.08 + jitter(0.05)).toStringAsFixed(3)),
        'accel_z': double.parse((0.98 + jitter(0.04)).toStringAsFixed(3)),
        'gyro_x': double.parse(jitter(1.5).toStringAsFixed(2)),
        'gyro_y': double.parse(jitter(1.5).toStringAsFixed(2)),
        'gyro_z': double.parse(jitter(1.5).toStringAsFixed(2)),
      },
      if (includeBattery) 'battery': _battery,
      'signal_quality': double.parse(
        (0.93 + jitter(0.05)).clamp(0.0, 1.0).toStringAsFixed(2),
      ),
    };
  }

  /// Emits a simulated raw ECG burst, for exercising the waveform path.
  void emitEcgBurst({int samples = 100, double sampleRate = 250}) {
    if (_disposed || !_status.isConnected) return;
    final values = List<double>.generate(samples, (i) {
      final phase = (i % 50) / 50;
      final beat = phase < 0.12
          ? math.sin(phase / 0.12 * math.pi) * 300
          : phase < 0.20
          ? -600
          : phase < 0.26
          ? 3000
          : phase < 0.34
          ? -900
          : phase < 0.60
          ? math.sin((phase - 0.34) / 0.26 * math.pi) * 450
          : 0.0;
      return 2048 + beat + (_random.nextDouble() * 40 - 20);
    });

    emitRaw(
      jsonEncode({
        'type': 'ecg',
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'sample_rate': sampleRate,
        'samples': values.map((v) => v.round()).toList(),
      }),
    );
  }

  void _emit(BleLinkStatus status) {
    if (_disposed) return;
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _streamTimer?.cancel();
    await _statusController.close();
    await _scanController.close();
    await _packetController.close();
    await _ecgController.close();
    await _rejectController.close();
  }
}
