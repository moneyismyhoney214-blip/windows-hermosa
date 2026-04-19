import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized [ThemeData] factories for the Hermosa POS app.
///
/// We keep a single brand color (Hermosa orange) and derive the rest of the
/// palette from it so both modes stay cohesive. The dark theme uses a
/// modern near-black surface stack (not pure black) to avoid harsh OLED
/// contrast and to keep the orange accents looking warm.
/// Theme-aware color helpers accessible from any [BuildContext].
///
/// Use these instead of hardcoded Color literals so widgets adapt between
/// light and dark modes automatically.
///
/// Example:
///   Container(color: context.appBg)  // swaps with theme
extension AppColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Main scaffold background — medium dark gray so product cards stand out.
  Color get appBg => isDark ? const Color(0xFF242933) : const Color(0xFFF8FAFC);

  /// Panel/surface — slightly darker than the main bg in dark mode.
  Color get appSurface => isDark ? const Color(0xFF1B1F27) : Colors.white;

  /// Alternative surface (inputs, chips, hover states).
  Color get appSurfaceAlt => isDark ? const Color(0xFF2C313B) : const Color(0xFFF1F5F9);

  /// Higher-elevation surface (modals, elevated cards).
  Color get appSurfaceHigh => isDark ? const Color(0xFF353B46) : const Color(0xFFE2E8F0);

  /// Subtle borders between sections.
  Color get appBorder => isDark ? const Color(0xFF353B46) : const Color(0xFFE2E8F0);
  Color get appDivider => isDark ? const Color(0xFF2C313B) : const Color(0xFFF1F5F9);

  Color get appText => isDark ? const Color(0xFFE6E9EF) : const Color(0xFF0F172A);
  Color get appTextMuted => isDark ? const Color(0xFF9AA3B2) : const Color(0xFF64748B);
  Color get appTextSubtle => isDark ? const Color(0xFF6B7280) : const Color(0xFF94A3B8);
  Color get appPrimary => isDark ? const Color(0xFFFF9A3C) : const Color(0xFFF58220);
  Color get appDanger => isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  Color get appSuccess => isDark ? const Color(0xFF34D399) : const Color(0xFF059669);

  /// Header / top nav — darkest tone so it reads as a frame.
  Color get appHeaderBg => isDark ? const Color(0xFF161A20) : Colors.white;
  Color get appSidebarBg => isDark ? const Color(0xFF161A20) : Colors.white;

  /// Card surface, used for product cards / list cards — darker than the
  /// scaffold bg so cards feel "below" the frame (matches reference design).
  Color get appCardBg => isDark ? const Color(0xFF1B1F27) : Colors.white;

  /// Semi-transparent overlay for hover / pressed states.
  Color get appHoverTint => isDark
      ? Colors.white.withValues(alpha: 0.04)
      : Colors.black.withValues(alpha: 0.04);
}

class AppThemes {
  AppThemes._();

  // ─── Brand palette ───────────────────────────────────────────────
  static const Color brandPrimary = Color(0xFFF58220); // Hermosa orange
  static const Color brandPrimaryDark = Color(0xFFE57200);
  static const Color brandSecondary = Color(0xFF2563EB); // accent blue

  // ─── Light palette ───────────────────────────────────────────────
  static const Color _lightBg = Color(0xFFF8FAFC);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceAlt = Color(0xFFF1F5F9);
  static const Color _lightBorder = Color(0xFFE2E8F0);
  static const Color _lightText = Color(0xFF0F172A);
  static const Color _lightTextMuted = Color(0xFF64748B);

  // ─── Dark palette (warm near-black, not OLED black) ──────────────
  static const Color _darkBg = Color(0xFF242933);
  static const Color _darkSurface = Color(0xFF1B1F27);
  static const Color _darkSurfaceAlt = Color(0xFF2C313B);
  static const Color _darkSurfaceHigh = Color(0xFF353B46);
  static const Color _darkBorder = Color(0xFF353B46);
  static const Color _darkText = Color(0xFFE6E9EF);
  static const Color _darkTextMuted = Color(0xFF9AA3B2);
  static const Color _darkDanger = Color(0xFFF87171);

  // ─── Public accessors ────────────────────────────────────────────
  static ThemeData light({bool isRTL = false}) =>
      _buildLight(isRTL: isRTL);

  static ThemeData dark({bool isRTL = false}) =>
      _buildDark(isRTL: isRTL);

