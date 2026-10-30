import 'dart:math' as math;

import '../../data/models/game_session.dart';
import '../stress/stress_level.dart';
import 'game_catalog.dart';

/// Turns a finished [GameResult] into a persisted [GameSession].
///
/// It also owns the *simulated* post-session estimate. Today that estimate is
/// a demo rule based on how much of the session the user completed. When the
/// hardware lands, the honest version of this flow is to re-measure and run the
/// real engine again; [simulatePostLevel] is the single place that changes.
class GameSessionManager {
  const GameSessionManager();

  /// How complete a session must be before the demo lowers the estimate.
  static const double completionThreshold = 0.75;

  GameSession buildSession({
    required GameResult result,
    required StressLevel preStressLevel,
    required DateTime startTime,
    required String source,
    String? id,
  }) {
    final definition = GameCatalog.tryById(result.gameId);
    final endTime = startTime.add(result.duration);

    return GameSession(
      id: id ?? _generateId(startTime, result.gameId),
      gameId: result.gameId,
      gameName: definition?.name ?? result.gameId,
      startTime: startTime,
      endTime: endTime,
      score: result.score,
      completion: result.completion,
      preStressLevel: preStressLevel,
      postStressLevel: simulatePostLevel(pre: preStressLevel, result: result),
      source: source,
      metrics: result.metrics,
    );
  }

  /// Demo model of how the estimate moves after a session.
  ///
  /// A meaningfully completed session lowers the estimate by one level; a
  /// calming activity finished in full at a high starting level can lower it by
  /// two. Nothing here claims a clinical effect - it exists so the biofeedback
  /// loop can be demonstrated before real re-measurement is possible.
  StressLevel simulatePostLevel({
    required StressLevel pre,
    required GameResult result,
  }) {
    if (result.completion < completionThreshold) return pre;

    final definition = GameCatalog.tryById(result.gameId);
    final isCalming = definition?.isCalming ?? false;
    final fullyCompleted = result.completion >= 0.98;

    var drop = 1;
    if (isCalming && fullyCompleted && pre.number >= 4) drop = 2;

    return StressLevel.fromNumber(math.max(1, pre.number - drop));
  }

  String _generateId(DateTime startTime, String gameId) =>
      'gs_${startTime.microsecondsSinceEpoch}_$gameId';
}
