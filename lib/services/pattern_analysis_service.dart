import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models.dart';

/// Service for pattern recognition, conflict detection, and fairness analysis
class PatternAnalysisService {
  static final PatternAnalysisService instance =
      PatternAnalysisService._internal();
  PatternAnalysisService._internal();

  final _uuid = const Uuid();

  /// Detect conflicts in a roster pattern
  List<PatternConflict> detectConflicts({
    required Map<String, Map<DateTime, String>> rosterData,
    required List<SchedulingConstraint> constraints,
    required List<BankHoliday> holidays,
  }) {
    final conflicts = <PatternConflict>[];

    // Check each staff member's schedule
    rosterData.forEach((staffName, schedule) {
      conflicts.addAll(_checkStaffSchedule(
        staffName,
        schedule,
        constraints,
        holidays,
      ));
    });

    // Check overall coverage
    conflicts.addAll(_checkCoverageConflicts(rosterData));

    return conflicts;
  }

  /// Check a single staff member's schedule for conflicts
  List<PatternConflict> _checkStaffSchedule(
    String staffName,
    Map<DateTime, String> schedule,
    List<SchedulingConstraint> constraints,
    List<BankHoliday> holidays,
  ) {
    final conflicts = <PatternConflict>[];

    // Sort dates
    final sortedDates = schedule.keys.toList()..sort();

    // Check consecutive days constraint
    final maxConsecutiveConstraint = constraints.firstWhere(
      (c) => c.type == ConstraintType.maxConsecutiveDays && c.isActive,
      orElse: () => SchedulingConstraint(
        id: '',
        type: ConstraintType.maxConsecutiveDays,
        name: 'Default Max Consecutive Days',
        value: 7,
      ),
    );

    int consecutiveDays = 0;
    DateTime? consecutiveStart;

    for (final date in sortedDates) {
      final shift = schedule[date]!;

      if (shift != 'OFF' && shift != 'L') {
        consecutiveDays++;
        consecutiveStart ??= date;

        if (consecutiveDays > maxConsecutiveConstraint.value) {
          conflicts.add(PatternConflict(
            id: _uuid.v4(),
            type: ConflictType.maxConsecutiveDays,
            description:
                '$staffName has worked $consecutiveDays consecutive days, exceeding the limit of ${maxConsecutiveConstraint.value}',
            date: date,
            affectedStaff: [staffName],
            suggestedResolution:
                'Add a rest day for $staffName on ${_formatDate(date)}',
          ));
        }
      } else {
        consecutiveDays = 0;
        consecutiveStart = null;
      }
    }

    // Check minimum rest hours between shifts
    conflicts.addAll(_checkRestPeriods(staffName, schedule, constraints));

    // Check maximum hours per week
    conflicts.addAll(_checkWeeklyHours(staffName, schedule, constraints));

    return conflicts;
  }

  /// Check rest periods between shifts
  List<PatternConflict> _checkRestPeriods(
    String staffName,
    Map<DateTime, String> schedule,
    List<SchedulingConstraint> constraints,
  ) {
    final conflicts = <PatternConflict>[];

    final minRestConstraint = constraints.firstWhere(
      (c) => c.type == ConstraintType.minRestHours && c.isActive,
      orElse: () => SchedulingConstraint(
        id: '',
        type: ConstraintType.minRestHours,
        name: 'Default Min Rest Hours',
        value: 11,
      ),
    );

    final sortedDates = schedule.keys.toList()..sort();

    for (int i = 0; i < sortedDates.length - 1; i++) {
      final currentDate = sortedDates[i];
      final nextDate = sortedDates[i + 1];
      final currentShift = schedule[currentDate]!;
      final nextShift = schedule[nextDate]!;

      // Check if there's a night shift followed by a day shift
      if (currentShift == 'N' && nextShift == 'D') {
        final hoursBetween = nextDate.difference(currentDate).inHours;
        if (hoursBetween < minRestConstraint.value) {
          conflicts.add(PatternConflict(
            id: _uuid.v4(),
            type: ConflictType.insufficientRest,
            description:
                '$staffName has only $hoursBetween hours between night shift and day shift',
            date: nextDate,
            affectedStaff: [staffName],
            suggestedResolution:
                'Ensure at least ${minRestConstraint.value} hours rest between shifts',
          ));
        }
      }
    }

    return conflicts;
  }

