import '../models/baseline.dart';

/// Per-user data that is not the account itself.
abstract class UserRepository {
  Future<Baseline?> loadBaseline();

  Future<void> saveBaseline(Baseline baseline);

  Future<void> clearBaseline();
}
