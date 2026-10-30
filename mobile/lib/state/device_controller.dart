import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/physiological_input_packet.dart';
import '../data/models/raw_ecg_packet.dart';
import '../domain/ble/ble_protocol.dart';
import '../domain/ble/ble_service.dart';

/// UI-facing state for the wearable link.
///
/// Wraps [BleService] streams in a [ChangeNotifier] so screens can bind to it
/// with `context.watch`. It holds no BLE logic of its own - it is a view model,
/// and everything it exposes comes from the service.
class DeviceController extends ChangeNotifier {
  DeviceController(this._service) {
    _statusSubscription = _service.status.listen((status) {
      _status = status;
      notifyListeners();
    });
    _scanSubscription = _service.scanResults.listen((devices) {
      _devices = devices;
      notifyListeners();
    });
    _packetSubscription = _service.packets.listen((packet) {
      _latestPacket = packet;
      notifyListeners();
    });
    _ecgSubscription = _service.ecgPackets.listen((packet) {
      _ecgBuffer.add(packet);
      notifyListeners();
    });
    _rejectSubscription = _service.rejectedPackets.listen((rejection) {
      _rejections.insert(0, rejection);
      if (_rejections.length > _maxRejections) _rejections.removeLast();
      notifyListeners();
    });
    _status = _service.currentStatus;
  }

  static const int _maxRejections = 20;

  final BleService _service;

  late StreamSubscription<BleLinkStatus> _statusSubscription;
  late StreamSubscription<List<DiscoveredDevice>> _scanSubscription;
  late StreamSubscription<PhysiologicalInputPacket> _packetSubscription;
  late StreamSubscription<RawEcgPacket> _ecgSubscription;
  late StreamSubscription<InvalidPacketResult> _rejectSubscription;

  BleLinkStatus _status = const BleLinkStatus();
  List<DiscoveredDevice> _devices = const [];
  PhysiologicalInputPacket? _latestPacket;
  final RawEcgBuffer _ecgBuffer = RawEcgBuffer();
  final List<InvalidPacketResult> _rejections = [];

  BleService get service => _service;

  BleLinkStatus get status => _status;

  List<DiscoveredDevice> get devices => List.unmodifiable(_devices);

  /// The most recent packet received, or null if none has arrived.
  PhysiologicalInputPacket? get latestPacket => _latestPacket;

  /// Raw ECG samples buffered for the waveform view.
  RawEcgBuffer get ecgBuffer => _ecgBuffer;

  /// Recent rejected packets, newest first. Developer panel only.
  List<InvalidPacketResult> get rejections => List.unmodifiable(_rejections);

  bool get isConnected => _status.isConnected;

  bool get isScanning =>
      _status.connectionState == BleConnectionState.scanning;

  bool get canScan => _status.adapterState.canScan && !_status.connectionState.isBusy;

  /// True when raw ECG has actually been received.
  ///
  /// The waveform view shows "ECG waveform unavailable" when this is false.
  /// It never falls back to a generated trace while in Bluetooth mode.
  bool get hasRawEcg => _ecgBuffer.isNotEmpty;

  Future<void> requestPermissions() => _service.requestPermissions();

  Future<void> enableBluetooth() => _service.requestEnableBluetooth();

  Future<void> scan() => _service.startScan();

  Future<void> stopScan() => _service.stopScan();

  Future<void> connect(DiscoveredDevice device) async {
    _ecgBuffer.clear();
    _latestPacket = null;
    await _service.connect(device);
  }

  Future<void> disconnect() async {
    await _service.disconnect();
    _ecgBuffer.clear();
    _latestPacket = null;
    notifyListeners();
  }

  void clearRejections() {
    _rejections.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSubscription.cancel();
    _scanSubscription.cancel();
    _packetSubscription.cancel();
    _ecgSubscription.cancel();
    _rejectSubscription.cancel();
    super.dispose();
  }
}