  static TextTheme _resolveTextTheme(bool isRTL, Color onSurface) {
    final base = isRTL
        ? GoogleFonts.tajawalTextTheme()
        : GoogleFonts.robotoTextTheme();
    return base.apply(bodyColor: onSurface, displayColor: onSurface);
  }

  static ThemeData _buildLight({required bool isRTL}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: brandPrimary,
      brightness: Brightness.light,
      primary: brandPrimary,
      onPrimary: Colors.white,
      secondary: brandSecondary,
      surface: _lightSurface,
      onSurface: _lightText,
      surfaceContainerHighest: _lightSurfaceAlt,
      outline: _lightBorder,
      error: const Color(0xFFDC2626),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _lightBg,
      colorScheme: colorScheme,
      primaryColor: brandPrimary,
      canvasColor: _lightBg,
      dividerColor: _lightBorder,
      dividerTheme: const DividerThemeData(
        color: _lightBorder,
        thickness: 1,
        space: 1,
      ),
      textTheme: _resolveTextTheme(isRTL, _lightText),
      iconTheme: const IconThemeData(size: 20, color: _lightText),
      appBarTheme: const AppBarTheme(
        backgroundColor: _lightSurface,
        foregroundColor: _lightText,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: _lightText),
        titleTextStyle: TextStyle(
          color: _lightText,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: _lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _lightBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: const TextStyle(
          color: _lightText,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(color: _lightText, fontSize: 14),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSurfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: brandPrimary, width: 1.5),
        ),
        labelStyle: const TextStyle(color: _lightTextMuted),
        hintStyle: const TextStyle(color: _lightTextMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: brandPrimary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brandPrimary,
          side: const BorderSide(color: brandPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return brandPrimary;
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return brandPrimary.withValues(alpha: 0.35);
          }
          return _lightBorder;
        }),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: _lightTextMuted,
        textColor: _lightText,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _lightText,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _lightSurfaceAlt,
        selectedColor: brandPrimary.withValues(alpha: 0.12),
        labelStyle: const TextStyle(color: _lightText),
        side: const BorderSide(color: _lightBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: brandPrimary,
        unselectedLabelColor: _lightTextMuted,
        indicatorColor: brandPrimary,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brandPrimary,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brandPrimary,
        foregroundColor: Colors.white,
      ),
    );
  }

  static ThemeData _buildDark({required bool isRTL}) {
    // For dark mode we pick a slightly brighter orange so it holds up against
    // the dark surfaces without losing warmth.
    const darkAccent = Color(0xFFFF9A3C);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: darkAccent,
      brightness: Brightness.dark,
      primary: darkAccent,
      onPrimary: const Color(0xFF1A120A),
      secondary: const Color(0xFF60A5FA),
      onSecondary: const Color(0xFF0B1220),
      surface: _darkSurface,
      onSurface: _darkText,
      surfaceContainerHighest: _darkSurfaceHigh,
      outline: _darkBorder,
      error: _darkDanger,
      onError: const Color(0xFF1A0A0A),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _darkBg,
      colorScheme: colorScheme,
      primaryColor: darkAccent,
      canvasColor: _darkBg,
      dividerColor: _darkBorder,
      dividerTheme: const DividerThemeData(
        color: _darkBorder,
        thickness: 1,
        space: 1,
      ),
      textTheme: _resolveTextTheme(isRTL, _darkText),
      iconTheme: const IconThemeData(size: 20, color: _darkText),
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkSurface,
        foregroundColor: _darkText,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: _darkText),
        titleTextStyle: TextStyle(
          color: _darkText,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: _darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _darkBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _darkSurfaceAlt,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: const TextStyle(
          color: _darkText,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(color: _darkText, fontSize: 14),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: darkAccent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: _darkTextMuted),
        hintStyle: const TextStyle(color: _darkTextMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkAccent,
          foregroundColor: const Color(0xFF1A120A),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: darkAccent),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkAccent,
          side: const BorderSide(color: darkAccent),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return darkAccent;
          return _darkTextMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return darkAccent.withValues(alpha: 0.35);
          }
          return _darkBorder;
        }),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: _darkTextMuted,
        textColor: _darkText,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _darkSurfaceHigh,
        contentTextStyle: const TextStyle(color: _darkText),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _darkSurfaceAlt,
        selectedColor: darkAccent.withValues(alpha: 0.18),
        labelStyle: const TextStyle(color: _darkText),
        side: const BorderSide(color: _darkBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: darkAccent,
        unselectedLabelColor: _darkTextMuted,
        indicatorColor: darkAccent,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: darkAccent,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: darkAccent,
        foregroundColor: Color(0xFF1A120A),
      ),
    );
  }
}
