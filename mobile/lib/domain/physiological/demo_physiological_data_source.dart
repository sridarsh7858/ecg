import 'dart:async';
import 'dart:math' as math;

import '../../data/models/physiological_features.dart';
import '../../data/models/physiological_input_packet.dart';
import '../stress/stress_level.dart';
import '../stress/stress_scoring.dart';
import 'physiological_data_source.dart';

/// Simulated data source used while there is no ECG hardware.
///
/// It produces a plausible feature vector for a *requested* stress level by
/// inverting [StressScoring]. That keeps the demo honest and end-to-end
/// consistent: pick level 4 in the developer panel, and the measurement returns
/// level-4-looking features which the demo engine then scores as level 4.
///
/// The numbers are illustrative only. They are simulated for demonstrating the
/// application and are always tagged [DataSourceTag.demo].
class DemoPhysiologicalDataSource extends PhysiologicalDataSource {
  DemoPhysiologicalDataSource({
    required StressLevel Function() targetLevel,
    math.Random? random,
    this.tickInterval = const Duration(milliseconds: 100),
  }) : _targetLevel = targetLevel,
       _random = random ?? math.Random();

  /// Supplies the level the demo should simulate. Wired to the developer panel
  /// so the whole app reacts to the selected level.
  final StressLevel Function() _targetLevel;

  final math.Random _random;
  final Duration tickInterval;

  DataSourceStatus _status = DataSourceStatus.connected;
  PhysiologicalFeatures? _lastFeatures;

  @override
  String get id => 'demo';

  @override
  String get displayName => 'Demo Mode';

  @override
  String get sourceTag => DataSourceTag.demo;

  @override
  MeasurementMode get mode => MeasurementMode.demo;

  @override
  DataSourceStatus get status => _status;

  @override
  bool get isReady => _status == DataSourceStatus.connected;

  @override
  Future<void> connect() async {
    _status = DataSourceStatus.connected;
  }

  @override
  Future<void> disconnect() async {
    _status = DataSourceStatus.disconnected;
  }

  /// Symmetric noise in -1..1.
  double _noise() => _random.nextDouble() * 2 - 1;

  /// Builds a feature vector that scores as the currently requested level.
  ///
  /// The score is jittered within the level's band but kept clear of the band
  /// edges, so the round trip is deterministic in level even though the exact
  /// numbers differ every time.
  PhysiologicalFeatures generateFeatures({StressLevel? level}) {
    final target = level ?? _targetLevel();
    final centre = StressScoring.bandCentre(target);
    final margin = StressScoring.bandWidth * 0.28;
    final score = centre + _noise() * margin;

    return StressScoring.featuresForScore(score, noise: _noise);
  }

  @override
  Stream<MeasurementTick> measure(Duration duration) async* {
    final features = generateFeatures();
    _lastFeatures = features;

    final totalTicks = math.max(
      1,
      duration.inMilliseconds ~/ tickInterval.inMilliseconds,
    );
    final targetRr = features.meanRR;

    for (var tick = 1; tick <= totalTicks; tick++) {
      await Future<void>.delayed(tickInterval);

      final elapsed = tickInterval * tick;
      final t = tick / totalTicks;

      // Instantaneous values wander around the final averages, converging as
      // the measurement settles - the way a real rolling estimate behaves.
      final settle = 1 - 0.75 * t;
      final rr = targetRr + _noise() * features.rmssd * 1.6 * settle;
      final hr = 60000 / math.max(rr, 250);

      yield MeasurementTick(
        elapsed: elapsed,
        total: duration,
        hr: hr,
        rr: rr,
        signalQuality: _qualityAt(t),
        waveformSample: _waveformSample(tick, features.hr),
      );
    }
  }

  /// Signal locks on shortly after the electrodes settle.
  SignalQuality _qualityAt(double progress) {
    if (progress < 0.08) return SignalQuality.fair;
    if (progress < 0.14) return SignalQuality.fair;
    return SignalQuality.good;
  }

  /// A crude but recognisable ECG-like sample in -1..1 for the live trace.
  double _waveformSample(int tick, double hr) {
    final samplesPerBeat = (60 / hr) / (tickInterval.inMilliseconds / 1000);
    final phase = (tick % samplesPerBeat) / samplesPerBeat;

    if (phase < 0.10) return math.sin(phase / 0.10 * math.pi) * 0.18; // P
    if (phase < 0.16) return -0.16; // Q
    if (phase < 0.22) return 1.0 - ((phase - 0.16) / 0.06) * 0.05; // R
    if (phase < 0.30) return -0.30; // S
    if (phase < 0.52) {
      return math.sin((phase - 0.30) / 0.22 * math.pi) * 0.28; // T
    }
    return 0.02 * math.sin(phase * math.pi * 6);
  }

  @override
  Future<PhysiologicalInputPacket> readPacket() async {
    return generatePacket(_lastFeatures ?? generateFeatures());
  }

  /// Wraps simulated cardiovascular features into a full packet.
  ///
  /// GSR, movement and battery are simulated here too, so that Demo mode can
  /// exercise every panel in the UI. They are plausible-looking numbers with
  /// no physiological basis whatsoever, and they only ever reach the app
  /// tagged [PhysiologicalSource.demo], which the UI always renders as
  /// "Demo data". Bluetooth mode never fabricates a missing sensor.
  PhysiologicalInputPacket generatePacket([PhysiologicalFeatures? features]) {
    final f = features ?? generateFeatures();

    // Position within the 1..5 range, recovered from the score the features
    // were built to hit, so the simulated extras move with the stress level.
    final t = (StressScoring.score(f)).clamp(0.0, 1.0);

    return PhysiologicalInputPacket(
      timestamp: f.timestamp,
      source: PhysiologicalSource.demo,
      heartRate: f.hr,
      meanRR: f.meanRR,
      rmssd: f.rmssd,
      sdnn: f.sdnn,
      pnn50: f.pnn50,
      gsrValue: double.parse((1.8 + 3.4 * t + _noise() * 0.2).toStringAsFixed(2)),
      gsrPeaks: (1 + 6 * t + _random.nextInt(2)).round(),
      accelX: double.parse((_noise() * 0.05).toStringAsFixed(3)),
      accelY: double.parse((0.08 + _noise() * 0.05).toStringAsFixed(3)),
      accelZ: double.parse((0.98 + _noise() * 0.04).toStringAsFixed(3)),
      gyroX: double.parse((_noise() * 1.5).toStringAsFixed(2)),
      gyroY: double.parse((_noise() * 1.5).toStringAsFixed(2)),
      gyroZ: double.parse((_noise() * 1.5).toStringAsFixed(2)),
      batteryPercentage: 92,
      signalQuality: double.parse(
        (0.93 + _noise() * 0.05).clamp(0.0, 1.0).toStringAsFixed(2),
      ),
    );
  }
}
