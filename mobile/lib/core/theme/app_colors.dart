import 'package:flutter/material.dart';

/// Centralised colour tokens for NeuroPulse.
///
/// The palette is intentionally calm: desaturated teals and sands rather than
/// clinical blues. Stress levels never use an alarming pure red — level 5 is a
/// muted rose so the interface encourages rather than frightens.
class AppColors {
  const AppColors._();

  /// Brand seed used to derive the Material 3 colour scheme.
  static const Color seed = Color(0xFF3E8E7E);

  static const Color brandDeep = Color(0xFF1F4F47);
  static const Color brandSoft = Color(0xFF8FD3C4);
  static const Color accent = Color(0xFF6C7BE0);

  // Stress level accents (light theme). Each is paired with an icon and a
  // written label so meaning never depends on colour alone.
  static const Color level1 = Color(0xFF2E9E7A); // very low  - green
  static const Color level2 = Color(0xFF57A85B); // low       - leaf
  static const Color level3 = Color(0xFFC79A2E); // moderate  - amber
  static const Color level4 = Color(0xFFCE7B4A); // high      - warm clay
  static const Color level5 = Color(0xFFB4636F); // very high - muted rose

  /// Slightly lighter variants used on dark surfaces for contrast.
  static const Color level1Dark = Color(0xFF63C9A6);
  static const Color level2Dark = Color(0xFF8FCB86);
  static const Color level3Dark = Color(0xFFE3C062);
  static const Color level4Dark = Color(0xFFEBA47B);
  static const Color level5Dark = Color(0xFFDE97A2);

  static const Color positive = Color(0xFF2E9E7A);
  static const Color caution = Color(0xFFC79A2E);
  static const Color info = Color(0xFF6C7BE0);
}
