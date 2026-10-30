import 'dart:async';

import '../../data/models/physiological_features.dart';
import '../../data/models/physiological_input_packet.dart';
import 'physiological_data_source.dart';

/// Values typed in by the user.
///
/// This is the mode that keeps the project moving while the wearable does not
/// exist. The user enters whatever they have - from a chest strap, a clinical
/// monitor, a published example, or a figure they want to test the app with -
/// and the app treats it exactly as it will later treat a BLE packet.
///
/// Everything it produces is tagged [PhysiologicalSource.manual]. The app never
/// describes these as measurements it took: they are values the user supplied,
/// and history records them that way permanently.
///
/// There is no streaming here. A manual entry is already a finished
/// observation, so [measure] emits a short, honest settling sequence built from
/// the entered heart rate rather than pretending to acquire a signal.
class ManualPhysiologicalDataSource extends PhysiologicalDataSource {
  ManualPhysiologicalDataSource({
    this.tickInterval = const Duration(milliseconds: 60),
    this.tickCount = 12,
  });

  /// Pacing of the brief confirmation animation shown after Analyze.
  final Duration tickInterval;
  final int tickCount;

  PhysiologicalInputPacket? _packet;

  /// The packet most recently submitted from the manual form.
  PhysiologicalInputPacket? get packet => _packet;

  @override
  String get id => 'manual';

  @override
  String get displayName => 'Manual Entry';

  @override
  String get sourceTag => PhysiologicalSource.manual.tag;

  @override
  MeasurementMode get mode => MeasurementMode.manual;

  @override
  DataSourceStatus get status => _packet == null
      ? DataSourceStatus.disconnected
      : DataSourceStatus.connected;

  /// Ready only once values have actually been entered.
  ///
  /// Without this the Analyze button would happily produce a reading from an
  /// empty form, which would be a fabricated result.
  @override
  bool get isReady => _packet != null && _packet!.isUsable;

  /// Installs the values from the manual form.
  ///
  /// Forces the source tag to [PhysiologicalSource.manual] regardless of what
  /// the caller passed, so a manually entered reading can never be recorded as
  /// though it came from hardware.
  void submit(PhysiologicalInputPacket packet) {
    _packet = packet.copyWith(source: PhysiologicalSource.manual);
  }

  /// Discards the entered values.
  void clear() => _packet = null;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Stream<MeasurementTick> measure(Duration duration) async* {
    final packet = _packet;
    if (packet == null || !packet.isUsable) {
      throw StateError(
        'No manual values have been entered. Fill in at least a heart rate '
        'before running an analysis.',
      );
    }

    final hr = packet.effectiveHeartRate ?? 70;
    final rr = packet.effectiveMeanRR ?? 60000 / hr;

    // A short fixed sequence, not a simulated acquisition. The values do not
    // wander, because nothing is being measured - they are the numbers the
    // user typed, shown back to them while the engine runs.
    for (var tick = 1; tick <= tickCount; tick++) {
      await Future<void>.delayed(tickInterval);
      yield MeasurementTick(
        elapsed: tickInterval * tick,
        total: tickInterval * tickCount,
        hr: hr,
        rr: rr,
        signalQuality: SignalQuality.good,
        waveformSample: 0,
      );
    }
  }

  @override
  Future<PhysiologicalInputPacket> readPacket() async {
    final packet = _packet;
    if (packet == null) {
      throw StateError('No manual values have been entered.');
    }
    return packet;
  }

  @override
  Future<PhysiologicalFeatures> readFeatures() async =>
      (await readPacket()).toLegacyFeatures();
}
