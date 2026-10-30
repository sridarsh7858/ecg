import 'dart:math' as math;

import 'physiological_features.dart';

/// Where one packet of physiological data came from.
///
/// This is the honesty mechanism for the whole app: every packet, every
/// prediction and every persisted session carries one of these, and they are
/// never silently mixed. A reading is either simulated, typed in by hand, or
/// measured by hardware, and the UI always says which.
enum PhysiologicalSource {
  /// Values generated on-device for demonstration. Not measurements.
  demo('DEMO', 'Demo'),

  /// Values typed in by the user. Not measurements taken by this app.
  manual('MANUAL', 'Manual'),

  /// Values received from the wearable over BLE.
  bluetooth('BLE', 'Bluetooth');

  const PhysiologicalSource(this.tag, this.label);

  /// Stable value written to storage and to JSON. Do not change these: they
  /// appear in already-persisted history.
  final String tag;

  /// Human readable label, e.g. shown as "Source: Bluetooth".
  final String label;

  /// True when the values did not come from hardware, and so must be labelled.
  bool get isSimulatedOrTyped => this != PhysiologicalSource.bluetooth;

  /// Tolerant parse. Accepts the stored tag, the enum name, and the spelling
  /// "BLUETOOTH" so that older and newer payloads both load.
  static PhysiologicalSource fromTag(String? value) {
    final normalised = (value ?? '').trim().toUpperCase();
    return switch (normalised) {
      'DEMO' => PhysiologicalSource.demo,
      'MANUAL' => PhysiologicalSource.manual,
      'BLE' || 'BLUETOOTH' => PhysiologicalSource.bluetooth,
      _ => PhysiologicalSource.demo,
    };
  }
}

/// The standard physiological input packet.
///
/// This is the single container the whole application is built around. Demo,
/// Manual and Bluetooth all produce one of these, and nothing downstream of
/// this point knows or cares which produced it.
///
/// **Every physiological field is nullable, and that is load-bearing.** The
/// wearable may ship with only an AD8232 and no GSR, or with an accelerometer
/// but no gyroscope. A missing sensor must read as "not available" everywhere
/// in the app, and must never be silently replaced with a zero or an invented
/// value - that would turn an absent sensor into a fake measurement.
class PhysiologicalInputPacket {
  const PhysiologicalInputPacket({
    required this.timestamp,
    required this.source,
    // ECG
    this.rawEcgSamples,
    this.rPeaks,
    this.rrIntervals,
    this.heartRate,
    // HRV
    this.meanRR,
    this.rmssd,
    this.sdnn,
    this.pnn50,
    // GSR / EDA
    this.gsrValue,
    this.gsrLevel,
    this.gsrPeaks,
    // Accelerometer
    this.accelX,
    this.accelY,
    this.accelZ,
    this.movementIntensity,
    // Gyroscope
    this.gyroX,
    this.gyroY,
    this.gyroZ,
    // Battery
    this.batteryVoltage,
    this.batteryCurrent,
    this.batteryPercentage,
    // Context
    this.userStressRating,
    this.sessionContext,
    // Quality
    this.signalQuality,
  });

  final DateTime timestamp;
  final PhysiologicalSource source;

  // --- ECG ----------------------------------------------------------------

  /// Raw ADC samples, when the firmware streams them. Usually null: the first
  /// firmware sends derived features only, to keep the BLE payload small.
  final List<double>? rawEcgSamples;

  /// Sample indices of detected R-peaks, when the firmware reports them.
  final List<int>? rPeaks;

  /// R-R intervals in milliseconds.
  final List<double>? rrIntervals;

  /// Heart rate in beats per minute.
  final double? heartRate;

  // --- HRV ----------------------------------------------------------------

  /// Mean R-R interval in milliseconds.
  final double? meanRR;

  /// Root mean square of successive R-R differences, milliseconds.
  final double? rmssd;

  /// Standard deviation of N-N intervals, milliseconds.
  final double? sdnn;

  /// Percentage of successive R-R intervals differing by more than 50 ms.
  /// Expressed 0..100, not 0..1.
  final double? pnn50;

