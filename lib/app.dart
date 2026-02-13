import 'package:flutter/material.dart';

import 'screens/map_screen.dart';
import 'theme/app_theme.dart';

/// Root app widget with light/dark themes.
class GasAhorroApp extends StatelessWidget {
  const GasAhorroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gas Ahorro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light),
      darkTheme: AppTheme.build(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const MapScreen(),
    );
  }
}
