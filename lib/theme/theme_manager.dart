import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart' as models;

class ThemeManager {
  static final ThemeManager _instance = ThemeManager._internal();
  static ThemeManager get instance => _instance;

  ThemeManager._internal();

  Future<void> initialize() async {
    // Theme initialization if needed
  }

  ThemeMode getThemeMode(models.AppThemeMode mode) {
    switch (mode) {
      case models.AppThemeMode.light:
        return ThemeMode.light;
      case models.AppThemeMode.dark:
        return ThemeMode.dark;
      case models.AppThemeMode.system:
      default:
        return ThemeMode.system;
    }
  }

  ThemeData getLightTheme(
    models.ColorSchemeType colorScheme,
    models.AppLayoutStyle layoutStyle,
    bool performanceMode,
  ) {
    final colorSchemeData = _getColorScheme(colorScheme, Brightness.light);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorSchemeData,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.grey[50],
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        displaySmall: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          color: Colors.black87,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          color: Colors.black87,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          color: Colors.black54,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
        color: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: colorSchemeData.primary,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorSchemeData.primary, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
        backgroundColor: Colors.white,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        tileColor: Colors.white,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        backgroundColor: Colors.grey[200],
        labelStyle: const TextStyle(color: Colors.black87),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey[300],
        thickness: 1,
        space: 1,
      ),
    );
    final styled = _applyLayoutStyle(base, layoutStyle, Brightness.light);
    return _applyPerformanceMode(styled, performanceMode);
  }

  ThemeData getDarkTheme(
    models.ColorSchemeType colorScheme,
    models.AppLayoutStyle layoutStyle,
    bool performanceMode,
  ) {
    final colorSchemeData = _getColorScheme(colorScheme, Brightness.dark);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorSchemeData,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF121212),
      textTheme:
          GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        displaySmall: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          color: Colors.white,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          color: Colors.white70,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          color: Colors.white60,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
        color: const Color(0xFF1E1E1E),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 2,
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: colorSchemeData.primary,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[600]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[600]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorSchemeData.primary, width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFF2D2D2D),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white54),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 12,
        backgroundColor: const Color(0xFF2D2D2D),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        tileColor: const Color(0xFF1E1E1E),
        textColor: Colors.white,
        iconColor: Colors.white70,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        backgroundColor: const Color(0xFF2D2D2D),
        labelStyle: const TextStyle(color: Colors.white),
        brightness: Brightness.dark,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF404040),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF2D2D2D),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    final styled = _applyLayoutStyle(base, layoutStyle, Brightness.dark);
    return _applyPerformanceMode(styled, performanceMode);
  }

  ThemeData _applyLayoutStyle(
    ThemeData base,
    models.AppLayoutStyle style,
    Brightness brightness,
  ) {
    switch (style) {
      case models.AppLayoutStyle.professional:
        return _styleProfessional(base, brightness);
      case models.AppLayoutStyle.sophisticated:
        return _styleSophisticated(base, brightness);
      case models.AppLayoutStyle.intuitive:
        return _styleIntuitive(base, brightness);
      case models.AppLayoutStyle.ambience:
        return _styleAmbience(base, brightness);
      case models.AppLayoutStyle.standard:
      default:
        return base;
    }
  }

  ThemeData _applyPerformanceMode(ThemeData base, bool enabled) {
    if (!enabled) return base;
    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoTransitionsBuilder(),
          TargetPlatform.iOS: _NoTransitionsBuilder(),
          TargetPlatform.windows: _NoTransitionsBuilder(),
          TargetPlatform.linux: _NoTransitionsBuilder(),
          TargetPlatform.macOS: _NoTransitionsBuilder(),
        },
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  ThemeData _styleProfessional(ThemeData base, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final textTheme = GoogleFonts.sourceSans3TextTheme(base.textTheme);
    final scheme = _seedScheme(
      isDark ? const Color(0xFF4C9AFF) : const Color(0xFF1B4F99),
      brightness,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF101418) : const Color(0xFFF5F7FA),
      textTheme: textTheme.copyWith(
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium:
            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      cardTheme: base.cardTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: isDark ? 6 : 2,
        color: isDark ? const Color(0xFF1B232C) : Colors.white,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        centerTitle: false,
        titleTextStyle: GoogleFonts.sourceSans3(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.black87,
        ),
        backgroundColor: isDark ? const Color(0xFF121821) : Colors.white,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  ThemeData _styleSophisticated(ThemeData base, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = _seedScheme(
      isDark ? const Color(0xFF1DB7C6) : const Color(0xFF0E7F8A),
      brightness,
    );
    final bodyTheme =
        GoogleFonts.spaceGroteskTextTheme(base.textTheme).copyWith(
      bodyLarge: GoogleFonts.spaceGrotesk(fontSize: 16),
      bodyMedium: GoogleFonts.spaceGrotesk(fontSize: 14),
    );
    final heading = GoogleFonts.orbitronTextTheme(base.textTheme);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0B1218) : const Color(0xFFF2F6F9),
      textTheme: bodyTheme.copyWith(
        displayLarge: heading.displayLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFEFF7FF) : const Color(0xFF0A2239),
        ),
        displayMedium: heading.displayMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFEFF7FF) : const Color(0xFF0A2239),
        ),
        titleLarge: heading.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFEFF7FF) : const Color(0xFF0A2239),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: isDark ? 10 : 5,
        color: isDark ? const Color(0xFF121A22) : Colors.white,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        centerTitle: true,
        backgroundColor:
            isDark ? const Color(0xFF0E151B) : const Color(0xFFF5F8FB),
        foregroundColor:
            isDark ? const Color(0xFFEFF7FF) : const Color(0xFF0A2239),
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: isDark ? const Color(0xFF1B2A35) : const Color(0xFFCCDAE5),
      ),
    );
  }

  ThemeData _styleIntuitive(ThemeData base, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final textTheme = GoogleFonts.manropeTextTheme(base.textTheme);
    final scheme = _seedScheme(
      isDark ? const Color(0xFF2CBFAE) : const Color(0xFF0C8C7A),
      brightness,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF101419) : const Color(0xFFF2F6F9),
      textTheme: textTheme.copyWith(
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: base.cardTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: isDark ? 4 : 2,
      ),
      listTileTheme: base.listTileTheme.copyWith(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      ),
    );
  }

  ThemeData _styleAmbience(ThemeData base, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final textTheme = GoogleFonts.spaceGroteskTextTheme(base.textTheme);
    final scheme = _seedScheme(
      isDark ? const Color(0xFF1EA7C6) : const Color(0xFF0B7F9E),
      brightness,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0B141A) : const Color(0xFFEAF4F8),
      textTheme: textTheme.copyWith(
        displayLarge: textTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 8 : 4,
        color: isDark ? const Color(0xFF111E26) : const Color(0xFFF7FCFF),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor:
            isDark ? const Color(0xFF0F1B22) : const Color(0xFFF0F8FB),
        foregroundColor:
            isDark ? const Color(0xFFE6FAFF) : const Color(0xFF0B2A35),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor:
            isDark ? const Color(0xFF172733) : const Color(0xFFE1F1F7),
      ),
    );
  }

  ColorScheme _seedScheme(Color seed, Brightness brightness) {
    return ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  }

  ColorScheme _getColorScheme(
      models.ColorSchemeType type, Brightness brightness) {
    switch (type) {
      case models.ColorSchemeType.green:
        return ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: brightness,
        );
      case models.ColorSchemeType.purple:
        return ColorScheme.fromSeed(
          seedColor: Colors.purple,
          brightness: brightness,
        );
      case models.ColorSchemeType.orange:
        return ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: brightness,
        );
      case models.ColorSchemeType.pink:
        return ColorScheme.fromSeed(
          seedColor: Colors.pink,
          brightness: brightness,
        );
      case models.ColorSchemeType.teal:
        return ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        );
      case models.ColorSchemeType.indigo:
        return ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: brightness,
        );
      case models.ColorSchemeType.amber:
        return ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: brightness,
        );
      case models.ColorSchemeType.blue:
      default:
        return ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        );
    }
  }
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
