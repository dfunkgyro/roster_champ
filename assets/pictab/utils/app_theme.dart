import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF003366);
  static const Color secondaryColor = Color(0xFF004488);
  static const Color accentColor = Color(0xFF0066CC);
  static const Color errorColor = Color(0xFFDC3545);
  static const Color successColor = Color(0xFF28A745);
  static const Color warningColor = Color(0xFFFFC107);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      primary: primaryColor,
      secondary: secondaryColor,
      error: errorColor,
      surface: Colors.white,
      background: const Color(0xFFF5F5F5),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardTheme(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: const BorderSide(color: primaryColor),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.dark(
      primary: accentColor,
      secondary: secondaryColor,
      error: errorColor,
      surface: const Color(0xFF1E1E1E),
      background: const Color(0xFF121212),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardTheme(
      elevation: 2,
      color: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accentColor,
      foregroundColor: Colors.white,
    ),
  );
}

// Shift colors for roster display
class ShiftColors {
  static const Map<String, Color> colors = {
    'R': Color(0xFFFFFFFF),      // Rest - White
    'N12': Color(0xFFE3F2FD),    // Night 12hr - Light Blue
    'N': Color(0xFFFFFF00),       // Night - Yellow
    'D': Color(0xFFFFEB3B),       // Day - Yellow
    'E': Color(0xFFFFF9C4),       // Evening - Light Yellow
    'C': Color(0xFFE8E8E8),       // Cover - Light Gray
    'L': Color(0xFFFFFFFF),       // Late - White
    'A/L': Color(0xFFFFEB3B),     // Annual Leave - Yellow
    'AD': Color(0xFFE0E0E0),      // Admin Day - Gray
    'Tr': Color(0xFF4CAF50),      // Training - Green
    'Sick': Color(0xFFF44336),    // Sick - Red
  };

  static Color getColor(String shiftCode) {
    return colors[shiftCode] ?? Colors.white;
  }

  static Color getTextColor(String shiftCode) {
    final bgColor = getColor(shiftCode);
    // Calculate luminance to determine text color
    final luminance = bgColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}
