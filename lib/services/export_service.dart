import 'dart:convert';
import 'package:intl/intl.dart';
import '../models.dart';

/// Service for exporting roster data in various formats
/// Note: This is a foundation. Actual PDF/Excel generation requires
/// additional packages like pdf, excel, etc.
class ExportService {
  static final ExportService instance = ExportService._internal();
  ExportService._internal();

  /// Export roster data to JSON
  String exportToJson(Map<String, dynamic> rosterData) {
    return const JsonEncoder.withIndent('  ').convert(rosterData);
  }

  /// Export roster to CSV format
  String exportToCSV({
    required List<String> staffNames,
    required Map<String, Map<DateTime, String>> rosterData,
    required DateTime startDate,
    required int numberOfWeeks,
  }) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('yyyy-MM-dd');

    // Header row
    buffer.write('Staff Name,');
    for (int week = 0; week < numberOfWeeks; week++) {
      for (int day = 0; day < 7; day++) {
        final date = startDate.add(Duration(days: week * 7 + day));
        buffer.write('${dateFormat.format(date)},');
      }
    }
    buffer.writeln();

    // Data rows
    for (final staffName in staffNames) {
      buffer.write('$staffName,');
      final staffRoster = rosterData[staffName] ?? {};

      for (int week = 0; week < numberOfWeeks; week++) {
        for (int day = 0; day < 7; day++) {
          final date = startDate.add(Duration(days: week * 7 + day));
          final shift = staffRoster[date] ?? 'OFF';
          buffer.write('$shift,');
        }
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Export weekly summary report
  String exportWeeklySummary({
    required DateTime weekStart,
    required List<String> staffNames,
    required Map<String, Map<DateTime, String>> rosterData,
    required Map<String, int> shiftCounts,
  }) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('EEEE, dd MMM yyyy');

    buffer.writeln('WEEKLY ROSTER SUMMARY');
    buffer.writeln('Week Starting: ${dateFormat.format(weekStart)}');
    buffer.writeln('=' * 80);
    buffer.writeln();

    // Shift distribution
    buffer.writeln('SHIFT DISTRIBUTION:');
    shiftCounts.forEach((shift, count) {
      buffer.writeln('  $shift: $count shifts');
    });
    buffer.writeln();

    // Daily breakdown
    buffer.writeln('DAILY BREAKDOWN:');
    for (int day = 0; day < 7; day++) {
      final date = weekStart.add(Duration(days: day));
      buffer.writeln('${dateFormat.format(date)}:');

      for (final staffName in staffNames) {
        final staffRoster = rosterData[staffName] ?? {};
        final shift = staffRoster[date] ?? 'OFF';
        buffer.writeln('  $staffName: $shift');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Export staff statistics report
  String exportStaffStats({
    required List<Map<String, dynamic>> staffStats,
    required DateTime reportDate,
  }) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('dd MMM yyyy');

    buffer.writeln('STAFF STATISTICS REPORT');
    buffer.writeln('Report Date: ${dateFormat.format(reportDate)}');
    buffer.writeln('=' * 80);
    buffer.writeln();

    for (final stat in staffStats) {
      buffer.writeln('Staff: ${stat['name']}');
      buffer.writeln('  Total Shifts: ${stat['total_shifts']}');
      buffer.writeln('  Day Shifts: ${stat['day_shifts']}');
      buffer.writeln('  Night Shifts: ${stat['night_shifts']}');
      buffer.writeln('  Leave Days: ${stat['leave_days']}');
      buffer.writeln('  Leave Balance: ${stat['leave_balance']}');
      buffer.writeln('  Overtime Hours: ${stat['overtime_hours']}');
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Export labor cost report
  String exportLaborCostReport({
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, dynamic> costBreakdown,
    required LaborCostSettings settings,
  }) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('dd MMM yyyy');
    final currencyFormat = NumberFormat.currency(symbol: settings.currency);

    buffer.writeln('LABOR COST REPORT');
    buffer.writeln('Period: ${dateFormat.format(startDate)} - ${dateFormat.format(endDate)}');
    buffer.writeln('=' * 80);
    buffer.writeln();

    buffer.writeln('COST BREAKDOWN BY SHIFT TYPE:');
    if (costBreakdown['by_shift_type'] != null) {
      final byShift = costBreakdown['by_shift_type'] as Map<String, dynamic>;
      byShift.forEach((shift, cost) {
        buffer.writeln('  $shift: ${currencyFormat.format(cost)}');
      });
    }
    buffer.writeln();

    buffer.writeln('ADDITIONAL COSTS:');
    buffer.writeln('  Overtime: ${currencyFormat.format(costBreakdown['overtime_cost'] ?? 0)}');
    buffer.writeln('  Weekend Premium: ${currencyFormat.format(costBreakdown['weekend_premium'] ?? 0)}');
    buffer.writeln('  Holiday Premium: ${currencyFormat.format(costBreakdown['holiday_premium'] ?? 0)}');
    buffer.writeln('  Night Shift Premium: ${currencyFormat.format(costBreakdown['night_premium'] ?? 0)}');
    buffer.writeln();

    buffer.writeln('TOTAL LABOR COST: ${currencyFormat.format(costBreakdown['total_cost'] ?? 0)}');

    return buffer.toString();
  }

  /// Export leave report
  String exportLeaveReport({
    required List<LeaveRequest> leaveRequests,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('dd MMM yyyy');

    buffer.writeln('LEAVE REPORT');
    buffer.writeln('Period: ${dateFormat.format(startDate)} - ${dateFormat.format(endDate)}');
    buffer.writeln('=' * 80);
    buffer.writeln();

    // Group by status
    final pending = leaveRequests.where((r) => r.status == ApprovalStatus.pending).toList();
    final approved = leaveRequests.where((r) => r.status == ApprovalStatus.approved).toList();
    final rejected = leaveRequests.where((r) => r.status == ApprovalStatus.rejected).toList();

    buffer.writeln('SUMMARY:');
    buffer.writeln('  Total Requests: ${leaveRequests.length}');
    buffer.writeln('  Pending: ${pending.length}');
    buffer.writeln('  Approved: ${approved.length}');
    buffer.writeln('  Rejected: ${rejected.length}');
    buffer.writeln();

    if (approved.isNotEmpty) {
      buffer.writeln('APPROVED LEAVE:');
      for (final request in approved) {
        buffer.writeln('  ${request.staffName}:');
        buffer.writeln('    Type: ${_getLeaveTypeName(request.leaveType)}');
        buffer.writeln('    Dates: ${dateFormat.format(request.startDate)} - ${dateFormat.format(request.endDate)}');
        buffer.writeln('    Days: ${request.daysRequested}');
        if (request.reason != null) {
          buffer.writeln('    Reason: ${request.reason}');
        }
        buffer.writeln();
      }
    }

    if (pending.isNotEmpty) {
      buffer.writeln('PENDING LEAVE REQUESTS:');
      for (final request in pending) {
        buffer.writeln('  ${request.staffName}:');
        buffer.writeln('    Type: ${_getLeaveTypeName(request.leaveType)}');
        buffer.writeln('    Dates: ${dateFormat.format(request.startDate)} - ${dateFormat.format(request.endDate)}');
        buffer.writeln('    Days: ${request.daysRequested}');
        if (request.reason != null) {
          buffer.writeln('    Reason: ${request.reason}');
        }
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Export audit log report
  String exportAuditLog({
    required List<AuditLog> logs,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('dd MMM yyyy HH:mm:ss');

    buffer.writeln('AUDIT LOG REPORT');
    buffer.writeln('Period: ${dateFormat.format(startDate)} - ${dateFormat.format(endDate)}');
    buffer.writeln('=' * 80);
    buffer.writeln();

    buffer.writeln('TOTAL ACTIONS: ${logs.length}');
    buffer.writeln();

    // Group by user
    final byUser = <String, List<AuditLog>>{};
    for (final log in logs) {
      byUser.putIfAbsent(log.userName, () => []).add(log);
    }

    buffer.writeln('ACTIONS BY USER:');
    byUser.forEach((user, userLogs) {
      buffer.writeln('  $user: ${userLogs.length} actions');
    });
    buffer.writeln();

    buffer.writeln('DETAILED LOG:');
    for (final log in logs) {
      buffer.writeln('${dateFormat.format(log.timestamp)} - ${log.userName}');
      buffer.writeln('  Action: ${log.action}');
      buffer.writeln('  Description: ${log.description}');
      if (log.ipAddress != null) {
        buffer.writeln('  IP: ${log.ipAddress}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Export iCalendar format for calendar integration
  String exportToICalendar({
    required String staffName,
    required Map<DateTime, String> schedule,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('yyyyMMdd');
    final timeFormat = DateFormat('HHmmss');

    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//Roster Champ//Roster Export//EN');
    buffer.writeln('CALSCALE:GREGORIAN');
    buffer.writeln('METHOD:PUBLISH');
    buffer.writeln('X-WR-CALNAME:$staffName Roster');
    buffer.writeln('X-WR-TIMEZONE:UTC');

    schedule.forEach((date, shift) {
      if (shift != 'OFF' && !date.isBefore(startDate) && !date.isAfter(endDate)) {
        // Create event for this shift
        final eventStart = date;
        final eventEnd = date.add(const Duration(hours: 8)); // Default 8-hour shift

        buffer.writeln('BEGIN:VEVENT');
        buffer.writeln('UID:${date.millisecondsSinceEpoch}@rosterchamp.app');
        buffer.writeln('DTSTAMP:${dateFormat.format(DateTime.now())}T${timeFormat.format(DateTime.now())}Z');
        buffer.writeln('DTSTART:${dateFormat.format(eventStart)}T060000Z');
        buffer.writeln('DTEND:${dateFormat.format(eventEnd)}T140000Z');
        buffer.writeln('SUMMARY:$shift Shift');
        buffer.writeln('DESCRIPTION:Scheduled shift: $shift');
        buffer.writeln('STATUS:CONFIRMED');
        buffer.writeln('TRANSP:OPAQUE');
        buffer.writeln('END:VEVENT');
      }
    });

    buffer.writeln('END:VCALENDAR');

    return buffer.toString();
  }

  /// Generate comprehensive monthly report
  String exportMonthlyReport({
    required int year,
    required int month,
    required Map<String, dynamic> statistics,
    required List<Map<String, dynamic>> staffStats,
    required Map<String, dynamic> costAnalysis,
  }) {
    final buffer = StringBuffer();
    final monthName = DateFormat('MMMM yyyy').format(DateTime(year, month, 1));

    buffer.writeln('MONTHLY ROSTER REPORT');
    buffer.writeln('Month: $monthName');
    buffer.writeln('=' * 80);
    buffer.writeln();

    // Overall statistics
    buffer.writeln('OVERALL STATISTICS:');
    buffer.writeln('  Total Staff: ${statistics['total_staff']}');
    buffer.writeln('  Active Staff: ${statistics['active_staff']}');
    buffer.writeln('  Total Shifts Scheduled: ${statistics['total_shifts']}');
    buffer.writeln('  Total Leave Days: ${statistics['total_leave_days']}');
    buffer.writeln('  Shift Swaps: ${statistics['shift_swaps'] ?? 0}');
    buffer.writeln();

    // Cost analysis
    if (costAnalysis.isNotEmpty) {
      buffer.writeln('COST ANALYSIS:');
      buffer.writeln('  Total Labor Cost: ${costAnalysis['total_cost']}');
      buffer.writeln('  Regular Hours Cost: ${costAnalysis['regular_cost']}');
      buffer.writeln('  Overtime Cost: ${costAnalysis['overtime_cost']}');
      buffer.writeln('  Average Cost per Shift: ${costAnalysis['avg_cost_per_shift']}');
      buffer.writeln();
    }

    // Staff performance
    buffer.writeln('STAFF PERFORMANCE:');
    for (final stat in staffStats) {
      buffer.writeln('  ${stat['name']}:');
      buffer.writeln('    Shifts Worked: ${stat['shifts_worked']}');
      buffer.writeln('    Hours Worked: ${stat['hours_worked']}');
      buffer.writeln('    Leave Days: ${stat['leave_days']}');
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Helper method to get leave type name
  String _getLeaveTypeName(LeaveType type) {
    switch (type) {
      case LeaveType.annual:
        return 'Annual Leave';
      case LeaveType.sick:
        return 'Sick Leave';
      case LeaveType.unpaid:
        return 'Unpaid Leave';
      case LeaveType.compassionate:
        return 'Compassionate Leave';
      case LeaveType.maternity:
        return 'Maternity Leave';
      case LeaveType.paternity:
        return 'Paternity Leave';
      case LeaveType.study:
        return 'Study Leave';
      case LeaveType.custom:
        return 'Custom Leave';
    }
  }

  /// Export to CSV format for staff list
  String exportStaffListToCSV(List<StaffMember> staff) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('ID,Name,Active,Leave Balance');

    // Data rows
    for (final member in staff) {
      buffer.writeln('${member.id},${member.name},${member.isActive},${member.leaveBalance}');
    }

    return buffer.toString();
  }

  /// Export events to CSV
  String exportEventsToCSV(List<Event> events) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('yyyy-MM-dd');

    // Header
    buffer.writeln('ID,Title,Description,Date,Type,Affected Staff');

    // Data rows
    for (final event in events) {
      final description = event.description?.replaceAll(',', ';') ?? '';
      final affectedStaff = event.affectedStaff.join(';');
      buffer.writeln('${event.id},${event.title},$description,${dateFormat.format(event.date)},${event.eventType.name},$affectedStaff');
    }

    return buffer.toString();
  }
}
