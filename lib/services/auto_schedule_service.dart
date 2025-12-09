import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models.dart';

/// AI-powered automatic schedule generation service
/// Uses constraint solving and optimization algorithms
class AutoScheduleService {
  static final AutoScheduleService instance = AutoScheduleService._internal();
  AutoScheduleService._internal();

  final _uuid = const Uuid();
  final _random = Random();

  /// Generate a roster based on constraints and preferences
  Future<Map<String, dynamic>> generateSchedule({
    required List<String> staffNames,
    required DateTime startDate,
    required int numberOfWeeks,
    required List<SchedulingConstraint> constraints,
    required List<BankHoliday> bankHolidays,
    required List<LeaveRequest> approvedLeave,
    required List<RosterAnomaly> anomalies,
    ShiftTemplate? template,
    Map<String, dynamic>? preferences,
  }) async {
    // Interactive questionnaire responses
    final config = preferences ?? {};

    // Extract configuration
    final minStaffPerShift = config['min_staff_per_shift'] as int? ?? 2;
    final maxConsecutiveDays = config['max_consecutive_days'] as int? ?? 7;
    final minRestHours = config['min_rest_hours'] as int? ?? 11;
    final maxWeeklyHours = config['max_weekly_hours'] as int? ?? 48;
    final shiftTypes = config['shift_types'] as List<String>? ?? ['D', 'N', 'OFF'];
    final fairnessWeight = config['fairness_weight'] as double? ?? 0.8;
    final coverageWeight = config['coverage_weight'] as double? ?? 1.0;

    // Initialize roster structure
    final roster = <String, Map<DateTime, String>>{};
    for (final staff in staffNames) {
      roster[staff] = {};
    }

    // If template provided, use it as a starting point
    if (template != null) {
      _applyTemplate(roster, staffNames, template, startDate, numberOfWeeks);
    } else {
      // Generate from scratch using constraint solver
      await _generateFromConstraints(
        roster: roster,
        staffNames: staffNames,
        startDate: startDate,
        numberOfWeeks: numberOfWeeks,
        constraints: constraints,
        minStaffPerShift: minStaffPerShift,
        maxConsecutiveDays: maxConsecutiveDays,
        shiftTypes: shiftTypes,
      );
    }

    // Apply leave periods
    _applyLeave(roster, approvedLeave, startDate, numberOfWeeks);

    // Apply anomalies (special rules like Christmas rotations)
    _applyAnomalies(roster, anomalies, startDate, numberOfWeeks);

    // Apply bank holidays
    _applyBankHolidays(roster, bankHolidays, startDate, numberOfWeeks);

    // Optimize for fairness
    await _optimizeForFairness(
      roster: roster,
      staffNames: staffNames,
      startDate: startDate,
      numberOfWeeks: numberOfWeeks,
      fairnessWeight: fairnessWeight,
    );

    // Validate the generated schedule
    final validation = _validateSchedule(
      roster: roster,
      constraints: constraints,
      startDate: startDate,
      numberOfWeeks: numberOfWeeks,
    );

    return {
      'roster': roster,
      'validation': validation,
      'statistics': _calculateStatistics(roster, startDate, numberOfWeeks),
      'fairness_score': _calculateFairnessScore(roster, startDate, numberOfWeeks),
    };
  }

  /// Apply a template to the roster
  void _applyTemplate(
    Map<String, Map<DateTime, String>> roster,
    List<String> staffNames,
    ShiftTemplate template,
    DateTime startDate,
    int numberOfWeeks,
  ) {
    final pattern = template.pattern;
    final cycleWeeks = template.cycleLengthWeeks;

    for (int staffIndex = 0; staffIndex < staffNames.length; staffIndex++) {
      final staffName = staffNames[staffIndex];
      final patternIndex = staffIndex % pattern.length;
      final weekPattern = pattern[patternIndex];

      for (int week = 0; week < numberOfWeeks; week++) {
        final cycleWeek = week % cycleWeeks;
        for (int day = 0; day < 7; day++) {
          final date = startDate.add(Duration(days: week * 7 + day));
          final dayInCycle = cycleWeek * 7 + day;
          if (dayInCycle < weekPattern.length) {
            roster[staffName]![date] = weekPattern[dayInCycle];
          }
        }
      }
    }
  }

