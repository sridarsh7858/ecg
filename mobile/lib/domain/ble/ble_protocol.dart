import 'dart:convert';

import '../../data/models/physiological_input_packet.dart';
import '../../data/models/raw_ecg_packet.dart';

/// GATT identifiers for the NeuroPulse wearable.
///
/// **These are not final.** The ESP32 firmware does not exist yet, so these
/// are the values the firmware should be written against; if the firmware ends
/// up using different ones, changing them here is the only app-side change
/// required. Nothing else in the codebase hard-codes a UUID.
///
/// They are 128-bit custom UUIDs rather than adopted 16-bit ones because this
/// is a vendor-specific service. The battery characteristic is the one
/// exception worth noting: the Bluetooth SIG defines a standard Battery
/// Service (0x180F), and [standardBatteryServiceUuid] is accepted as well, so
/// firmware may use either.
class BleUuids {
  const BleUuids._();

  /// Advertised name prefix the scanner filters on, e.g. "NeuroPulse-ESP32".
  static const String deviceNamePrefix = 'NeuroPulse';

  /// Primary service exposing all NeuroPulse characteristics.
  static const String neuropulseServiceUuid =
      '6e1a0001-b5a3-f393-e0a9-e50e24dcca9e';

  /// Notify. Derived physiological packets - the main data path.
  static const String physiologyCharacteristicUuid =
      '6e1a0002-b5a3-f393-e0a9-e50e24dcca9e';

  /// Read. Firmware version and sensor capability advertisement.
  static const String deviceInfoCharacteristicUuid =
      '6e1a0003-b5a3-f393-e0a9-e50e24dcca9e';

  /// Notify. Battery state, when the firmware does not use 0x180F.
  static const String batteryCharacteristicUuid =
      '6e1a0004-b5a3-f393-e0a9-e50e24dcca9e';

  /// Notify. Raw ECG sample bursts. Optional, off by default in firmware.
  static const String rawEcgCharacteristicUuid =
      '6e1a0005-b5a3-f393-e0a9-e50e24dcca9e';

  /// Write. Commands to the wearable (start, stop, set window length).
  static const String controlCharacteristicUuid =
      '6e1a0006-b5a3-f393-e0a9-e50e24dcca9e';

  /// Bluetooth SIG standard Battery Service, accepted as an alternative.
  static const String standardBatteryServiceUuid =
      '0000180f-0000-1000-8000-00805f9b34fb';

  /// Bluetooth SIG standard Battery Level characteristic.
  static const String standardBatteryLevelUuid =
      '00002a19-0000-1000-8000-00805f9b34fb';

  /// Case-insensitive UUID comparison. Platforms disagree on casing and on
  /// whether they return the short or long form, so never compare with `==`.
  static bool matches(String a, String b) {
    return _normalise(a) == _normalise(b);
  }

  static String _normalise(String uuid) {
    final lower = uuid.toLowerCase().replaceAll('-', '');
    // Expand a 16-bit short form into the full base UUID.
    if (lower.length == 4) return '0000${lower}00001000800000805f9b34fb';
    return lower;
  }
}

/// Packet type discriminator carried in the `type` field.
enum BlePacketType {
  physiology('physiology'),
  ecg('ecg'),
  status('status');

  const BlePacketType(this.wireValue);

  final String wireValue;

  static BlePacketType? fromWire(String? value) {
    if (value == null) return null;
    for (final type in BlePacketType.values) {
      if (type.wireValue == value.toLowerCase()) return type;
    }
    return null;
  }
}

/// Outcome of parsing one BLE notification.
///
/// A sealed hierarchy so callers cannot forget the failure case. Malformed
/// data from a half-written firmware is expected during bring-up, and it must
/// never reach the UI as an exception.
sealed class BlePacketResult {
  const BlePacketResult();
}

/// A validated physiological packet.
class PhysiologyPacketResult extends BlePacketResult {
  const PhysiologyPacketResult(this.packet, {this.warnings = const []});

  final PhysiologicalInputPacket packet;

