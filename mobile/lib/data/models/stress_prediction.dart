import '../../domain/stress/stress_level.dart';
import 'physiological_features.dart';

/// The output contract of every [StressPredictionService].
///
/// The rest of the app consumes only this object, so it cannot tell whether the
/// estimate came from the demo engine, an on-device ML model, or a remote one.
class StressPrediction {
  const StressPrediction({
    required this.level,
    required this.label,
    required this.confidence,
    required this.features,
    required this.timestamp,
    required this.source,
    required this.modelVersion,
  });

  final StressLevel level;

  /// Human readable label, e.g. "Moderate".
  final String label;

  /// 0.0 .. 1.0
  final double confidence;

  final PhysiologicalFeatures features;
  final DateTime timestamp;

  /// One of [DataSourceTag] - describes where the *input data* came from.
  final String source;

  /// Identifies the engine that produced the estimate, e.g. "demo-1.0.0".
  final String modelVersion;

  int get levelNumber => level.number;

  bool get isDemo => source == DataSourceTag.demo;

  /// Confidence as a whole percentage, for display.
  int get confidencePercent => (confidence * 100).round();

  StressPrediction copyWith({
    StressLevel? level,
    String? label,
    double? confidence,
    PhysiologicalFeatures? features,
    DateTime? timestamp,
    String? source,
    String? modelVersion,
  }) {
    return StressPrediction(
      level: level ?? this.level,
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      features: features ?? this.features,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      modelVersion: modelVersion ?? this.modelVersion,
    );
  }

  Map<String, dynamic> toJson() => {
    'level': level.number,
    'label': label,
    'confidence': confidence,
    'features': features.toJson(),
    'timestamp': timestamp.toIso8601String(),
    'source': source,
    'modelVersion': modelVersion,
  };

  factory StressPrediction.fromJson(Map<String, dynamic> json) {
    return StressPrediction(
      level: StressLevel.fromNumber((json['level'] as num).toInt()),
      label: json['label'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      features: PhysiologicalFeatures.fromJson(
        Map<String, dynamic>.from(json['features'] as Map),
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      source: json['source'] as String? ?? DataSourceTag.demo,
      modelVersion: json['modelVersion'] as String? ?? 'unknown',
    );
  }

  @override
  String toString() =>
      'StressPrediction(level: ${level.number}, label: $label, '
      'confidence: ${confidence.toStringAsFixed(2)}, model: $modelVersion)';
}
