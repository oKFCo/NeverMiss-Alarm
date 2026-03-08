import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const base = Color(0xFF0F172A);
  const accent = Color(0xFF0EA5E9);
  const border = Color(0xFFDBE4F0);

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.light,
    primary: accent,
    secondary: const Color(0xFF14B8A6),
    surface: const Color(0xFFFFFFFF),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFEFF3F8),
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: base,
      elevation: 0,
      centerTitle: false,
    ),
    dividerTheme: const DividerThemeData(
      color: border,
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF0F172A),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicator: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: scheme.onPrimaryContainer,
      unselectedLabelColor: const Color(0xFF475569),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: border),
      backgroundColor: const Color(0xFFF8FAFC),
      selectedColor: scheme.primary.withValues(alpha: 0.14),
      labelStyle: const TextStyle(color: base, fontWeight: FontWeight.w500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary;
        }
        return Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary.withValues(alpha: 0.45);
        }
        return const Color(0xFFCBD5E1);
      }),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(const Color(0xFF64748B)),
      trackColor: WidgetStateProperty.all(const Color(0x1A94A3B8)),
      trackBorderColor: WidgetStateProperty.all(Colors.transparent),
      radius: const Radius.circular(10),
      thickness: WidgetStateProperty.all(10),
      minThumbLength: 48,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFFFFFFFF),
      elevation: 1,
      shadowColor: const Color(0x1A0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: border),
      ),
    ),
  );
}

ThemeData buildDarkAppTheme() {
  const accent = Color(0xFF38BDF8);
  const base = Color(0xFFE2E8F0);
  const border = Color(0xFF1E293B);

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    primary: accent,
    secondary: const Color(0xFF2DD4BF),
    surface: const Color(0xFF0F172A),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF030712),
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: base,
      elevation: 0,
      centerTitle: false,
    ),
    dividerTheme: const DividerThemeData(
      color: border,
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF111827),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0B1220),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicator: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: scheme.onPrimaryContainer,
      unselectedLabelColor: const Color(0xFF9CA3AF),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: border),
      backgroundColor: const Color(0xFF0B1220),
      selectedColor: scheme.primary.withValues(alpha: 0.22),
      labelStyle: const TextStyle(color: base, fontWeight: FontWeight.w500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary;
        }
        return const Color(0xFFCBD5E1);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary.withValues(alpha: 0.45);
        }
        return const Color(0xFF334155);
      }),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(const Color(0xFF64748B)),
      trackColor: WidgetStateProperty.all(const Color(0x1A94A3B8)),
      trackBorderColor: WidgetStateProperty.all(Colors.transparent),
      radius: const Radius.circular(10),
      thickness: WidgetStateProperty.all(10),
      minThumbLength: 48,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF111827),
      elevation: 1,
      shadowColor: const Color(0x59000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
    ),
  );
}