  /// Generate schedule from constraints using AI algorithm
  Future<void> _generateFromConstraints({
    required Map<String, Map<DateTime, String>> roster,
    required List<String> staffNames,
    required DateTime startDate,
    required int numberOfWeeks,
    required List<SchedulingConstraint> constraints,
    required int minStaffPerShift,
    required int maxConsecutiveDays,
    required List<String> shiftTypes,
  }) async {
    final totalDays = numberOfWeeks * 7;
    final workingShifts = shiftTypes.where((s) => s != 'OFF').toList();

    // For each day, assign shifts to ensure coverage
    for (int dayOffset = 0; dayOffset < totalDays; dayOffset++) {
      final date = startDate.add(Duration(days: dayOffset));

      // Determine how many staff need to work
      final staffNeeded = minStaffPerShift;

      // Get available staff (not exceeding consecutive days limit)
      final availableStaff = _getAvailableStaff(
        roster: roster,
        staffNames: staffNames,
        date: date,
        maxConsecutiveDays: maxConsecutiveDays,
      );

      // Shuffle for randomness
      availableStaff.shuffle(_random);

      // Assign shifts
      int assigned = 0;
      for (final staff in availableStaff) {
        if (assigned < staffNeeded) {
          // Assign a working shift (rotate between day/night)
          final shiftType = workingShifts[assigned % workingShifts.length];
          roster[staff]![date] = shiftType;
          assigned++;
        } else {
          // Rest of staff get OFF
          roster[staff]![date] = 'OFF';
        }
      }

      // If not enough staff available, assign anyway with warning
      if (assigned < staffNeeded) {
        for (final staff in staffNames) {
          if (!availableStaff.contains(staff) && assigned < staffNeeded) {
            roster[staff]![date] = workingShifts[assigned % workingShifts.length];
            assigned++;
          }
        }
      }
    }
  }

  /// Get staff available for a given date
  List<String> _getAvailableStaff({
    required Map<String, Map<DateTime, String>> roster,
    required List<String> staffNames,
    required DateTime date,
    required int maxConsecutiveDays,
  }) {
    final available = <String>[];

    for (final staff in staffNames) {
      // Check consecutive days worked
      int consecutiveDays = 0;
      DateTime checkDate = date.subtract(const Duration(days: 1));

      while (roster[staff]![checkDate] != null) {
        final shift = roster[staff]![checkDate]!;
        if (shift != 'OFF' && shift != 'L') {
          consecutiveDays++;
          checkDate = checkDate.subtract(const Duration(days: 1));
        } else {
          break;
        }
      }

      if (consecutiveDays < maxConsecutiveDays) {
        available.add(staff);
      }
    }

    return available;
  }

  /// Apply approved leave to the roster
  void _applyLeave(
    Map<String, Map<DateTime, String>> roster,
    List<LeaveRequest> approvedLeave,
    DateTime startDate,
    int numberOfWeeks,
  ) {
    final endDate = startDate.add(Duration(days: numberOfWeeks * 7));

    for (final leave in approvedLeave) {
      if (leave.status != ApprovalStatus.approved) continue;

      // Find the staff member
      final staffName = leave.staffName;
      if (!roster.containsKey(staffName)) continue;

      // Mark leave days
      DateTime current = leave.startDate;
      while (!current.isAfter(leave.endDate)) {
        if (!current.isBefore(startDate) && current.isBefore(endDate)) {
          roster[staffName]![current] = 'L';
        }
        current = current.add(const Duration(days: 1));
      }
    }
  }