  // --- GSR / EDA ----------------------------------------------------------

  /// Raw GSR/EDA reading, microsiemens.
  final double? gsrValue;

  /// Slower-moving tonic GSR level, microsiemens.
  final double? gsrLevel;

  /// Count of phasic GSR peaks in the window.
  final int? gsrPeaks;

  // --- Accelerometer ------------------------------------------------------

  final double? accelX;
  final double? accelY;
  final double? accelZ;

  /// Movement intensity, 0..1.
  ///
  /// This is **context, not stress.** High movement does not mean high stress;
  /// it means the reading may contain motion artefact and that the user was
  /// active. See docs/physiological_inputs.md.
  final double? movementIntensity;

  // --- Gyroscope ----------------------------------------------------------

  final double? gyroX;
  final double? gyroY;
  final double? gyroZ;

  // --- Battery ------------------------------------------------------------

  final double? batteryVoltage;
  final double? batteryCurrent;
  final int? batteryPercentage;

  // --- Context ------------------------------------------------------------

  /// The user's own subjective rating, 1..5. Self-report, not a measurement.
  final int? userStressRating;

  /// Free-text context, e.g. "before exam".
  final String? sessionContext;

  // --- Quality ------------------------------------------------------------

  /// Signal quality 0..1 as reported by the firmware.
  final double? signalQuality;

  // --- Availability -------------------------------------------------------

  /// True when enough cardiovascular data is present to attempt an estimate.
  ///
  /// Heart rate alone is the minimum. HRV features improve the estimate but a
  /// packet with only HR is still usable.
  bool get hasCardiovascular => heartRate != null || meanRR != null;

  bool get hasHrv => rmssd != null || sdnn != null || pnn50 != null;

  bool get hasGsr => gsrValue != null || gsrLevel != null || gsrPeaks != null;

  bool get hasAccelerometer =>
      accelX != null || accelY != null || accelZ != null;

  bool get hasGyroscope => gyroX != null || gyroY != null || gyroZ != null;

  bool get hasMovement =>
      movementIntensity != null || hasAccelerometer || hasGyroscope;

  bool get hasBattery =>
      batteryPercentage != null ||
      batteryVoltage != null ||
      batteryCurrent != null;

  bool get hasRawEcg => rawEcgSamples != null && rawEcgSamples!.isNotEmpty;

  /// Whether this packet carries enough to run the prediction engine at all.
  bool get isUsable => hasCardiovascular;

  /// Mean R-R derived from heart rate when the firmware did not send it.
  ///
  /// Returns null rather than a guess when there is no heart rate either.
  double? get effectiveMeanRR {
    if (meanRR != null) return meanRR;
    final hr = heartRate;
    if (hr == null || hr <= 0) return null;
    return 60000 / hr;
  }

  /// Heart rate derived from mean R-R when the firmware sent only R-R.
  double? get effectiveHeartRate {
    if (heartRate != null) return heartRate;
    final rr = meanRR;
    if (rr == null || rr <= 0) return null;
    return 60000 / rr;
  }

  /// Movement intensity, computed from the accelerometer when not supplied.
  ///
  /// Uses the deviation of the acceleration magnitude from 1 g, so a still
  /// device resting in any orientation reads near zero. Returns null when
  /// there is no accelerometer, rather than pretending the user was still.
  double? get effectiveMovementIntensity {
    if (movementIntensity != null) return movementIntensity!.clamp(0.0, 1.0);
    if (!hasAccelerometer) return null;

    final x = accelX ?? 0;
    final y = accelY ?? 0;
    final z = accelZ ?? 0;
    final magnitude = math.sqrt(x * x + y * y + z * z);

    // Deviation from 1 g, scaled so that ~0.6 g of movement reads as full.
    return ((magnitude - 1.0).abs() / 0.6).clamp(0.0, 1.0);
  }

  /// Qualitative movement label for the dashboard, or null when unavailable.
  String? get movementLabel {
    final intensity = effectiveMovementIntensity;
    if (intensity == null) return null;
    if (intensity < 0.15) return 'Still';
    if (intensity < 0.40) return 'Low';
    if (intensity < 0.70) return 'Moderate';
    return 'High';
  }

