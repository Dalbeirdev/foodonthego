import 'package:flutter/material.dart';

import 'core/router/app_shell.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const FoodOnTheGoApp());
}

/// FoodOnTheGo — customer application.
///
/// Module 01 establishes the theme, the navigation architecture and the screen
/// scaffolding. No business feature is implemented here; every tab beyond Home
/// renders a placeholder that names the module which will replace it.
class FoodOnTheGoApp extends StatelessWidget {
  const FoodOnTheGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FoodOnTheGo',
      debugShowCheckedModeBanner: false,
      theme: FotgTheme.light(),
      darkTheme: FotgTheme.dark(),
      // Follows the OS setting rather than forcing one. A phone in a car cradle at
      // night is in dark mode for a reason.
      themeMode: ThemeMode.system,
      home: const FotgAppShell(),
    );
  }
}
