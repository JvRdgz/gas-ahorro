import 'package:flutter/material.dart';

import 'screens/map_screen.dart';

const _seedGreen = Color(0xFF2E7D32);
const _accentYellow = Color(0xFFF2C94C);

ThemeData _buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seedGreen,
    brightness: brightness,
  ).copyWith(secondary: _accentYellow);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
  );
}

/// Root app widget with light/dark themes.
class GasAhorroApp extends StatelessWidget {
  const GasAhorroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gas Ahorro',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const MapScreen(),
    );
  }
}
