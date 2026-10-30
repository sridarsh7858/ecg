import '../../data/models/physiological_input_packet.dart';
import 'feature_registry.dart';

/// The structured input to any [StressPredictionService].
///
/// A vector is always built through a [FeatureRegistry], so its ordering is
/// the registry's ordering and both the app and any future training pipeline
/// agree on what index means what.
///
/// **Values stay nullable all the way to the engine.** It is the engine's job
/// to decide what to do about a missing sensor, and to say so. Filling a gap
/// with a zero or a population mean here would hide the gap from the very code
/// that needs to know about it.
class StressFeatureVector {
  StressFeatureVector({
    required this.registry,
    required Map<StressFeature, double?> values,
    required this.packet,
  }) : _values = Map.unmodifiable(values);

  /// The registry that defined this vector's shape and order.
  final FeatureRegistry registry;

  /// The packet this vector was extracted from, kept for display and history.
  final PhysiologicalInputPacket packet;

  final Map<StressFeature, double?> _values;

  /// Extracts a vector from [packet] using [registry].
  factory StressFeatureVector.from(
    PhysiologicalInputPacket packet, {
    required FeatureRegistry registry,
  }) {
    return StressFeatureVector(
      registry: registry,
      packet: packet,
      values: {
        for (final feature in registry.enabledFeatures)
          feature: feature.extract(packet),
      },
    );
  }

  /// Features in vector order.
  List<StressFeature> get features => registry.enabledFeatures;

  /// Values in vector order. Entries are null where the sensor was absent.
  List<double?> get values =>
      features.map((f) => _values[f]).toList(growable: false);

  double? operator [](StressFeature feature) => _values[feature];

  bool has(StressFeature feature) => _values[feature] != null;

  /// Enabled features that this packet could not supply.
  List<StressFeature> get missingFeatures =>
      features.where((f) => _values[f] == null).toList(growable: false);

  /// Enabled features this packet did supply.
  List<StressFeature> get presentFeatures =>
      features.where((f) => _values[f] != null).toList(growable: false);

  /// True when every enabled feature has a value.
  bool get isComplete => missingFeatures.isEmpty;

  /// Fraction of enabled features that are present, 0..1.
  double get completeness =>
      features.isEmpty ? 0 : presentFeatures.length / features.length;

  /// A dense list for a model that cannot express "missing".
  ///
  /// Requires an explicit [substitute] for absent features, so that any
  /// imputation is a deliberate, visible decision made by the caller rather
  /// than a silent default buried in this class. A future
  /// `MLStressPredictionService` will pass its training-set means here.
  List<double> toDense(double Function(StressFeature feature) substitute) {
    return features
        .map((f) => _values[f] ?? substitute(f))
        .toList(growable: false);
  }

  /// Keyed view, handy for the developer panel and for logging.
  Map<String, double?> toMap() => {
    for (final feature in features) feature.key: _values[feature],
  };

  Map<String, dynamic> toJson() => {
    'order': registry.featureKeys,
    'values': toMap(),
    'complete': isComplete,
  };

  @override
  String toString() {
    final parts = features.map((f) {
      final value = _values[f];
      return '${f.key}=${value?.toStringAsFixed(1) ?? '-'}';
    });
    return 'StressFeatureVector(${parts.join(', ')})';
  }
}
