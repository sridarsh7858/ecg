import '../../data/models/physiological_input_packet.dart';
import '../../data/models/raw_ecg_packet.dart';
import 'ble_protocol.dart';
import 'device_capabilities.dart';

/// State of the phone's Bluetooth adapter.
enum BleAdapterState {
  /// Not yet determined.
  unknown,

  /// This device has no BLE support at all (or is a simulator/desktop test).
  unsupported,

  /// Bluetooth is switched off.
  off,

  /// Permission was denied, so the adapter cannot be used.
  unauthorized,

  /// Ready to scan.
  on;

  bool get canScan => this == BleAdapterState.on;

  String get label => switch (this) {
    BleAdapterState.unknown => 'Checking...',
    BleAdapterState.unsupported => 'Not supported on this device',
    BleAdapterState.off => 'Bluetooth is off',
    BleAdapterState.unauthorized => 'Permission needed',
    BleAdapterState.on => 'Ready',
  };
}

/// Where the link to a wearable currently is.
enum BleConnectionState {
  disconnected,
  scanning,
  connecting,

  /// Connected, enumerating GATT services.
  discovering,

  /// Connected and subscribed; packets may now arrive.
  connected;

  bool get isConnected => this == BleConnectionState.connected;

  bool get isBusy =>
      this == BleConnectionState.connecting ||
      this == BleConnectionState.discovering;

  String get label => switch (this) {
    BleConnectionState.disconnected => 'Not connected',
    BleConnectionState.scanning => 'Scanning...',
    BleConnectionState.connecting => 'Connecting...',
    BleConnectionState.discovering => 'Discovering services...',
    BleConnectionState.connected => 'Connected',
  };
}

/// A device seen during a scan.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.isNeuroPulse = false,
  });

  /// Platform device identifier (MAC on Android, UUID on iOS).
  final String id;

  /// Advertised name, or a placeholder when the device advertises none.
  final String name;

  /// Signal strength in dBm. Less negative is stronger.
  final int rssi;

  /// True when the advertised name matches the NeuroPulse prefix.
  final bool isNeuroPulse;

  /// Coarse signal bucket for the UI, 0..3.
  int get signalBars {
    if (rssi >= -60) return 3;
    if (rssi >= -75) return 2;
    if (rssi >= -90) return 1;
    return 0;
  }

  String get signalLabel => switch (signalBars) {
    3 => 'Excellent',
    2 => 'Good',
    1 => 'Weak',
    _ => 'Very weak',
  };

  @override
  bool operator ==(Object other) =>
      other is DiscoveredDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Everything the UI needs to know about the current link, in one object.
class BleLinkStatus {
  const BleLinkStatus({
    this.adapterState = BleAdapterState.unknown,
    this.connectionState = BleConnectionState.disconnected,
    this.device,
    this.capabilities = DeviceCapabilities.unknown,
    this.lastPacketAt,
    this.batteryPercentage,
    this.signalQuality,
    this.rssi,
    this.packetsReceived = 0,
    this.packetsRejected = 0,
    this.lastError,
  });

  final BleAdapterState adapterState;
  final BleConnectionState connectionState;

  /// The connected device, or null when disconnected.
  final DiscoveredDevice? device;

  final DeviceCapabilities capabilities;

  /// When the most recent valid packet arrived.
  final DateTime? lastPacketAt;

  /// Latest reported battery level, or null when the device does not report it.
  final int? batteryPercentage;

  /// Latest reported signal quality 0..1, or null when not reported.
  final double? signalQuality;

  /// Latest RSSI in dBm.
  final int? rssi;

  final int packetsReceived;
  final int packetsRejected;

  /// Last error message, for the Devices screen and the developer panel.
  final String? lastError;

  bool get isConnected => connectionState.isConnected;

  /// True when packets have arrived recently enough to call the stream live.
  ///
  /// A connection that is up but silent is not the same as a working one, and
  /// the device card must be able to say so.
  bool get isStreaming {
    final last = lastPacketAt;
    if (!isConnected || last == null) return false;
    return DateTime.now().difference(last) < const Duration(seconds: 10);
  }

  BleLinkStatus copyWith({
    BleAdapterState? adapterState,
    BleConnectionState? connectionState,
    DiscoveredDevice? device,
    bool clearDevice = false,
    DeviceCapabilities? capabilities,
    DateTime? lastPacketAt,
    int? batteryPercentage,
    double? signalQuality,
    int? rssi,
    int? packetsReceived,
    int? packetsRejected,
    String? lastError,
    bool clearError = false,
  }) {
    return BleLinkStatus(
      adapterState: adapterState ?? this.adapterState,
      connectionState: connectionState ?? this.connectionState,
      device: clearDevice ? null : (device ?? this.device),
      capabilities: capabilities ?? this.capabilities,
      lastPacketAt: lastPacketAt ?? this.lastPacketAt,
      batteryPercentage: batteryPercentage ?? this.batteryPercentage,
      signalQuality: signalQuality ?? this.signalQuality,
      rssi: rssi ?? this.rssi,
      packetsReceived: packetsReceived ?? this.packetsReceived,
      packetsRejected: packetsRejected ?? this.packetsRejected,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// The app's entire view of Bluetooth.
///
/// No screen, controller or repository imports `flutter_blue_plus` directly.
/// Everything goes through this interface, which means:
///
///  * the BLE package can be swapped without touching the UI;
///  * a [FakeBleService] can drive the whole app in tests and in the developer
///    panel, so the complete Bluetooth path is exercisable with no hardware.
abstract class BleService {
  /// Live link status. Emits on every state change.
  Stream<BleLinkStatus> get status;

  /// The most recent status, available synchronously.
  BleLinkStatus get currentStatus;

  /// Devices seen in the current scan, best signal first.
  Stream<List<DiscoveredDevice>> get scanResults;

  /// Validated physiological packets from the connected device.
  Stream<PhysiologicalInputPacket> get packets;

  /// Raw ECG bursts, when the firmware streams them.
  Stream<RawEcgPacket> get ecgPackets;

  /// Packets that failed validation. Surfaced in the developer panel so
  /// firmware bugs are visible rather than silently discarded.
  Stream<InvalidPacketResult> get rejectedPackets;

  /// Requests the runtime permissions BLE needs. Returns true when granted.
  Future<bool> requestPermissions();

  /// Asks the OS to switch Bluetooth on. Android only; a no-op elsewhere.
  Future<void> requestEnableBluetooth();

  Future<void> startScan({Duration timeout = const Duration(seconds: 12)});

  Future<void> stopScan();

  Future<void> connect(DiscoveredDevice device);

  Future<void> disconnect();

  /// Releases all resources. The service is unusable afterwards.
  Future<void> dispose();
}
