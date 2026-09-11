// lib/resources/designs/themes.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class Themes {
  static ColorScheme _scheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final neutral = dark ? const Color(0xFF282828) : const Color(0xFFF0F0F0);
    final ink = dark ? const Color(0xFFF5F5F5) : const Color(0xFF222222);
    final accent = dark ? const Color(0xFFEDA65F) : const Color(0xFF9A500C);
    final container = dark ? const Color(0xFF493018) : const Color(0xFFFFE4C9);
    return ColorScheme.fromSeed(
            seedColor: AppColors.primaryColor, brightness: brightness)
        .copyWith(
      primary: accent,
      onPrimary: dark ? Colors.black : Colors.white,
      secondary: accent,
      onSecondary: dark ? Colors.black : Colors.white,
      tertiary: accent,
      onTertiary: dark ? Colors.black : Colors.white,
      primaryContainer: container,
      secondaryContainer: container,
      tertiaryContainer: container,
      onPrimaryContainer: ink,
      onSecondaryContainer: ink,
      onTertiaryContainer: ink,
      primaryFixed: const Color(0xFFFFE4C9),
      primaryFixedDim: const Color(0xFFF5B97D),
      onPrimaryFixed: const Color(0xFF351A00),
      onPrimaryFixedVariant: const Color(0xFF663500),
      secondaryFixed: const Color(0xFFFFE4C9),
      secondaryFixedDim: const Color(0xFFF5B97D),
      onSecondaryFixed: const Color(0xFF351A00),
      onSecondaryFixedVariant: const Color(0xFF663500),
      tertiaryFixed: const Color(0xFFFFE4C9),
      tertiaryFixedDim: const Color(0xFFF5B97D),
      onTertiaryFixed: const Color(0xFF351A00),
      onTertiaryFixedVariant: const Color(0xFF663500),
      surface: dark ? const Color(0xFF0D0D0D) : const Color(0xFFF5F5F5),
      surfaceDim: dark ? const Color(0xFF0D0D0D) : const Color(0xFFDDDDDD),
      surfaceBright: dark ? const Color(0xFF383838) : Colors.white,
      surfaceContainerLowest: dark ? Colors.black : Colors.white,
      surfaceContainerLow:
          dark ? const Color(0xFF1A1A1A) : const Color(0xFFFAFAFA),
      surfaceContainer: neutral,
      surfaceContainerHigh:
          dark ? const Color(0xFF303030) : const Color(0xFFECECEC),
      surfaceContainerHighest:
          dark ? const Color(0xFF383838) : const Color(0xFFE2E2E2),
      onSurface: ink,
      onSurfaceVariant:
          dark ? const Color(0xFFC8C8C8) : const Color(0xFF606060),
      outline: const Color(0xFF858585),
      outlineVariant: dark ? const Color(0xFF454545) : const Color(0xFFD0D0D0),
      inverseSurface: dark ? const Color(0xFFEAEAEA) : const Color(0xFF303030),
      onInverseSurface: dark ? Colors.black : Colors.white,
      inversePrimary: dark ? const Color(0xFF9A500C) : const Color(0xFFEDA65F),
      surfaceTint: Colors.transparent,
    );
  }

  // Light Theme
  static final ThemeData lightTheme =
      ThemeData(colorScheme: _scheme(Brightness.light), useMaterial3: true)
          .copyWith(
    scaffoldBackgroundColor: AppColors.scaffoldBackgroundColor,
    // Kill surface tint so grays don't get a blue cast
    colorScheme: _scheme(Brightness.light),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.scaffoldBackgroundColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.scaffoldBackgroundColor,
      elevation: 0,
      selectedItemColor: AppColors.primaryColor,
      unselectedItemColor: Colors.grey,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.cardColorLight,
    ),
  );

  // Dark Theme
  static final ThemeData darkTheme =
      ThemeData(colorScheme: _scheme(Brightness.dark), useMaterial3: true)
          .copyWith(
    scaffoldBackgroundColor: AppColors.darkScaffoldBackgroundColor,
    colorScheme: _scheme(Brightness.dark),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkScaffoldBackgroundColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkScaffoldBackgroundColor,
      elevation: 0,
      selectedItemColor: AppColors.primaryColor,
      unselectedItemColor: Colors.grey,
    ),
  );
}
