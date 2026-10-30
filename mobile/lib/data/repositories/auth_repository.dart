import '../models/user_profile.dart';

/// Raised for expected sign-in and sign-up problems.
///
/// Carries a message that is safe to show directly to the user.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Authentication contract.
///
/// [LocalAuthRepository] backs this today so the app runs with no backend at
/// all. A `FirebaseAuthRepository` implementing the same members can be dropped
/// in at the composition root once credentials exist - see
/// `docs/architecture.md`.
abstract class AuthRepository {
  /// The signed-in user, or null.
  Future<UserProfile?> currentUser();

  Future<UserProfile> signIn({required String email, required String password});

  Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
    required int age,
  });

  Future<void> signOut();

  /// Starts a password reset. The local implementation only validates that the
  /// account exists; a real backend would send an email.
  Future<void> requestPasswordReset(String email);

  Future<UserProfile> updateProfile(UserProfile profile);
}
