import '../local/local_store.dart';
import '../models/baseline.dart';
import '../models/game_session.dart';
import '../models/measurement_session.dart';
import 'game_session_repository.dart';
import 'measurement_repository.dart';
import 'user_repository.dart';

/// Local implementations of the data repositories.
///
/// They all persist JSON through [LocalStore]. Each keeps its list ordered
/// newest-first and capped, so history stays fast and storage stays small.

class LocalUserRepository implements UserRepository {
  LocalUserRepository(this._store);

  final LocalStore _store;

  @override
  Future<Baseline?> loadBaseline() async {
    final json = _store.getObject(LocalStore.keyBaseline);
    return json == null ? null : Baseline.fromJson(json);
  }

  @override
  Future<void> saveBaseline(Baseline baseline) =>
      _store.setObject(LocalStore.keyBaseline, baseline.toJson());

  @override
  Future<void> clearBaseline() => _store.remove(LocalStore.keyBaseline);
}

class LocalMeasurementRepository implements MeasurementRepository {
  LocalMeasurementRepository(this._store);

  final LocalStore _store;

  /// Enough for well over a year of daily check-ins.
  static const int maxRecords = 500;

  @override
  Future<List<MeasurementSession>> loadAll() async {
    final sessions =
        _store
            .getObjectList(LocalStore.keyMeasurements)
            .map(MeasurementSession.fromJson)
            .toList()
          ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return sessions;
  }

  @override
  Future<void> save(MeasurementSession session) async {
    final all = await loadAll();
    final updated = [session, ...all.where((s) => s.id != session.id)]
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    await _write(updated);
  }

  @override
  Future<void> update(MeasurementSession session) async {
    final all = await loadAll();
    if (!all.any((s) => s.id == session.id)) return;
    await _write([
      for (final existing in all)
        if (existing.id == session.id) session else existing,
    ]);
  }

  @override
  Future<void> delete(String id) async {
    final all = await loadAll();
    await _write(all.where((s) => s.id != id).toList());
  }

  @override
  Future<void> clear() => _store.remove(LocalStore.keyMeasurements);

  Future<void> _write(List<MeasurementSession> sessions) {
    final capped = sessions.take(maxRecords).map((s) => s.toJson()).toList();
    return _store.setObjectList(LocalStore.keyMeasurements, capped);
  }
}

class LocalGameSessionRepository implements GameSessionRepository {
  LocalGameSessionRepository(this._store);

  final LocalStore _store;

  static const int maxRecords = 500;

  @override
  Future<List<GameSession>> loadAll() async {
    final sessions =
        _store
            .getObjectList(LocalStore.keyGameSessions)
            .map(GameSession.fromJson)
            .toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
    return sessions;
  }

  @override
  Future<void> save(GameSession session) async {
    final all = await loadAll();
    final updated = [session, ...all.where((s) => s.id != session.id)]
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final capped = updated.take(maxRecords).map((s) => s.toJson()).toList();
    await _store.setObjectList(LocalStore.keyGameSessions, capped);
  }

  @override
  Future<void> clear() => _store.remove(LocalStore.keyGameSessions);
}