  /// Fields that were present but out of range, and were therefore dropped.
  /// The packet is still usable; these are for the developer panel.
  final List<String> warnings;
}

/// A validated raw ECG burst.
class EcgPacketResult extends BlePacketResult {
  const EcgPacketResult(this.packet);

  final RawEcgPacket packet;
}

/// The packet was rejected. [reason] is developer-facing, not user-facing.
class InvalidPacketResult extends BlePacketResult {
  const InvalidPacketResult(this.reason, {this.raw});

  final String reason;

  /// The offending payload, truncated, for the developer panel.
  final String? raw;
}

/// Parses and validates packets sent by the wearable.
///
/// The wire format is JSON. Binary would be smaller, but JSON is inspectable
/// with a serial monitor and a phone-side log, which matters far more while
/// firmware is being brought up. Switching to a packed binary layout later is
/// a change confined to this class.
///
/// Two rules govern everything here:
///
/// 1. **Missing is fine.** Any field may be absent. A packet carrying only
///    `{"hr": 82}` is valid. Absent stays absent - it is never defaulted.
/// 2. **Malformed is survivable.** No input, however broken, may throw out of
///    [parse]. Bad packets are rejected and counted, and the link stays up.
class BleProtocol {
  const BleProtocol._();

  /// Largest payload accepted, guarding against a runaway firmware loop.
  static const int maxPayloadBytes = 64 * 1024;

  /// Largest raw ECG burst accepted in a single packet.
  static const int maxEcgSamplesPerPacket = 2000;

  // Physiological plausibility ranges. Values outside these are dropped as
  // sensor error rather than trusted. They are deliberately wide: the job is
  // to catch a disconnected electrode reading 0 or an ADC glitch reading
  // 40000, not to enforce a clinical normal range on a real person.
  static const ValueRange hrRange = ValueRange(20, 250);
  static const ValueRange rrRange = ValueRange(200, 3000);
  static const ValueRange rmssdRange = ValueRange(0, 1000);
  static const ValueRange sdnnRange = ValueRange(0, 1000);
  static const ValueRange pnn50Range = ValueRange(0, 100);
  static const ValueRange gsrRange = ValueRange(0, 1000);
  static const ValueRange accelRange = ValueRange(-16, 16);
  static const ValueRange gyroRange = ValueRange(-2000, 2000);
  static const ValueRange batteryPercentRange = ValueRange(0, 100);
  static const ValueRange batteryVoltageRange = ValueRange(0, 12);
  static const ValueRange batteryCurrentRange = ValueRange(-5000, 5000);
  static const ValueRange signalQualityRange = ValueRange(0, 1);

