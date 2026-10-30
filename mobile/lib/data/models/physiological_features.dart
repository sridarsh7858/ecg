import 'dart:math' as math;

/// Where a set of features came from.
///
/// The value is persisted with every session so history can always tell demo
/// data apart from real hardware data once the ESP32 is connected.
class DataSourceTag {
  const DataSourceTag._();

  /// Simulated data produced on-device. Always shown as "Demo data" in the UI.
  static const String demo = 'DEMO';

  /// Data streamed from the ECG front-end over BLE. Not active yet.
  static const String ble = 'BLE';
}

/// Heart-rate variability feature vector.
///
/// This is the single input contract for every [StressPredictionService]
/// implementation. When the ESP32 pipeline lands it will produce exactly this
/// object, so nothing downstream needs to change.
class PhysiologicalFeatures {
  const PhysiologicalFeatures({
    required this.hr,
    required this.meanRR,
    required this.rmssd,
    required this.sdnn,
    required this.pnn50,
    required this.timestamp,
    required this.source,
  });

  /// Heart rate in beats per minute.
  final double hr;

  /// Mean R-R interval in milliseconds.
  final double meanRR;

  /// Root mean square of successive R-R differences, in milliseconds.
  final double rmssd;

  /// Standard deviation of N-N intervals, in milliseconds.
  final double sdnn;

  /// Percentage of successive R-R intervals differing by more than 50 ms.
  final double pnn50;

  final DateTime timestamp;

  /// One of [DataSourceTag].
  final String source;

  bool get isDemo => source == DataSourceTag.demo;

  /// Convenience constructor deriving [meanRR] from [hr].
  factory PhysiologicalFeatures.fromHr({
    required double hr,
    required double rmssd,
    required double sdnn,
    required double pnn50,
    DateTime? timestamp,
    String source = DataSourceTag.demo,
  }) {
    return PhysiologicalFeatures(
      hr: hr,
      meanRR: 60000 / math.max(hr, 1),
      rmssd: rmssd,
      sdnn: sdnn,
      pnn50: pnn50,
      timestamp: timestamp ?? DateTime.now(),
      source: source,
    );
  }

  PhysiologicalFeatures copyWith({
    double? hr,
    double? meanRR,
    double? rmssd,
    double? sdnn,
    double? pnn50,
    DateTime? timestamp,
    String? source,
  }) {
    return PhysiologicalFeatures(
      hr: hr ?? this.hr,
      meanRR: meanRR ?? this.meanRR,
      rmssd: rmssd ?? this.rmssd,
      sdnn: sdnn ?? this.sdnn,
      pnn50: pnn50 ?? this.pnn50,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
    'hr': hr,
    'meanRR': meanRR,
    'rmssd': rmssd,
    'sdnn': sdnn,
    'pnn50': pnn50,
    'timestamp': timestamp.toIso8601String(),
    'source': source,
  };

  factory PhysiologicalFeatures.fromJson(Map<String, dynamic> json) {
    return PhysiologicalFeatures(
      hr: (json['hr'] as num).toDouble(),
      meanRR: (json['meanRR'] as num).toDouble(),
      rmssd: (json['rmssd'] as num).toDouble(),
      sdnn: (json['sdnn'] as num).toDouble(),
      pnn50: (json['pnn50'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      source: json['source'] as String? ?? DataSourceTag.demo,
    );
  }

  @override
  String toString() =>
      'PhysiologicalFeatures(hr: ${hr.toStringAsFixed(1)}, '
      'rmssd: ${rmssd.toStringAsFixed(1)}, sdnn: ${sdnn.toStringAsFixed(1)}, '
      'pnn50: ${pnn50.toStringAsFixed(1)}, source: $source)';

  @override
  bool operator ==(Object other) =>
      other is PhysiologicalFeatures &&
      other.hr == hr &&
      other.meanRR == meanRR &&
      other.rmssd == rmssd &&
      other.sdnn == sdnn &&
      other.pnn50 == pnn50 &&
      other.timestamp == timestamp &&
      other.source == source;

  @override
  int get hashCode =>
      Object.hash(hr, meanRR, rmssd, sdnn, pnn50, timestamp, source);
}
