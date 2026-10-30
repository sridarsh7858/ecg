import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../data/models/stress_prediction.dart';
import 'dummy_stress_prediction_service.dart';
import 'feature_registry.dart';
import 'stress_feature_vector.dart';
import 'stress_level.dart';
import 'stress_prediction_service.dart';
import 'stress_scoring.dart';

/// The trained stress engine: a TFLite model exported by `training/export.py`.
///
/// ## What the model is
///
/// A 5-16-8-1 MLP trained on WESAD chest ECG (Schmidt et al., ICMI 2018),
/// leave-one-subject-out, with the standardiser baked in as the first layer
/// and the Platt calibration baked in as the last. Measured numbers are in
/// `assets/models/model_card.md`, which the exporter generates from the
/// training run rather than from literature.
///
/// ## Dart does no arithmetic on the features
///
/// The graph takes the **raw** vector `[hr, meanRR, rmssd, sdnn, pnn50]` and
/// returns one calibrated probability that the 30-second window came from a
/// stressed state. That is deliberate: `docs/future_ml_integration.md`
/// originally had Dart load the scaler and standardise before inference, and
/// a Dart-side scaler is the classic way a silently transposed or
/// mis-scaled vector ships. Dart cannot scale wrongly if Dart never scales.
///
/// [_expectedOrder] is still checked against `feature_scaler.json` on load, so
/// a registry that disagrees with the training order fails loudly at startup
/// instead of quietly producing nonsense.
///
/// ## The five levels
///
/// The model outputs one probability, not five classes. No public dataset has
/// five-level stress ground truth. The probability is banded into the app's
/// existing five levels by [StressScoring.levelForScore], exactly as the
/// demo engine's score was. The percentage the UI shows is therefore a
/// measured quantity - P(stress) - and the model card says plainly that the
/// five levels are a banding of one number, not five validated states.
///
/// ## If the asset will not load
///
/// The service falls back to [DummyStressPredictionService] and **says so**:
/// [isDemo] becomes true, [modelVersion] reverts to `demo-1.0.0`, and every
/// badge in the app goes back to labelling the result as demo data. A silent
/// fallback that kept claiming `ml-1.0.0` would be the one genuinely
/// dishonest failure mode available here.
class MLStressPredictionService extends StressPredictionService {
  MLStressPredictionService({
    this.modelAsset = 'assets/models/stress_model.tflite',
    this.scalerAsset = 'assets/models/feature_scaler.json',
    FeatureRegistry? registry,
  }) : _registry = registry ?? FeatureRegistry(),
       _fallback = DummyStressPredictionService();

  /// The exported graph: raw features in, calibrated probability out.
  final String modelAsset;

  /// Reference constants. Not used for scaling - see the class doc. Read for
  /// the feature order contract and for training-set means used to stand in
  /// for a sensor that was not present.
  final String scalerAsset;

  final FeatureRegistry _registry;
  final DummyStressPredictionService _fallback;

  /// The feature order the exported graph was trained on. Must match
  /// `hrv.FEATURE_ORDER` in the training pipeline and the declaration order of
  /// [StressFeature].
  static const List<String> _expectedOrder = [
    'hr',
    'meanRR',
    'rmssd',
    'sdnn',
    'pnn50',
  ];

  Interpreter? _interpreter;
  Map<StressFeature, double> _trainingMeans = const {};
  bool _initialised = false;

  /// Why the model is not loaded, or null when it is. Shown in the developer
  /// panel; never swallowed.
  String? loadError;

  /// True once the trained graph is loaded and usable.
  bool get isReady => _interpreter != null;

  @override
  FeatureRegistry get featureRegistry => _registry;

  @override
  String get modelVersion => isReady ? 'ml-1.0.0' : _fallback.modelVersion;

  @override
  String get displayName =>
      isReady ? 'Stress Model v1' : _fallback.displayName;

  @override
  bool get isDemo => !isReady;

  @override
  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;

