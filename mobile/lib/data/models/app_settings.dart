import 'package:flutter/material.dart';

/// User-adjustable app settings, persisted locally.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.demoMode = true,
    this.measurementSeconds = 30,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.reduceMotion = false,
  });

  final ThemeMode themeMode;

  /// While true the app uses [DemoPhysiologicalDataSource]. Turning it off is
  /// only meaningful once real hardware is paired.
  final bool demoMode;

  /// Length of a check-in, in seconds.
  final int measurementSeconds;

  final bool soundEnabled;
  final bool hapticsEnabled;

  /// App-level override on top of the OS "reduce motion" setting.
  final bool reduceMotion;

  /// Selectable measurement durations, in seconds.
  static const List<int> durationOptions = [15, 30, 45, 60];

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? demoMode,
    int? measurementSeconds,
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? reduceMotion,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      demoMode: demoMode ?? this.demoMode,
      measurementSeconds: measurementSeconds ?? this.measurementSeconds,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      reduceMotion: reduceMotion ?? this.reduceMotion,
    );
  }

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'demoMode': demoMode,
    'measurementSeconds': measurementSeconds,
    'soundEnabled': soundEnabled,
    'hapticsEnabled': hapticsEnabled,
    'reduceMotion': reduceMotion,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    themeMode: ThemeMode.values.firstWhere(
      (mode) => mode.name == json['themeMode'],
      orElse: () => ThemeMode.system,
    ),
    demoMode: json['demoMode'] as bool? ?? true,
    measurementSeconds: (json['measurementSeconds'] as num?)?.toInt() ?? 30,
    soundEnabled: json['soundEnabled'] as bool? ?? true,
    hapticsEnabled: json['hapticsEnabled'] as bool? ?? true,
    reduceMotion: json['reduceMotion'] as bool? ?? false,
  );
}
