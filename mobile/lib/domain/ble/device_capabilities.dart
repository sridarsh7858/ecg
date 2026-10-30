import '../../data/models/physiological_input_packet.dart';

/// A sensor the wearable may or may not have.
enum SensorKind {
  ecg('ECG'),
  gsr('GSR'),
  accelerometer('Accelerometer'),
  gyroscope('Gyroscope'),
  battery('Battery'),
  rawEcg('Raw ECG');

  const SensorKind(this.label);

  final String label;
}

/// What the connected wearable can actually provide.
///
/// The hardware is expected to grow over time: an early board may be an ESP32
/// and an AD8232 only, with GSR and the IMU added later. The app must therefore
/// never assume a sensor exists. Capabilities are established two ways:
///
/// 1. **Declared** - the device info characteristic advertises them on connect.
/// 2. **Observed** - a field arriving in a packet proves that sensor is live.
///
/// Observation is the more trustworthy of the two, because firmware that
/// advertises a sensor it is not actually reading is a normal bring-up state.
/// A sensor is reported present if either source says so, and the UI shows
/// which sensors have been *seen*, so a mis-declared capability is visible
/// rather than silently believed.
class DeviceCapabilities {
  const DeviceCapabilities({
    this.declared = const {},
    this.observed = const {},
    this.firmwareVersion,
    this.hardwareRevision,
  });

  /// Sensors the device claimed in its device info characteristic.
  final Set<SensorKind> declared;

  /// Sensors for which real data has actually arrived.
  final Set<SensorKind> observed;

  final String? firmwareVersion;
  final String? hardwareRevision;

  /// Nothing known yet - the state before a device connects.
  static const DeviceCapabilities unknown = DeviceCapabilities();

  Set<SensorKind> get all => {...declared, ...observed};

  bool has(SensorKind sensor) => all.contains(sensor);

  /// True when data for this sensor has genuinely been received.
  bool hasSeen(SensorKind sensor) => observed.contains(sensor);

  /// Declared but never actually delivered. Useful during firmware bring-up.
  Set<SensorKind> get declaredButUnseen => declared.difference(observed);

  bool get isEmpty => all.isEmpty;

  /// Updates capabilities from a packet that just arrived.
  ///
  /// Only fields that are genuinely present count. A packet omitting GSR does
  /// not retract a previously observed GSR sensor - BLE packets are allowed to
  /// be partial, so absence in one packet is not evidence of absence overall.
  DeviceCapabilities observing(PhysiologicalInputPacket packet) {
    final seen = <SensorKind>{...observed};

    if (packet.hasCardiovascular || packet.hasHrv) seen.add(SensorKind.ecg);
    if (packet.hasGsr) seen.add(SensorKind.gsr);
    if (packet.hasAccelerometer) seen.add(SensorKind.accelerometer);
    if (packet.hasGyroscope) seen.add(SensorKind.gyroscope);
    if (packet.hasBattery) seen.add(SensorKind.battery);
    if (packet.hasRawEcg) seen.add(SensorKind.rawEcg);

    if (seen.length == observed.length) return this;

    return DeviceCapabilities(
      declared: declared,
      observed: seen,
      firmwareVersion: firmwareVersion,
      hardwareRevision: hardwareRevision,
    );
  }

  /// Records that a raw ECG burst arrived.
  DeviceCapabilities observingRawEcg() {
    if (observed.contains(SensorKind.rawEcg)) return this;
    return DeviceCapabilities(
      declared: declared,
      observed: {...observed, SensorKind.rawEcg},
      firmwareVersion: firmwareVersion,
      hardwareRevision: hardwareRevision,
    );
  }

  /// Parses the device info characteristic payload.
  ///
  /// Expected shape, all fields optional:
  /// ```json
  /// {
  ///   "fw": "0.1.0",
  ///   "hw": "rev-a",
  ///   "sensors": ["ecg", "gsr", "accel", "battery"]
  /// }
  /// ```
  factory DeviceCapabilities.fromDeviceInfo(
    Map<String, dynamic> json, {
    Set<SensorKind> observed = const {},
  }) {
    final declared = <SensorKind>{};
    final sensors = json['sensors'];
    if (sensors is List) {
      for (final entry in sensors) {
        final kind = _sensorFromWire(entry?.toString());
        if (kind != null) declared.add(kind);
      }
    }
    return DeviceCapabilities(
      declared: declared,
      observed: observed,
      firmwareVersion: json['fw'] as String? ?? json['firmware'] as String?,
      hardwareRevision: json['hw'] as String? ?? json['hardware'] as String?,
    );
  }

  static SensorKind? _sensorFromWire(String? value) {
    return switch (value?.toLowerCase().trim()) {
      'ecg' || 'hr' || 'hrv' || 'ad8232' => SensorKind.ecg,
      'gsr' || 'eda' => SensorKind.gsr,
      'accel' || 'accelerometer' || 'acc' => SensorKind.accelerometer,
      'gyro' || 'gyroscope' => SensorKind.gyroscope,
      'battery' || 'batt' => SensorKind.battery,
      'raw_ecg' || 'rawecg' => SensorKind.rawEcg,
      _ => null,
    };
  }

  /// Rows for the capability list in the Devices screen.
  ///
  /// Every sensor is listed, present or not, so a missing sensor is visibly
  /// absent rather than merely unmentioned.
  List<({SensorKind sensor, bool present, bool seen})> get summary =>
      SensorKind.values
          .map(
            (sensor) => (
              sensor: sensor,
              present: has(sensor),
              seen: hasSeen(sensor),
            ),
          )
          .toList(growable: false);

  @override
  String toString() {
    if (isEmpty) return 'DeviceCapabilities(none known)';
    final parts = SensorKind.values.map(
      (s) => '${s.label}: ${has(s) ? (hasSeen(s) ? 'yes' : 'declared') : '-'}',
    );
    return 'DeviceCapabilities(${parts.join(', ')})';
  }
}
