import '../../data/models/physiological_input_packet.dart';

/// Every physiological feature the stress model may eventually consume.
///
/// Adding a feature here does **not** mean the model uses it. It means the app
/// knows how to extract it from a [PhysiologicalInputPacket] and can offer it
/// to a model that wants it. Which of these a trained model actually consumes
/// is decided when the dataset exists - see docs/future_ml_training.md.
enum StressFeature {
  hr('hr', 'Heart Rate', 'BPM', FeatureGroup.cardiovascular),
  meanRR('meanRR', 'Mean R-R', 'ms', FeatureGroup.cardiovascular),
  rmssd('rmssd', 'RMSSD', 'ms', FeatureGroup.cardiovascular),
  sdnn('sdnn', 'SDNN', 'ms', FeatureGroup.cardiovascular),
  pnn50('pnn50', 'pNN50', '%', FeatureGroup.cardiovascular),
  gsrLevel('gsrLevel', 'GSR Level', 'uS', FeatureGroup.electrodermal),
  gsrPeaks('gsrPeaks', 'GSR Peaks', 'count', FeatureGroup.electrodermal),
  movementIntensity(
    'movementIntensity',
    'Movement Intensity',
    '0-1',
    FeatureGroup.movement,
  );

  const StressFeature(this.key, this.label, this.unit, this.group);

  /// Stable identifier used in storage, in the registry and in any future
  /// training pipeline. Must match the column name the dataset uses.
  final String key;

  final String label;
  final String unit;
  final FeatureGroup group;

  /// Pulls this feature out of a packet, or null when the sensor is absent.
  ///
  /// Null means "not measured". It never falls back to a default, because a
  /// zero would be indistinguishable from a real reading of zero.
  double? extract(PhysiologicalInputPacket packet) => switch (this) {
    StressFeature.hr => packet.effectiveHeartRate,
    StressFeature.meanRR => packet.effectiveMeanRR,
    StressFeature.rmssd => packet.rmssd,
    StressFeature.sdnn => packet.sdnn,
    StressFeature.pnn50 => packet.pnn50,
    StressFeature.gsrLevel => packet.gsrLevel ?? packet.gsrValue,
    StressFeature.gsrPeaks => packet.gsrPeaks?.toDouble(),
    StressFeature.movementIntensity => packet.effectiveMovementIntensity,
  };

  static StressFeature? fromKey(String key) {
    for (final feature in StressFeature.values) {
      if (feature.key == key) return feature;
    }
    return null;
  }
}

/// How features are grouped in the UI and in the registry.
enum FeatureGroup {
  cardiovascular('Cardiovascular'),
  electrodermal('GSR / EDA'),
  movement('Movement');

  const FeatureGroup(this.label);

  final String label;

  List<StressFeature> get features =>
      StressFeature.values.where((f) => f.group == this).toList();
}

/// Which features are offered to the prediction engine, and in what order.
///
/// This exists so that the app does not hard-code a feature set before the
/// training dataset is known. When a dataset arrives, whichever columns it
/// actually contains determine the registry the shipped model is built
/// against, and nothing in the UI or the data layer has to change.
///
/// The order of [enabledFeatures] is the vector order. It is derived from the
/// declaration order of [StressFeature], never from a set's iteration order,
/// so it is stable across runs and across platforms. A silently reordered
/// feature vector is a classic way to ship a model that quietly does nothing.
class FeatureRegistry {
  FeatureRegistry({Set<StressFeature>? enabled})
    : _enabled = {...(enabled ?? defaultEnabled)};

  /// The features enabled today.
  ///
  /// Cardiovascular only. GSR and movement are declared and plumbed all the
  /// way through, but are off by default because no dataset has yet shown they
  /// help - and turning them on would imply a validated contribution that has
  /// not been measured. Flip them on when the data says to.
  static const Set<StressFeature> defaultEnabled = {
    StressFeature.hr,
    StressFeature.meanRR,
    StressFeature.rmssd,
    StressFeature.sdnn,
    StressFeature.pnn50,
  };

  /// Every feature the app can extract, whether enabled or not.
  static List<StressFeature> get available => StressFeature.values;

  final Set<StressFeature> _enabled;

  /// Enabled features in stable declaration order. This is the vector order.
  List<StressFeature> get enabledFeatures =>
      StressFeature.values.where(_enabled.contains).toList(growable: false);

  /// Feature keys in vector order, e.g. `[hr, meanRR, rmssd, sdnn, pnn50]`.
  List<String> get featureKeys =>
      enabledFeatures.map((f) => f.key).toList(growable: false);

  int get length => _enabled.length;

  bool isEnabled(StressFeature feature) => _enabled.contains(feature);

  void enable(StressFeature feature) => _enabled.add(feature);

  void disable(StressFeature feature) => _enabled.remove(feature);

  void setEnabled(StressFeature feature, bool enabled) {
    if (enabled) {
      _enabled.add(feature);
    } else {
      _enabled.remove(feature);
    }
  }

  /// Enabled features belonging to [group], in vector order.
  List<StressFeature> enabledIn(FeatureGroup group) =>
      enabledFeatures.where((f) => f.group == group).toList(growable: false);

  FeatureRegistry copy() => FeatureRegistry(enabled: _enabled);

  /// Builds a registry from the columns a dataset actually provides.
  ///
  /// This is the hook the future training pipeline uses: hand it the dataset's
  /// column names and it enables exactly the intersection with what the app
  /// can extract, ignoring columns the app has no sensor for.
  factory FeatureRegistry.forDatasetColumns(Iterable<String> columns) {
    final enabled = <StressFeature>{};
    for (final column in columns) {
      final feature = StressFeature.fromKey(column);
      if (feature != null) enabled.add(feature);
    }
    return FeatureRegistry(enabled: enabled);
  }

  Map<String, dynamic> toJson() => {'enabled': featureKeys};

  factory FeatureRegistry.fromJson(Map<String, dynamic> json) {
    final keys = (json['enabled'] as List?)?.cast<String>() ?? const [];
    if (keys.isEmpty) return FeatureRegistry();
    return FeatureRegistry.forDatasetColumns(keys);
  }

  @override
  String toString() => 'FeatureRegistry(${featureKeys.join(', ')})';
}
