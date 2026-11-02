import 'package:flutter/material.dart';

class AppThemeColors {
  final bool isDark;
  final Color background;
  final Color surface;
  final Color primaryText;
  final Color secondaryText;
  final Color border;
  final Color cardBg;
  final Color headerBg;
  final Color sidebarBg;
  final Color tableHeaderBg;
  final Color tableRowEvenBg;
  final Color tableRowOddBg;
  final Color inputBg;

  const AppThemeColors({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.primaryText,
    required this.secondaryText,
    required this.border,
    required this.cardBg,
    required this.headerBg,
    required this.sidebarBg,
    required this.tableHeaderBg,
    required this.tableRowEvenBg,
    required this.tableRowOddBg,
    required this.inputBg,
  });

  static const AppThemeColors light = AppThemeColors(
    isDark: false,
    background: Color(0xFFF8FAFC),
    surface: Colors.white,
    primaryText: Colors.black, // Solid pure black
    secondaryText: Color(0xFF0F172A), // High-contrast Navy/Slate 900
    border: Color(0xFF94A3B8), // Crisp Slate 400 border
    cardBg: Colors.white,
    headerBg: Color(0xFFF8FAFC),
    sidebarBg: Color(0xFFF1F5F9),
    tableHeaderBg: Color(0xFFF1F5F9),
    tableRowEvenBg: Colors.white,
    tableRowOddBg: Color(0xFFF8FAFC),
    inputBg: Color(0xFFF8FAFC),
  );

  static const AppThemeColors dark = AppThemeColors(
    isDark: true,
    background: Color(0xFF0F172A),
    surface: Color(0xFF1E293B),
    primaryText: Color(0xFFFFFFFF), // Pure crisp white
    secondaryText: Color(0xFFCBD5E1), // High-contrast Slate 300
    border: Color(0xFF475569), // Crisp Slate 600
    cardBg: Color(0xFF1E293B),
    headerBg: Color(0xFF0F172A),
    sidebarBg: Color(0xFF0F172A),
    tableHeaderBg: Color(0xFF1E293B),
    tableRowEvenBg: Color(0xFF0F172A),
    tableRowOddBg: Color(0xFF182232),
    inputBg: Color(0xFF0F172A),
  );
}

class AppColors {
  // Brand Colors
  static const Color primary = Color(0xFF0F172A); // Navy Blue (Pro)
  static const Color secondary = Color(0xFF3B82F6); // Blue
  static const Color accent = Color(0xFFF59E0B); // Amber

  // Neutral Colors (Light mode legacy fallbacks)
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE2E8F0);

  // Status Colors
  static const Color success = Color(0xFF10B981);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // Sidebar/Toolbar Colors
  static const Color sidebarBg = Color(0xFFF1F5F9);
  static const Color toolbarBg = Colors.white;

  // Dynamic Theme helper
  static AppThemeColors of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppThemeColors.dark : AppThemeColors.light;
  }

  static AppThemeColors mode(bool isDark) {
    return isDark ? AppThemeColors.dark : AppThemeColors.light;
  }
}

extension ThemeContextExt on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  AppThemeColors get colors => AppColors.of(this);
}

class AppStyles {
  static BoxDecoration cardDecorationOf(BuildContext context) {
    final c = AppColors.of(context);
    return BoxDecoration(
      color: c.cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: c.isDark ? 0.3 : 0.03),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static BoxDecoration innerInputDecorationOf(BuildContext context) {
    final c = AppColors.of(context);
    return BoxDecoration(
      color: c.inputBg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.border),
    );
  }

  static TextStyle h1Of(BuildContext context) => TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
    color: AppColors.of(context).primaryText,
  );

  static TextStyle h2Of(BuildContext context) => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: AppColors.of(context).primaryText,
  );

  static TextStyle bodyOf(BuildContext context, {double fontSize = 13.0, FontWeight fontWeight = FontWeight.w600}) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: 0.2,
    color: AppColors.of(context).primaryText,
  );

  static TextStyle subtextOf(BuildContext context, {double fontSize = 11.0, FontWeight fontWeight = FontWeight.w600}) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: 0.3,
    color: AppColors.of(context).secondaryText,
  );

  static TextStyle labelOf(BuildContext context) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w900,
    color: AppColors.of(context).secondaryText,
    letterSpacing: 0.8,
  );

  static BoxDecoration cardDecoration = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: AppColors.border),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.03),
        blurRadius: 20,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration innerInputDecoration = BoxDecoration(
    color: AppColors.background,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: AppColors.border),
  );

  static TextStyle h1 = const TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
    color: AppColors.primary,
  );

  static TextStyle h2 = const TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: AppColors.primary,
  );

  static TextStyle label = const TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w900,
    color: Colors.black,
    letterSpacing: 1,
  );
}

class AppGridTheme {
  static Color cellTextColor(bool isDark) =>
      isDark ? const Color(0xFFFFFFFF) : Colors.black;

  static Color cellSecondaryTextColor(bool isDark) =>
      isDark ? const Color(0xFFCBD5E1) : const Color(0xFF0F172A);

  static TextStyle cellStyle(bool isDark, {double fontSize = 12.0, FontWeight fontWeight = FontWeight.w600}) => TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: 0.2,
        color: cellTextColor(isDark),
      );

  static Color rowEvenBg(bool isDark) =>
      isDark ? const Color(0xFF0F172A) : Colors.white;

  static Color rowOddBg(bool isDark) =>
      isDark ? const Color(0xFF182232) : const Color(0xFFF8FAFC);

  static Color activeCellBorder(bool isDark) =>
      const Color(0xFF2563EB);

  static Color activeCellFill(bool isDark) =>
      isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.3) : const Color(0xFFEFF6FF);
}
