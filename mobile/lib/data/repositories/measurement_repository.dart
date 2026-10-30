import '../models/measurement_session.dart';

/// Storage for completed check-ins.
abstract class MeasurementRepository {
  /// Newest first.
  Future<List<MeasurementSession>> loadAll();

  Future<void> save(MeasurementSession session);

  /// Replaces an existing record with the same id; no-op when absent.
  Future<void> update(MeasurementSession session);

  Future<void> delete(String id);

  Future<void> clear();
}