  /// True when movement is high enough that the reading may contain artefact.
  ///
  /// This flags data quality. It is explicitly **not** a stress signal.
  bool get hasMotionArtefactRisk => (effectiveMovementIntensity ?? 0) > 0.55;

  PhysiologicalInputPacket copyWith({
    DateTime? timestamp,
    PhysiologicalSource? source,
    List<double>? rawEcgSamples,
    List<int>? rPeaks,
    List<double>? rrIntervals,
    double? heartRate,
    double? meanRR,
    double? rmssd,
    double? sdnn,
    double? pnn50,
    double? gsrValue,
    double? gsrLevel,
    int? gsrPeaks,
    double? accelX,
    double? accelY,
    double? accelZ,
    double? movementIntensity,
    double? gyroX,
    double? gyroY,
    double? gyroZ,
    double? batteryVoltage,
    double? batteryCurrent,
    int? batteryPercentage,
    int? userStressRating,
    String? sessionContext,
    double? signalQuality,
  }) {
    return PhysiologicalInputPacket(
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      rawEcgSamples: rawEcgSamples ?? this.rawEcgSamples,
      rPeaks: rPeaks ?? this.rPeaks,
      rrIntervals: rrIntervals ?? this.rrIntervals,
      heartRate: heartRate ?? this.heartRate,
      meanRR: meanRR ?? this.meanRR,
      rmssd: rmssd ?? this.rmssd,
      sdnn: sdnn ?? this.sdnn,
      pnn50: pnn50 ?? this.pnn50,
      gsrValue: gsrValue ?? this.gsrValue,
      gsrLevel: gsrLevel ?? this.gsrLevel,
      gsrPeaks: gsrPeaks ?? this.gsrPeaks,
      accelX: accelX ?? this.accelX,
      accelY: accelY ?? this.accelY,
      accelZ: accelZ ?? this.accelZ,
      movementIntensity: movementIntensity ?? this.movementIntensity,
      gyroX: gyroX ?? this.gyroX,
      gyroY: gyroY ?? this.gyroY,
      gyroZ: gyroZ ?? this.gyroZ,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      batteryCurrent: batteryCurrent ?? this.batteryCurrent,
      batteryPercentage: batteryPercentage ?? this.batteryPercentage,
      userStressRating: userStressRating ?? this.userStressRating,
      sessionContext: sessionContext ?? this.sessionContext,
      signalQuality: signalQuality ?? this.signalQuality,
    );
  }

  /// Bridges to the legacy [PhysiologicalFeatures] contract.
  ///
  /// The existing measurement flow, scoring and persisted history are written
  /// against [PhysiologicalFeatures]. Rather than rewrite all of that, a packet
  /// can present itself in the old shape. Missing HRV fields become 0 here
  /// because the legacy type is non-nullable - which is exactly why the new
  /// [StressFeatureVector] path preserves nullability instead. Prefer the
  /// packet itself, and use this only at the boundary with older code.
  PhysiologicalFeatures toLegacyFeatures() {
    final hr = effectiveHeartRate ?? 0;
    return PhysiologicalFeatures(
      hr: hr,
      meanRR: effectiveMeanRR ?? 0,
      rmssd: rmssd ?? 0,
      sdnn: sdnn ?? 0,
      pnn50: pnn50 ?? 0,
      timestamp: timestamp,
      source: source.tag,
    );
  }