  /// Parses raw notification bytes.
  static BlePacketResult parseBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      return const InvalidPacketResult('empty payload');
    }
    if (bytes.length > maxPayloadBytes) {
      return InvalidPacketResult('payload too large (${bytes.length} bytes)');
    }
    try {
      return parse(utf8.decode(bytes, allowMalformed: false));
    } on FormatException {
      return const InvalidPacketResult('payload is not valid UTF-8');
    }
  }

  /// Parses a JSON payload into a validated packet.
  ///
  /// Never throws. Every failure path returns an [InvalidPacketResult].
  static BlePacketResult parse(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) {
      return const InvalidPacketResult('empty payload');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (error) {
      return InvalidPacketResult(
        'malformed JSON: ${error.message}',
        raw: _truncate(trimmed),
      );
    }

    if (decoded is! Map) {
      return InvalidPacketResult(
        'expected a JSON object, got ${decoded.runtimeType}',
        raw: _truncate(trimmed),
      );
    }

    final json = Map<String, dynamic>.from(decoded);

    // An absent `type` is treated as a physiology packet. The firmware should
    // always send it, but rejecting a packet that is otherwise perfectly good
    // over a missing discriminator would be needlessly brittle during
    // bring-up.
    final type =
        BlePacketType.fromWire(json['type'] as String?) ??
        BlePacketType.physiology;

    return switch (type) {
      BlePacketType.physiology => _parsePhysiology(json, trimmed),
      BlePacketType.ecg => _parseEcg(json, trimmed),
      BlePacketType.status => _parsePhysiology(json, trimmed),
    };
  }

  static BlePacketResult _parsePhysiology(
    Map<String, dynamic> json,
    String raw,
  ) {
    final warnings = <String>[];

    double? read(List<String> keys, ValueRange range) {
      for (final key in keys) {
        if (!json.containsKey(key)) continue;
        final value = json[key];
        if (value == null) return null;
        if (value is! num) {
          warnings.add('$key is not numeric (${value.runtimeType}), dropped');
          return null;
        }
        final asDouble = value.toDouble();
        if (asDouble.isNaN || asDouble.isInfinite) {
          warnings.add('$key is not finite, dropped');
          return null;
        }
        if (!range.contains(asDouble)) {
          warnings.add('$key=$asDouble outside $range, dropped');
          return null;
        }
        return asDouble;
      }
      return null;
    }

    int? readInt(List<String> keys, ValueRange range) =>
        read(keys, range)?.round();

    final packet = PhysiologicalInputPacket(
      timestamp: _readTimestamp(json),
      source: PhysiologicalSource.bluetooth,
      heartRate: read(['hr', 'heart_rate', 'heartRate'], hrRange),
      meanRR: read(['mean_rr', 'meanRR', 'meanRr'], rrRange),
      rmssd: read(['rmssd', 'RMSSD'], rmssdRange),
      sdnn: read(['sdnn', 'SDNN'], sdnnRange),
      pnn50: read(['pnn50', 'pNN50'], pnn50Range),
      gsrValue: read(['gsr', 'gsr_value', 'gsrValue'], gsrRange),
      gsrLevel: read(['gsr_level', 'gsrLevel'], gsrRange),
      gsrPeaks: readInt(['gsr_peaks', 'gsrPeaks'], const ValueRange(0, 1000)),
      accelX: read(['accel_x', 'accelX', 'ax'], accelRange),
      accelY: read(['accel_y', 'accelY', 'ay'], accelRange),
      accelZ: read(['accel_z', 'accelZ', 'az'], accelRange),
      movementIntensity: read(
        ['movement', 'movement_intensity', 'movementIntensity'],
        const ValueRange(0, 1),
      ),
      gyroX: read(['gyro_x', 'gyroX', 'gx'], gyroRange),
      gyroY: read(['gyro_y', 'gyroY', 'gy'], gyroRange),
      gyroZ: read(['gyro_z', 'gyroZ', 'gz'], gyroRange),
      batteryVoltage: read(
        ['battery_voltage', 'batteryVoltage', 'vbat'],
        batteryVoltageRange,
      ),
      batteryCurrent: read(
        ['battery_current', 'batteryCurrent', 'ibat'],
        batteryCurrentRange,
      ),
      batteryPercentage: readInt(
        ['battery', 'battery_percentage', 'batteryPercentage'],
        batteryPercentRange,
      ),
      userStressRating: readInt(
        ['stress_rating', 'userStressRating'],
        const ValueRange(1, 5),
      ),
      sessionContext: json['context'] as String? ?? json['session_context'] as String?,
      signalQuality: read(
        ['signal_quality', 'signalQuality', 'sq'],
        signalQualityRange,
      ),
      rrIntervals: _readDoubleList(json, ['rr_intervals', 'rrIntervals']),
      rPeaks: _readIntList(json, ['r_peaks', 'rPeaks']),
    );

    // A packet in which every physiological field was absent or rejected
    // carries no information. Accepting it would let the UI display a reading
    // built entirely out of nulls.
    //
    // HRV counts on its own here. A detached electrode can produce a packet
    // whose heart rate is out of range and therefore dropped, while RMSSD and
    // SDNN are still present and valid - discarding the whole packet over the
    // one bad field would throw away good data.
    if (!packet.hasCardiovascular &&
        !packet.hasHrv &&
        !packet.hasGsr &&
        !packet.hasMovement &&
        !packet.hasBattery) {
      return InvalidPacketResult(
        warnings.isEmpty
            ? 'packet contained no recognised physiological fields'
            : 'every field was rejected: ${warnings.join('; ')}',
        raw: _truncate(raw),
      );
    }

    return PhysiologyPacketResult(packet, warnings: warnings);
  }

  static BlePacketResult _parseEcg(Map<String, dynamic> json, String raw) {
    final samplesField = json['samples'];
    if (samplesField is! List) {
      return InvalidPacketResult(
        'ecg packet missing a "samples" array',
        raw: _truncate(raw),
      );
    }
    if (samplesField.isEmpty) {
      return InvalidPacketResult('ecg packet has no samples', raw: _truncate(raw));
    }
    if (samplesField.length > maxEcgSamplesPerPacket) {
      return InvalidPacketResult(
        'ecg burst too large (${samplesField.length} samples)',
        raw: _truncate(raw),
      );
    }

    final samples = <double>[];
    for (final value in samplesField) {
      if (value is! num) {
        return InvalidPacketResult(
          'ecg samples must all be numeric, found ${value.runtimeType}',
          raw: _truncate(raw),
        );
      }
      final asDouble = value.toDouble();
      if (asDouble.isNaN || asDouble.isInfinite) {
        return InvalidPacketResult(
          'ecg samples must all be finite',
          raw: _truncate(raw),
        );
      }
      samples.add(asDouble);
    }

    final rate = json['sample_rate'] ?? json['sampleRate'] ?? json['fs'];
    final sequence = json['seq'] ?? json['sequence'];

    return EcgPacketResult(
      RawEcgPacket(
        timestamp: _readTimestamp(json),
        samples: samples,
        sampleRateHz: rate is num && rate > 0 && rate <= 10000
            ? rate.toDouble()
            : null,
        sequence: sequence is num ? sequence.toInt() : null,
      ),
    );
  }

  /// Reads the packet timestamp.
  ///
  /// The firmware sends Unix seconds. An ESP32 without an RTC or an NTP sync
  /// will send something meaningless (often near zero, or its uptime), so a
  /// timestamp that is not plausibly recent is replaced with the phone's
  /// clock. The phone's clock is the one we can actually trust here.
  static DateTime _readTimestamp(Map<String, dynamic> json) {
    final value = json['timestamp'] ?? json['ts'];
    if (value is num) {
      final seconds = value.toInt();
      // 1_000_000_000 = 2001-09-09. Anything earlier is not a real wall clock.
      if (seconds > 1000000000 && seconds < 4102444800) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
      // Milliseconds, in case the firmware sends those instead.
      if (seconds > 1000000000000 && seconds < 4102444800000) {
        return DateTime.fromMillisecondsSinceEpoch(seconds);
      }
    }
    return DateTime.now();
  }

  static List<double>? _readDoubleList(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value is! List) continue;
      final result = <double>[];
      for (final entry in value) {
        if (entry is! num) return null;
        final asDouble = entry.toDouble();
        if (asDouble.isNaN || asDouble.isInfinite) return null;
        result.add(asDouble);
      }
      return result.isEmpty ? null : result;
    }
    return null;
  }

  static List<int>? _readIntList(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value is! List) continue;
      final result = <int>[];
      for (final entry in value) {
        if (entry is! num) return null;
        result.add(entry.toInt());
      }
      return result.isEmpty ? null : result;
    }
    return null;
  }

  static String _truncate(String value, [int limit = 240]) =>
      value.length <= limit ? value : '${value.substring(0, limit)}...';
}

/// Inclusive numeric range used for packet validation.
///
/// Public because the validation bounds are part of the protocol contract:
/// firmware authors need to know what the app will accept.
class ValueRange {
  const ValueRange(this.min, this.max);

  final double min;
  final double max;

  bool contains(double value) => value >= min && value <= max;

  @override
  String toString() => '[$min, $max]';
}
