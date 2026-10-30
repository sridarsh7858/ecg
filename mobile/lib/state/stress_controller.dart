import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/local/local_store.dart';
import '../data/models/baseline.dart';
import '../data/models/game_recommendation.dart';
import '../data/models/game_session.dart';
import '../data/models/measurement_session.dart';
import '../data/models/physiological_features.dart';
import '../data/models/physiological_input_packet.dart';
import '../data/models/stress_prediction.dart';
import '../data/repositories/game_session_repository.dart';
import '../data/repositories/measurement_repository.dart';
import '../data/repositories/user_repository.dart';
import '../domain/games/game_catalog.dart';
import '../domain/games/game_recommendation_service.dart';
import '../domain/games/game_session_manager.dart';
import '../domain/physiological/demo_physiological_data_source.dart';
import '../domain/stress/stress_level.dart';
import '../domain/stress/stress_prediction_service.dart';

/// The central application state: the current estimate, the demo level that
/// drives it, the stored baseline, and the session history.
///
/// Screens read from here and never construct predictions themselves, which is
/// what makes the whole app react to a level change from one place.
class StressController extends ChangeNotifier {
  StressController({
    required StressPredictionService predictionService,
    required DemoPhysiologicalDataSource demoSource,
    required MeasurementRepository measurementRepository,
    required GameSessionRepository gameSessionRepository,
    required UserRepository userRepository,
    required LocalStore store,
    this.recommendationService = const GameRecommendationService(),
    this.sessionManager = const GameSessionManager(),
  }) : _predictionService = predictionService,
       _demoSource = demoSource,
       _measurements = measurementRepository,
       _gameSessions = gameSessionRepository,
       _users = userRepository,
       _store = store;

  final StressPredictionService _predictionService;
  final DemoPhysiologicalDataSource _demoSource;
  final MeasurementRepository _measurements;
  final GameSessionRepository _gameSessions;
  final UserRepository _users;
  final LocalStore _store;

  final GameRecommendationService recommendationService;
  final GameSessionManager sessionManager;

  StressLevel _demoLevel = StressLevel.moderate;
  StressPrediction? _current;
  PhysiologicalInputPacket? _currentPacket;
  Baseline? _baseline;
  List<MeasurementSession> _history = const [];
  List<GameSession> _games = const [];
  bool _loaded = false;

  // --- Reads ----------------------------------------------------------------

  bool get isLoaded => _loaded;

  /// The level currently selected in the developer/demo panel.
  StressLevel get demoLevel => _demoLevel;

  /// The most recent estimate. Null only before the first one is generated.
  StressPrediction? get current => _current;

  /// The full packet behind [current], when the reading came through the
  /// packet-aware path. Null for readings restored from older storage.
  PhysiologicalInputPacket? get currentPacket => _currentPacket;

  /// The level the whole UI should render right now.
  StressLevel get currentLevel => _current?.level ?? _demoLevel;

  StressLevelInfo get currentInfo => StressLevelConfig.of(currentLevel);

  Baseline? get baseline => _baseline;
  bool get hasBaseline => _baseline != null;

  List<MeasurementSession> get history => _history;
  List<GameSession> get gameSessions => _games;

  String get engineName => _predictionService.displayName;
  String get modelVersion => _predictionService.modelVersion;
  bool get usingDemoEngine => _predictionService.isDemo;
  String get dataSourceName => _demoSource.displayName;

  /// Recommendation for the current estimate.
  GameRecommendation get recommendation =>
      recommendationService.recommendFor(currentLevel);

  /// Comparison of the latest features against the stored baseline.
  BaselineComparison? get baselineComparison {
    final baseline = _baseline;
    final features = _current?.features;
    if (baseline == null || features == null) return null;
    return baseline.compare(features);
  }

  // --- Statistics -----------------------------------------------------------

  int get totalMeasurements => _history.length;
  int get totalGamesPlayed => _games.length;

  int get calmingSessionsPlayed => _games
      .where((s) => GameCatalog.tryById(s.gameId)?.isCalming ?? false)
      .length;

