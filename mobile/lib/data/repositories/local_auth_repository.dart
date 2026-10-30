import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../local/local_store.dart';
import '../models/user_profile.dart';
import 'auth_repository.dart';

/// Offline authentication backed by [LocalStore].
///
/// This exists so the app is fully usable without any backend. Passwords are
/// stored as a salted SHA-256 hash rather than plain text, but this is a
/// prototype account system on a single device - it is not a substitute for a
/// real identity provider, and it is expected to be replaced by Firebase
/// Authentication in a later phase.
class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository(this._store);

  final LocalStore _store;

  /// Fixed salt. Adequate for a local prototype; a real backend does this
  /// properly server-side with a per-user salt.
  static const String _salt = 'neuropulse.v1';

  @override
  Future<UserProfile?> currentUser() async {
    final id = _store.getString(LocalStore.keyCurrentUserId);
    if (id == null) return null;
    return _findById(id);
  }

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    final normalised = _normaliseEmail(email);
    final user = _findByEmail(normalised);
    if (user == null) {
      throw const AuthException('No account found for that email address.');
    }

    final credentials = _store.getObject(LocalStore.keyCredentials) ?? {};
    if (credentials[user.id] != _hash(password)) {
      throw const AuthException('That password does not match our records.');
    }

    await _store.setString(LocalStore.keyCurrentUserId, user.id);
    return user;
  }

  @override
  Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
    required int age,
  }) async {
    final normalised = _normaliseEmail(email);
    if (_findByEmail(normalised) != null) {
      throw const AuthException('An account already uses that email address.');
    }

    final user = UserProfile(
      id: 'u_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      email: normalised,
      age: age,
      createdAt: DateTime.now(),
      avatarSeed: normalised,
    );

    final users = _store.getObjectList(LocalStore.keyUsers).toList()
      ..add(user.toJson());
    await _store.setObjectList(LocalStore.keyUsers, users);

    final credentials = _store.getObject(LocalStore.keyCredentials) ?? {};
    credentials[user.id] = _hash(password);
    await _store.setObject(LocalStore.keyCredentials, credentials);

    await _store.setString(LocalStore.keyCurrentUserId, user.id);
    return user;
  }

  @override
  Future<void> signOut() => _store.remove(LocalStore.keyCurrentUserId);

  @override
  Future<void> requestPasswordReset(String email) async {
    final user = _findByEmail(_normaliseEmail(email));
    if (user == null) {
      throw const AuthException('No account found for that email address.');
    }
    // A real backend would send a reset link here. Locally there is nothing
    // to send, so succeeding is the honest outcome.
  }

  @override
  Future<UserProfile> updateProfile(UserProfile profile) async {
    final users = _store.getObjectList(LocalStore.keyUsers).toList();
    final index = users.indexWhere((json) => json['id'] == profile.id);
    if (index == -1) {
      throw const AuthException('That account no longer exists.');
    }
    users[index] = profile.toJson();
    await _store.setObjectList(LocalStore.keyUsers, users);
    return profile;
  }

  // --- Helpers --------------------------------------------------------------

  String _normaliseEmail(String email) => email.trim().toLowerCase();

  String _hash(String password) =>
      sha256.convert(utf8.encode('$_salt:$password')).toString();

  UserProfile? _findById(String id) {
    for (final json in _store.getObjectList(LocalStore.keyUsers)) {
      if (json['id'] == id) return UserProfile.fromJson(json);
    }
    return null;
  }

  UserProfile? _findByEmail(String email) {
    for (final json in _store.getObjectList(LocalStore.keyUsers)) {
      if (json['email'] == email) return UserProfile.fromJson(json);
    }
    return null;
  }
}
