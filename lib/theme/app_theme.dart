import 'package:flutter/material.dart';

const _seedGreen = Color(0xFF2E7D32);
const _accentYellow = Color(0xFFF2C94C);

class AppTheme {
  static ThemeData build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedGreen,
      brightness: brightness,
    ).copyWith(secondary: _accentYellow);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
    );
  }
}