  /// Consecutive days, ending today or yesterday, with at least one check-in.
  int get currentStreak {
    if (_history.isEmpty) return 0;

    final days = _history
        .map(
          (s) =>
              DateTime(s.recordedAt.year, s.recordedAt.month, s.recordedAt.day),
        )
        .toSet();

    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);

    // A streak may legitimately end yesterday when the check-in for today has
    // not happened yet, so allow one day of grace before giving up.
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(cursor)) return 0;
    }

    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Mean level over the last [days] days, or null when there is no data.
  double? averageLevel({int days = 7}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final recent = _history.where((s) => s.recordedAt.isAfter(cutoff)).toList();
    if (recent.isEmpty) return null;
    final total = recent.fold<int>(
      0,
      (sum, s) => sum + s.prediction.levelNumber,
    );
    return total / recent.length;
  }

  /// Sessions from the last [days] days, oldest first - the shape the trend
  /// charts want.
  List<MeasurementSession> historyWithin(int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return _history
        .where((s) => s.recordedAt.isAfter(cutoff))
        .toList()
        .reversed
        .toList();
  }

  // --- Lifecycle ------------------------------------------------------------

  /// Loads persisted state and makes sure there is always something to show.
  Future<void> load() async {
    await _predictionService.initialise();

    _demoLevel = StressLevel.fromNumber(
      _store.getInt(LocalStore.keyDemoLevel, fallback: 3),
    );

    _baseline = await _users.loadBaseline();
    _history = await _measurements.loadAll();
    _games = await _gameSessions.loadAll();

    final storedPrediction = _store.getObject(LocalStore.keyLastPrediction);
    if (storedPrediction != null) {
      _current = StressPrediction.fromJson(storedPrediction);
      _demoLevel = _current!.level;
    } else {
      await refreshCurrent(persist: true);
    }

    _loaded = true;
    notifyListeners();
  }

  // --- Demo control ---------------------------------------------------------

  /// Switches the simulated level and regenerates the current estimate.
  ///
  /// Everything that renders the estimate - dashboard, recommendation, measure
  /// screen, result screen - follows from this single call.
  Future<void> setDemoLevel(StressLevel level) async {
    _demoLevel = level;
    await _store.setInt(LocalStore.keyDemoLevel, level.number);
    await refreshCurrent(persist: true);
  }

  /// Regenerates demo features for [demoLevel] and re-runs the engine.
  Future<StressPrediction> refreshCurrent({bool persist = false}) async {
    final features = _demoSource.generateFeatures(level: _demoLevel);
    final prediction = await _predictionService.predict(features);
    _current = prediction;
    if (persist) {
      await _store.setObject(LocalStore.keyLastPrediction, prediction.toJson());
    }
    notifyListeners();
    return prediction;
  }

  /// Runs the engine over [features] without touching stored state - used by
  /// the developer panel to preview a feature vector.
  Future<StressPrediction> predictOnly(PhysiologicalFeatures features) =>
      _predictionService.predict(features);

  /// Generates a demo feature vector without running the engine.
  PhysiologicalFeatures generateDemoFeatures({StressLevel? level}) =>
      _demoSource.generateFeatures(level: level ?? _demoLevel);

  /// Applies a prediction produced by the measurement flow.
  Future<void> applyPrediction(
    StressPrediction prediction, {
    PhysiologicalInputPacket? packet,
  }) async {
    _current = prediction;
    _currentPacket = packet;
    _demoLevel = prediction.level;
    await _store.setObject(LocalStore.keyLastPrediction, prediction.toJson());
    await _store.setInt(LocalStore.keyDemoLevel, prediction.level.number);
    notifyListeners();
  }

  // --- Persistence ----------------------------------------------------------

  /// Saves a completed check-in and returns the stored record.
  Future<MeasurementSession> saveMeasurement(
    StressPrediction prediction, {
    required int durationSeconds,
    PhysiologicalInputPacket? packet,
  }) async {
    final session = MeasurementSession(
      id: 'ms_${DateTime.now().microsecondsSinceEpoch}',
      prediction: prediction,
      recordedAt: prediction.timestamp,
      durationSeconds: durationSeconds,
      packet: packet ?? _currentPacket,
    );
    await _measurements.save(session);
    _history = await _measurements.loadAll();
    notifyListeners();
    return session;
  }

  /// Records a finished game and links it back to [measurementId] when the
  /// user arrived from a result screen, which is what closes the loop.
  Future<GameSession> recordGameResult({
    required GameResult result,
    required DateTime startTime,
    StressLevel? preLevel,
    String? measurementId,
  }) async {
    final pre = preLevel ?? currentLevel;
    final session = sessionManager.buildSession(
      result: result,
      preStressLevel: pre,
      startTime: startTime,
      source: _demoSource.sourceTag,
    );

    await _gameSessions.save(session);
    _games = await _gameSessions.loadAll();

    if (measurementId != null) {
      final index = _history.indexWhere((m) => m.id == measurementId);
      if (index != -1) {
        final linked = _history[index].copyWith(
          gameSessionId: session.id,
          gameName: session.gameName,
          gameScore: session.score,
          postStressLevel: session.postStressLevel.number,
        );
        await _measurements.update(linked);
        _history = await _measurements.loadAll();
      }
    }

    // The post-session estimate becomes the current view of the user.
    if (session.postStressLevel != pre) {
      _demoLevel = session.postStressLevel;
      await _store.setInt(LocalStore.keyDemoLevel, _demoLevel.number);
      await refreshCurrent(persist: true);
    } else {
      notifyListeners();
    }

    return session;
  }

  Future<void> setBaselineFromFeatures(PhysiologicalFeatures features) async {
    final baseline = Baseline.fromFeatures(features);
    await _users.saveBaseline(baseline);
    _baseline = baseline;
    notifyListeners();
  }

  Future<void> clearBaseline() async {
    await _users.clearBaseline();
    _baseline = null;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _measurements.clear();
    await _gameSessions.clear();
    _history = const [];
    _games = const [];
    notifyListeners();
  }

  /// Fills History with generated sessions so charts and lists are meaningful
  /// on a fresh install. Every record is tagged as demo data.
  Future<void> seedDemoHistory({int days = 60, int? seed}) async {
    final random = math.Random(seed ?? 7);
    final now = DateTime.now();
    final sessions = <MeasurementSession>[];

    for (var dayOffset = days; dayOffset >= 0; dayOffset--) {
      // Roughly two check-ins in three days, so history looks lived-in rather
      // than robotic.
      if (random.nextDouble() > 0.66) continue;

      final day = now.subtract(Duration(days: dayOffset));
      final recordedAt = DateTime(
        day.year,
        day.month,
        day.day,
        8 + random.nextInt(12),
        random.nextInt(60),
      );

      // Gentle downward drift over time, plus day-to-day variation.
      final drift = 3.6 - (days - dayOffset) / days * 0.9;
      final level = StressLevel.fromNumber(
        (drift + (random.nextDouble() * 2 - 1) * 1.3).round().clamp(1, 5),
      );

      final features = _demoSource
          .generateFeatures(level: level)
          .copyWith(timestamp: recordedAt);
      final prediction = await _predictionService.predict(features);

      final played = random.nextDouble() < 0.55;
      final game = played
          ? recommendationService.recommendFor(level).primary
          : null;

      sessions.add(
        MeasurementSession(
          id: 'ms_seed_${recordedAt.microsecondsSinceEpoch}',
          prediction: prediction.copyWith(timestamp: recordedAt),
          recordedAt: recordedAt,
          durationSeconds: 30,
          gameSessionId: game == null ? null : 'gs_seed_$dayOffset',
          gameName: game?.name,
          gameScore: game == null ? null : 40 + random.nextInt(160),
          postStressLevel: game == null ? null : math.max(1, level.number - 1),
        ),
      );
    }

    for (final session in sessions) {
      await _measurements.save(session);
    }
    _history = await _measurements.loadAll();
    notifyListeners();
  }
}
