import 'package:flutter/material.dart';
import '../models/roster.dart';

class ShiftCell extends StatelessWidget {
  final String shiftCode;
  final bool isWeekend;
  final Map<String, ShiftCode> shiftCodes;
  final VoidCallback onTap;
  final double width;
  final double height;

  const ShiftCell({
    super.key,
    required this.shiftCode,
    required this.isWeekend,
    required this.shiftCodes,
    required this.onTap,
    this.width = 40,
    this.height = 35,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getShiftColor();
    final textColor = _getTextColor(color);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isWeekend ? _blendWithWeekend(color) : color,
          border: Border.all(
            color: Colors.grey[300]!,
            width: 0.5,
          ),
        ),
        child: Center(
          child: Text(
            shiftCode,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Color _getShiftColor() {
    final shiftDef = shiftCodes[shiftCode];
    if (shiftDef != null) {
      return _parseColor(shiftDef.color);
    }

    // Default colors for common shift codes
    switch (shiftCode.toUpperCase()) {
      case 'R':
        return Colors.white;
      case 'N12':
        return const Color(0xFFE3F2FD);
      case 'N':
        return const Color(0xFFFFFF00);
      case 'D':
        return const Color(0xFFFFEB3B);
      case 'E':
        return const Color(0xFFFFF9C4);
      case 'C':
        return const Color(0xFFE8E8E8);
      case 'L':
        return Colors.white;
      case 'A/L':
        return const Color(0xFFFFEB3B);
      case 'AD':
        return const Color(0xFFE0E0E0);
      case 'TR':
        return const Color(0xFF4CAF50);
      case 'SICK':
        return const Color(0xFFF44336);
      default:
        return Colors.white;
    }
  }

  Color _getTextColor(Color backgroundColor) {
    // Calculate luminance to determine text color
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  Color _blendWithWeekend(Color color) {
    // Blend with a light blue tint for weekends
    const weekendTint = Color(0xFFE3F2FD);
    return Color.lerp(color, weekendTint, 0.3)!;
  }

  Color _parseColor(String colorString) {
    try {
      final hex = colorString.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }
}