    try {
      final scaler =
          jsonDecode(await rootBundle.loadString(scalerAsset))
              as Map<String, dynamic>;

      final order = (scaler['order'] as List).cast<String>();
      if (!listEquals(order, _expectedOrder)) {
        throw StateError(
          'Model feature order $order does not match the app contract '
          '$_expectedOrder. Refusing to run a transposed vector.',
        );
      }
      if (!listEquals(_registry.featureKeys, _expectedOrder)) {
        throw StateError(
          'Registry supplies ${_registry.featureKeys} but the model expects '
          '$_expectedOrder.',
        );
      }

      // Training-set means, used only as the explicit substitute for a feature
      // the sensor did not supply. StressFeatureVector.toDense demands a
      // substitute rather than defaulting one, so the choice stays visible.
      final means = (scaler['mean'] as List).cast<num>();
      _trainingMeans = {
        for (var i = 0; i < order.length; i++)
          StressFeature.fromKey(order[i])!: means[i].toDouble(),
      };

      final interpreter = await Interpreter.fromAsset(modelAsset);

      // The graph is [1, 5] in and [1, 1] out. Anything else means the asset
      // and this file have drifted apart.
      final inputShape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;
      if (inputShape.last != _expectedOrder.length) {
        interpreter.close();
        throw StateError(
          'Model takes ${inputShape.last} inputs, expected '
          '${_expectedOrder.length}.',
        );
      }
      if (outputShape.last != 1) {
        interpreter.close();
        throw StateError(
          'Model returns ${outputShape.last} outputs, expected 1 calibrated '
          'probability.',
        );
      }

      _interpreter = interpreter;
      loadError = null;
    } catch (error) {
      // Keep running on the demo engine, labelled as the demo engine.
      loadError = '$error';
      _interpreter = null;
      debugPrint('MLStressPredictionService: falling back to demo engine: $error');
      await _fallback.initialise();
    }
  }

  @override
  Future<StressPrediction> predictFromVector(StressFeatureVector vector) async {
    final interpreter = _interpreter;
    if (interpreter == null) return _fallback.predictFromVector(vector);

    // Absent sensors take the training-set mean. This is an imputation, so it
    // costs confidence below rather than passing silently.
    final dense = vector.toDense((feature) => _trainingMeans[feature] ?? 0);

    final input = [dense.map((v) => v.toDouble()).toList(growable: false)];
    final output = [List<double>.filled(1, 0)];
    interpreter.run(input, output);

    final probability = output[0][0].clamp(0.0, 1.0);
    final level = StressScoring.levelForScore(probability);

    return StressPrediction(
      level: level,
      label: StressLevelConfig.of(level).title,
      confidence: _confidence(probability, vector),
      features: vector.packet.toLegacyFeatures(),
      timestamp: DateTime.now(),
      // Describes where the INPUT came from (DEMO or BLE), not the engine.
      source: vector.packet.source.tag,
      modelVersion: modelVersion,
    );
  }

  /// How much to trust the *level*, which is a band of the probability.
  ///
  /// Two things lower it, both real reasons to be less sure:
  ///
  /// 1. A probability sitting near a band boundary. 0.399 and 0.401 are the
  ///    same reading physiologically but different levels, so a reading near
  ///    an edge is genuinely ambiguous ([StressScoring.confidenceForScore]).
  /// 2. Imputed features. Each cardiovascular feature the sensor did not
  ///    supply was replaced by a training-set mean, which is a guess, so it
  ///    costs 12% - the same tariff the demo engine charges.
  ///
  /// This is confidence in the banding, not a second probability. The
  /// calibrated probability itself is the model's own measured output and is
  /// reported as the level.
  double _confidence(double probability, StressFeatureVector vector) {
    final base = StressScoring.confidenceForScore(probability);
    final present = vector.presentFeatures.length;
    if (present == 0) return 0.2;

    final penalty = 1 - 0.12 * (vector.features.length - present);
    return (base * penalty).clamp(0.2, 0.96);
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    _initialised = false;
  }
}
