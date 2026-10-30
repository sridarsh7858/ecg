import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/data/models/app_settings.dart';
import 'package:neuropulse/data/models/baseline.dart';
import 'package:neuropulse/data/models/game_session.dart';
import 'package:neuropulse/data/models/measurement_session.dart';
import 'package:neuropulse/data/models/physiological_features.dart';
import 'package:neuropulse/data/models/stress_prediction.dart';
import 'package:neuropulse/data/models/user_profile.dart';
import 'package:neuropulse/domain/stress/stress_level.dart';
import 'package:flutter/material.dart' show ThemeMode;

/// Round-trips every model through JSON, the way local storage does.
void main() {
  final features = PhysiologicalFeatures.fromHr(
    hr: 91,
    rmssd: 24,
    sdnn: 31,
    pnn50: 7,
    timestamp: DateTime.utc(2026, 9, 4, 9, 30),
  );

  final prediction = StressPrediction(
    level: StressLevel.high,
    label: 'High',
    confidence: 0.82,
    features: features,
    timestamp: DateTime.utc(2026, 9, 4, 9, 30, 30),
    source: DataSourceTag.demo,
    modelVersion: 'demo-1.0.0',
  );

  /// Encoding and decoding for real catches anything a Map alone would miss.
  T roundTrip<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) f,
  ) {
    return f(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
  }

  group('PhysiologicalFeatures', () {
    test('survives a JSON round trip', () {
      final restored = roundTrip(
        features.toJson(),
        PhysiologicalFeatures.fromJson,
      );
      expect(restored, features);
    });

    test('fromHr derives mean R-R from heart rate', () {
      expect(features.meanRR, closeTo(60000 / 91, 1e-9));
    });

    test('copyWith replaces only what it is given', () {
      final copy = features.copyWith(hr: 60);
      expect(copy.hr, 60);
      expect(copy.rmssd, features.rmssd);
      expect(copy.timestamp, features.timestamp);
    });

    test('defaults to the demo source tag', () {
      expect(features.isDemo, isTrue);
      expect(features.source, DataSourceTag.demo);
    });
  });

  group('StressPrediction', () {
    test('survives a JSON round trip', () {
      final restored = roundTrip(
        prediction.toJson(),
        StressPrediction.fromJson,
      );
      expect(restored.level, prediction.level);
      expect(restored.label, prediction.label);
      expect(restored.confidence, prediction.confidence);
      expect(restored.features, prediction.features);
      expect(restored.timestamp, prediction.timestamp);
      expect(restored.modelVersion, prediction.modelVersion);
    });

    test('exposes the level number and confidence percentage', () {
      expect(prediction.levelNumber, 4);
      expect(prediction.confidencePercent, 82);
    });

    test('a corrupt level number is clamped rather than thrown', () {
      final json = prediction.toJson()..['level'] = 42;
      expect(StressPrediction.fromJson(json).level, StressLevel.veryHigh);
    });
  });

  group('MeasurementSession', () {
    final session = MeasurementSession(
      id: 'ms_1',
      prediction: prediction,
      recordedAt: DateTime.utc(2026, 9, 4, 9, 31),
      durationSeconds: 30,
    );

    test('survives a JSON round trip, including the linked game', () {
      final linked = session.copyWith(
        gameSessionId: 'gs_1',
        gameName: 'Calm Breathing',
        gameScore: 120,
        postStressLevel: 3,
      );
      final restored = roundTrip(linked.toJson(), MeasurementSession.fromJson);

      expect(restored.id, 'ms_1');
      expect(restored.hasGame, isTrue);
      expect(restored.gameName, 'Calm Breathing');
      expect(restored.gameScore, 120);
      expect(restored.postStressLevel, 3);
      expect(restored.durationSeconds, 30);
    });

    test('has no game until one is linked', () {
      expect(session.hasGame, isFalse);
      final restored = roundTrip(session.toJson(), MeasurementSession.fromJson);
      expect(restored.hasGame, isFalse);
      expect(restored.gameName, isNull);
    });
  });

  group('GameSession', () {
    final session = GameSession(
      id: 'gs_1',
      gameId: 'calm_breathing',
      gameName: 'Calm Breathing',
      startTime: DateTime.utc(2026, 9, 4, 10),
      endTime: DateTime.utc(2026, 9, 4, 10, 2),
      score: 120,
      completion: 1,
      preStressLevel: StressLevel.high,
      postStressLevel: StressLevel.moderate,
      source: DataSourceTag.demo,
      metrics: {'breaths': 12},
    );

    test('survives a JSON round trip including metrics', () {
      final restored = roundTrip(session.toJson(), GameSession.fromJson);
      expect(restored.gameName, 'Calm Breathing');
      expect(restored.duration, const Duration(minutes: 2));
      expect(restored.preStressLevel, StressLevel.high);
      expect(restored.postStressLevel, StressLevel.moderate);
      expect(restored.metrics['breaths'], 12);
    });

    test('reports the direction of the change', () {
      expect(session.levelDelta, -1);
      expect(session.improved, isTrue);
    });
  });

  group('Baseline', () {
    final baseline = Baseline.fromFeatures(features);

    test('survives a JSON round trip', () {
      final restored = roundTrip(baseline.toJson(), Baseline.fromJson);
      expect(restored.hr, baseline.hr);
      expect(restored.rmssd, baseline.rmssd);
      expect(restored.sdnn, baseline.sdnn);
      expect(restored.pnn50, baseline.pnn50);
      expect(restored.recordedAt, baseline.recordedAt);
    });

    test('compare produces signed per-feature deltas', () {
      final later = features.copyWith(hr: 100, rmssd: 20);
      final comparison = baseline.compare(later);
      expect(comparison.hrDelta, closeTo(9, 1e-9));
      expect(comparison.rmssdDelta, closeTo(-4, 1e-9));
      expect(comparison.sdnnDelta, 0);
    });
  });

  group('UserProfile', () {
    final user = UserProfile(
      id: 'u_1',
      name: 'Asha Ramesh',
      email: 'asha@example.com',
      age: 21,
      createdAt: DateTime.utc(2026, 9, 1),
    );

    test('survives a JSON round trip', () {
      final restored = roundTrip(user.toJson(), UserProfile.fromJson);
      expect(restored.name, 'Asha Ramesh');
      expect(restored.email, 'asha@example.com');
      expect(restored.age, 21);
    });

    test('derives initials and first name', () {
      expect(user.initials, 'AR');
      expect(user.firstName, 'Asha');
      expect(user.copyWith(name: 'Sam').initials, 'SA');
      expect(user.copyWith(name: '  ').firstName, 'there');
    });
  });

  group('AppSettings', () {
    test('survives a JSON round trip', () {
      const settings = AppSettings(
        themeMode: ThemeMode.dark,
        demoMode: false,
        measurementSeconds: 45,
        soundEnabled: false,
        hapticsEnabled: false,
        reduceMotion: true,
      );
      final restored = roundTrip(settings.toJson(), AppSettings.fromJson);
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.demoMode, isFalse);
      expect(restored.measurementSeconds, 45);
      expect(restored.reduceMotion, isTrue);
    });

    test('falls back to sane defaults for missing or bad fields', () {
      final restored = AppSettings.fromJson({'themeMode': 'nonsense'});
      expect(restored.themeMode, ThemeMode.system);
      expect(restored.demoMode, isTrue);
      expect(restored.measurementSeconds, 30);
    });
  });
}
