import '../../data/models/physiological_features.dart';
import '../../data/models/physiological_input_packet.dart';
import '../../data/models/stress_prediction.dart';
import 'feature_registry.dart';
import 'stress_feature_vector.dart';

/// Contract for anything that turns physiological input into a stress level.
///
/// The application depends only on this interface. Today the concrete
/// implementation is [DummyStressPredictionService], a documented heuristic.
/// When a model has actually been trained, `MLStressPredictionService` will
/// implement the same members and be swapped in at the composition root
/// (`lib/app/dependencies.dart`). No screen, controller or repository changes.
///
/// The input is a [StressFeatureVector] rather than a loose bag of numbers, so
/// that the feature set the engine consumes is explicit, ordered, and declared
/// by a [FeatureRegistry]. That is what lets a future model be trained against
/// exactly the features the app can supply.
///
/// See `docs/future_ml_training.md` for the insertion procedure.
abstract class StressPredictionService {
  /// Identifies the engine in results and history, e.g. "demo-1.0.0".
  String get modelVersion;

  /// Human readable engine name shown in Profile, e.g. "Demo Stress Engine".
  String get displayName;

  /// True when the estimate does not come from a trained model.
  ///
  /// The UI uses this to label results. An engine that returns false here is
  /// asserting that a real model produced the number.
  bool get isDemo;

  /// Which features this engine consumes, and in what order.
  FeatureRegistry get featureRegistry;

  /// Prepares the engine (loads an interpreter, warms caches, ...).
  ///
  /// Safe to call more than once.
  Future<void> initialise();

  /// Produces an estimate from a structured feature vector.
  ///
  /// This is the real entry point. Implementations decide for themselves how
  /// to handle [StressFeatureVector.missingFeatures] and must not pretend a
  /// missing sensor was measured.
  Future<StressPrediction> predictFromVector(StressFeatureVector vector);

  /// Convenience: extracts a vector from [packet] and predicts.
  Future<StressPrediction> predictFromPacket(
    PhysiologicalInputPacket packet,
  ) => predictFromVector(
    StressFeatureVector.from(packet, registry: featureRegistry),
  );

  /// Legacy entry point for code still holding a [PhysiologicalFeatures].
  Future<StressPrediction> predict(PhysiologicalFeatures features) =>
      predictFromPacket(
        PhysiologicalInputPacket.fromLegacyFeatures(features),
      );

  /// Releases any resources held by the engine.
  Future<void> dispose() async {}
}
