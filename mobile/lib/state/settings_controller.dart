import 'package:flutter/material.dart';

import '../data/local/local_store.dart';
import '../data/models/app_settings.dart';

/// Owns [AppSettings] and persists every change immediately.
class SettingsController extends ChangeNotifier {
  SettingsController(this._store) {
    _settings = _read();
  }

  final LocalStore _store;
  late AppSettings _settings;

  AppSettings get settings => _settings;

  ThemeMode get themeMode => _settings.themeMode;
  bool get demoMode => _settings.demoMode;
  int get measurementSeconds => _settings.measurementSeconds;
  bool get soundEnabled => _settings.soundEnabled;
  bool get hapticsEnabled => _settings.hapticsEnabled;
  bool get reduceMotion => _settings.reduceMotion;

  Duration get measurementDuration => Duration(seconds: measurementSeconds);

  AppSettings _read() {
    final json = _store.getObject(LocalStore.keySettings);
    return json == null ? const AppSettings() : AppSettings.fromJson(json);
  }

  Future<void> _write(AppSettings next) async {
    _settings = next;
    notifyListeners();
    await _store.setObject(LocalStore.keySettings, next.toJson());
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _write(_settings.copyWith(themeMode: mode));

  Future<void> setDemoMode(bool enabled) =>
      _write(_settings.copyWith(demoMode: enabled));

  Future<void> setMeasurementSeconds(int seconds) =>
      _write(_settings.copyWith(measurementSeconds: seconds));

  Future<void> setSoundEnabled(bool enabled) =>
      _write(_settings.copyWith(soundEnabled: enabled));

  Future<void> setHapticsEnabled(bool enabled) =>
      _write(_settings.copyWith(hapticsEnabled: enabled));

  Future<void> setReduceMotion(bool enabled) =>
      _write(_settings.copyWith(reduceMotion: enabled));

  Future<void> reset() => _write(const AppSettings());
}
