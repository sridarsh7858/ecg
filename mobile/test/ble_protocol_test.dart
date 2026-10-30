import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/data/models/physiological_input_packet.dart';
import 'package:neuropulse/data/models/raw_ecg_packet.dart';
import 'package:neuropulse/domain/ble/ble_protocol.dart';

/// Section 16, 18 and 19: the wire protocol.
///
/// These tests are the firmware contract. If the ESP32 sends something that
/// passes here, the app will accept it; if it sends something that fails here,
/// the app will reject it safely rather than crashing.
void main() {
  PhysiologicalInputPacket parsePhysiology(String payload) {
    final result = BleProtocol.parse(payload);
    expect(
      result,
      isA<PhysiologyPacketResult>(),
      reason: 'expected a valid physiology packet from: $payload',
    );
    return (result as PhysiologyPacketResult).packet;
  }

  group('well-formed packets', () {
    test('parses the full documented packet', () {
      final packet = parsePhysiology(
        jsonEncode({
          'type': 'physiology',
          'timestamp': 1720000000,
          'hr': 82.0,
          'mean_rr': 731.7,
          'rmssd': 34.2,
          'sdnn': 41.8,
          'pnn50': 12.5,
          'gsr': 2.14,
          'gsr_peaks': 3,
          'accel_x': 0.02,
          'accel_y': 0.11,
          'accel_z': 0.98,
          'gyro_x': 0.01,
          'gyro_y': 0.03,
          'gyro_z': 0.02,
          'battery': 87,
          'signal_quality': 0.92,
        }),
      );

      expect(packet.heartRate, 82.0);
      expect(packet.meanRR, 731.7);
      expect(packet.rmssd, 34.2);
      expect(packet.sdnn, 41.8);
      expect(packet.pnn50, 12.5);
      expect(packet.gsrValue, 2.14);
      expect(packet.gsrPeaks, 3);
      expect(packet.accelZ, 0.98);
      expect(packet.gyroY, 0.03);
      expect(packet.batteryPercentage, 87);
      expect(packet.signalQuality, 0.92);
      expect(packet.source, PhysiologicalSource.bluetooth);
    });

    test('accepts the minimal packet from the brief', () {
      // Section 36 names this exact payload as one that must parse.
      final packet = parsePhysiology('{"type":"physiology","hr":82,'
          '"rmssd":34.2,"sdnn":41.8,"pnn50":12.5}');

      expect(packet.heartRate, 82);
      expect(packet.rmssd, 34.2);
    });

    test('accepts a packet carrying only two fields', () {
      final packet = parsePhysiology('{"hr": 82, "rmssd": 34.2}');

      expect(packet.heartRate, 82);
      expect(packet.rmssd, 34.2);

      // Everything absent stays absent. This is the whole point: a missing
      // sensor must never become a zero, because zero is a real reading.
      expect(packet.sdnn, isNull);
      expect(packet.pnn50, isNull);
      expect(packet.gsrValue, isNull);
      expect(packet.gsrPeaks, isNull);
      expect(packet.accelX, isNull);
      expect(packet.gyroX, isNull);
      expect(packet.batteryPercentage, isNull);
      expect(packet.hasGsr, isFalse);
      expect(packet.hasMovement, isFalse);
      expect(packet.hasBattery, isFalse);
    });

    test('derives mean R-R from heart rate when not sent', () {
      final packet = parsePhysiology('{"hr": 80}');
      expect(packet.meanRR, isNull, reason: 'not sent, so not stored');
      expect(packet.effectiveMeanRR, closeTo(750, 0.01));
    });

    test('derives heart rate from mean R-R when not sent', () {
      final packet = parsePhysiology('{"mean_rr": 750}');
      expect(packet.effectiveHeartRate, closeTo(80, 0.01));
    });

    test('a missing type field is treated as physiology', () {
      expect(BleProtocol.parse('{"hr": 70}'), isA<PhysiologyPacketResult>());
    });

    test('accepts camelCase and alternative field spellings', () {
      final packet = parsePhysiology('{"heartRate": 70, "meanRR": 857}');
      expect(packet.heartRate, 70);
      expect(packet.meanRR, 857);
    });
  });

  group('malformed packets are rejected safely', () {
    for (final payload in <String>[
      '',
      '   ',
      'not json at all',
      '{ unclosed',
      '[1, 2, 3]',
      '"just a string"',
      '42',
      '{}',
      '{"type": "physiology"}',
    ]) {
      test('rejects ${payload.isEmpty ? '(empty)' : payload}', () {
        // The contract is that parse NEVER throws, whatever it is handed.
        final result = BleProtocol.parse(payload);
        expect(result, isA<InvalidPacketResult>());
        expect((result as InvalidPacketResult).reason, isNotEmpty);
      });
    }

    test('rejects a packet whose fields are all non-numeric', () {
      final result = BleProtocol.parse('{"hr": "fast", "rmssd": null}');
      expect(result, isA<InvalidPacketResult>());
    });

    test('rejects invalid UTF-8 bytes', () {
      final result = BleProtocol.parseBytes([0xC3, 0x28, 0xA0]);
      expect(result, isA<InvalidPacketResult>());
    });

    test('rejects an empty notification', () {
      expect(BleProtocol.parseBytes([]), isA<InvalidPacketResult>());
    });
  });

  group('range validation', () {
    test('drops out-of-range values but keeps the rest of the packet', () {
      // A detached electrode reporting 0 BPM alongside a good RMSSD must not
      // poison the reading, and must not be silently believed either.
      final result = BleProtocol.parse('{"hr": 0, "rmssd": 34.2}');

      expect(result, isA<PhysiologyPacketResult>());
      final success = result as PhysiologyPacketResult;
      expect(success.packet.heartRate, isNull);
      expect(success.packet.rmssd, 34.2);
      expect(success.warnings, isNotEmpty);
    });

    test('drops an ADC glitch', () {
      final result = BleProtocol.parse('{"hr": 40000, "rmssd": 30}');
      expect((result as PhysiologyPacketResult).packet.heartRate, isNull);
    });

    test('rejects NaN and infinity', () {
      // These cannot be written as JSON literals, so they arrive as strings
      // from a firmware that formatted a float badly.
      for (final bad in ['NaN', 'Infinity', '-Infinity']) {
        final result = BleProtocol.parse('{"hr": "$bad", "rmssd": 30}');
        expect((result as PhysiologyPacketResult).packet.heartRate, isNull);
      }
    });

    test('pNN50 above 100 percent is impossible and is dropped', () {
      final result = BleProtocol.parse('{"hr": 70, "pnn50": 180}');
      expect((result as PhysiologyPacketResult).packet.pnn50, isNull);
    });

    test('battery outside 0-100 is dropped', () {
      final result = BleProtocol.parse('{"hr": 70, "battery": 250}');
      expect(
        (result as PhysiologyPacketResult).packet.batteryPercentage,
        isNull,
      );
    });

    test('accepts values at the range boundaries', () {
      final packet = parsePhysiology('{"hr": 20, "pnn50": 100}');
      expect(packet.heartRate, 20);
      expect(packet.pnn50, 100);
    });
  });

  group('timestamps', () {
    test('uses the firmware clock when it is plausible', () {
      final packet = parsePhysiology('{"hr": 70, "timestamp": 1720000000}');
      expect(packet.timestamp.year, 2024);
    });

    test('falls back to the phone clock for an unsynced ESP32', () {
      // A board with no RTC sends its uptime, which would date every reading
      // to 1970 and wreck the history chart.
      final before = DateTime.now();
      final packet = parsePhysiology('{"hr": 70, "timestamp": 4213}');
      expect(
        packet.timestamp.isAfter(before.subtract(const Duration(seconds: 5))),
        isTrue,
      );
    });
  });

  group('raw ECG packets', () {
    test('parses a burst of samples', () {
      final result = BleProtocol.parse(
        '{"type":"ecg","timestamp":1720000000,'
        '"sample_rate":250,"samples":[1234,1250,1288,1302]}',
      );

      expect(result, isA<EcgPacketResult>());
      final packet = (result as EcgPacketResult).packet;
      expect(packet.samples, [1234, 1250, 1288, 1302]);
      expect(packet.sampleRateHz, 250);
      expect(packet.duration, isNotNull);
    });

    test('rejects a burst with no samples array', () {
      expect(
        BleProtocol.parse('{"type":"ecg","timestamp":1}'),
        isA<InvalidPacketResult>(),
      );
    });

    test('rejects non-numeric samples', () {
      expect(
        BleProtocol.parse('{"type":"ecg","samples":[1,"x",3]}'),
        isA<InvalidPacketResult>(),
      );
    });

    test('rejects an oversized burst', () {
      final samples = List<int>.filled(
        BleProtocol.maxEcgSamplesPerPacket + 1,
        1000,
      );
      expect(
        BleProtocol.parse('{"type":"ecg","samples":${jsonEncode(samples)}}'),
        isA<InvalidPacketResult>(),
      );
    });
  });

  group('RawEcgBuffer', () {
    test('is bounded and keeps the most recent samples', () {
      final buffer = RawEcgBuffer(capacity: 5);
      for (var i = 0; i < 4; i++) {
        buffer.add(
          RawEcgPacket(
            timestamp: DateTime.now(),
            samples: [i * 3.0, i * 3 + 1.0, i * 3 + 2.0],
          ),
        );
      }
      expect(buffer.length, 5, reason: 'must not grow without bound');
      expect(buffer.samples.last, 11.0);
    });

    test('normalises into -1..1 for drawing', () {
      final buffer = RawEcgBuffer()
        ..add(
          RawEcgPacket(
            timestamp: DateTime.now(),
            samples: const [0, 50, 100],
          ),
        );
      expect(buffer.normalised(), [-1.0, 0.0, 1.0]);
    });

    test('an empty buffer normalises to nothing, not to a flat line', () {
      expect(RawEcgBuffer().normalised(), isEmpty);
    });

    test('counts dropped packets from sequence gaps', () {
      final buffer = RawEcgBuffer();
      for (final seq in [1, 2, 5]) {
        buffer.add(
          RawEcgPacket(
            timestamp: DateTime.now(),
            samples: const [1],
            sequence: seq,
          ),
        );
      }
      expect(buffer.droppedPackets, 2);
    });
  });
}