  /// Check weekly hours constraint
  List<PatternConflict> _checkWeeklyHours(
    String staffName,
    Map<DateTime, String> schedule,
    List<SchedulingConstraint> constraints,
  ) {
    final conflicts = <PatternConflict>[];

    final maxHoursConstraint = constraints.firstWhere(
      (c) => c.type == ConstraintType.maxHoursPerWeek && c.isActive,
      orElse: () => SchedulingConstraint(
        id: '',
        type: ConstraintType.maxHoursPerWeek,
        name: 'Default Max Hours Per Week',
        value: 48,
      ),
    );

    // Group shifts by week
    final weeklyHours = <DateTime, double>{};
    schedule.forEach((date, shift) {
      final weekStart = _getWeekStart(date);
      final hours = _getShiftHours(shift);
      weeklyHours[weekStart] = (weeklyHours[weekStart] ?? 0) + hours;
    });

    weeklyHours.forEach((weekStart, hours) {
      if (hours > maxHoursConstraint.value) {
        conflicts.add(PatternConflict(
          id: _uuid.v4(),
          type: ConflictType.maxConsecutiveDays,
          description:
              '$staffName is scheduled for $hours hours in week starting ${_formatDate(weekStart)}, exceeding the ${maxHoursConstraint.value} hour limit',
          date: weekStart,
          affectedStaff: [staffName],
          suggestedResolution: 'Reduce working hours for this week',
        ));
      }
    });

    return conflicts;
  }

  /// Check overall coverage conflicts
  List<PatternConflict> _checkCoverageConflicts(
    Map<String, Map<DateTime, String>> rosterData,
  ) {
    final conflicts = <PatternConflict>[];

    // Get all unique dates
    final allDates = <DateTime>{};
    rosterData.values.forEach((schedule) {
      allDates.addAll(schedule.keys);
    });

    // Check coverage for each date
    for (final date in allDates) {
      final shiftCounts = <String, int>{};
      final workingStaff = <String>[];

      rosterData.forEach((staffName, schedule) {
        final shift = schedule[date];
        if (shift != null && shift != 'OFF' && shift != 'L') {
          shiftCounts[shift] = (shiftCounts[shift] ?? 0) + 1;
          workingStaff.add(staffName);
        }
      });

      // Check if understaffed (less than 2 people)
      if (workingStaff.length < 2) {
        conflicts.add(PatternConflict(
          id: _uuid.v4(),
          type: ConflictType.underStaffed,
          description:
              'Only ${workingStaff.length} staff scheduled for ${_formatDate(date)}',
          date: date,
          affectedStaff: workingStaff,
          suggestedResolution: 'Schedule additional staff for this date',
        ));
      }
    }

    return conflicts;
  }

  /// Analyze pattern fairness
  Map<String, dynamic> analyzeFairness({
    required Map<String, Map<DateTime, String>> rosterData,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final analysis = <String, dynamic>{};

    // Count shift types per staff
    final shiftCounts = <String, Map<String, int>>{};
    final weekendCounts = <String, int>{};
    final nightCounts = <String, int>{};

    rosterData.forEach((staffName, schedule) {
      shiftCounts[staffName] = {};
      weekendCounts[staffName] = 0;
      nightCounts[staffName] = 0;

      schedule.forEach((date, shift) {
        if (!date.isBefore(startDate) && !date.isAfter(endDate)) {
          // Count shift types
          shiftCounts[staffName]![shift] =
              (shiftCounts[staffName]![shift] ?? 0) + 1;

          // Count weekends
          if (date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday) {
            if (shift != 'OFF' && shift != 'L') {
              weekendCounts[staffName] = weekendCounts[staffName]! + 1;
            }
          }

          // Count night shifts
          if (shift == 'N' || shift == 'N12') {
            nightCounts[staffName] = nightCounts[staffName]! + 1;
          }
        }
      });
    });

    // Calculate fairness metrics
    final weekendValues = weekendCounts.values.toList();
    final nightValues = nightCounts.values.toList();

    analysis['weekend_distribution'] = {
      'min': weekendValues.isEmpty ? 0 : weekendValues.reduce(min),
      'max': weekendValues.isEmpty ? 0 : weekendValues.reduce(max),
      'avg': weekendValues.isEmpty
          ? 0
          : weekendValues.reduce((a, b) => a + b) / weekendValues.length,
      'by_staff': weekendCounts,
    };

    analysis['night_shift_distribution'] = {
      'min': nightValues.isEmpty ? 0 : nightValues.reduce(min),
      'max': nightValues.isEmpty ? 0 : nightValues.reduce(max),
      'avg': nightValues.isEmpty
          ? 0
          : nightValues.reduce((a, b) => a + b) / nightValues.length,
      'by_staff': nightCounts,
    };

    // Calculate fairness score (0-100, higher is more fair)
    final weekendRange = (weekendValues.isEmpty
        ? 0
        : weekendValues.reduce(max) - weekendValues.reduce(min));
    final nightRange = (nightValues.isEmpty
        ? 0
        : nightValues.reduce(max) - nightValues.reduce(min));

    final weekendFairness = weekendRange == 0 ? 100 : max(0, 100 - weekendRange * 10);
    final nightFairness = nightRange == 0 ? 100 : max(0, 100 - nightRange * 10);

    analysis['fairness_score'] = ((weekendFairness + nightFairness) / 2).round();
    analysis['weekend_fairness'] = weekendFairness.round();
    analysis['night_fairness'] = nightFairness.round();

    // Identify staff with most/least desirable shifts
    analysis['recommendations'] = <String>[];

    if (weekendRange > 3) {
      final mostWeekends = weekendCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b);
      final leastWeekends = weekendCounts.entries
          .reduce((a, b) => a.value < b.value ? a : b);
      analysis['recommendations'].add(
          'Balance weekend shifts: ${mostWeekends.key} has ${mostWeekends.value} while ${leastWeekends.key} has ${leastWeekends.value}');
    }

    if (nightRange > 3) {
      final mostNights = nightCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b);
      final leastNights = nightCounts.entries
          .reduce((a, b) => a.value < b.value ? a : b);
      analysis['recommendations'].add(
          'Balance night shifts: ${mostNights.key} has ${mostNights.value} while ${leastNights.key} has ${leastNights.value}');
    }

