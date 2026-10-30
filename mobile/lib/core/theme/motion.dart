import 'package:flutter/material.dart';

/// Animation durations and curves used across the app.
///
/// Every duration is routed through [scale] so that a user who has enabled
/// "reduce motion" (either at the OS level or in NeuroPulse settings) gets a
/// near-instant, non-animated experience.
class AppMotion {
  const AppMotion._();

  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 600);
  static const Duration reveal = Duration(milliseconds: 900);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasised = Curves.easeInOutCubicEmphasized;

  /// Returns [duration], or a negligible duration when motion is reduced.
  static Duration scale(Duration duration, {required bool reduceMotion}) {
    return reduceMotion ? const Duration(milliseconds: 1) : duration;
  }

  /// True when the platform requests reduced motion.
  static bool platformPrefersReducedMotion(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }
}
