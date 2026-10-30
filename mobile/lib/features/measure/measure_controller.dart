import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/physiological_features.dart';
import '../../data/models/physiological_input_packet.dart';
import '../../data/models/stress_prediction.dart';
import '../../domain/physiological/physiological_data_source.dart';
import '../../domain/stress/stress_prediction_service.dart';

/// The four states of a check-in.
enum MeasurePhase { idle, measuring, processing, complete }

/// Drives one measurement: stream from the data source, then run the engine.
///
/// It talks to [PhysiologicalDataSource] and [StressPredictionService] through
/// their interfaces only, so the same controller will drive a real BLE
/// measurement with a trained model without modification.
class MeasureController extends ChangeNotifier {
  MeasureController({
    required PhysiologicalDataSource dataSource,
    required StressPredictionService predictionService,
  }) : _dataSource = dataSource,
       _predictionService = predictionService;

  final PhysiologicalDataSource _dataSource;
  final StressPredictionService _predictionService;

  StreamSubscription<MeasurementTick>? _subscription;

  MeasurePhase _phase = MeasurePhase.idle;
  MeasurementTick? _tick;
  PhysiologicalInputPacket? _packet;
  StressPrediction? _prediction;
  String? _error;
  Duration _duration = const Duration(seconds: 30);

  /// Recent waveform samples, used to draw the live trace.
  final List<double> _waveform = [];

  static const int waveformWindow = 90;

  MeasurePhase get phase => _phase;
  MeasurementTick? get tick => _tick;

  /// The packet the last completed measurement produced.
  ///
  /// Carries everything the source supplied - GSR, movement, battery - not
  /// just the cardiovascular features the estimate was built from.
  PhysiologicalInputPacket? get packet => _packet;

  StressPrediction? get prediction => _prediction;
  String? get error => _error;
  Duration get duration => _duration;
  List<double> get waveform => List.unmodifiable(_waveform);

  bool get isRunning =>
      _phase == MeasurePhase.measuring || _phase == MeasurePhase.processing;

  String get deviceName => _dataSource.displayName;
  bool get deviceReady => _dataSource.isReady;

  double get progress => switch (_phase) {
    MeasurePhase.idle => 0,
    MeasurePhase.measuring => _tick?.progress ?? 0,
    MeasurePhase.processing || MeasurePhase.complete => 1,
  };

  /// Starts a measurement of [duration]. Safe to call while idle only.
  Future<void> start(Duration duration) async {
    if (isRunning) return;

    _duration = duration;
    _phase = MeasurePhase.measuring;
    _tick = null;
    _packet = null;
    _prediction = null;
    _error = null;
    _waveform.clear();
    notifyListeners();

    final completer = Completer<void>();

    _subscription = _dataSource
        .measure(duration)
        .listen(
          (tick) {
            _tick = tick;
            _waveform.add(tick.waveformSample);
            if (_waveform.length > waveformWindow) _waveform.removeAt(0);
            notifyListeners();
          },
          onError: (Object error) {
            _fail(error.toString());
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

    await completer.future;
    if (_phase != MeasurePhase.measuring) return; // cancelled or failed

    await _process();
  }

  Future<void> _process() async {
    _phase = MeasurePhase.processing;
    notifyListeners();

    try {
      final packet = await _dataSource.readPacket();
      _packet = packet;
      _prediction = await _predictionService.predictFromPacket(packet);
      _phase = MeasurePhase.complete;
    } catch (error) {
      _fail(error.toString());
      return;
    }
    notifyListeners();
  }

  /// Runs the engine over supplied [features] without streaming - used by the
  /// baseline flow, which needs a capture but no live view.
  Future<StressPrediction> predictFor(PhysiologicalFeatures features) =>
      _predictionService.predict(features);

  void cancel() {
    _subscription?.cancel();
    _subscription = null;
    _phase = MeasurePhase.idle;
    _tick = null;
    _waveform.clear();
    notifyListeners();
  }

  /// Returns to the ready state, keeping nothing from the last run.
  void reset() {
    cancel();
    _prediction = null;
    _error = null;
    notifyListeners();
  }

  void _fail(String message) {
    _subscription?.cancel();
    _subscription = null;
    _error = message;
    _phase = MeasurePhase.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
