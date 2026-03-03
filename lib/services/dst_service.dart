class DstService {
  static int dayLengthMinutes(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day + 1);
    return end.difference(start).inMinutes;
  }

  static int dayDeltaMinutes(DateTime date) {
    return dayLengthMinutes(date) - 1440;
  }

  static double adjustShiftHours({
    required DateTime date,
    required String shiftCode,
    required double baseHours,
    required bool enabled,
  }) {
    if (!enabled) return baseHours;
    final deltaMinutes = dayDeltaMinutes(date);
    if (deltaMinutes == 0) return baseHours;
    final normalized = shiftCode.toUpperCase();
    final isNight = normalized.contains('N') || normalized.contains('NIGHT');
    if (!isNight) return baseHours;
    final adjusted = baseHours + (deltaMinutes / 60.0);
    return adjusted.clamp(0.0, 24.0);
  }

  static String? deltaLabel(DateTime date) {
    final deltaMinutes = dayDeltaMinutes(date);
    if (deltaMinutes == 0) return null;
    final hours = (deltaMinutes / 60.0).toStringAsFixed(1);
    return deltaMinutes > 0 ? 'DST +$hours h' : 'DST $hours h';
  }
}
