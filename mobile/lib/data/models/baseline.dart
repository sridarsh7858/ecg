import 'physiological_features.dart';

/// The user's personal calm reference point.
///
/// It is used for *contextual visualisation only* - the prediction engine does
/// not consume it. Once a real model exists, personalisation can be layered on
/// deliberately rather than by accident.
class Baseline {
  const Baseline({
    required this.hr,
    required this.rmssd,
    required this.sdnn,
    required this.pnn50,
    required this.recordedAt,
    required this.source,
  });

  final double hr;
  final double rmssd;
  final double sdnn;
  final double pnn50;
  final DateTime recordedAt;
  final String source;

  factory Baseline.fromFeatures(PhysiologicalFeatures features) => Baseline(
    hr: features.hr,
    rmssd: features.rmssd,
    sdnn: features.sdnn,
    pnn50: features.pnn50,
    recordedAt: features.timestamp,
    source: features.source,
  );

  /// Signed difference of [current] against this baseline, per feature.
  BaselineComparison compare(PhysiologicalFeatures current) {
    return BaselineComparison(
      hrDelta: current.hr - hr,
      rmssdDelta: current.rmssd - rmssd,
      sdnnDelta: current.sdnn - sdnn,
      pnn50Delta: current.pnn50 - pnn50,
    );
  }

  Map<String, dynamic> toJson() => {
    'hr': hr,
    'rmssd': rmssd,
    'sdnn': sdnn,
    'pnn50': pnn50,
    'recordedAt': recordedAt.toIso8601String(),
    'source': source,
  };

  factory Baseline.fromJson(Map<String, dynamic> json) => Baseline(
    hr: (json['hr'] as num).toDouble(),
    rmssd: (json['rmssd'] as num).toDouble(),
    sdnn: (json['sdnn'] as num).toDouble(),
    pnn50: (json['pnn50'] as num).toDouble(),
    recordedAt: DateTime.parse(json['recordedAt'] as String),
    source: json['source'] as String,
  );
}

/// Per-feature deltas between a measurement and the stored baseline.
class BaselineComparison {
  const BaselineComparison({
    required this.hrDelta,
    required this.rmssdDelta,
    required this.sdnnDelta,
    required this.pnn50Delta,
  });

  final double hrDelta;
  final double rmssdDelta;
  final double sdnnDelta;
  final double pnn50Delta;
}
