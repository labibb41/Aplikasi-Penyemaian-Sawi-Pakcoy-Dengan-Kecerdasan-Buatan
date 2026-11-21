import 'package:flutter/material.dart';

import 'core/constants/app_colors.dart';
import 'screens/splash/splash_screen.dart';

/// ============================================================================
/// SemaiKu — Aplikasi IoT Penyemaian Bibit Tanaman (Flutter Material 3)
/// ============================================================================
/// Arsitektur Modul:
/// ├── lib/core/
/// │   ├── constants/ (AppColors)
/// │   └── utils/     (date_formatter, snackbar_utils)
/// ├── lib/models/    (control_mode, vision_source, plant_profile)
/// └── lib/screens/
///     ├── splash/     (SplashScreen & SplashBackgroundPainter)
///     ├── auth/       (LoginScreen)
///     └── main_shell/ (MainShellScreen, tabs/, dialogs/, widgets/)
/// ============================================================================

void main() {
  runApp(const SemaiKuApp());
}

class SemaiKuApp extends StatelessWidget {
  const SemaiKuApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      surface: AppColors.surface,
    );

    return MaterialApp(
      title: 'SemaiKu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: AppColors.surface,
        fontFamily: 'Roboto',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD5DDD7), width: 1.4),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD5DDD7), width: 1.4),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