  /// Apply roster anomalies (special rules)
  void _applyAnomalies(
    Map<String, Map<DateTime, String>> roster,
    List<RosterAnomaly> anomalies,
    DateTime startDate,
    int numberOfWeeks,
  ) {
    final endDate = startDate.add(Duration(days: numberOfWeeks * 7));

    for (final anomaly in anomalies) {
      if (!anomaly.isActive) continue;

      // Check if anomaly applies to this period
      if (anomaly.startDate.isAfter(endDate) ||
          (anomaly.endDate != null && anomaly.endDate!.isBefore(startDate))) {
        continue;
      }

      // Calculate which year in the cycle we're in
      final yearsSinceStart = startDate.year - anomaly.startDate.year;
      final cycleYear = yearsSinceStart % anomaly.cycleYears;

      // Get staff for this cycle year
      final staffForYear = anomaly.staffRotation[cycleYear.toString()] ?? [];

      // Apply the anomaly
      DateTime current = anomaly.startDate.isAfter(startDate)
          ? anomaly.startDate
          : startDate;
      final anomalyEnd = anomaly.endDate ?? endDate;

      while (!current.isAfter(anomalyEnd) && current.isBefore(endDate)) {
        for (final staff in staffForYear) {
          if (roster.containsKey(staff)) {
            // Override shift for this staff on this date
            roster[staff]![current] = anomaly.rules?['shift_type'] as String? ?? 'D';
          }
        }
        current = current.add(const Duration(days: 1));
      }
    }
  }

  /// Apply bank holiday adjustments
  void _applyBankHolidays(
    Map<String, Map<DateTime, String>> roster,
    List<BankHoliday> bankHolidays,
    DateTime startDate,
    int numberOfWeeks,
  ) {
    final endDate = startDate.add(Duration(days: numberOfWeeks * 7));

    for (final holiday in bankHolidays) {
      if (holiday.date.isBefore(startDate) || holiday.date.isAfter(endDate)) {
        continue;
      }

      // For bank holidays, you might want special rules
      // For now, we'll just mark them in metadata
      // The actual logic depends on business requirements
    }
  }

  /// Optimize roster for fairness
  Future<void> _optimizeForFairness({
    required Map<String, Map<DateTime, String>> roster,
    required List<String> staffNames,
    required DateTime startDate,
    required int numberOfWeeks,
    required double fairnessWeight,
  }) async {
    // Calculate current fairness metrics
    final weekendCounts = <String, int>{};
    final nightCounts = <String, int>{};

    for (final staff in staffNames) {
      weekendCounts[staff] = 0;
      nightCounts[staff] = 0;

      roster[staff]!.forEach((date, shift) {
        if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
          if (shift != 'OFF' && shift != 'L') {
            weekendCounts[staff] = weekendCounts[staff]! + 1;
          }
        }
        if (shift == 'N' || shift == 'N12') {
          nightCounts[staff] = nightCounts[staff]! + 1;
        }
      });
    }

