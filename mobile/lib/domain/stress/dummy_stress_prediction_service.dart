import '../../data/models/stress_prediction.dart';
import 'feature_registry.dart';
import 'stress_feature_vector.dart';
import 'stress_level.dart';
import 'stress_prediction_service.dart';
import 'stress_scoring.dart';

/// The demo stress engine. **This is not a machine-learning model.**
///
/// It is a transparent weighted heuristic over HRV features ([StressScoring]).
/// It exists so the whole application - dashboard, measurement flow,
/// recommendations, games, history - can be built, demonstrated and tested end
/// to end with no hardware and no dataset.
///
/// It is deliberately *not* called a prediction, an AI, or a model anywhere in
/// the UI. It is shown as "Demo Stress Engine", every result it produces
/// carries `modelVersion: demo-1.0.0`, and [isDemo] is true so that every
/// screen can label it. It has never been validated against anything, and no
/// accuracy is claimed for it because none has been measured.
///
/// ## The heuristic, in full
///
/// Each available feature is normalised to 0..1 over a plausible adult range,
/// inverted where lower means more aroused (the HRV features), and combined
/// with the weights in [StressScoring]. The result is banded into five equal
/// fifths. That is the entire model. It is written down here so that nobody -
/// including a future reader of this project - can mistake it for something
/// that learned anything from data.
class DummyStressPredictionService extends StressPredictionService {
  DummyStressPredictionService({
    this.processingDelay = Duration.zero,
    FeatureRegistry? registry,
  }) : _registry = registry ?? FeatureRegistry();

  /// Small artificial delay so the "Processing" step is visible in the UI.
  /// Tests construct the service with [Duration.zero].
  final Duration processingDelay;

  final FeatureRegistry _registry;

  @override
  FeatureRegistry get featureRegistry => _registry;

  @override
  String get modelVersion => 'demo-1.0.0';

  @override
  String get displayName => 'Demo Stress Engine';

  @override
  bool get isDemo => true;

  @override
  Future<void> initialise() async {
    // Nothing to load. A trained engine would load its asset here.
  }

  @override
  Future<StressPrediction> predictFromVector(StressFeatureVector vector) async {
    if (processingDelay > Duration.zero) {
      await Future<void>.delayed(processingDelay);
    }
    return scoreSync(vector);
  }

  /// Synchronous variant, for tests and for the developer panel.
  StressPrediction scoreSync(StressFeatureVector vector) {
    final score = _score(vector);
    final level = StressScoring.levelForScore(score);
    final packet = vector.packet;

    return StressPrediction(
      level: level,
      label: StressLevelConfig.of(level).title,
      confidence: _confidence(score, vector),
      features: packet.toLegacyFeatures(),
      timestamp: DateTime.now(),
      source: packet.source.tag,
      modelVersion: modelVersion,
    );
  }

  /// Weighted arousal score over the features that are actually present.
  ///
  /// Weights are renormalised across the available features rather than
  /// treating an absent one as zero. A missing SDNN must not drag the score
  /// toward "calm" - it should simply not vote. When nothing at all is
  /// available the score is the neutral midpoint, which lands on level 3.
  double _score(StressFeatureVector vector) {
    var weighted = 0.0;
    var totalWeight = 0.0;

    void contribute(StressFeature feature, double weight, double Function(double) transform) {
      final value = vector[feature];
      if (value == null) return;
      weighted += transform(value) * weight;
      totalWeight += weight;
    }

    contribute(StressFeature.hr, StressScoring.hrWeight, StressScoring.hrScore);
    contribute(
      StressFeature.rmssd,
      StressScoring.rmssdWeight,
      StressScoring.rmssdScore,
    );
    contribute(
      StressFeature.sdnn,
      StressScoring.sdnnWeight,
      StressScoring.sdnnScore,
    );
    contribute(
      StressFeature.pnn50,
      StressScoring.pnn50Weight,
      StressScoring.pnn50Score,
    );

    // GSR and movement are deliberately not scored, even when the registry
    // enables them and the sensors are present. No dataset has told this
    // project how they should contribute, and inventing a coefficient would
    // be exactly the fake science this engine is meant to avoid. They are
    // carried, displayed and stored - just not used to produce a number.

    if (totalWeight == 0) return 0.5;
    return (weighted / totalWeight).clamp(0.0, 1.0);
  }

  /// How confident the heuristic is, tempered by how much data it had.
  ///
  /// Two things reduce it: sitting near a band boundary (genuinely ambiguous),
  /// and missing cardiovascular features (less to go on). Both are real
  /// reasons to be less sure, so both are reflected rather than hidden.
  double _confidence(double score, StressFeatureVector vector) {
    final base = StressScoring.confidenceForScore(score);

    const scored = [
      StressFeature.hr,
      StressFeature.rmssd,
      StressFeature.sdnn,
      StressFeature.pnn50,
    ];
    final present = scored.where(vector.has).length;
    if (present == 0) return 0.2;

    // Full data keeps the base confidence; each missing feature costs 12%.
    final penalty = 1 - 0.12 * (scored.length - present);
    return (base * penalty).clamp(0.2, 0.96);
  }
}
