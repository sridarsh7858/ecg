import '../../domain/stress/stress_level.dart';

/// The standardised result every mini-game returns when it finishes.
///
/// Games know nothing about persistence or stress levels - they hand back a
/// [GameResult] and [GameSessionManager] turns it into a [GameSession].
class GameResult {
  const GameResult({
    required this.gameId,
    required this.duration,
    required this.score,
    required this.completion,
    this.metrics = const {},
  });

  final String gameId;
  final Duration duration;
  final int score;

  /// 0.0 .. 1.0 - how much of the intended session the user finished.
  final double completion;

  /// Game-specific extras, e.g. {'breaths': 12} or {'accuracy': 0.83}.
  final Map<String, num> metrics;

  bool get isMeaningfullyComplete => completion >= 0.75;
}

/// A persisted record of one play-through.
class GameSession {
  const GameSession({
    required this.id,
    required this.gameId,
    required this.gameName,
    required this.startTime,
    required this.endTime,
    required this.score,
    required this.completion,
    required this.preStressLevel,
    required this.postStressLevel,
    required this.source,
    this.metrics = const {},
  });

  final String id;
  final String gameId;
  final String gameName;
  final DateTime startTime;
  final DateTime endTime;
  final int score;
  final double completion;

  /// Estimated level before playing.
  final StressLevel preStressLevel;

  /// Simulated estimated level after playing. Demo behaviour for now.
  final StressLevel postStressLevel;

  final String source;
  final Map<String, num> metrics;

  Duration get duration => endTime.difference(startTime);

  /// Negative means the estimate went down (calmer).
  int get levelDelta => postStressLevel.number - preStressLevel.number;

  bool get improved => levelDelta < 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'gameId': gameId,
    'gameName': gameName,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'score': score,
    'completion': completion,
    'preStressLevel': preStressLevel.number,
    'postStressLevel': postStressLevel.number,
    'source': source,
    'metrics': metrics,
  };

  factory GameSession.fromJson(Map<String, dynamic> json) => GameSession(
    id: json['id'] as String,
    gameId: json['gameId'] as String,
    gameName: json['gameName'] as String,
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: DateTime.parse(json['endTime'] as String),
    score: (json['score'] as num).toInt(),
    completion: (json['completion'] as num).toDouble(),
    preStressLevel: StressLevel.fromNumber(
      (json['preStressLevel'] as num).toInt(),
    ),
    postStressLevel: StressLevel.fromNumber(
      (json['postStressLevel'] as num).toInt(),
    ),
    source: json['source'] as String,
    metrics:
        (json['metrics'] as Map?)?.map(
          (key, value) => MapEntry(key as String, value as num),
        ) ??
        const {},
  );
}
