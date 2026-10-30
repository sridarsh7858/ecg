import '../models/game_session.dart';

/// Storage for completed game play-throughs.
abstract class GameSessionRepository {
  /// Newest first.
  Future<List<GameSession>> loadAll();

  Future<void> save(GameSession session);

  Future<void> clear();
}