    // Try to balance by swapping shifts
    final maxIterations = 100;
    for (int iteration = 0; iteration < maxIterations; iteration++) {
      final weekendRange = _getRange(weekendCounts.values);
      final nightRange = _getRange(nightCounts.values);

      if (weekendRange <= 2 && nightRange <= 2) {
        break; // Good enough
      }

      // Find staff with most and least weekends
      final mostWeekends = _getMaxKey(weekendCounts);
      final leastWeekends = _getMinKey(weekendCounts);

      // Try to swap a weekend shift
      if (mostWeekends != null && leastWeekends != null) {
        _trySwapWeekend(roster, mostWeekends, leastWeekends, startDate, numberOfWeeks);
      }
    }
  }

  /// Try to swap a weekend shift between two staff members
  void _trySwapWeekend(
    Map<String, Map<DateTime, String>> roster,
    String staff1,
    String staff2,
    DateTime startDate,
    int numberOfWeeks,
  ) {
    final endDate = startDate.add(Duration(days: numberOfWeeks * 7));
    DateTime current = startDate;

    while (current.isBefore(endDate)) {
      if (current.weekday == DateTime.saturday || current.weekday == DateTime.sunday) {
        final shift1 = roster[staff1]![current];
        final shift2 = roster[staff2]![current];

        // If one is working and other is off, swap
        if (shift1 != 'OFF' && shift1 != 'L' && (shift2 == 'OFF' || shift2 == null)) {
          roster[staff1]![current] = 'OFF';
          roster[staff2]![current] = shift1;
          return;
        }
      }
      current = current.add(const Duration(days: 1));
    }
  }

  /// Validate the generated schedule
  Map<String, dynamic> _validateSchedule({
    required Map<String, Map<DateTime, String>> roster,
    required List<SchedulingConstraint> constraints,
    required DateTime startDate,
    required int numberOfWeeks,
  }) {
    final violations = <String>[];
    final warnings = <String>[];

    // Check each constraint
    for (final constraint in constraints) {
      if (!constraint.isActive) continue;

      switch (constraint.type) {
        case ConstraintType.maxConsecutiveDays:
          final maxViolations = _checkMaxConsecutiveDays(roster, constraint.value);
          violations.addAll(maxViolations);
          break;

        case ConstraintType.minStaffPerShift:
          final coverageViolations = _checkMinStaffCoverage(
            roster,
            startDate,
            numberOfWeeks,
            constraint.value,
          );
          violations.addAll(coverageViolations);
          break;

        case ConstraintType.maxHoursPerWeek:
          final hoursViolations = _checkMaxWeeklyHours(
            roster,
            startDate,
            numberOfWeeks,
            constraint.value,
          );
          warnings.addAll(hoursViolations);
          break;

        default:
          break;
      }
    }

    return {
      'is_valid': violations.isEmpty,
      'violations': violations,
      'warnings': warnings,
      'total_issues': violations.length + warnings.length,
    };
  }

  /// Check max consecutive days constraint
  List<String> _checkMaxConsecutiveDays(
    Map<String, Map<DateTime, String>> roster,
    int maxDays,
  ) {
    final violations = <String>[];

    roster.forEach((staff, schedule) {
      final sortedDates = schedule.keys.toList()..sort();
      int consecutive = 0;

      for (final date in sortedDates) {
        final shift = schedule[date]!;
        if (shift != 'OFF' && shift != 'L') {
          consecutive++;
          if (consecutive > maxDays) {
            violations.add('$staff exceeded $maxDays consecutive days');
            break;
          }
        } else {
          consecutive = 0;
        }
      }
    });

    return violations;
  }

  /// Check minimum staff coverage
  List<String> _checkMinStaffCoverage(
    Map<String, Map<DateTime, String>> roster,
    DateTime startDate,
    int numberOfWeeks,
    int minStaff,
  ) {
    final violations = <String>[];
    final endDate = startDate.add(Duration(days: numberOfWeeks * 7));
    DateTime current = startDate;

    while (current.isBefore(endDate)) {
      int workingStaff = 0;
      roster.forEach((staff, schedule) {
        final shift = schedule[current];
        if (shift != null && shift != 'OFF' && shift != 'L') {
          workingStaff++;
        }
      });

      if (workingStaff < minStaff) {
        violations.add('${_formatDate(current)}: Only $workingStaff staff (need $minStaff)');
      }

      current = current.add(const Duration(days: 1));
    }

    return violations;
  }

  /// Check max weekly hours
  List<String> _checkMaxWeeklyHours(
    Map<String, Map<DateTime, String>> roster,
    DateTime startDate,
    int numberOfWeeks,
    int maxHours,
  ) {
    final warnings = <String>[];

    roster.forEach((staff, schedule) {
      for (int week = 0; week < numberOfWeeks; week++) {
        final weekStart = startDate.add(Duration(days: week * 7));
        double weeklyHours = 0;

        for (int day = 0; day < 7; day++) {
          final date = weekStart.add(Duration(days: day));
          final shift = schedule[date];
          weeklyHours += _getShiftHours(shift ?? 'OFF');
        }

        if (weeklyHours > maxHours) {
          warnings.add('$staff: Week ${week + 1} has $weeklyHours hours (max $maxHours)');
        }
      }
    });

    return warnings;
  }

  /// Calculate roster statistics
  Map<String, dynamic> _calculateStatistics(
    Map<String, Map<DateTime, String>> roster,
    DateTime startDate,
    int numberOfWeeks,
  ) {
    final shiftCounts = <String, int>{};
    int totalShifts = 0;

    roster.forEach((staff, schedule) {
      schedule.forEach((date, shift) {
        shiftCounts[shift] = (shiftCounts[shift] ?? 0) + 1;
        if (shift != 'OFF' && shift != 'L') {
          totalShifts++;
        }
      });
    });

    return {
      'total_shifts': totalShifts,
      'shift_distribution': shiftCounts,
      'total_staff': roster.length,
      'period_weeks': numberOfWeeks,
    };
  }

  /// Calculate fairness score
  double _calculateFairnessScore(
    Map<String, Map<DateTime, String>> roster,
    DateTime startDate,
    int numberOfWeeks,
  ) {
    final weekendCounts = <String, int>{};
    final nightCounts = <String, int>{};

    roster.forEach((staff, schedule) {
      weekendCounts[staff] = 0;
      nightCounts[staff] = 0;

      schedule.forEach((date, shift) {
        if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
          if (shift != 'OFF' && shift != 'L') {
            weekendCounts[staff] = weekendCounts[staff]! + 1;
          }
        }
        if (shift == 'N' || shift == 'N12') {
          nightCounts[staff] = nightCounts[staff]! + 1;
        }
      });
    });

    final weekendRange = _getRange(weekendCounts.values);
    final nightRange = _getRange(nightCounts.values);

    final weekendScore = max(0, 100 - weekendRange * 10);
    final nightScore = max(0, 100 - nightRange * 10);

    return (weekendScore + nightScore) / 2;
  }

  /// Helper methods

  int _getRange(Iterable<int> values) {
    if (values.isEmpty) return 0;
    final list = values.toList();
    return list.reduce(max) - list.reduce(min);
  }

  String? _getMaxKey(Map<String, int> map) {
    if (map.isEmpty) return null;
    return map.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  String? _getMinKey(Map<String, int> map) {
    if (map.isEmpty) return null;
    return map.entries.reduce((a, b) => a.value < b.value ? a : b).key;
  }

  double _getShiftHours(String shift) {
    switch (shift) {
      case 'D':
      case 'E':
        return 8;
      case 'N':
      case 'N12':
        return 12;
      case 'L':
      case 'OFF':
        return 0;
      default:
        return 8;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Get configuration questions for interactive setup
  static List<Map<String, dynamic>> getConfigurationQuestions() {
    return [
      {
        'id': 'min_staff_per_shift',
        'question': 'What is the minimum number of staff required per shift?',
        'type': 'number',
        'default': 2,
        'min': 1,
        'max': 10,
      },
      {
        'id': 'max_consecutive_days',
        'question': 'Maximum consecutive working days allowed?',
        'type': 'number',
        'default': 7,
        'min': 3,
        'max': 14,
      },
      {
        'id': 'min_rest_hours',
        'question': 'Minimum rest hours between shifts?',
        'type': 'number',
        'default': 11,
        'min': 8,
        'max': 24,
      },
      {
        'id': 'max_weekly_hours',
        'question': 'Maximum working hours per week?',
        'type': 'number',
        'default': 48,
        'min': 20,
        'max': 60,
      },
      {
        'id': 'shift_types',
        'question': 'What shift types do you need?',
        'type': 'multi_select',
        'options': ['D (Day)', 'N (Night)', 'E (Evening)', 'OFF (Rest)'],
        'default': ['D', 'N', 'OFF'],
      },
      {
        'id': 'prefer_weekends_off',
        'question': 'Should weekends off be preferred?',
        'type': 'boolean',
        'default': true,
      },
      {
        'id': 'fairness_weight',
        'question': 'How important is fairness in shift distribution? (0-1)',
        'type': 'slider',
        'default': 0.8,
        'min': 0.0,
        'max': 1.0,
      },
      {
        'id': 'coverage_weight',
        'question': 'How important is full coverage? (0-1)',
        'type': 'slider',
        'default': 1.0,
        'min': 0.0,
        'max': 1.0,
      },
    ];
  }
}