    return analysis;
  }

  /// Recognize patterns in historical data using ML-like approach
  PatternRecognitionResult recognizePattern({
    required Map<String, Map<DateTime, String>> rosterData,
    required int lookbackWeeks,
  }) {
    // Extract shift sequences
    final sequences = <List<String>>[];
    final shiftFrequency = <String, int>{};

    rosterData.forEach((staffName, schedule) {
      final sortedDates = schedule.keys.toList()..sort();
      final shifts = sortedDates.map((date) => schedule[date]!).toList();

      // Count shift frequencies
      for (final shift in shifts) {
        shiftFrequency[shift] = (shiftFrequency[shift] ?? 0) + 1;
      }

      // Extract weekly patterns
      for (int i = 0; i + 7 <= shifts.length; i += 7) {
        sequences.add(shifts.sublist(i, i + 7));
      }
    });

    // Find most common cycle length (2-8 weeks)
    int detectedCycle = 1;
    double bestConfidence = 0;

    for (int cycleLength = 1; cycleLength <= 8; cycleLength++) {
      final confidence = _calculateCycleConfidence(sequences, cycleLength);
      if (confidence > bestConfidence) {
        bestConfidence = confidence;
        detectedCycle = cycleLength;
      }
    }

    // Extract the detected pattern
    final detectedPattern = <List<String>>[];
    if (sequences.isNotEmpty) {
      for (int i = 0; i < detectedCycle && i < sequences.length; i++) {
        detectedPattern.add(sequences[i]);
      }
    }

    // Generate suggestions
    final suggestions = <String>[];

    if (bestConfidence > 0.8) {
      suggestions.add('Strong $detectedCycle-week pattern detected');
    } else if (bestConfidence > 0.6) {
      suggestions.add('Moderate $detectedCycle-week pattern detected');
    } else {
      suggestions.add('No clear pattern detected, consider using a template');
    }

    if (shiftFrequency.containsKey('N')) {
      final nightPercentage =
          (shiftFrequency['N']! / shiftFrequency.values.reduce((a, b) => a + b)) * 100;
      if (nightPercentage > 30) {
        suggestions.add('High night shift usage (${nightPercentage.toStringAsFixed(1)}%)');
      }
    }

    return PatternRecognitionResult(
      detectedCycleLength: detectedCycle,
      confidence: bestConfidence,
      detectedPattern: detectedPattern,
      shiftFrequency: shiftFrequency,
      suggestions: suggestions,
      analyzedAt: DateTime.now(),
    );
  }

  /// Calculate how well a cycle length fits the data
  double _calculateCycleConfidence(List<List<String>> sequences, int cycleLength) {
    if (sequences.length < cycleLength) return 0;

    int matches = 0;
    int comparisons = 0;

    for (int i = 0; i < sequences.length - cycleLength; i++) {
      for (int j = 0; j < 7; j++) {
        if (sequences[i][j] == sequences[i + cycleLength][j]) {
          matches++;
        }
        comparisons++;
      }
    }

    return comparisons > 0 ? matches / comparisons : 0;
  }

  /// Get shift hours (default values)
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

  /// Get week start date (Monday)
  DateTime _getWeekStart(DateTime date) {
    final daysSinceMonday = (date.weekday - DateTime.monday) % 7;
    return date.subtract(Duration(days: daysSinceMonday));
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Suggest pattern improvements
  List<String> suggestPatternImprovements({
    required Map<String, Map<DateTime, String>> rosterData,
    required List<PatternConflict> conflicts,
    required Map<String, dynamic> fairnessAnalysis,
  }) {
    final suggestions = <String>[];

    // Based on conflicts
    if (conflicts.isNotEmpty) {
      final conflictTypes = conflicts.map((c) => c.type).toSet();

      if (conflictTypes.contains(ConflictType.insufficientRest)) {
        suggestions.add('Add rest days between night and day shifts');
      }

      if (conflictTypes.contains(ConflictType.maxConsecutiveDays)) {
        suggestions.add('Reduce consecutive working days');
      }

      if (conflictTypes.contains(ConflictType.underStaffed)) {
        suggestions.add('Increase staff coverage on understaffed days');
      }
    }

    // Based on fairness
    final fairnessScore = fairnessAnalysis['fairness_score'] as int;
    if (fairnessScore < 70) {
      suggestions.add('Improve fairness by balancing weekend and night shifts');
    }

    return suggestions;
  }
}
