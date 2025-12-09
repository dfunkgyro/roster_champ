import 'package:add_2_calendar/add_2_calendar.dart' as add2calendar;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/export_service.dart';

/// Service for calendar integration (Google, iOS, Outlook)
class CalendarIntegrationService {
  static final CalendarIntegrationService instance =
      CalendarIntegrationService._internal();
  CalendarIntegrationService._internal();

  /// Add a single shift to device calendar
  Future<bool> addShiftToCalendar({
    required DateTime shiftDate,
    required String shiftType,
    required String staffName,
    Duration? shiftDuration,
  }) async {
    final duration = shiftDuration ?? _getDefaultShiftDuration(shiftType);
    final startTime = _getShiftStartTime(shiftType, shiftDate);
    final endTime = startTime.add(duration);

    final event = add2calendar.Event(
      title: '$shiftType Shift - $staffName',
      description: 'Scheduled $shiftType shift for $staffName',
      location: 'Workplace',
      startDate: startTime,
      endDate: endTime,
      allDay: false,
    );

    try {
      await add2calendar.Add2Calendar.addEvent2Cal(event);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Export entire schedule to iCalendar format and share
  Future<bool> exportScheduleToCalendar({
    required String staffName,
    required Map<DateTime, String> schedule,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // Generate iCal content
      final icalContent = ExportService.instance.exportToICalendar(
        staffName: staffName,
        schedule: schedule,
        startDate: startDate,
        endDate: endDate,
      );

      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${staffName}_schedule.ics');
      await file.writeAsString(icalContent);

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '$staffName Schedule',
        text: 'Import this schedule to your calendar app',
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Add multiple shifts to calendar
  Future<Map<String, dynamic>> addWeekToCalendar({
    required String staffName,
    required Map<DateTime, String> weekSchedule,
  }) async {
    int successCount = 0;
    int failureCount = 0;
    final errors = <String>[];

    for (final entry in weekSchedule.entries) {
      final date = entry.key;
      final shift = entry.value;

      if (shift == 'OFF' || shift == 'L') continue;

      final success = await addShiftToCalendar(
        shiftDate: date,
        shiftType: shift,
        staffName: staffName,
      );

      if (success) {
        successCount++;
      } else {
        failureCount++;
        errors.add('Failed to add ${shift} shift on ${_formatDate(date)}');
      }
    }

    return {
      'success': failureCount == 0,
      'added': successCount,
      'failed': failureCount,
      'errors': errors,
    };
  }

  /// Sync schedule with calendar (add all upcoming shifts)
  Future<Map<String, dynamic>> syncWithCalendar({
    required String staffName,
    required Map<DateTime, String> schedule,
    int daysAhead = 30,
  }) async {
    final now = DateTime.now();
    final futureDate = now.add(Duration(days: daysAhead));

    final upcomingShifts = schedule.entries.where((entry) =>
        !entry.key.isBefore(now) &&
        !entry.key.isAfter(futureDate) &&
        entry.value != 'OFF' &&
        entry.value != 'L');

    int added = 0;
    final errors = <String>[];

    for (final entry in upcomingShifts) {
      final success = await addShiftToCalendar(
        shiftDate: entry.key,
        shiftType: entry.value,
        staffName: staffName,
      );

      if (success) {
        added++;
      } else {
        errors.add('Failed: ${entry.value} on ${_formatDate(entry.key)}');
      }
    }

    return {
      'success': errors.isEmpty,
      'shifts_added': added,
      'total_upcoming': upcomingShifts.length,
      'errors': errors,
    };
  }

  /// Create a calendar event for a specific shift
  add2calendar.Event createShiftEvent({
    required DateTime shiftDate,
    required String shiftType,
    required String staffName,
    String? notes,
  }) {
    final startTime = _getShiftStartTime(shiftType, shiftDate);
    final duration = _getDefaultShiftDuration(shiftType);
    final endTime = startTime.add(duration);

    return add2calendar.Event(
      title: '$shiftType Shift',
      description: notes ?? 'Scheduled $shiftType shift for $staffName',
      location: 'Workplace',
      startDate: startTime,
      endDate: endTime,
      allDay: false,
    );
  }

  /// Get shift start time based on shift type
  DateTime _getShiftStartTime(String shiftType, DateTime date) {
    switch (shiftType) {
      case 'D': // Day shift: 6:00 AM
        return DateTime(date.year, date.month, date.day, 6, 0);
      case 'E': // Evening shift: 2:00 PM
        return DateTime(date.year, date.month, date.day, 14, 0);
      case 'N': // Night shift: 10:00 PM
      case 'N12':
        return DateTime(date.year, date.month, date.day, 22, 0);
      default: // Default to 8:00 AM
        return DateTime(date.year, date.month, date.day, 8, 0);
    }
  }

  /// Get default shift duration
  Duration _getDefaultShiftDuration(String shiftType) {
    switch (shiftType) {
      case 'N':
      case 'N12':
        return const Duration(hours: 12);
      case 'D':
      case 'E':
        return const Duration(hours: 8);
      default:
        return const Duration(hours: 8);
    }
  }

  /// Generate Google Calendar URL
  String generateGoogleCalendarUrl({
    required DateTime shiftDate,
    required String shiftType,
    required String staffName,
  }) {
    final startTime = _getShiftStartTime(shiftType, shiftDate);
    final duration = _getDefaultShiftDuration(shiftType);
    final endTime = startTime.add(duration);

    final title = Uri.encodeComponent('$shiftType Shift - $staffName');
    final details = Uri.encodeComponent('Scheduled $shiftType shift');
    final startFormatted = _formatDateTimeForGoogle(startTime);
    final endFormatted = _formatDateTimeForGoogle(endTime);

    return 'https://www.google.com/calendar/render?action=TEMPLATE&text=$title&dates=$startFormatted/$endFormatted&details=$details';
  }

  /// Format datetime for Google Calendar URL
  String _formatDateTimeForGoogle(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}T${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}00Z';
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  /// Check if calendar permissions are granted
  Future<bool> hasCalendarPermissions() async {
    // This would use permission_handler in a real implementation
    // For now, return true
    return true;
  }

  /// Request calendar permissions
  Future<bool> requestCalendarPermissions() async {
    // This would use permission_handler in a real implementation
    // For now, return true
    return true;
  }
}
