import 'dart:collection';

/// A burst of raw ECG samples streamed from the wearable.
///
/// The first firmware is expected to send derived features only - streaming
/// 250-500 Hz of raw ADC over BLE is a lot of bandwidth for a battery-powered
/// ESP32. This type exists so that raw streaming can be switched on later
/// without touching anything but the firmware and [RawEcgBuffer].
///
/// Samples are raw ADC counts as the ESP32 read them. The app does not assume
/// a scale, a resolution or a sampling rate beyond what the packet declares.
class RawEcgPacket {
  const RawEcgPacket({
    required this.timestamp,
    required this.samples,
    this.sampleRateHz,
    this.sequence,
  });

  final DateTime timestamp;

  /// Raw ADC samples in acquisition order.
  final List<double> samples;

  /// Sampling rate in Hz, when the firmware declares it.
  ///
  /// Null means unknown - the waveform can still be drawn, it just cannot be
  /// given a real time axis.
  final double? sampleRateHz;

  /// Monotonic counter, used to detect dropped packets.
  final int? sequence;

  bool get isEmpty => samples.isEmpty;

  /// Duration this burst covers, when the sample rate is known.
  Duration? get duration {
    final rate = sampleRateHz;
    if (rate == null || rate <= 0) return null;
    return Duration(microseconds: (samples.length / rate * 1e6).round());
  }

  Map<String, dynamic> toJson() => {
    'type': 'ecg',
    'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
    'samples': samples,
    if (sampleRateHz != null) 'sample_rate': sampleRateHz,
    if (sequence != null) 'seq': sequence,
  };

  @override
  String toString() =>
      'RawEcgPacket(${samples.length} samples'
      '${sampleRateHz != null ? ' @ ${sampleRateHz}Hz' : ''}'
      '${sequence != null ? ', seq $sequence' : ''})';
}

/// Fixed-capacity ring buffer of raw ECG samples for the live waveform.
///
/// Bounded on purpose. A stream of raw ECG that is never trimmed is an
/// unbounded memory leak on a long session, and the waveform view only ever
/// needs the most recent screenful.
class RawEcgBuffer {
  RawEcgBuffer({this.capacity = 1500});

  /// Maximum samples retained. At 250 Hz this is six seconds.
  final int capacity;

  final Queue<double> _samples = Queue<double>();

  DateTime? _lastPacketAt;
  double? _sampleRateHz;
  int? _lastSequence;
  int _droppedPackets = 0;

  /// Samples oldest-first, at most [capacity] of them.
  List<double> get samples => List.unmodifiable(_samples);

  int get length => _samples.length;

  bool get isEmpty => _samples.isEmpty;

  bool get isNotEmpty => _samples.isNotEmpty;

  /// When the most recent packet arrived, or null if none ever has.
  DateTime? get lastPacketAt => _lastPacketAt;

  double? get sampleRateHz => _sampleRateHz;

  /// Packets missed, inferred from gaps in the sequence counter.
  int get droppedPackets => _droppedPackets;

  void add(RawEcgPacket packet) {
    _lastPacketAt = packet.timestamp;
    _sampleRateHz = packet.sampleRateHz ?? _sampleRateHz;

    final sequence = packet.sequence;
    if (sequence != null) {
      final previous = _lastSequence;
      if (previous != null && sequence > previous + 1) {
        _droppedPackets += sequence - previous - 1;
      }
      _lastSequence = sequence;
    }

    for (final sample in packet.samples) {
      _samples.addLast(sample);
    }
    while (_samples.length > capacity) {
      _samples.removeFirst();
    }
  }

  void clear() {
    _samples.clear();
    _lastPacketAt = null;
    _lastSequence = null;
    _droppedPackets = 0;
  }

  /// Samples normalised to -1..1 for drawing.
  ///
  /// Scales against the observed range of the buffer rather than an assumed
  /// ADC width, so it renders correctly whatever resolution the ESP32 uses.
  /// Returns an empty list when the buffer is empty - the caller shows
  /// "ECG waveform unavailable" rather than a flat fake line.
  List<double> normalised() {
    if (_samples.isEmpty) return const [];

    var min = _samples.first;
    var max = _samples.first;
    for (final sample in _samples) {
      if (sample < min) min = sample;
      if (sample > max) max = sample;
    }

    final range = max - min;
    if (range <= 0) return List<double>.filled(_samples.length, 0);

    return _samples.map((s) => ((s - min) / range) * 2 - 1).toList();
  }
}
