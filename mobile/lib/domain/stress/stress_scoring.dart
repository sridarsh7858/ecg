import 'dart:math' as math;

import '../../data/models/physiological_features.dart';
import 'stress_level.dart';

/// Shared, transparent scoring maths used by the demo pipeline.
///
/// It maps an HRV feature vector onto a single 0..1 "arousal score" and then
/// onto one of the five project stress levels. The demo data generator uses the
/// exact inverse of these formulas, which is what makes the demo end-to-end
/// consistent: request level 4, get plausible level-4 features back, and the
/// engine scores them as level 4.
///
/// This is a deliberately simple heuristic for demonstrating the application.
/// It is NOT a validated physiological model and makes no clinical claim. The
/// trained model will replace it entirely.
class StressScoring {
  const StressScoring._();

  // Plausible adult ranges used purely to normalise each feature to 0..1.
  static const double hrMin = 55;
  static const double hrMax = 105;
  static const double rmssdMin = 12;
  static const double rmssdMax = 75;
  static const double sdnnMin = 18;
  static const double sdnnMax = 90;
  static const double pnn50Min = 2;
  static const double pnn50Max = 45;

  /// Relative contribution of each feature to the arousal score.
  static const double hrWeight = 0.30;
  static const double rmssdWeight = 0.30;
  static const double sdnnWeight = 0.22;
  static const double pnn50Weight = 0.18;

  /// Width of one stress-level band on the 0..1 score axis.
  static const double bandWidth = 0.2;

  static double _normalise(double value, double min, double max) =>
      ((value - min) / (max - min)).clamp(0.0, 1.0);

  /// Higher heart rate reads as higher arousal.
  static double hrScore(double hr) => _normalise(hr, hrMin, hrMax);

  /// Lower variability reads as higher arousal, so these are inverted.
  static double rmssdScore(double rmssd) =>
      1 - _normalise(rmssd, rmssdMin, rmssdMax);

  static double sdnnScore(double sdnn) =>
      1 - _normalise(sdnn, sdnnMin, sdnnMax);

  static double pnn50Score(double pnn50) =>
      1 - _normalise(pnn50, pnn50Min, pnn50Max);

  /// Weighted arousal score in 0..1.
  static double score(PhysiologicalFeatures f) {
    final value =
        hrScore(f.hr) * hrWeight +
        rmssdScore(f.rmssd) * rmssdWeight +
        sdnnScore(f.sdnn) * sdnnWeight +
        pnn50Score(f.pnn50) * pnn50Weight;
    return value.clamp(0.0, 1.0);
  }

  /// Buckets a 0..1 score into levels 1..5 using five equal bands.
  static StressLevel levelForScore(double score) {
    final index = (score / bandWidth).floor().clamp(0, 4);
    return StressLevel.fromNumber(index + 1);
  }

  /// Centre of the score band that maps to [level].
  static double bandCentre(StressLevel level) =>
      (level.number - 1) * bandWidth + bandWidth / 2;

  /// Inclusive-exclusive score range that maps to [level].
  static (double, double) bandRange(StressLevel level) {
    final start = (level.number - 1) * bandWidth;
    return (start, start + bandWidth);
  }

  /// Confidence derived from how close the score sits to its band centre.
  ///
  /// A score near a boundary is genuinely more ambiguous, so it reports lower
  /// confidence. Bounded to a believable 0.62 .. 0.96.
  static double confidenceForScore(double score) {
    final level = levelForScore(score);
    final distance = (score - bandCentre(level)).abs();
    final normalised = (distance / (bandWidth / 2)).clamp(0.0, 1.0);
    return (0.96 - 0.34 * normalised).clamp(0.62, 0.96);
  }

  /// Inverse of [hrScore] and friends: builds features that score as [target].
  ///
  /// [jitter] in -1..1 nudges the score inside its band; [noise] applies small
  /// independent per-feature variation so two demo readings never look
  /// identical while still landing in the requested band.
  static PhysiologicalFeatures featuresForScore(
    double target, {
    double Function()? noise,
  }) {
    final s = target.clamp(0.0, 1.0);
    double vary(double value, double spread) {
      if (noise == null) return value;
      return value + noise() * spread;
    }

    final hr = vary(hrMin + s * (hrMax - hrMin), 1.6);
    final rmssd = vary(rmssdMin + (1 - s) * (rmssdMax - rmssdMin), 2.0);
    final sdnn = vary(sdnnMin + (1 - s) * (sdnnMax - sdnnMin), 2.2);
    final pnn50 = vary(pnn50Min + (1 - s) * (pnn50Max - pnn50Min), 1.4);

    return PhysiologicalFeatures.fromHr(
      hr: _round(hr.clamp(45.0, 120.0), 1),
      rmssd: _round(math.max(rmssd, 5), 1),
      sdnn: _round(math.max(sdnn, 8), 1),
      pnn50: _round(math.max(pnn50, 0), 1),
    );
  }

  static double _round(double value, int places) {
    final factor = math.pow(10, places);
    return (value * factor).round() / factor;
  }
}
