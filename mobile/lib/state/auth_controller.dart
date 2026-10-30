import 'package:flutter/foundation.dart';

import '../data/local/local_store.dart';
import '../data/models/user_profile.dart';
import '../data/repositories/auth_repository.dart';

/// Coarse state of the sign-in flow, used by the root gate to decide what to
/// show while startup work is still running.
enum AuthStatus { unknown, signedOut, signedIn }

/// Owns the signed-in user and the onboarding flag.
class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    required LocalStore store,
  }) : _repository = repository,
       _store = store;

  final AuthRepository _repository;
  final LocalStore _store;

  AuthStatus _status = AuthStatus.unknown;
  UserProfile? _user;
  bool _busy = false;
  String? _error;

  AuthStatus get status => _status;
  UserProfile? get user => _user;
  bool get isBusy => _busy;
  String? get error => _error;
  bool get isSignedIn => _status == AuthStatus.signedIn;

  bool get hasSeenOnboarding => _store.getBool(LocalStore.keyOnboardingSeen);

  Future<void> completeOnboarding() async {
    await _store.setBool(LocalStore.keyOnboardingSeen, true);
    notifyListeners();
  }

  /// Restores any previously signed-in user. Called once at startup.
  Future<void> restore() async {
    final user = await _repository.currentUser();
    _user = user;
    _status = user == null ? AuthStatus.signedOut : AuthStatus.signedIn;
    notifyListeners();
  }

  Future<bool> signIn({required String email, required String password}) {
    return _run(() => _repository.signIn(email: email, password: password));
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required int age,
  }) {
    return _run(
      () => _repository.register(
        name: name,
        email: email,
        password: password,
        age: age,
      ),
    );
  }

  Future<bool> requestPasswordReset(String email) async {
    return _guard(() async {
      await _repository.requestPasswordReset(email);
      return true;
    });
  }

  Future<void> signOut() async {
    await _repository.signOut();
    _user = null;
    _status = AuthStatus.signedOut;
    _error = null;
    notifyListeners();
  }

  Future<bool> updateProfile(UserProfile profile) async {
    return _guard(() async {
      _user = await _repository.updateProfile(profile);
      return true;
    });
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Runs an auth call that yields a user, updating status on success.
  Future<bool> _run(Future<UserProfile> Function() action) {
    return _guard(() async {
      _user = await action();
      _status = AuthStatus.signedIn;
      return true;
    });
  }

  /// Shared busy/error handling. Returns false and exposes a user-facing
  /// message when the repository reports a known problem.
  Future<bool> _guard(Future<bool> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      return await action();
    } on AuthException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'Something went wrong. Please try again.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
