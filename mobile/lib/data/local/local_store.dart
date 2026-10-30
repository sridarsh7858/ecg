import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Thin JSON-over-key-value wrapper around [SharedPreferences].
///
/// Everything the app persists today is small (a profile, settings, a few
/// hundred session records), so a document store would be over-engineering.
/// Repositories talk to this class rather than to SharedPreferences directly,
/// which keeps the swap to Firebase or a real database a repository-level
/// change.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  // --- Keys -----------------------------------------------------------------

  static const String keyOnboardingSeen = 'onboarding_seen';
  static const String keyCurrentUserId = 'current_user_id';
  static const String keyUsers = 'users';
  static const String keyCredentials = 'credentials';
  static const String keySettings = 'settings';
  static const String keyBaseline = 'baseline';
  static const String keyMeasurements = 'measurements';
  static const String keyGameSessions = 'game_sessions';
  static const String keyDemoLevel = 'demo_level';
  static const String keyLastPrediction = 'last_prediction';
  static const String keyGarden = 'zen_garden';

  // --- Primitives -----------------------------------------------------------

  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;

  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  int getInt(String key, {int fallback = 0}) => _prefs.getInt(key) ?? fallback;

  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  String? getString(String key) => _prefs.getString(key);

  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  Future<void> remove(String key) => _prefs.remove(key);

  // --- JSON -----------------------------------------------------------------

  /// Reads a JSON object, returning null when absent or unparseable.
  ///
  /// Corrupt data is dropped rather than thrown so a bad write from an earlier
  /// build cannot brick the app.
  Map<String, dynamic>? getObject(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> setObject(String key, Map<String, dynamic> value) =>
      _prefs.setString(key, jsonEncode(value));

  /// Reads a JSON array of objects. Returns an empty list when absent.
  List<Map<String, dynamic>> getObjectList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
    } on FormatException {
      return [];
    }
  }

  Future<void> setObjectList(String key, List<Map<String, dynamic>> value) =>
      _prefs.setString(key, jsonEncode(value));

  /// Removes every key this app owns. Used by "clear local data".
  Future<void> clearAll() async {
    for (final key in [
      keyOnboardingSeen,
      keyCurrentUserId,
      keyUsers,
      keyCredentials,
      keySettings,
      keyBaseline,
      keyMeasurements,
      keyGameSessions,
      keyDemoLevel,
      keyLastPrediction,
      keyGarden,
    ]) {
      await _prefs.remove(key);
    }
  }
}
