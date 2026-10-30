import '../../data/models/physiological_features.dart';
import '../../data/models/physiological_input_packet.dart';

/// Connection state of a physiological data source.
enum DataSourceStatus {
  /// No device configured for this source.
  unavailable,

  disconnected,
  connecting,
  connected,
}

/// Qualitative signal quality reported during a measurement.
enum SignalQuality {
  poor,
  fair,
  good;

  String get label => switch (this) {
    SignalQuality.poor => 'Poor',
    SignalQuality.fair => 'Fair',
    SignalQuality.good => 'Good',
  };
}

/// One update emitted while a measurement is running.
class MeasurementTick {
  const MeasurementTick({
    required this.elapsed,
    required this.total,
    required this.hr,
    required this.rr,
    required this.signalQuality,
    required this.waveformSample,
  });

  final Duration elapsed;
  final Duration total;

  /// Instantaneous heart rate, BPM.
  final double hr;

  /// Instantaneous R-R interval, ms.
  final double rr;

  final SignalQuality signalQuality;

  /// A single -1..1 sample for the live trace drawn on the measure screen.
  final double waveformSample;

  /// 0.0 .. 1.0
  double get progress => total.inMilliseconds == 0
      ? 0
      : (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

  Duration get remaining {
    final left = total - elapsed;
    return left.isNegative ? Duration.zero : left;
  }
}

/// The three interchangeable ways a measurement can be obtained.
///
/// The rest of the application is written against [PhysiologicalDataSource]
/// and does not branch on this. It exists so the Measure screen can offer a
/// choice, and so every session can record which path produced it.
enum MeasurementMode {
  demo('demo', 'Demo', 'Simulated values, for demonstration'),
  manual('manual', 'Manual', 'Values you enter yourself'),
  bluetooth('ble', 'Bluetooth', 'Live values from the wearable');

  const MeasurementMode(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  PhysiologicalSource get source => switch (this) {
    MeasurementMode.demo => PhysiologicalSource.demo,
    MeasurementMode.manual => PhysiologicalSource.manual,
    MeasurementMode.bluetooth => PhysiologicalSource.bluetooth,
  };

  static MeasurementMode fromId(String? id) => MeasurementMode.values
      .firstWhere((m) => m.id == id, orElse: () => MeasurementMode.demo);
}

/// Where physiological data comes from.
///
/// Three implementations exist, one per [MeasurementMode]:
///  * [DemoPhysiologicalDataSource]    - simulated values.
///  * [ManualPhysiologicalDataSource]  - values typed in by the user.
///  * [BlePhysiologicalDataSource]     - live packets from the wearable.
///
/// The measurement flow talks only to this interface, so swapping the active
/// source does not touch any UI code. All three produce a
/// [PhysiologicalInputPacket], which is the single contract everything
/// downstream consumes.
abstract class PhysiologicalDataSource {
  /// Stable identifier, e.g. "demo", "manual" or "ble".
  String get id;

  /// Shown on the measure screen, e.g. "Demo Mode".
  String get displayName;

  /// Tag written onto produced features, one of [DataSourceTag].
  String get sourceTag;

  /// Which of the three modes this source implements.
  MeasurementMode get mode;

  DataSourceStatus get status;

  /// True when a measurement can be started right now.
  bool get isReady;

  Future<void> connect();

  Future<void> disconnect();

  /// Streams live values for [duration]. The stream closes when the
  /// measurement completes; cancelling the subscription aborts it.
  Stream<MeasurementTick> measure(Duration duration);

  /// Produces the packet for the measurement that just streamed.
  ///
  /// Called once [measure] completes. This is the primary output of a data
  /// source; [readFeatures] exists only to bridge to older code.
  Future<PhysiologicalInputPacket> readPacket();

  /// Legacy narrow view of [readPacket], kept for the parts of the app still
  /// written against [PhysiologicalFeatures].
  ///
  /// Implementations should not override this - the default delegation is what
  /// keeps the two representations from drifting apart.
  Future<PhysiologicalFeatures> readFeatures() async =>
      (await readPacket()).toLegacyFeatures();
}
