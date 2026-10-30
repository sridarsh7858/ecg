import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

import '../../data/models/physiological_input_packet.dart';
import '../../data/models/raw_ecg_packet.dart';
import 'ble_protocol.dart';
import 'ble_service.dart';
import 'device_capabilities.dart';

/// The production [BleService], backed by `flutter_blue_plus`.
///
/// This is the only file in the application that imports the BLE package.
/// Everything above it sees [BleService] and the plain data types in
/// `ble_service.dart`, so replacing the package - or running the whole app
/// against [FakeBleService] with no hardware at all - changes nothing else.
class FlutterBlueBleService implements BleService {
  FlutterBlueBleService() {
    _watchAdapter();
  }

  final _statusController = StreamController<BleLinkStatus>.broadcast();
  final _scanController = StreamController<List<DiscoveredDevice>>.broadcast();
  final _packetController =
      StreamController<PhysiologicalInputPacket>.broadcast();
  final _ecgController = StreamController<RawEcgPacket>.broadcast();
  final _rejectController = StreamController<InvalidPacketResult>.broadcast();

  StreamSubscription<fbp.BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<List<fbp.ScanResult>>? _scanSubscription;
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionSubscription;
  final List<StreamSubscription<List<int>>> _valueSubscriptions = [];
  Timer? _rssiTimer;

  fbp.BluetoothDevice? _device;
  BleLinkStatus _status = const BleLinkStatus();
  bool _disposed = false;

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

  // --- Adapter ------------------------------------------------------------

  /// Begins watching the adapter.
  ///
  /// Wrapped in a catch-all because this runs in the constructor, and in a
  /// plain `flutter test` (or on a desktop host) the platform channel does not
  /// exist at all. A missing BLE stack must degrade to "unsupported", never
  /// take down app startup - the rest of the app has to work without it.
  Future<void> _watchAdapter() async {
    try {
      if (!await fbp.FlutterBluePlus.isSupported) {
        _emit(_status.copyWith(adapterState: BleAdapterState.unsupported));
        return;
      }
      _adapterSubscription = fbp.FlutterBluePlus.adapterState.listen(
        (state) => _emit(_status.copyWith(adapterState: _mapAdapterState(state))),
        onError: (Object _) =>
            _emit(_status.copyWith(adapterState: BleAdapterState.unsupported)),
      );
    } catch (_) {
      _emit(_status.copyWith(adapterState: BleAdapterState.unsupported));
    }
  }

  static BleAdapterState _mapAdapterState(fbp.BluetoothAdapterState state) {
    return switch (state) {
      fbp.BluetoothAdapterState.on => BleAdapterState.on,
      fbp.BluetoothAdapterState.off ||
      fbp.BluetoothAdapterState.turningOff ||
      fbp.BluetoothAdapterState.turningOn => BleAdapterState.off,
      fbp.BluetoothAdapterState.unauthorized => BleAdapterState.unauthorized,
      fbp.BluetoothAdapterState.unavailable => BleAdapterState.unsupported,
      fbp.BluetoothAdapterState.unknown => BleAdapterState.unknown,
    };
  }

  @override
  Future<bool> requestPermissions() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    if (Platform.isAndroid) {
      // Android 12+ uses the split Bluetooth permissions. On older releases
      // these resolve to "granted" immediately and scanning needs location
      // instead, so both are requested and the result is judged leniently.
      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final scanOk = results[Permission.bluetoothScan]?.isGranted ?? false;
      final connectOk = results[Permission.bluetoothConnect]?.isGranted ?? false;
      final locationOk =
          results[Permission.locationWhenInUse]?.isGranted ?? false;

      final granted = (scanOk && connectOk) || locationOk;
      if (!granted) {
        _emit(
          _status.copyWith(
            adapterState: BleAdapterState.unauthorized,
            lastError: 'Bluetooth permission was denied.',
          ),
        );
      }
      return granted;
    }