  /// Lifts a legacy feature vector into a packet.
  factory PhysiologicalInputPacket.fromLegacyFeatures(
    PhysiologicalFeatures features, {
    PhysiologicalSource? source,
  }) {
    return PhysiologicalInputPacket(
      timestamp: features.timestamp,
      source: source ?? PhysiologicalSource.fromTag(features.source),
      heartRate: features.hr,
      meanRR: features.meanRR,
      rmssd: features.rmssd,
      sdnn: features.sdnn,
      pnn50: features.pnn50,
    );
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'source': source.tag,
    if (rawEcgSamples != null) 'rawEcgSamples': rawEcgSamples,
    if (rPeaks != null) 'rPeaks': rPeaks,
    if (rrIntervals != null) 'rrIntervals': rrIntervals,
    if (heartRate != null) 'heartRate': heartRate,
    if (meanRR != null) 'meanRR': meanRR,
    if (rmssd != null) 'rmssd': rmssd,
    if (sdnn != null) 'sdnn': sdnn,
    if (pnn50 != null) 'pnn50': pnn50,
    if (gsrValue != null) 'gsrValue': gsrValue,
    if (gsrLevel != null) 'gsrLevel': gsrLevel,
    if (gsrPeaks != null) 'gsrPeaks': gsrPeaks,
    if (accelX != null) 'accelX': accelX,
    if (accelY != null) 'accelY': accelY,
    if (accelZ != null) 'accelZ': accelZ,
    if (movementIntensity != null) 'movementIntensity': movementIntensity,
    if (gyroX != null) 'gyroX': gyroX,
    if (gyroY != null) 'gyroY': gyroY,
    if (gyroZ != null) 'gyroZ': gyroZ,
    if (batteryVoltage != null) 'batteryVoltage': batteryVoltage,
    if (batteryCurrent != null) 'batteryCurrent': batteryCurrent,
    if (batteryPercentage != null) 'batteryPercentage': batteryPercentage,
    if (userStressRating != null) 'userStressRating': userStressRating,
    if (sessionContext != null) 'sessionContext': sessionContext,
    if (signalQuality != null) 'signalQuality': signalQuality,
  };

  /// Reads back a packet this app wrote. Tolerant of every field being absent.
  factory PhysiologicalInputPacket.fromJson(Map<String, dynamic> json) {
    double? number(String key) => (json[key] as num?)?.toDouble();
    int? integer(String key) => (json[key] as num?)?.toInt();

    return PhysiologicalInputPacket(
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      source: PhysiologicalSource.fromTag(json['source'] as String?),
      rawEcgSamples: (json['rawEcgSamples'] as List?)
          ?.map((value) => (value as num).toDouble())
          .toList(),
      rPeaks: (json['rPeaks'] as List?)
          ?.map((value) => (value as num).toInt())
          .toList(),
      rrIntervals: (json['rrIntervals'] as List?)
          ?.map((value) => (value as num).toDouble())
          .toList(),
      heartRate: number('heartRate'),
      meanRR: number('meanRR'),
      rmssd: number('rmssd'),
      sdnn: number('sdnn'),
      pnn50: number('pnn50'),
      gsrValue: number('gsrValue'),
      gsrLevel: number('gsrLevel'),
      gsrPeaks: integer('gsrPeaks'),
      accelX: number('accelX'),
      accelY: number('accelY'),
      accelZ: number('accelZ'),
      movementIntensity: number('movementIntensity'),
      gyroX: number('gyroX'),
      gyroY: number('gyroY'),
      gyroZ: number('gyroZ'),
      batteryVoltage: number('batteryVoltage'),
      batteryCurrent: number('batteryCurrent'),
      batteryPercentage: integer('batteryPercentage'),
      userStressRating: integer('userStressRating'),
      sessionContext: json['sessionContext'] as String?,
      signalQuality: number('signalQuality'),
    );
  }

  @override
  String toString() {
    final parts = <String>[
      'source: ${source.tag}',
      if (heartRate != null) 'hr: ${heartRate!.toStringAsFixed(1)}',
      if (rmssd != null) 'rmssd: ${rmssd!.toStringAsFixed(1)}',
      if (sdnn != null) 'sdnn: ${sdnn!.toStringAsFixed(1)}',
      if (pnn50 != null) 'pnn50: ${pnn50!.toStringAsFixed(1)}',
      if (hasGsr) 'gsr: ${(gsrValue ?? gsrLevel)!.toStringAsFixed(2)}',
      if (effectiveMovementIntensity != null)
        'movement: ${effectiveMovementIntensity!.toStringAsFixed(2)}',
      if (batteryPercentage != null) 'battery: $batteryPercentage%',
    ];
    return 'PhysiologicalInputPacket(${parts.join(', ')})';
  }
}