    final result = await Permission.bluetooth.request();
    return result.isGranted || result.isLimited;
  }

  @override
  Future<void> requestEnableBluetooth() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await fbp.FlutterBluePlus.turnOn();
    } catch (error) {
      _emit(_status.copyWith(lastError: 'Could not turn Bluetooth on: $error'));
    }
  }

  // --- Scanning -----------------------------------------------------------

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_disposed) return;

    if (!await requestPermissions()) return;

    if (_status.adapterState != BleAdapterState.on) {
      _emit(_status.copyWith(lastError: 'Bluetooth is not ready.'));
      return;
    }

    await stopScan();
    _scanController.add(const []);
    _emit(
      _status.copyWith(
        connectionState: BleConnectionState.scanning,
        clearError: true,
      ),
    );

    // No service filter is applied. The ESP32 firmware does not exist yet, so
    // filtering by our own service UUID would hide the very device being
    // brought up if its advertisement is not yet correct. Everything nearby is
    // listed, with NeuroPulse devices sorted to the top.
    _scanSubscription = fbp.FlutterBluePlus.onScanResults.listen(
      (results) {
        final devices = results.map(_toDiscovered).toList()
          ..sort((a, b) {
            if (a.isNeuroPulse != b.isNeuroPulse) {
              return a.isNeuroPulse ? -1 : 1;
            }
            return b.rssi.compareTo(a.rssi);
          });
        _scanController.add(devices);
      },
      onError: (Object error) {
        _emit(_status.copyWith(lastError: 'Scan failed: $error'));
      },
    );

    try {
      await fbp.FlutterBluePlus.startScan(timeout: timeout);
      // startScan completes when the timeout elapses.
      if (_status.connectionState == BleConnectionState.scanning) {
        _emit(_status.copyWith(connectionState: BleConnectionState.disconnected));
      }
    } catch (error) {
      _emit(
        _status.copyWith(
          connectionState: BleConnectionState.disconnected,
          lastError: 'Scan failed: $error',
        ),
      );
    }
  }

  static DiscoveredDevice _toDiscovered(fbp.ScanResult result) {
    final advertised = result.advertisementData.advName;
    final platform = result.device.platformName;
    final name = advertised.isNotEmpty
        ? advertised
        : (platform.isNotEmpty ? platform : 'Unknown device');

    return DiscoveredDevice(
      id: result.device.remoteId.str,
      name: name,
      rssi: result.rssi,
      isNeuroPulse: name.toLowerCase().contains(
        BleUuids.deviceNamePrefix.toLowerCase(),
      ),
    );
  }

  @override
  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      if (fbp.FlutterBluePlus.isScanningNow) {
        await fbp.FlutterBluePlus.stopScan();
      }
    } catch (_) {
      // Stopping a scan that is not running is not an error worth surfacing.
    }
  }

  // --- Connecting ---------------------------------------------------------

  @override
  Future<void> connect(DiscoveredDevice device) async {
    if (_disposed) return;
    await stopScan();
    await _teardownConnection();

    final target = fbp.BluetoothDevice.fromId(device.id);
    _device = target;

    _emit(
      _status.copyWith(
        connectionState: BleConnectionState.connecting,
        device: device,
        capabilities: DeviceCapabilities.unknown,
        packetsReceived: 0,
        packetsRejected: 0,
        clearError: true,
      ),
    );

    _connectionSubscription = target.connectionState.listen((state) {
      if (state == fbp.BluetoothConnectionState.disconnected &&
          _status.connectionState != BleConnectionState.disconnected) {
        _handleUnexpectedDisconnect();
      }
    });

    try {
      await target.connect(timeout: const Duration(seconds: 20));
    } catch (error) {
      _emit(
        _status.copyWith(
          connectionState: BleConnectionState.disconnected,
          clearDevice: true,
          lastError: 'Could not connect: $error',
        ),
      );
      await _teardownConnection();
      return;
    }

    _emit(_status.copyWith(connectionState: BleConnectionState.discovering));

    try {
      final services = await target.discoverServices();
      await _subscribeToCharacteristics(services);
    } catch (error) {
      _emit(
        _status.copyWith(
          connectionState: BleConnectionState.disconnected,
          clearDevice: true,
          lastError: 'Service discovery failed: $error',
        ),
      );
      await _teardownConnection();
      return;
    }

    _emit(_status.copyWith(connectionState: BleConnectionState.connected));
    _startRssiPolling(target);
  }

  /// Subscribes to every characteristic the app understands.
  ///
  /// Missing characteristics are tolerated. A board that exposes only the
  /// physiology characteristic works; one that also exposes raw ECG and a
  /// battery service works better. Only a missing *physiology* characteristic
  /// is worth complaining about, since without it no data can arrive.
  Future<void> _subscribeToCharacteristics(
    List<fbp.BluetoothService> services,
  ) async {
    var foundPhysiology = false;
    var declared = DeviceCapabilities.unknown;

    for (final service in services) {
      final serviceUuid = service.uuid.toString();

      for (final characteristic in service.characteristics) {
        final uuid = characteristic.uuid.toString();

        if (BleUuids.matches(uuid, BleUuids.physiologyCharacteristicUuid)) {
          await _subscribe(characteristic, _handlePhysiologyBytes);
          foundPhysiology = true;
        } else if (BleUuids.matches(uuid, BleUuids.rawEcgCharacteristicUuid)) {
          await _subscribe(characteristic, _handleEcgBytes);
        } else if (BleUuids.matches(uuid, BleUuids.batteryCharacteristicUuid)) {
          await _subscribe(characteristic, _handlePhysiologyBytes);
        } else if (BleUuids.matches(uuid, BleUuids.standardBatteryLevelUuid) &&
            BleUuids.matches(
              serviceUuid,
              BleUuids.standardBatteryServiceUuid,
            )) {
          await _subscribeStandardBattery(characteristic);
        } else if (BleUuids.matches(
          uuid,
          BleUuids.deviceInfoCharacteristicUuid,
        )) {
          declared = await _readDeviceInfo(characteristic) ?? declared;
        }
      }
    }

    _emit(_status.copyWith(capabilities: declared));

    if (!foundPhysiology) {
      _emit(
        _status.copyWith(
          lastError:
              'Connected, but this device does not expose the NeuroPulse '
              'physiology characteristic. Check the firmware UUIDs against '
              'docs/ble_protocol.md.',
        ),
      );
    }
  }

  Future<void> _subscribe(
    fbp.BluetoothCharacteristic characteristic,
    void Function(List<int> bytes) handler,
  ) async {
    if (!characteristic.properties.notify &&
        !characteristic.properties.indicate) {
      return;
    }
    try {
      await characteristic.setNotifyValue(true);
      _valueSubscriptions.add(
        characteristic.onValueReceived.listen(
          handler,
          onError: (Object error) {
            _emit(_status.copyWith(lastError: 'Stream error: $error'));
          },
        ),
      );
    } catch (error) {
      _emit(
        _status.copyWith(
          lastError: 'Could not subscribe to ${characteristic.uuid}: $error',
        ),
      );
    }
  }

  /// The SIG battery characteristic is a single unsigned byte, not JSON.
  Future<void> _subscribeStandardBattery(
    fbp.BluetoothCharacteristic characteristic,
  ) async {
    void handle(List<int> bytes) {
      if (bytes.isEmpty) return;
      final percent = bytes.first;
      if (percent < 0 || percent > 100) return;
      _emit(
        _status.copyWith(
          batteryPercentage: percent,
          capabilities: _status.capabilities.observing(
            PhysiologicalInputPacket(
              timestamp: DateTime.now(),
              source: PhysiologicalSource.bluetooth,
              batteryPercentage: percent,
            ),
          ),
        ),
      );
    }

    try {
      final initial = await characteristic.read();
      handle(initial);
    } catch (_) {
      // Not readable on every stack; the notification path still works.
    }
    await _subscribe(characteristic, handle);
  }

  Future<DeviceCapabilities?> _readDeviceInfo(
    fbp.BluetoothCharacteristic characteristic,
  ) async {
    if (!characteristic.properties.read) return null;
    try {
      final bytes = await characteristic.read();
      if (bytes.isEmpty) return null;
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is! Map) return null;
      return DeviceCapabilities.fromDeviceInfo(
        Map<String, dynamic>.from(decoded),
        observed: _status.capabilities.observed,
      );
    } catch (_) {
      // A device that cannot describe itself is still perfectly usable;
      // capabilities will simply be discovered by observation instead.
      return null;
    }
  }

  // --- Incoming data ------------------------------------------------------

  void _handlePhysiologyBytes(List<int> bytes) {
    final result = BleProtocol.parseBytes(bytes);
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
            packetsRejected:
                _status.packetsRejected + (warnings.isNotEmpty ? 0 : 0),
          ),
        );
        for (final warning in warnings) {
          _rejectController.add(InvalidPacketResult('field dropped: $warning'));
        }
      case EcgPacketResult(:final packet):
        _handleEcgPacket(packet);
      case InvalidPacketResult():
        _rejectController.add(result);
        _emit(
          _status.copyWith(packetsRejected: _status.packetsRejected + 1),
        );
    }
  }

  void _handleEcgBytes(List<int> bytes) {
    final result = BleProtocol.parseBytes(bytes);
    switch (result) {
      case EcgPacketResult(:final packet):
        _handleEcgPacket(packet);
      case InvalidPacketResult():
        _rejectController.add(result);
        _emit(_status.copyWith(packetsRejected: _status.packetsRejected + 1));
      case PhysiologyPacketResult(:final packet):
        _packetController.add(packet);
    }
  }

  void _handleEcgPacket(RawEcgPacket packet) {
    _ecgController.add(packet);
    _emit(
      _status.copyWith(
        lastPacketAt: packet.timestamp,
        capabilities: _status.capabilities.observingRawEcg(),
        packetsReceived: _status.packetsReceived + 1,
      ),
    );
  }

  // --- RSSI ---------------------------------------------------------------

  void _startRssiPolling(fbp.BluetoothDevice device) {
    _rssiTimer?.cancel();
    _rssiTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_status.isConnected) return;
      try {
        final rssi = await device.readRssi();
        _emit(_status.copyWith(rssi: rssi));
      } catch (_) {
        // RSSI is cosmetic; a failed read must not disturb the link.
      }
    });
  }

  // --- Disconnecting ------------------------------------------------------

  void _handleUnexpectedDisconnect() {
    _emit(
      _status.copyWith(
        connectionState: BleConnectionState.disconnected,
        clearDevice: true,
        lastError: 'The wearable disconnected.',
      ),
    );
    unawaited(_teardownConnection());
  }

  @override
  Future<void> disconnect() async {
    final device = _device;
    await _teardownConnection();
    try {
      await device?.disconnect();
    } catch (_) {
      // Already gone. Reflecting the disconnected state is what matters.
    }
    _emit(
      _status.copyWith(
        connectionState: BleConnectionState.disconnected,
        clearDevice: true,
        capabilities: DeviceCapabilities.unknown,
        clearError: true,
      ),
    );
  }

  Future<void> _teardownConnection() async {
    _rssiTimer?.cancel();
    _rssiTimer = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    for (final subscription in _valueSubscriptions) {
      await subscription.cancel();
    }
    _valueSubscriptions.clear();
    _device = null;
  }

  void _emit(BleLinkStatus status) {
    if (_disposed) return;
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stopScan();
    await _teardownConnection();
    await _adapterSubscription?.cancel();
    await _statusController.close();
    await _scanController.close();
    await _packetController.close();
    await _ecgController.close();
    await _rejectController.close();
  }
}
