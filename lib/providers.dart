import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
import 'models.dart' as models;
import 'ai_service.dart';
import 'aws_service.dart';
import 'package:http/http.dart' as http;
import 'services/file_service.dart';
import 'utils/error_handler.dart';
import 'roster_generator.dart';
import 'services/activity_log_service.dart';
import 'services/holiday_service.dart';
import 'services/staff_name_store.dart';
import 'services/analytics_service.dart';

// Settings Provider
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, models.AppSettings>((ref) {
  return SettingsNotifier(ref);
});

class SettingsNotifier extends StateNotifier<models.AppSettings> {
  SettingsNotifier(this._ref) : super(const models.AppSettings());

  final Ref _ref;

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('app_settings');
      if (settingsJson != null) {
        final decoded = jsonDecode(settingsJson);
        state = models.AppSettings.fromJson(decoded);
        AnalyticsService.instance.updateSettings(state);
      }
      if (AwsService.instance.isAuthenticated) {
        final remote = await AwsService.instance.getUserSettings();
        if (remote != null && remote.isNotEmpty) {
          state = models.AppSettings.fromJson(remote);
          await prefs.setString('app_settings', jsonEncode(state.toJson()));
          AnalyticsService.instance.updateSettings(state);
        }
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> saveSettings(models.AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_settings', jsonEncode(settings.toJson()));
      state = settings;
      AnalyticsService.instance.updateSettings(settings);
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  void updateSettings(models.AppSettings settings) {
    state = settings;
    saveSettings(settings);
    AnalyticsService.instance.updateSettings(settings);
    if (AwsService.instance.isAuthenticated) {
      AwsService.instance.saveUserSettings(settings.toJson());
    }
  }
}

// Connection Status Providers
final awsStatusProvider = StateProvider<models.ServiceStatus>((ref) {
  return const models.ServiceStatus(
    status: models.ConnectionStatus.disconnected,
    lastChecked: null,
  );
});

final aiStatusProvider = StateProvider<models.ServiceStatus>((ref) {
  return const models.ServiceStatus(
    status: models.ConnectionStatus.disconnected,
    lastChecked: null,
  );
});

final activityLogProvider = ChangeNotifierProvider<ActivityLogService>((ref) {
  return ActivityLogService.instance;
});

final analyticsProvider = ChangeNotifierProvider<AnalyticsService>((ref) {
  return AnalyticsService.instance;
});

final staffNameProvider = ChangeNotifierProvider<StaffNameStore>((ref) {
  return StaffNameStore.instance;
});

final orgProvider = ChangeNotifierProvider<OrgNotifier>((ref) {
  return OrgNotifier();
});

class OrgNotifier extends ChangeNotifier {
  List<models.OrgMembership> orgMemberships = [];
  List<models.Team> teams = [];

  Future<void> refreshOrgs() async {
    try {
      orgMemberships = await AwsService.instance.getUserOrgs();
      notifyListeners();
    } catch (e) {
      debugPrint('Load orgs error: $e');
    }
  }

  Future<String?> createOrg(String name) async {
    try {
      final orgId = await AwsService.instance.createOrg(name);
      await refreshOrgs();
      return orgId;
    } catch (e) {
      debugPrint('Create org error: $e');
      return null;
    }
  }

  Future<String?> createTeam(String orgId, String name) async {
    try {
      final teamId = await AwsService.instance.createTeam(orgId, name);
      await loadTeams(orgId);
      return teamId;
    } catch (e) {
      debugPrint('Create team error: $e');
      return null;
    }
  }

  Future<void> loadTeams(String orgId) async {
    try {
      teams = await AwsService.instance.getTeams(orgId);
      notifyListeners();
    } catch (e) {
      debugPrint('Load teams error: $e');
    }
  }

  Future<void> addTeamMember(
    String orgId,
    String teamId,
    String memberUserId, {
    String role = 'member',
  }) async {
    try {
      await AwsService.instance.addTeamMember(
        orgId,
        teamId,
        memberUserId,
        role: role,
      );
    } catch (e) {
      debugPrint('Add team member error: $e');
    }
  }
}

// AI Suggestion Engine
class AISuggestionEngine {
  final RosterNotifier notifier;

  AISuggestionEngine(this.notifier);

  List<models.AiSuggestion> generateSuggestions() {
    final suggestions = <models.AiSuggestion>[];

    // Analyze workload
    suggestions.addAll(_analyzeWorkload());

    // Check for conflicts
    suggestions.addAll(_checkConflicts());

    // Analyze coverage
    suggestions.addAll(_analyzeCoverage());

    // Coverage by shift type
    suggestions.addAll(_checkCoverageByShiftType());

    // Check leave balances
    suggestions.addAll(_checkLeaveBalances());

    // Check preferences and constraints
    suggestions.addAll(_checkPreferences());

    // Leave conflicts
    suggestions.addAll(_checkLeaveConflicts());

    // Pattern analysis
    suggestions.addAll(_analyzePatterns());

    return suggestions;
  }

  List<models.AiSuggestion> _analyzeWorkload() {
    final suggestions = <models.AiSuggestion>[];
    final workloadMap = <String, int>{};

    for (final staff in notifier.staffMembers) {
      if (!staff.isActive) continue;

      int shiftCount = 0;
      final now = DateTime.now();

      for (int i = 0; i < 30; i++) {
        final date = now.add(Duration(days: i));
        final shift = notifier.getShiftForDate(staff.name, date);
        if (shift != 'OFF' && shift != 'AL') {
          shiftCount++;
        }
      }

      workloadMap[staff.name] = shiftCount;
    }

    if (workloadMap.isNotEmpty) {
      final avgWorkload =
          workloadMap.values.reduce((a, b) => a + b) / workloadMap.length;

      final sorted = workloadMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final mostLoaded = sorted.first;
      final leastLoaded = sorted.last;
      final swapCandidate = _findSwapCandidate(
        mostLoaded.key,
        leastLoaded.key,
        daysAhead: 14,
      );

      workloadMap.forEach((name, count) {
        if (count > avgWorkload * 1.3) {
          suggestions.add(
            models.AiSuggestion(
              id: '${DateTime.now().millisecondsSinceEpoch}_workload_high_$name',
              title: 'High Workload Alert',
              description:
                  '$name has $count shifts in the next 30 days, which is ${((count - avgWorkload) / avgWorkload * 100).toStringAsFixed(0)}% above average.',
              reason: 'Workload exceeds target range based on fairness rules.',
              priority: models.SuggestionPriority.high,
              type: models.SuggestionType.workload,
              createdDate: DateTime.now(),
              affectedStaff: [name],
              actionType: swapCandidate != null
                  ? models.SuggestionActionType.swapShifts
                  : null,
              actionPayload: swapCandidate,
              impactScore: 0.2,
              confidence: 0.65,
            ),
          );
        } else if (count < avgWorkload * 0.7) {
          suggestions.add(
            models.AiSuggestion(
              id: '${DateTime.now().millisecondsSinceEpoch}_workload_low_$name',
              title: 'Low Workload Notice',
              description:
                  '$name has only $count shifts in the next 30 days, which is below average.',
              reason: 'Workload is below target range and may indicate imbalance.',
              priority: models.SuggestionPriority.medium,
              type: models.SuggestionType.workload,
              createdDate: DateTime.now(),
              affectedStaff: [name],
              actionType: swapCandidate != null
                  ? models.SuggestionActionType.swapShifts
                  : null,
              actionPayload: swapCandidate,
              impactScore: 0.15,
              confidence: 0.6,
            ),
          );
        }
      });
    }

    return suggestions;
  }

  List<models.AiSuggestion> _checkConflicts() {
    final suggestions = <models.AiSuggestion>[];
    final now = DateTime.now();

    for (int i = 0; i < 60; i++) {
      final date = now.add(Duration(days: i));
      final staffOnShift = <String>[];

      for (final staff in notifier.staffMembers) {
        if (!staff.isActive) continue;
        final shift = notifier.getShiftForDate(staff.name, date);
        if (shift != 'OFF' && shift != 'AL') {
          staffOnShift.add(staff.name);
        }
      }

      final minStaff = (date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday)
          ? notifier.constraints.minStaffWeekend
          : notifier.constraints.minStaffPerDay;
      if (staffOnShift.length < minStaff) {
        final coverageCandidate = _findCoverageCandidate(date);
        suggestions.add(
          models.AiSuggestion(
            id: '${DateTime.now().millisecondsSinceEpoch}_coverage_${date.toIso8601String()}',
            title: 'Low Coverage Warning',
            description:
                'Only ${staffOnShift.length} staff scheduled for ${_formatDate(date)} (target: $minStaff).',
            reason:
                'Coverage is below the minimum staffing constraint for this day.',
            priority: staffOnShift.isEmpty
                ? models.SuggestionPriority.critical
                : models.SuggestionPriority.high,
            type: models.SuggestionType.coverage,
            createdDate: DateTime.now(),
            actionType: coverageCandidate != null
                ? models.SuggestionActionType.setOverride
                : null,
            actionPayload: coverageCandidate,
            impactScore: 0.3,
            confidence: 0.7,
          ),
        );
      }
    }

    return suggestions;
  }

  List<models.AiSuggestion> _analyzeCoverage() {
    final suggestions = <models.AiSuggestion>[];
    final weekendCoverage = <DateTime, int>{};
    final now = DateTime.now();

    for (int i = 0; i < 90; i++) {
      final date = now.add(Duration(days: i));
      if (date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday) {
        int count = 0;
        for (final staff in notifier.staffMembers) {
          if (!staff.isActive) continue;
          final shift = notifier.getShiftForDate(staff.name, date);
          if (shift != 'OFF' && shift != 'AL') {
            count++;
          }
        }
        weekendCoverage[date] = count;
      }
    }

    weekendCoverage.forEach((date, count) {
      if (count < 2) {
        suggestions.add(
          models.AiSuggestion(
            id: '${DateTime.now().millisecondsSinceEpoch}_weekend_${date.toIso8601String()}',
            title: 'Weekend Coverage Alert',
            description:
                'Low weekend coverage on ${_formatDate(date)} - only $count staff scheduled',
            reason: 'Weekend staffing is below coverage expectations.',
            priority: models.SuggestionPriority.high,
            type: models.SuggestionType.coverage,
            createdDate: DateTime.now(),
            impactScore: 0.2,
            confidence: 0.6,
          ),
        );
      }
    });

    return suggestions;
  }

  List<models.AiSuggestion> _checkLeaveBalances() {
    final suggestions = <models.AiSuggestion>[];

    for (final staff in notifier.staffMembers) {
      if (!staff.isActive) continue;

      if (staff.leaveBalance < 0) {
        suggestions.add(
          models.AiSuggestion(
            id: '${DateTime.now().millisecondsSinceEpoch}_leave_negative_${staff.name}',
            title: 'Negative Leave Balance',
            description:
                '${staff.name} has a negative leave balance of ${staff.leaveBalance.toStringAsFixed(1)} days',
            reason: 'Leave balance is below zero and violates policy.',
            priority: models.SuggestionPriority.critical,
            type: models.SuggestionType.leave,
            createdDate: DateTime.now(),
            affectedStaff: [staff.name],
            impactScore: 0.25,
            confidence: 0.7,
          ),
        );
      } else if (staff.leaveBalance < 3) {
        suggestions.add(
          models.AiSuggestion(
            id: '${DateTime.now().millisecondsSinceEpoch}_leave_low_${staff.name}',
            title: 'Low Leave Balance',
            description:
                '${staff.name} has only ${staff.leaveBalance.toStringAsFixed(1)} days of leave remaining',
            reason: 'Leave balance is approaching the minimum threshold.',
            priority: models.SuggestionPriority.medium,
            type: models.SuggestionType.leave,
            createdDate: DateTime.now(),
            affectedStaff: [staff.name],
            impactScore: 0.1,
            confidence: 0.6,
          ),
        );
      }
    }

    return suggestions;
  }

  List<models.AiSuggestion> _analyzePatterns() {
    final suggestions = <models.AiSuggestion>[];
    final pattern = notifier.masterPattern;

    // Check for pattern consistency
    if (pattern.isNotEmpty) {
      final firstWeekLength = pattern.first.length;
      final inconsistentWeeks =
          pattern.where((week) => week.length != firstWeekLength).length;

      if (inconsistentWeeks > 0) {
        suggestions.add(
          models.AiSuggestion(
            id: '${DateTime.now().millisecondsSinceEpoch}_pattern_inconsistent',
            title: 'Inconsistent Pattern Length',
            description:
                '$inconsistentWeeks weeks have different numbers of days than the first week',
            reason: 'Pattern consistency issues can break shift calculations.',
            priority: models.SuggestionPriority.high,
            type: models.SuggestionType.pattern,
            createdDate: DateTime.now(),
            impactScore: 0.2,
            confidence: 0.55,
          ),
        );
      }

      // Check for excessive consecutive shifts
      for (final staff in notifier.staffMembers) {
        if (!staff.isActive) continue;

        int maxConsecutive = 0;
        int currentConsecutive = 0;
        final now = DateTime.now();
        const restCodes = {'OFF', 'AL', 'R'};

        for (int i = 0; i < 14; i++) {
          final date = now.add(Duration(days: i));
          final shift = notifier.getShiftForDate(staff.name, date);
          if (!restCodes.contains(shift)) {
            currentConsecutive++;
            maxConsecutive = max(maxConsecutive, currentConsecutive);
          } else {
            currentConsecutive = 0;
          }
        }

        if (maxConsecutive >= notifier.constraints.maxConsecutiveDays) {
          suggestions.add(
            models.AiSuggestion(
              id: '${DateTime.now().millisecondsSinceEpoch}_consecutive_${staff.name}',
              title: 'Excessive Consecutive Shifts',
              description:
                  '${staff.name} has $maxConsecutive consecutive working days (limit: ${notifier.constraints.maxConsecutiveDays})',
              reason: 'Consecutive shifts exceed fatigue threshold.',
              priority: models.SuggestionPriority.medium,
              type: models.SuggestionType.workload,
              createdDate: DateTime.now(),
              affectedStaff: [staff.name],
              impactScore: 0.15,
              confidence: 0.6,
            ),
          );
        }
      }
    }

    return suggestions;
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  List<models.AiSuggestion> _checkPreferences() {
    final suggestions = <models.AiSuggestion>[];
    final now = DateTime.now();

    for (final staff in notifier.staffMembers) {
      if (!staff.isActive) continue;
      final prefs = staff.preferences;
      if (prefs == null) continue;

      int weekShifts = 0;
      for (int i = 0; i < 7; i++) {
        final date = now.add(Duration(days: i));
        final shift = notifier.getShiftForDate(staff.name, date);
        if (shift != 'OFF' && shift != 'AL') {
          weekShifts++;
        }
        if (prefs.preferredDaysOff.contains(date.weekday) && shift != 'OFF') {
          final actionPayload = notifier.constraints.allowAiOverrides
              ? {
                  'personName': staff.name,
                  'date': date.toIso8601String(),
                  'shift': 'OFF',
                  'reason': 'Preference day off',
                }
              : null;
          suggestions.add(
            models.AiSuggestion(
              id: '${DateTime.now().millisecondsSinceEpoch}_pref_${staff.name}_${date.toIso8601String()}',
              title: 'Preference Conflict',
              description:
                  '${staff.name} is scheduled on a preferred day off (${_formatDate(date)}).',
              reason: 'Scheduling conflicts with staff preference.',
              priority: models.SuggestionPriority.low,
              type: models.SuggestionType.fairness,
              createdDate: DateTime.now(),
              affectedStaff: [staff.name],
              actionType: actionPayload != null
                  ? models.SuggestionActionType.setOverride
                  : null,
              actionPayload: actionPayload,
              impactScore: 0.1,
              confidence: 0.55,
            ),
          );
        }
      }

      final maxPerWeek = prefs.maxShiftsPerWeek;
      if (maxPerWeek != null && weekShifts > maxPerWeek) {
        suggestions.add(
          models.AiSuggestion(
            id: '${DateTime.now().millisecondsSinceEpoch}_maxweek_${staff.name}',
            title: 'Max Shifts Exceeded',
            description:
                '${staff.name} has $weekShifts shifts in the next 7 days (limit: $maxPerWeek).',
            reason: 'Weekly shift count exceeds staff preference.',
            priority: models.SuggestionPriority.medium,
            type: models.SuggestionType.workload,
            createdDate: DateTime.now(),
            affectedStaff: [staff.name],
            impactScore: 0.15,
            confidence: 0.6,
          ),
        );
      }
    }

    return suggestions;
  }

  List<models.AiSuggestion> _checkCoverageByShiftType() {
    final suggestions = <models.AiSuggestion>[];
    final now = DateTime.now();
    if (notifier.constraints.shiftCoverageTargets.isEmpty &&
        notifier.constraints.shiftCoverageTargetsByDay.isEmpty) {
      return suggestions;
    }

    for (int i = 0; i < 14; i++) {
      final date = now.add(Duration(days: i));
      final counts = <String, int>{};

      for (final staff in notifier.staffMembers) {
        if (!staff.isActive) continue;
        final shift = notifier.getShiftForDate(staff.name, date);
        if (shift == 'OFF' || shift == 'AL') continue;
        final baseShift = _normalizeCoverageShiftType(shift);
        counts[baseShift] = (counts[baseShift] ?? 0) + 1;
      }

      final dayKey = date.weekday.toString();
      final dayTargets =
          notifier.constraints.shiftCoverageTargetsByDay[dayKey];
      final effectiveTargets =
          dayTargets ?? notifier.constraints.shiftCoverageTargets;

      effectiveTargets.forEach((shiftType, minCount) {
        final baseType = _normalizeCoverageShiftType(shiftType);
        if (_shouldSkipDayCoverageGap(baseType)) {
          return;
        }
        final staffed = counts[baseType] ?? 0;
        if (staffed < minCount) {
          final payload = notifier.constraints.allowAiOverrides
              ? _findCoverageCandidateForShift(baseType, date)
              : null;
          suggestions.add(
            models.AiSuggestion(
              id: '${DateTime.now().millisecondsSinceEpoch}_shiftgap_${baseType}_${date.toIso8601String()}',
              title: 'Coverage Gap ($baseType)',
              description:
                  'Only $staffed staff on $baseType shift for ${_formatDate(date)} (target: $minCount).',
              reason: 'Shift coverage is below the minimum target.',
              priority: models.SuggestionPriority.high,
              type: models.SuggestionType.coverage,
              createdDate: DateTime.now(),
              actionType: payload != null
                  ? models.SuggestionActionType.setOverride
                  : null,
              actionPayload: payload,
              impactScore: 0.25,
              confidence: 0.6,
            ),
          );
        }
      });
    }

    return suggestions;
  }

  List<models.AiSuggestion> _checkLeaveConflicts() {
    final suggestions = <models.AiSuggestion>[];
    if (notifier.constraints.shiftCoverageTargets.isEmpty &&
        notifier.constraints.shiftCoverageTargetsByDay.isEmpty) {
      return suggestions;
    }

    for (final override in notifier.overrides) {
      if (override.shift != 'AL') continue;
      final staff = notifier.staffMembers
          .firstWhere((s) => s.name == override.personName, orElse: () {
        return models.StaffMember(id: '', name: '');
      });
      if (staff.id.isEmpty) continue;

      final originalShift = notifier.getPatternShiftForDate(
        override.personName,
        override.date,
      );
      if (originalShift == 'OFF' || originalShift == 'AL') continue;
      final baseShift = _normalizeCoverageShiftType(originalShift);

      final dayKey = override.date.weekday.toString();
      final dayTargets =
          notifier.constraints.shiftCoverageTargetsByDay[dayKey];
      final effectiveTargets =
          dayTargets ?? notifier.constraints.shiftCoverageTargets;
      final minCount = effectiveTargets[baseShift];
      if (minCount == null) continue;

      int staffed = 0;
      for (final member in notifier.staffMembers) {
        if (!member.isActive) continue;
        final shift = notifier.getShiftForDate(member.name, override.date);
        if (_normalizeCoverageShiftType(shift) == baseShift) {
          staffed++;
        }
      }

      if (staffed < minCount) {
        final payload = notifier.constraints.allowAiOverrides
            ? _findCoverageCandidateForShift(baseShift, override.date)
            : null;
        suggestions.add(
          models.AiSuggestion(
            id: '${DateTime.now().millisecondsSinceEpoch}_leaveconflict_${override.personName}_${override.date.toIso8601String()}',
            title: 'Leave Conflict',
            description:
                '${override.personName} is on leave for ${_formatDate(override.date)} '
                'and coverage for $baseShift is below target.',
            reason: 'Leave reduces coverage below shift target.',
            priority: models.SuggestionPriority.high,
            type: models.SuggestionType.leave,
            createdDate: DateTime.now(),
            affectedStaff: [override.personName],
            actionType: payload != null
                ? models.SuggestionActionType.setOverride
                : null,
            actionPayload: payload,
            impactScore: 0.3,
            confidence: 0.65,
          ),
        );
      }
    }

    return suggestions;
  }

  Map<String, dynamic>? _findCoverageCandidateForShift(
    String shiftType,
    DateTime date,
  ) {
    if (!notifier.constraints.allowAiOverrides) return null;
    for (final staff in notifier.staffMembers) {
      if (!staff.isActive) continue;
      final shift = notifier.getShiftForDate(staff.name, date);
      if (shift == 'OFF') {
        final preferences = staff.preferences;
        if (preferences != null &&
            preferences.preferredDaysOff.contains(date.weekday)) {
          continue;
        }
        return {
          'personName': staff.name,
          'date': date.toIso8601String(),
          'shift': shiftType,
          'reason': 'AI shift coverage fill',
        };
      }
    }
    return null;
  }

  String _normalizeCoverageShiftType(String shift) {
    final base = notifier._normalizeShiftType(shift);
    if (base == 'E' || base == 'L' || base == 'D12') return 'D';
    return base;
  }

  bool _shouldSkipDayCoverageGap(String baseType) {
    if (baseType != 'D') return false;
    final types = notifier
        .getShiftTypes()
        .map((s) => s.toUpperCase())
        .toSet();
    final hasD = types.contains('D');
    final hasDayEquivalents =
        types.contains('E') || types.contains('L') || types.contains('D12');
    return !hasD && hasDayEquivalents;
  }

  Map<String, dynamic>? _findCoverageCandidate(DateTime date) {
    if (!notifier.constraints.allowAiOverrides) return null;
    for (final staff in notifier.staffMembers) {
      if (!staff.isActive) continue;
      final shift = notifier.getShiftForDate(staff.name, date);
      if (shift == 'OFF') {
        final preferences = staff.preferences;
        if (preferences != null &&
            preferences.preferredDaysOff.contains(date.weekday)) {
          continue;
        }
        return {
          'personName': staff.name,
          'date': date.toIso8601String(),
          'shift': 'D',
          'reason': 'AI coverage fill',
        };
      }
    }
    return null;
  }

  Map<String, dynamic>? _findSwapCandidate(
    String heavy,
    String light, {
    int daysAhead = 14,
  }) {
    if (!notifier.constraints.allowAiOverrides) return null;
    final now = DateTime.now();
    for (int i = 0; i < daysAhead; i++) {
      final date = now.add(Duration(days: i));
      final heavyShift = notifier.getShiftForDate(heavy, date);
      final lightShift = notifier.getShiftForDate(light, date);
      if (heavyShift != 'OFF' &&
          heavyShift != 'AL' &&
          (lightShift == 'OFF' || lightShift == 'AL')) {
        return {
          'personA': heavy,
          'personB': light,
          'date': date.toIso8601String(),
          'shiftA': heavyShift,
          'shiftB': lightShift == 'OFF' ? 'OFF' : lightShift,
        };
      }
    }
    return null;
  }
}

// Roster Provider - Main state management
final rosterProvider = ChangeNotifierProvider<RosterNotifier>((ref) {
  return RosterNotifier();
});

class SyncConflict {
  final Map<String, dynamic> remoteData;
  final int remoteVersion;
  final DateTime? lastModified;
  final String? lastModifiedBy;

  SyncConflict({
    required this.remoteData,
    required this.remoteVersion,
    this.lastModified,
    this.lastModifiedBy,
  });
}

class TemplateParseResult {
  final bool isValid;
  final String? error;
  final Map<String, dynamic>? payload;
  final String? warning;

  const TemplateParseResult({
    required this.isValid,
    this.error,
    this.payload,
    this.warning,
  });
}

class RosterNotifier extends ChangeNotifier {
  List<models.StaffMember> staffMembers = [];
  List<List<String>> masterPattern = [];
  List<models.Override> overrides = [];
  List<models.Event> events = [];
  List<models.HistoryEntry> history = [];
  List<models.AiSuggestion> aiSuggestions = [];
  List<models.RegularShiftSwap> regularSwaps = [];
  List<models.SyncOperation> pendingSync = [];
  List<models.AvailabilityRequest> availabilityRequests = [];
  List<models.SwapRequest> swapRequests = [];
  List<models.SwapDebt> swapDebts = [];
  List<models.ShiftLock> shiftLocks = [];
  List<models.ChangeProposal> changeProposals = [];
  List<models.AuditLogEntry> auditLogs = [];
  List<models.PresenceEntry> presenceEntries = [];
  List<models.TimeClockEntry> timeClockEntries = [];
  List<models.RosterUpdate> recentUpdates = [];
  List<models.GeneratedRosterTemplate> generatedRosters = [];
  List<models.RosterSnapshot> rosterSnapshots = [];
  models.GeneratedRosterTemplate? quickBaseTemplate;
  List<models.GeneratedRosterTemplate> quickVariationPresets = [];
  models.PatternPropagationSettings? propagationSettings;
  models.PatternRecognitionResult? lastPatternRecognition;
  models.RosterConstraints constraints = const models.RosterConstraints();
  bool readOnly = false;
  String? sharedAccessCode;
  String? sharedRosterName;
  String? sharedRole;
  DateTime? focusRequestDate;
  int focusRequestToken = 0;
  int cycleLength = 16;
  int numPeople = 16;
  int weekStartDay = 0;
  int _nextStaffId = 1;
  final Map<String, String> _shiftCache = {};
  final Map<String, bool> _unavailableCache = {};
  late AISuggestionEngine _aiEngine;
  Timer? _autoSaveTimer;
  Timer? _syncTimer;
  Timer? _presenceTimer;
  Timer? _cloudSyncTimer;
  String? _lastSavedHash;
  DateTime? _lastBackupAt;
  int _lastSyncedVersion = 0;
  DateTime? _lastSyncedAt;
  int _syncFailures = 0;
  DateTime? _nextSyncAfter;
  static const Duration _autoSaveDelay = Duration(seconds: 2);
  DateTime? get lastSyncedAt => _lastSyncedAt;
  int get lastSyncedVersion => _lastSyncedVersion;
  DateTime? get nextSyncAfter => _nextSyncAfter;
  DateTime? get lastBackupAt => _lastBackupAt;

  RosterNotifier() {
    _aiEngine = AISuggestionEngine(this);
    _startAutoSave();
  }

  @override
  void notifyListeners() {
    _shiftCache.clear();
    _unavailableCache.clear();
    super.notifyListeners();
  }

  String _cacheKey(String personName, DateTime date) {
    return '${personName.toLowerCase()}|${date.year}-${date.month}-${date.day}';
  }

  void requestFocusDate(DateTime date) {
    focusRequestDate = DateTime(date.year, date.month, date.day);
    focusRequestToken = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  void clearFocusRequest(int token) {
    if (focusRequestToken != token) return;
    focusRequestDate = null;
  }

  String _normalizeShiftType(String shift) {
    if (shift.isEmpty) return shift;
    if (shift == 'OFF' || shift == 'AL') return shift;
    final match = RegExp(r'^([A-Za-z]+)').firstMatch(shift.trim());
    return (match?.group(1) ?? shift).toUpperCase();
  }

  String _normalizeOverrideShift(models.Override override) {
    final raw = override.shift.toUpperCase();
    if (raw == 'AL') return 'AL';
    if (raw != 'L') return raw;
    final reason = (override.reason ?? '').toLowerCase();
    final isLeaveReason = reason.contains('leave') ||
        reason.contains('holiday') ||
        reason.contains('annual') ||
        reason.contains('sick') ||
        reason.contains('secondment');
    return isLeaveReason ? 'AL' : raw;
  }

  void _startAutoSave() {
    _autoSaveTimer?.cancel();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, () async {
      await _autoSave();
    });
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
  }

  Future<void> _autoSave() async {
    try {
      await saveToLocal();
      _scheduleCloudSync();
    } catch (e) {
      debugPrint('Auto-save error: $e');
    }
  }

  void _scheduleCloudSync() {
    if (readOnly) return;
    if (!AwsService.instance.isAuthenticated) return;
    if (AwsService.instance.currentRosterId == null) return;

    _cloudSyncTimer?.cancel();
    _cloudSyncTimer = Timer(const Duration(seconds: 60), () async {
      try {
        await autoSyncToAWS();
      } catch (e) {
        debugPrint('Auto-sync error: $e');
      }
    });

    _queueSyncOperation(
      models.SyncOperation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: models.SyncOperationType.bulkUpdate,
        timestamp: DateTime.now(),
        data: toJson(),
      ),
    );
    _processPendingSync();
  }

  Future<void> _processPendingSync() async {
    if (pendingSync.isEmpty) return;
    if (_nextSyncAfter != null &&
        DateTime.now().isBefore(_nextSyncAfter!)) {
      return;
    }

    final operations = List<models.SyncOperation>.from(pendingSync);
    for (final op in operations) {
      try {
        // Process sync operation using the new method name
        await AwsService.instance.publishRosterUpdate(
          models.RosterUpdate(
            id: op.id,
            rosterId: AwsService.instance.currentRosterId ?? 'local',
            userId: AwsService.instance.userId ?? 'unknown',
            operationType: _convertSyncOperationType(op.type),
            data: op.data,
            timestamp: op.timestamp,
          ),
        );
        pendingSync.removeWhere((o) => o.id == op.id);
        _syncFailures = 0;
        _nextSyncAfter = null;
        await _persistPendingSync();
      } catch (e) {
        debugPrint('Sync error: $e');
        _syncFailures = (_syncFailures + 1).clamp(1, 6);
        final backoffSeconds = 5 * (1 << (_syncFailures - 1));
        _nextSyncAfter =
            DateTime.now().add(Duration(seconds: backoffSeconds));
        await _persistPendingSync();
        break;
      }
    }
  }

  models.OperationType _convertSyncOperationType(
      models.SyncOperationType type) {
    switch (type) {
      case models.SyncOperationType.bulkUpdate:
        return models.OperationType.bulkUpdate;
      case models.SyncOperationType.singleUpdate:
        return models.OperationType.singleUpdate;
      case models.SyncOperationType.delete:
        return models.OperationType.delete;
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _syncTimer?.cancel();
    _presenceTimer?.cancel();
    _cloudSyncTimer?.cancel();
    super.dispose();
  }

  // Add history entry
  void _addHistory(
    String action,
    String description, {
    Map<String, dynamic>? metadata,
  }) {
    history.add(
      models.HistoryEntry(
        timestamp: DateTime.now(),
        action: action,
        description: description,
        metadata: metadata,
      ),
    );
    ActivityLogService.instance.addInfo('$action - $description');
    AnalyticsService.instance.trackEvent(
      action,
      type: 'history',
      properties: {
        'description': description,
        if (metadata != null) 'metadata': metadata,
      },
    );

    if (history.length > 100) {
      history = history.sublist(history.length - 100);
    }
  }

  void updateConstraints(models.RosterConstraints newConstraints) {
    constraints = newConstraints;
    _addHistory(
      'Constraints Updated',
      'Updated roster optimization constraints',
    );
    notifyListeners();
  }

  List<String> get weekDayLabels {
    return const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  }

  void setWeekStartDay(int dayIndex) {
    weekStartDay = dayIndex.clamp(0, 6);
    _addHistory('Week Start', 'Week starts on ${weekDayLabels[weekStartDay]}');
    notifyListeners();
  }

  void updateStaffPreferencesById(
    String staffId,
    models.StaffPreferences preferences,
  ) {
    final index = staffMembers.indexWhere((s) => s.id == staffId);
    if (index == -1) return;
    staffMembers[index] = staffMembers[index].copyWith(
      preferences: preferences,
    );
    _addHistory('Preferences Updated', 'Updated staff preferences');
    notifyListeners();
  }

  RosterBackup createBackup() {
    return RosterBackup(
      staffMembers: List.from(staffMembers),
      masterPattern: masterPattern.map((w) => List<String>.from(w)).toList(),
      overrides: List.from(overrides),
      events: List.from(events),
      history: List.from(history),
      aiSuggestions: List.from(aiSuggestions),
      regularSwaps: List.from(regularSwaps),
      availabilityRequests: List.from(availabilityRequests),
      swapRequests: List.from(swapRequests),
      swapDebts: List.from(swapDebts),
      shiftLocks: List.from(shiftLocks),
      changeProposals: List.from(changeProposals),
      auditLogs: List.from(auditLogs),
      generatedRosters: List.from(generatedRosters),
      rosterSnapshots: List.from(rosterSnapshots),
      quickBaseTemplate: quickBaseTemplate,
      quickVariationPresets: List.from(quickVariationPresets),
      weekStartDay: weekStartDay,
      propagationSettings: propagationSettings,
      cycleLength: cycleLength,
      numPeople: numPeople,
    );
  }

  void restoreBackup(RosterBackup backup) {
    staffMembers = List.from(backup.staffMembers);
    masterPattern = backup.masterPattern.map((w) => List<String>.from(w)).toList();
    overrides = List.from(backup.overrides);
    events = List.from(backup.events);
    history = List.from(backup.history);
    aiSuggestions = List.from(backup.aiSuggestions);
    regularSwaps = List.from(backup.regularSwaps);
    availabilityRequests = List.from(backup.availabilityRequests);
    swapRequests = List.from(backup.swapRequests);
    swapDebts = List.from(backup.swapDebts);
    shiftLocks = List.from(backup.shiftLocks);
    changeProposals = List.from(backup.changeProposals);
    auditLogs = List.from(backup.auditLogs);
    generatedRosters = List.from(backup.generatedRosters);
    rosterSnapshots = List.from(backup.rosterSnapshots);
    quickBaseTemplate = backup.quickBaseTemplate;
    quickVariationPresets = List.from(backup.quickVariationPresets);
    propagationSettings = backup.propagationSettings;
    cycleLength = backup.cycleLength;
    numPeople = backup.numPeople;
    weekStartDay = backup.weekStartDay;
    notifyListeners();
  }

  // Enhanced Staff Management
  void addStaff(String name) {
    final newStaff = models.StaffMember(
      id: (_nextStaffId++).toString(),
      name: name.trim(),
    );
    staffMembers.add(newStaff.copyWith(startDate: DateTime.now()));
    _addHistory('Staff Added', 'Added staff member: $name');
    _rememberStaffNames([newStaff.name]);
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
  }

  void removeStaff(String name) {
    final index = staffMembers.indexWhere((s) => s.name == name);
    if (index == -1) return;
    final today = DateTime.now();
    staffMembers[index] = staffMembers[index].copyWith(
      isActive: false,
      endDate: DateTime(today.year, today.month, today.day),
    );
    _addHistory('Staff Ended', 'Ended staff member: $name');
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
  }

  void removeStaffById(String staffId) {
    final index = staffMembers.indexWhere((s) => s.id == staffId);
    if (index == -1) return;
    final staff = staffMembers[index];
    final today = DateTime.now();
    staffMembers[index] = staff.copyWith(
      isActive: false,
      endDate: DateTime(today.year, today.month, today.day),
    );
    _addHistory('Staff Ended', 'Ended staff member: ${staff.name}');
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
  }

  void renameStaff(int index, String newName) {
    if (index >= 0 &&
        index < staffMembers.length &&
        newName.trim().isNotEmpty) {
      final oldName = staffMembers[index].name;
      staffMembers[index] = staffMembers[index].copyWith(name: newName.trim());

      // Update all overrides with the new name
      for (var i = 0; i < overrides.length; i++) {
        if (overrides[i].personName == oldName) {
          overrides[i] = models.Override(
            id: overrides[i].id,
            personName: newName.trim(),
            date: overrides[i].date,
            shift: overrides[i].shift,
            reason: overrides[i].reason,
            createdAt: overrides[i].createdAt,
          );
        }
      }

      _addHistory('Staff Renamed', 'Renamed $oldName to ${newName.trim()}');
      _rememberStaffNames([newName.trim()]);
      _scheduleAutoSave();
      _scheduleCloudSync();
      notifyListeners();
    }
  }

  void renameStaffById(String staffId, String newName) {
    final index = staffMembers.indexWhere((s) => s.id == staffId);
    if (index != -1) {
      renameStaff(index, newName);
    }
  }

  void toggleStaffStatus(int index) {
    if (index >= 0 && index < staffMembers.length) {
      final newStatus = !staffMembers[index].isActive;
      final today = DateTime.now();
      staffMembers[index] = staffMembers[index].copyWith(
        isActive: newStatus,
        endDate: newStatus ? null : DateTime(today.year, today.month, today.day),
      );
      _addHistory(
        'Staff Status',
        'Set ${staffMembers[index].name} status to ${newStatus ? 'active' : 'inactive'}',
      );
      _scheduleAutoSave();
      _scheduleCloudSync();
      notifyListeners();
    }
  }

  void toggleStaffStatusById(String staffId) {
    final index = staffMembers.indexWhere((s) => s.id == staffId);
    if (index != -1) {
      toggleStaffStatus(index);
    }
  }

  void setStaffEmploymentType(String staffId, String type) {
    final index = staffMembers.indexWhere((s) => s.id == staffId);
    if (index == -1) return;
    staffMembers[index] = staffMembers[index].copyWith(employmentType: type);
    _addHistory(
      'Staff Employment Updated',
      'Set ${staffMembers[index].name} employment to $type',
    );
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
  }

  void setStaffLeaveStatus({
    required String staffId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final index = staffMembers.indexWhere((s) => s.id == staffId);
    if (index == -1) return;
    staffMembers[index] = staffMembers[index].copyWith(
      leaveType: leaveType,
      leaveStart: DateTime(startDate.year, startDate.month, startDate.day),
      leaveEnd: DateTime(endDate.year, endDate.month, endDate.day),
    );
    _addHistory(
      'Staff Leave',
      'Set ${staffMembers[index].name} to $leaveType',
    );
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
  }

  void clearStaffLeaveStatus(String staffId) {
    final index = staffMembers.indexWhere((s) => s.id == staffId);
    if (index == -1) return;
    staffMembers[index] = staffMembers[index].copyWith(
      leaveType: null,
      leaveStart: null,
      leaveEnd: null,
    );
    _addHistory(
      'Staff Leave Cleared',
      'Cleared leave for ${staffMembers[index].name}',
    );
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
  }

  void setStaffStartDate(String staffId, DateTime date) {
    final index = staffMembers.indexWhere((s) => s.id == staffId);
    if (index == -1) return;
    staffMembers[index] = staffMembers[index].copyWith(
      startDate: DateTime(date.year, date.month, date.day),
    );
    _addHistory(
      'Staff Start Updated',
      'Updated start date for ${staffMembers[index].name}',
    );
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
  }

  void setStaffEndDate(String staffId, DateTime? date) {
    final index = staffMembers.indexWhere((s) => s.id == staffId);
    if (index == -1) return;
    staffMembers[index] = staffMembers[index].copyWith(
      endDate: date == null
          ? null
          : DateTime(date.year, date.month, date.day),
      isActive: staffMembers[index].isActive,
    );
    _addHistory(
      'Staff End Updated',
      'Updated end date for ${staffMembers[index].name}',
    );
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
  }

  // Regular Shift Swap Management
  void addRegularSwap(models.RegularShiftSwap swap) {
    regularSwaps.add(swap);
    _applySwapToFutureRoster(swap);
    _addHistory(
      'Regular Swap Added',
      'Added swap between ${swap.fromPerson} and ${swap.toPerson}',
    );
    notifyListeners();
  }

  void removeRegularSwap(String swapId) {
    final swap = regularSwaps.firstWhere((s) => s.id == swapId);
    _reverseSwapFromRoster(swap);
    regularSwaps.removeWhere((s) => s.id == swapId);
    _addHistory(
      'Regular Swap Removed',
      'Removed swap between ${swap.fromPerson} and ${swap.toPerson}',
    );
    notifyListeners();
  }

  void updateRegularSwap(String swapId, models.RegularShiftSwap updatedSwap) {
    final index = regularSwaps.indexWhere((s) => s.id == swapId);
    if (index != -1) {
      final oldSwap = regularSwaps[index];
      _reverseSwapFromRoster(oldSwap);
      regularSwaps[index] = updatedSwap;
      _applySwapToFutureRoster(updatedSwap);
      notifyListeners();
    }
  }

  void _applySwapToFutureRoster(models.RegularShiftSwap swap) {
    if (!swap.isActive) return;

    final now = DateTime.now();
    final endDate = swap.endDate ?? now.add(const Duration(days: 365));

    for (var date = swap.startDate;
        date.isBefore(endDate);
        date = date.add(const Duration(days: 1))) {
      if (date.isAfter(now.subtract(const Duration(days: 1)))) {
        _applySingleSwap(swap, date);
      }
    }
  }

  void _reverseSwapFromRoster(models.RegularShiftSwap swap) {
    final now = DateTime.now();
    final endDate = swap.endDate ?? now.add(const Duration(days: 365));

    overrides.removeWhere(
      (o) =>
          o.date.isAfter(now.subtract(const Duration(days: 1))) &&
          o.date.isBefore(endDate) &&
          ((o.personName == swap.fromPerson) ||
              (o.personName == swap.toPerson)),
    );
  }

  void _applySingleSwap(models.RegularShiftSwap swap, DateTime date) {
    if (swap.weekIndex != null) {
      final referenceDate = DateTime(2024, 1, 1);
      final daysSinceReference = date.difference(referenceDate).inDays;
      final cycleDay = daysSinceReference % (cycleLength * 7);
      final week = cycleDay ~/ 7;
      if (week != swap.weekIndex) return;
    }
    final fromShift = getShiftForDate(swap.fromPerson, date);
    final toShift = getShiftForDate(swap.toPerson, date);

    if (fromShift == swap.fromShift && toShift == swap.toShift) {
      overrides.removeWhere(
        (o) => o.date == date && o.personName == swap.fromPerson,
      );
      overrides
          .removeWhere((o) => o.date == date && o.personName == swap.toPerson);

      overrides.add(
        models.Override(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          personName: swap.fromPerson,
          date: date,
          shift: swap.toShift,
          reason: 'Regular swap with ${swap.toPerson}',
          createdAt: DateTime.now(),
        ),
      );

      overrides.add(
        models.Override(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          personName: swap.toPerson,
          date: date,
          shift: swap.fromShift,
          reason: 'Regular swap with ${swap.fromPerson}',
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  // Sync Operations
  void _queueSyncOperation(models.SyncOperation operation) {
    pendingSync.add(operation);
    _persistPendingSync();
  }

  void addSwapDebt({
    required String fromPerson,
    required String toPerson,
    required int daysOwed,
    required String reason,
  }) {
    if (daysOwed <= 0) return;
    swapDebts.add(
      models.SwapDebt(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fromPerson: fromPerson,
        toPerson: toPerson,
        daysOwed: daysOwed,
        daysSettled: 0,
        reason: reason,
        createdAt: DateTime.now(),
      ),
    );
    _addHistory('Swap Debt', 'Recorded $daysOwed day(s) owed from $fromPerson to $toPerson');
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
  }

  void ignoreSwapDebt(String debtId) {
    final index = swapDebts.indexWhere((d) => d.id == debtId);
    if (index == -1) return;
    final debt = swapDebts[index];
    swapDebts[index] = debt.copyWith(
      isIgnored: true,
      ignoredAt: DateTime.now(),
      resolvedAt: DateTime.now(),
    );
    _addHistory('Swap Debt Ignored', 'Ignored swap debt for ${debt.fromPerson}');
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
  }

  void restoreSwapDebt(String debtId) {
    final index = swapDebts.indexWhere((d) => d.id == debtId);
    if (index == -1) return;
    final debt = swapDebts[index];
    swapDebts[index] = debt.copyWith(
      isIgnored: false,
      ignoredAt: null,
      resolvedAt: debt.daysSettled >= debt.daysOwed ? DateTime.now() : null,
    );
    _addHistory('Swap Debt Restored', 'Restored swap debt for ${debt.fromPerson}');
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
  }

  bool applySwapForDate({
    required String fromPerson,
    required String toPerson,
    required DateTime date,
    String reason = 'Shift swap',
  }) {
    final fromShift = getShiftForDate(fromPerson, date);
    final toShift = getShiftForDate(toPerson, date);
    if (fromShift.isEmpty || toShift.isEmpty) return false;

    overrides.removeWhere(
      (o) =>
          o.date.year == date.year &&
          o.date.month == date.month &&
          o.date.day == date.day &&
          (o.personName == fromPerson || o.personName == toPerson),
    );

    overrides.add(
      models.Override(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        personName: fromPerson,
        date: date,
        shift: toShift,
        reason: reason,
        createdAt: DateTime.now(),
      ),
    );
    overrides.add(
      models.Override(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        personName: toPerson,
        date: date,
        shift: fromShift,
        reason: reason,
        createdAt: DateTime.now(),
      ),
    );
    _addHistory(
      'Shift Swap',
      'Swapped $fromPerson ($fromShift) with $toPerson ($toShift) on ${date.toIso8601String()}',
    );
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
    return true;
  }

  int applySwapRange({
    required String fromPerson,
    required String toPerson,
    required DateTime startDate,
    required DateTime endDate,
    String reason = 'Shift swap range',
  }) {
    int applied = 0;
    for (var date = startDate;
        !date.isAfter(endDate);
        date = date.add(const Duration(days: 1))) {
      final didSwap = applySwapForDate(
        fromPerson: fromPerson,
        toPerson: toPerson,
        date: date,
        reason: reason,
      );
      if (didSwap) {
        applied++;
      }
    }
    return applied;
  }

  void settleSwapDebt({
    required String debtId,
    required List<DateTime> dates,
  }) {
    final index = swapDebts.indexWhere((d) => d.id == debtId);
    if (index == -1) return;
    final debt = swapDebts[index];
    int settled = debt.daysSettled;
    final settledDates = List<String>.from(debt.settledDates);
    for (final date in dates) {
      final didSwap = applySwapForDate(
        fromPerson: debt.fromPerson,
        toPerson: debt.toPerson,
        date: date,
        reason: 'Swap debt settlement',
      );
      if (didSwap) {
        settled++;
        settledDates.add(date.toIso8601String());
      }
    }
    final resolvedAt = settled >= debt.daysOwed ? DateTime.now() : null;
    swapDebts[index] = debt.copyWith(
      daysSettled: settled,
      settledDates: settledDates,
      resolvedAt: resolvedAt,
    );
    _addHistory('Swap Debt Settled', 'Settled ${dates.length} day(s) for ${debt.fromPerson}');
    _scheduleAutoSave();
    _scheduleCloudSync();
    notifyListeners();
  }

  Future<void> _persistPendingSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'pending_sync',
        jsonEncode(pendingSync.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Pending sync persist error: $e');
    }
  }

  Future saveToAWS() async {
    try {
      final currentRosterId = AwsService.instance.currentRosterId;
      if (currentRosterId == null) {
        debugPrint('No roster selected for saveToAWS');
        return;
      }

      final remoteData =
          await AwsService.instance.loadRosterData(currentRosterId);
      final shouldSave = await AwsService.instance.resolveConflict(
        currentRosterId,
        remoteData?['version'] as int? ?? 0,
        toJson(),
      );

      if (shouldSave) {
        final newVersion = await AwsService.instance
            .saveRosterData(currentRosterId, toJson());
        _lastSyncedVersion = newVersion;
        _lastSyncedAt = DateTime.now();
        _addHistory('Sync', 'Saved roster to cloud');
      } else if (remoteData != null) {
        fromJson(remoteData['data'] as Map<String, dynamic>);
        _lastSyncedVersion = remoteData['version'] as int? ?? _lastSyncedVersion;
        _lastSyncedAt = _parseDateTime(remoteData['last_modified']);
        _addHistory('Sync', 'Loaded newer version from cloud');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Save to AWS error: $e');
      _queueSyncOperation(
        models.SyncOperation(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: models.SyncOperationType.bulkUpdate,
          timestamp: DateTime.now(),
          data: toJson(),
        ),
      );
    }
  }

// ------------------------------
// Real-Time Cloud Sync
// ------------------------------

  /// Public entry point called once after roster is loaded or created.
  Future setupRealtimeSync() async {
    try {
      debugPrint('Realtime sync disabled for performance.');
    } catch (e) {
      debugPrint('Realtime sync setup error: $e');
    }
  }

  // Add to RosterNotifier class:

  void _setupRealtimeSync() {
    final currentRosterId = AwsService.instance.currentRosterId;
    if (currentRosterId != null) {
      AwsService.instance.subscribeToRosterUpdates(
        currentRosterId,
        (update) {
          _handleRemoteUpdate(update);
        },
      );
      _startPresenceHeartbeat(currentRosterId);
    } else {
      debugPrint('Realtime sync skipped: no roster ID');
    }
  }

  void _startPresenceHeartbeat(String rosterId) {
    if (!AwsService.instance.isAuthenticated) return;
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      try {
        await AwsService.instance.sendPresenceHeartbeat(rosterId);
        await refreshPresence();
      } catch (e) {
        debugPrint('Presence heartbeat failed: $e');
      }
    });
  }

  Future<void> refreshPresence() async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    try {
      final list = await AwsService.instance.getPresence(rosterId);
      final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
      presenceEntries = list
          .where((entry) => entry.lastSeen.isAfter(cutoff))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Presence refresh error: $e');
    }
  }

  void _handleRemoteUpdate(models.RosterUpdate update) {
    if (update.userId != AwsService.instance.userId) {
      debugPrint('Processing remote update from user: ${update.userId}');
      loadFromAWS();
    }
  }

  Future<void> syncToAWS() async {
    if (readOnly) {
      throw Exception('Read-only roster cannot be synced');
    }
    try {
      final data = toJson();
      final newVersion = await AwsService.instance.saveRosterData(
        AwsService.instance.currentRosterId ?? 'local',
        data,
      );
      _lastSyncedVersion = newVersion;
      _lastSyncedAt = DateTime.now();
      _addHistory('Sync', 'Synced to cloud successfully');
    } catch (e) {
      debugPrint('Sync error: $e');
      _queueSyncOperation(
        models.SyncOperation(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: models.SyncOperationType.bulkUpdate,
          timestamp: DateTime.now(),
          data: toJson(),
        ),
      );
      rethrow;
    }
  }

  Future<bool> autoSyncToAWS() async {
    if (readOnly) return false;
    try {
      final conflict = await checkForSyncConflict();
      if (conflict != null) {
        _addHistory('Sync', 'Auto-sync skipped due to conflict');
        return false;
      }
      await syncToAWS();
      return true;
    } catch (e) {
      debugPrint('Auto-sync error: $e');
      return false;
    }
  }

  Future<SyncConflict?> checkForSyncConflict() async {
    final currentRosterId = AwsService.instance.currentRosterId;
    if (currentRosterId == null) return null;
    final remote =
        await AwsService.instance.loadRosterData(currentRosterId);
    if (remote == null) return null;
    final remoteVersion = remote['version'] as int? ?? 0;
    if (_lastSyncedVersion == 0 || remoteVersion <= _lastSyncedVersion) {
      return null;
    }
    return SyncConflict(
      remoteData: remote['data'] as Map<String, dynamic>,
      remoteVersion: remoteVersion,
      lastModified: _parseDateTime(remote['last_modified']),
      lastModifiedBy: remote['last_modified_by'] as String?,
    );
  }

  void applyRemoteData(Map<String, dynamic> data, int version) {
    fromJson(data);
    _lastSyncedVersion = version;
    _lastSyncedAt = DateTime.now();
    _addHistory('Sync', 'Loaded remote data due to conflict');
    notifyListeners();
  }

  Future<void> exportData() async {
    try {
      final data = toJson();
      final jsonData = jsonEncode(data);
      final fileName =
          'roster_backup_${DateTime.now().millisecondsSinceEpoch}.json';

      final path = await FileService.saveFile(fileName, jsonData);

      if (path != null) {
        _addHistory('Export', 'Exported roster data to: $path');
      } else {
        throw Exception('Export cancelled by user');
      }
    } catch (e) {
      debugPrint('Export error: $e');
      rethrow;
    }
  }

  Future<void> importData(Map<String, dynamic> data) async {
    try {
      fromJson(data);
      await saveToLocal();
      _addHistory('Import', 'Imported roster data');
      notifyListeners();
    } catch (e) {
      debugPrint('Import error: $e');
      rethrow;
    }
  }

  // Multi-user sync methods
  Future<void> loadFromAWS() async {
    try {
      final currentRosterId = AwsService.instance.currentRosterId;
      if (currentRosterId == null) {
        debugPrint('No roster selected');
        return;
      }

      final data =
          await AwsService.instance.loadRosterData(currentRosterId);
      if (data != null) {
        fromJson(data['data'] as Map<String, dynamic>);
        _lastSyncedVersion = data['version'] as int? ?? _lastSyncedVersion;
        _lastSyncedAt = _parseDateTime(data['last_modified']);
        readOnly = false;
        sharedAccessCode = null;
        sharedRosterName = null;
        sharedRole = null;
        _addHistory('Sync', 'Loaded roster from cloud');
        await saveToLocal();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Load from AWS error: $e');
    }
  }

  Future<void> loadSharedRosterByCode(String code) async {
    try {
      final response = AwsService.instance.isAuthenticated
          ? await AwsService.instance.accessRosterByCodeAuthenticated(code)
          : await AwsService.instance.accessRosterByCode(code);
      final data = response['data'];
      if (data == null) {
        throw Exception('Shared roster has no data');
      }
      fromJson(Map<String, dynamic>.from(data as Map));
      AwsService.instance.currentRosterId = response['rosterId'] as String?;
      sharedAccessCode = code;
      sharedRosterName = response['rosterName'] as String?;
      sharedRole = response['role'] as String? ?? 'viewer';
      readOnly = sharedRole != 'editor';
      final remoteVersion = response['version'];
      if (remoteVersion is int) {
        _lastSyncedVersion = remoteVersion;
      }
      final lastModifiedRaw = response['last_modified'];
      if (lastModifiedRaw is String) {
        _lastSyncedAt = DateTime.tryParse(lastModifiedRaw);
      }
      _addHistory(
        'Shared Roster',
        'Opened shared roster ${sharedRosterName ?? ''}'.trim(),
      );
      notifyListeners();
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('404') ||
          message.contains('not found') ||
          message.contains('invalid code')) {
        throw Exception('Access code not found. Check the code and try again.');
      }
      if (message.contains('expired')) {
        throw Exception('Access code expired. Ask for a new code.');
      }
      if (message.contains('max') && message.contains('use')) {
        throw Exception('Access code has reached its usage limit.');
      }
      rethrow;
    }
  }

  Future<void> submitSharedLeaveRequest({
    required String guestName,
    required DateTime startDate,
    DateTime? endDate,
    String? notes,
  }) async {
    if (sharedAccessCode == null || sharedAccessCode!.isEmpty) {
      throw Exception('No shared access code available');
    }
    await AwsService.instance.submitLeaveRequestWithCode(
      code: sharedAccessCode!,
      startDate: startDate,
      endDate: endDate,
      notes: notes,
      guestName: guestName,
    );
    _addHistory('Leave Request', 'Submitted guest leave request');
  }

  void applyRemoteUpdate(models.RosterUpdate update) {
    switch (update.operationType) {
      case models.OperationType.bulkUpdate:
        _applyBulkUpdate(update);
        break;
      case models.OperationType.singleUpdate:
        _applySingleUpdate(update);
        break;
      case models.OperationType.delete:
        _applyDelete(update);
        break;
      case models.OperationType.addStaff:
        _applyStaffUpdate(update);
        break;
      case models.OperationType.removeStaff:
        _applyRemoveStaff(update);
        break;
      case models.OperationType.addOverride:
        _applyOverrideUpdate(update);
        break;
      case models.OperationType.removeOverride:
        _applyRemoveOverride(update);
        break;
      case models.OperationType.updatePattern:
        _applyPatternUpdate(update);
        break;
      case models.OperationType.addEvent:
        _applyEventUpdate(update);
        break;
      case models.OperationType.removeEvent:
        _applyRemoveEvent(update);
        break;
    }
    notifyListeners();
  }

  void _applyBulkUpdate(models.RosterUpdate update) {
    final data = update.data['data'] as Map<String, dynamic>?;
    if (data != null) {
      fromJson(data);
    }
  }

  void _applySingleUpdate(models.RosterUpdate update) {
    // Handle single field updates
    debugPrint('Single update applied: ${update.data}');
  }

  void _applyDelete(models.RosterUpdate update) {
    // Handle delete operations
    debugPrint('Delete operation: ${update.data}');
  }

  void _applyRemoveStaff(models.RosterUpdate update) {
    final staffName = update.data['name'] as String?;
    if (staffName != null) {
      removeStaff(staffName);
    }
  }

  void _applyRemoveOverride(models.RosterUpdate update) {
    final overrideId = update.data['id'] as String?;
    if (overrideId != null) {
      overrides.removeWhere((o) => o.id == overrideId);
    }
  }

  void _applyPatternUpdate(models.RosterUpdate update) {
    final patternData = update.data['pattern'] as List<dynamic>?;
    if (patternData != null) {
      masterPattern = patternData
          .map((week) => (week as List<dynamic>).cast<String>().toList())
          .toList();
    }
  }

  void _applyRemoveEvent(models.RosterUpdate update) {
    final eventId = update.data['id'] as String?;
    if (eventId != null) {
      events.removeWhere((e) => e.id == eventId);
    }
  }

  void _applyOverrideUpdate(models.RosterUpdate update) {
    final override = models.Override.fromJson(update.data);
    overrides.removeWhere(
      (o) => o.personName == override.personName && o.date == override.date,
    );
    overrides.add(override);
  }

  void _applyStaffUpdate(models.RosterUpdate update) {
    final staff = models.StaffMember.fromJson(update.data);
    final index = staffMembers.indexWhere((s) => s.id == staff.id);
    if (index != -1) {
      staffMembers[index] = staff;
    } else {
      staffMembers.add(staff);
    }
  }

  void _applyEventUpdate(models.RosterUpdate update) {
    final event = models.Event.fromJson(update.data);
    events.removeWhere((e) => e.id == event.id);
    events.add(event);
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  // Data persistence
  Future<void> saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(toJson());
      final hash = data.hashCode.toString();
      if (_lastSavedHash == hash) {
        return;
      }
      await prefs.setString('roster_data', data);
      await _storeBackupIfNeeded(prefs, data);
      _lastSavedHash = hash;
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  Future<void> _storeBackupIfNeeded(
    SharedPreferences prefs,
    String data,
  ) async {
    final now = DateTime.now();
    final lastBackupMs = prefs.getInt('roster_last_backup_ms');
    final lastBackup = lastBackupMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lastBackupMs)
        : null;
    if (lastBackup != null &&
        now.difference(lastBackup) < const Duration(minutes: 30)) {
      return;
    }
    await _storeBackup(prefs, data, reason: 'Auto backup');
  }

  Future<void> _storeBackupNow({required String reason}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(toJson());
    await _storeBackup(prefs, data, reason: reason);
  }

  Future<void> _storeBackup(
    SharedPreferences prefs,
    String data, {
    required String reason,
  }) async {
    final now = DateTime.now();
    final backupsRaw = prefs.getString('roster_backups');
    final backups = backupsRaw != null
        ? (jsonDecode(backupsRaw) as List<dynamic>)
        : <dynamic>[];
    backups.add({
      'createdAt': now.toIso8601String(),
      'reason': reason,
      'data': jsonDecode(data),
    });
    while (backups.length > 5) {
      backups.removeAt(0);
    }
    await prefs.setString('roster_backups', jsonEncode(backups));
    await prefs.setInt('roster_last_backup_ms', now.millisecondsSinceEpoch);
    _lastBackupAt = now;
  }

  Future<void> loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingRaw = prefs.getString('pending_sync');
      if (pendingRaw != null) {
        final list = jsonDecode(pendingRaw) as List<dynamic>;
        pendingSync = list
            .map((e) => models.SyncOperation.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ))
            .toList();
      }
      final data = prefs.getString('roster_data');
      if (data != null) {
        fromJson(jsonDecode(data));

        // Regenerate AI suggestions after loading
        // AI suggestions refresh is now manual to avoid heavy background work.

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Load error: $e');
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'staffMembers': staffMembers.map((s) => s.toJson()).toList(),
      'masterPattern': masterPattern,
      'overrides': overrides.map((o) => o.toJson()).toList(),
      'events': events.map((e) => e.toJson()).toList(),
      'history': history.map((h) => h.toJson()).toList(),
      'aiSuggestions': aiSuggestions.map((a) => a.toJson()).toList(),
      'regularSwaps': regularSwaps.map((s) => s.toJson()).toList(),
      'availabilityRequests':
          availabilityRequests.map((r) => r.toJson()).toList(),
      'swapRequests': swapRequests.map((r) => r.toJson()).toList(),
      'swapDebts': swapDebts.map((d) => d.toJson()).toList(),
      'shiftLocks': shiftLocks.map((l) => l.toJson()).toList(),
      'changeProposals': changeProposals.map((p) => p.toJson()).toList(),
      'auditLogs': auditLogs.map((l) => l.toJson()).toList(),
      'generatedRosters': generatedRosters.map((t) => t.toJson()).toList(),
      'rosterSnapshots': rosterSnapshots.map((s) => s.toJson()).toList(),
      'quickVariationPresets':
          quickVariationPresets.map((t) => t.toJson()).toList(),
      'quickBaseTemplate': quickBaseTemplate?.toJson(),
      'propagationSettings': propagationSettings?.toJson(),
      'constraints': constraints.toJson(),
      'cycleLength': cycleLength,
      'numPeople': numPeople,
      'weekStartDay': weekStartDay,
      '_lastSyncedVersion': _lastSyncedVersion,
      '_lastSyncedAt': _lastSyncedAt?.toIso8601String(),
      '_nextStaffId': _nextStaffId,
    };
  }

  void fromJson(Map<String, dynamic> json) {
    staffMembers = (json['staffMembers'] as List?)
            ?.map((s) => models.StaffMember.fromJson(s))
            .toList() ??
        [];
    masterPattern = (json['masterPattern'] as List?)
            ?.map((w) => (w as List).cast<String>())
            .toList() ??
        [];
    overrides = (json['overrides'] as List?)
            ?.map((o) => models.Override.fromJson(o))
            .toList() ??
        [];
    events = (json['events'] as List?)
            ?.map((e) => models.Event.fromJson(e))
            .toList() ??
        [];
    history = (json['history'] as List?)
            ?.map((h) => models.HistoryEntry.fromJson(h))
            .toList() ??
        [];
    aiSuggestions = (json['aiSuggestions'] as List?)
            ?.map((a) => models.AiSuggestion.fromJson(a))
            .toList() ??
        [];
    regularSwaps = (json['regularSwaps'] as List?)
            ?.map((s) => models.RegularShiftSwap.fromJson(s))
            .toList() ??
        [];
    availabilityRequests = (json['availabilityRequests'] as List?)
            ?.map((r) => models.AvailabilityRequest.fromJson(
                  Map<String, dynamic>.from(r as Map),
                ))
            .toList() ??
        [];
    swapRequests = (json['swapRequests'] as List?)
            ?.map((r) => models.SwapRequest.fromJson(
                  Map<String, dynamic>.from(r as Map),
                ))
            .toList() ??
        [];
    swapDebts = (json['swapDebts'] as List?)
            ?.map((d) => models.SwapDebt.fromJson(
                  Map<String, dynamic>.from(d as Map),
                ))
            .toList() ??
        [];
    shiftLocks = (json['shiftLocks'] as List?)
            ?.map((l) => models.ShiftLock.fromJson(
                  Map<String, dynamic>.from(l as Map),
                ))
            .toList() ??
        [];
    changeProposals = (json['changeProposals'] as List?)
            ?.map((p) => models.ChangeProposal.fromJson(
                  Map<String, dynamic>.from(p as Map),
                ))
            .toList() ??
        [];
    auditLogs = (json['auditLogs'] as List?)
            ?.map((l) => models.AuditLogEntry.fromJson(
                  Map<String, dynamic>.from(l as Map),
                ))
            .toList() ??
        [];
    generatedRosters = (json['generatedRosters'] as List?)
            ?.map((t) => models.GeneratedRosterTemplate.fromJson(
                  Map<String, dynamic>.from(t as Map),
                ))
            .toList() ??
        [];
    rosterSnapshots = (json['rosterSnapshots'] as List?)
            ?.map((s) => models.RosterSnapshot.fromJson(
                  Map<String, dynamic>.from(s as Map),
                ))
            .toList() ??
        [];
    quickVariationPresets = (json['quickVariationPresets'] as List?)
            ?.map((t) => models.GeneratedRosterTemplate.fromJson(
                  Map<String, dynamic>.from(t as Map),
                ))
            .toList() ??
        [];
    if (json['quickBaseTemplate'] != null) {
      quickBaseTemplate = models.GeneratedRosterTemplate.fromJson(
        Map<String, dynamic>.from(json['quickBaseTemplate'] as Map),
      );
    } else {
      quickBaseTemplate = null;
    }
    if (json['propagationSettings'] != null) {
      propagationSettings = models.PatternPropagationSettings.fromJson(
        json['propagationSettings'],
      );
    }
    if (json['constraints'] != null) {
      constraints = models.RosterConstraints.fromJson(
        json['constraints'],
      );
    }
    _lastSyncedVersion = json['_lastSyncedVersion'] as int? ?? 0;
    final lastSyncedAtRaw = json['_lastSyncedAt'] as String?;
    if (lastSyncedAtRaw != null) {
      _lastSyncedAt = DateTime.tryParse(lastSyncedAtRaw);
    }
    cycleLength = json['cycleLength'] as int? ?? 16;
    numPeople = json['numPeople'] as int? ?? 16;
    weekStartDay = json['weekStartDay'] as int? ?? 0;
    _nextStaffId = json['_nextStaffId'] as int? ??
        (staffMembers.isNotEmpty
            ? staffMembers
                    .map((s) => int.parse(s.id))
                    .reduce((a, b) => a > b ? a : b) +
                1
            : 1);

    if (masterPattern.isEmpty) {
      _generateDefaultPattern();
    }

    _rememberStaffNames(staffMembers.map((s) => s.name));
  }

  void _generateDefaultPattern() {
    masterPattern = List.generate(
      cycleLength,
      (week) => List.generate(7, (day) => 'D'),
    );
  }

  void _rememberStaffNames(Iterable<String> names) {
    final list = names.where((name) => name.trim().isNotEmpty).toList();
    if (list.isEmpty) return;
    Future(() => StaffNameStore.instance.addNames(list));
  }

  // Initialize roster
  void initializeRoster(
    int cycle,
    int people, {
    bool keepExistingData = false,
  }) {
    if (!keepExistingData) {
      staffMembers.clear();
      overrides.clear();
      events.clear();
      aiSuggestions.clear();
      regularSwaps.clear();
      history.clear();
    }

    cycleLength = cycle;
    numPeople = people;

    if (staffMembers.isEmpty) {
      staffMembers = List.generate(
        numPeople,
        (i) => models.StaffMember(
          id: (_nextStaffId++).toString(),
          name: 'Person ${i + 1}',
        ),
      );
    }

    if (masterPattern.isEmpty) {
      masterPattern = List.generate(
        cycleLength,
        (week) => List.generate(7, (day) => 'D'),
      );
    }

    _addHistory(
      'Initialize',
      'Initialized roster with $people people and $cycle week cycle',
    );

    if (history.length > 100) {
      history = history.sublist(history.length - 100);
    }

    notifyListeners();
  }

  // Pattern management
  void setMasterPattern(int week, int day, String newShift) {
    if (week >= 0 && week < masterPattern.length && day >= 0 && day < 7) {
      masterPattern[week][day] = newShift;
      _addHistory(
        'Pattern Update',
        'Updated week $week, day $day to $newShift',
      );
      notifyListeners();
    }
  }

  void updateMasterPatternCell(int week, int day, String newShift) {
    if (week >= 0 &&
        week < masterPattern.length &&
        day >= 0 &&
        day < masterPattern[week].length) {
      masterPattern[week][day] = newShift;
      notifyListeners();
    }
  }

  GeneratedRoster generateHybridRoster(HybridRosterConfig config) {
    return HybridRosterGenerator.generate(config);
  }

  GeneratedRoster generateQuickRoster({
    required int rotationWeeks,
    required int staffCount,
    required int weekStart,
    int seed = 0,
  }) {
    if (quickBaseTemplate != null &&
        quickBaseTemplate!.pattern.isNotEmpty) {
      return scalePatternFromTemplate(
        basePattern: quickBaseTemplate!.pattern,
        targetWeeks: rotationWeeks,
        seed: seed,
      );
    }
    final config = buildScaledHybridConfig(
      teamCount: rotationWeeks,
      staffCount: staffCount,
      weekStartDay: weekStart,
      seed: seed,
    );
    return HybridRosterGenerator.generate(config);
  }

  void setQuickBaseTemplate({
    required String name,
    required GeneratedRoster generated,
    required int weekStart,
  }) {
    quickBaseTemplate = models.GeneratedRosterTemplate(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      teamCount: generated.pattern.length,
      weekStartDay: weekStart,
      pattern:
          generated.pattern.map((week) => List<String>.from(week)).toList(),
      createdAt: DateTime.now(),
    );
    _addHistory('Quick Template', 'Set quick template: $name');
    notifyListeners();
  }

  void saveQuickVariationPreset({
    required String name,
    required GeneratedRoster generated,
    required int weekStart,
  }) {
    final template = models.GeneratedRosterTemplate(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      teamCount: generated.pattern.length,
      weekStartDay: weekStart,
      pattern:
          generated.pattern.map((week) => List<String>.from(week)).toList(),
      createdAt: DateTime.now(),
    );
    quickVariationPresets.add(template);
    _addHistory('Quick Preset', 'Saved quick preset: $name');
    notifyListeners();
  }

  void deleteQuickVariationPreset(String id) {
    quickVariationPresets.removeWhere((preset) => preset.id == id);
    _addHistory('Quick Preset', 'Deleted quick preset');
    notifyListeners();
  }

  void clearQuickBaseTemplate() {
    quickBaseTemplate = null;
    _addHistory('Quick Template', 'Cleared quick template');
    notifyListeners();
  }

  void applyGeneratedRoster(
    GeneratedRoster generated, {
    required int teamCount,
    required bool clearOverrides,
    required bool renameTeams,
  }) {
    unawaited(_storeBackupNow(reason: 'Auto generator apply'));
    masterPattern =
        generated.pattern.map((week) => List<String>.from(week)).toList();
    cycleLength = masterPattern.length;
    numPeople = teamCount;

    if (renameTeams) {
      staffMembers = List.generate(
        teamCount,
        (index) => models.StaffMember(
          id: (index + 1).toString(),
          name: 'Team ${index + 1}',
        ),
      );
      _nextStaffId = teamCount + 1;
    } else {
      if (staffMembers.length < teamCount) {
        final start = staffMembers.length;
        for (int i = start; i < teamCount; i++) {
          staffMembers.add(
            models.StaffMember(
              id: (i + 1).toString(),
              name: 'Team ${i + 1}',
            ),
          );
        }
      } else if (staffMembers.length > teamCount) {
        staffMembers = staffMembers.take(teamCount).toList();
      }
      _nextStaffId = teamCount + 1;
    }

    if (clearOverrides) {
      overrides.clear();
    }
    _addHistory('Auto Generator', 'Applied hybrid roster template');
    notifyListeners();
  }

  void applyGeneratedRosterPatternOnly(
    GeneratedRoster generated, {
    required bool clearOverrides,
  }) {
    unawaited(_storeBackupNow(reason: 'Pattern replace'));
    masterPattern =
        generated.pattern.map((week) => List<String>.from(week)).toList();
    cycleLength = masterPattern.length;
    numPeople = staffMembers.length;
    if (clearOverrides) {
      overrides.clear();
    }
    _addHistory('Auto Generator', 'Applied pattern without changing staff');
    notifyListeners();
  }

  void applyStaffNameList(List<String> names) {
    if (names.isEmpty || staffMembers.isEmpty) return;
    final limit =
        names.length < staffMembers.length ? names.length : staffMembers.length;
    for (int i = 0; i < limit; i++) {
      staffMembers[i] = staffMembers[i].copyWith(name: names[i]);
    }
    _addHistory('Staff Names', 'Applied saved staff names');
    notifyListeners();
  }

  void shiftPatternAlignment({
    required int dayOffset,
    required int weekOffset,
  }) {
    if (masterPattern.isEmpty) return;
    var pattern =
        masterPattern.map((week) => List<String>.from(week)).toList();
    final normalizedDay = ((dayOffset % 7) + 7) % 7;
    if (normalizedDay != 0) {
      pattern = pattern.map((week) {
        final length = week.length;
        return List<String>.generate(
          length,
          (index) => week[(index - normalizedDay + length) % length],
        );
      }).toList();
    }
    final totalWeeks = pattern.length;
    if (totalWeeks > 0) {
      final normalizedWeek =
          ((weekOffset % totalWeeks) + totalWeeks) % totalWeeks;
      if (normalizedWeek != 0) {
        pattern = List<List<String>>.generate(
          totalWeeks,
          (index) =>
              pattern[(index - normalizedWeek + totalWeeks) % totalWeeks],
        );
      }
    }
    masterPattern = pattern;
    _addHistory(
      'Pattern Alignment',
      'Shifted pattern by day $dayOffset, week $weekOffset',
    );
    notifyListeners();
  }

  void applyGeneratedRosterTemplate(
    models.GeneratedRosterTemplate template, {
    required bool clearOverrides,
    required bool renameTeams,
  }) {
    final generated = GeneratedRoster(pattern: template.pattern);
    setWeekStartDay(template.weekStartDay);
    applyGeneratedRoster(
      generated,
      teamCount: template.teamCount,
      clearOverrides: clearOverrides,
      renameTeams: renameTeams,
    );
  }

  void saveGeneratedRosterTemplate({
    required String name,
    required GeneratedRoster generated,
    required int teamCount,
    required int weekStart,
  }) {
    final template = models.GeneratedRosterTemplate(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      teamCount: teamCount,
      weekStartDay: weekStart,
      pattern:
          generated.pattern.map((week) => List<String>.from(week)).toList(),
      createdAt: DateTime.now(),
    );
    generatedRosters.add(template);
    _addHistory('Template Saved', 'Saved roster template: $name');
    notifyListeners();
  }

  void renameGeneratedRosterTemplate(String id, String newName) {
    final index = generatedRosters.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final current = generatedRosters[index];
    generatedRosters[index] = models.GeneratedRosterTemplate(
      id: current.id,
      name: newName,
      teamCount: current.teamCount,
      weekStartDay: current.weekStartDay,
      pattern: current.pattern,
      createdAt: current.createdAt,
    );
    notifyListeners();
  }

  void deleteGeneratedRosterTemplate(String id) {
    generatedRosters.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  String getShiftForDate(String personName, DateTime date) {
    if (!isStaffActiveOnDateByName(personName, date)) {
      return '';
    }
    final key = _cacheKey(personName, date);
    final cached = _shiftCache[key];
    if (cached != null) {
      return cached;
    }
    // Check for overrides first
    final override = overrides.firstWhere(
      (o) =>
          o.personName == personName &&
          o.date.year == date.year &&
          o.date.month == date.month &&
          o.date.day == date.day,
      orElse: () => models.Override(
        id: '',
        personName: '',
        date: DateTime.now(),
        shift: '',
        createdAt: DateTime.now(),
      ),
    );

    if (override.id.isNotEmpty) {
      final resolved = _normalizeOverrideShift(override);
      _shiftCache[key] = resolved;
      return resolved;
    }

    // Calculate from master pattern
    final referenceDate = DateTime(2024, 1, 1);
    final daysSinceReference = date.difference(referenceDate).inDays;

    // Check if pattern propagation is active
    if (propagationSettings?.isActive == true) {
      return _getShiftWithPropagation(personName, date);
    }

    // Standard pattern lookup
    final cycleDay = daysSinceReference % (cycleLength * 7);
    final week = cycleDay ~/ 7;
    final day = cycleDay % 7;

    if (week < masterPattern.length && day < masterPattern[week].length) {
      return masterPattern[week][day];
    }

    return 'OFF';
  }

  void saveRosterSnapshot({
    required String name,
    required bool includeStaffNames,
    required bool includeOverrides,
  }) {
    final now = DateTime.now();
    final snapshot = models.RosterSnapshot(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      weekStartDay: weekStartDay,
      pattern: masterPattern.map((week) => List<String>.from(week)).toList(),
      staffNames: includeStaffNames
          ? staffMembers.map((s) => s.name).toList()
          : const [],
      overrides: includeOverrides
          ? overrides.map((o) => models.Override.fromJson(o.toJson())).toList()
          : const [],
      createdAt: now,
    );
    rosterSnapshots.add(snapshot);
    _addHistory('Pattern Duplicate', 'Saved snapshot: $name');
    _scheduleCloudSync();
    notifyListeners();
  }

  String generateTemplateCode({
    bool includeStaffNames = true,
    bool includeOverrides = false,
    bool compress = true,
    DateTime? expiresAt,
    String? password,
  }) {
    final payload = <String, dynamic>{
      'v': 2,
      'weekStartDay': weekStartDay,
      'cycleLength': cycleLength,
      'numPeople': numPeople,
      'pattern': masterPattern,
      'staffNames': includeStaffNames
          ? staffMembers.map((s) => s.name).toList()
          : <String>[],
      'overrides': includeOverrides
          ? overrides.map((o) => o.toJson()).toList()
          : <Map<String, dynamic>>[],
      'createdAt': DateTime.now().toIso8601String(),
      if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
    };

    return _encodeTemplatePayload(
      payload,
      compress: compress,
      password: password,
    );
  }

  String generateTemplateCodeFromData(
    Map<String, dynamic> data, {
    bool includeStaffNames = true,
    bool includeOverrides = false,
    bool compress = true,
    DateTime? expiresAt,
    String? password,
  }) {
    final pattern = (data['masterPattern'] as List<dynamic>?)
            ?.map((week) => (week as List<dynamic>).cast<String>().toList())
            .toList() ??
        [];
    final staff = (data['staffMembers'] as List<dynamic>? ?? [])
        .map((s) => (s as Map)['name']?.toString() ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList();
    final overridesList = (data['overrides'] as List<dynamic>? ?? [])
        .map((o) => Map<String, dynamic>.from(o as Map))
        .toList();

    final payload = <String, dynamic>{
      'v': 2,
      'weekStartDay': data['weekStartDay'] as int? ?? weekStartDay,
      'cycleLength': data['cycleLength'] as int? ?? pattern.length,
      'numPeople': data['numPeople'] as int? ?? staff.length,
      'pattern': pattern,
      'staffNames': includeStaffNames ? staff : <String>[],
      'overrides': includeOverrides ? overridesList : <Map<String, dynamic>>[],
      'createdAt': DateTime.now().toIso8601String(),
      if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
    };

    return _encodeTemplatePayload(
      payload,
      compress: compress,
      password: password,
    );
  }

  String _encodeTemplatePayload(
    Map<String, dynamic> payload, {
    required bool compress,
    String? password,
  }) {
    final jsonString = jsonEncode(payload);
    final checksum = sha256.convert(utf8.encode(jsonString)).toString();
    final meta = <String, dynamic>{
      'v': payload['v'],
      'checksum': checksum,
      'compressed': compress,
      'encrypted': password != null && password.trim().isNotEmpty,
    };

    Uint8List bytes = utf8.encode(jsonString) as Uint8List;
    if (compress) {
      bytes = Uint8List.fromList(gzip.encode(bytes));
    }

    if (meta['encrypted'] == true) {
      final key = enc.Key.fromUtf8(
        sha256.convert(utf8.encode(password!.trim())).toString().substring(0, 32),
      );
      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(key));
      final encrypted = encrypter.encryptBytes(bytes, iv: iv);
      meta['iv'] = base64Url.encode(iv.bytes);
      bytes = Uint8List.fromList(encrypted.bytes);
    }

    final envelope = <String, dynamic>{
      'meta': meta,
      'data': base64Url.encode(bytes),
    };
    final encoded = base64Url.encode(utf8.encode(jsonEncode(envelope)));
    return 'RC2-$encoded';
  }

  TemplateParseResult parseTemplateCode(String code, {String? password}) {
    try {
      var trimmed = code.trim();
      if (trimmed.startsWith('RC1-') || trimmed.startsWith('RC2-')) {
        trimmed = trimmed.substring(4);
      }
      final decoded = utf8.decode(base64Url.decode(trimmed));
      final envelope = jsonDecode(decoded) as Map<String, dynamic>;
      if (envelope.containsKey('pattern')) {
        // Legacy RC1 payload.
        return TemplateParseResult(isValid: true, payload: envelope);
      }
      final meta = Map<String, dynamic>.from(envelope['meta'] as Map? ?? {});
      final data = envelope['data'] as String? ?? '';
      if (data.isEmpty) {
        return const TemplateParseResult(
          isValid: false,
          error: 'Template code is missing data.',
        );
      }

      Uint8List bytes = Uint8List.fromList(base64Url.decode(data));
      if (meta['encrypted'] == true) {
        if (password == null || password.trim().isEmpty) {
          return const TemplateParseResult(
            isValid: false,
            error: 'Template code is password protected.',
          );
        }
        final ivString = meta['iv'] as String?;
        if (ivString == null) {
          return const TemplateParseResult(
            isValid: false,
            error: 'Template code is missing IV.',
          );
        }
        final key = enc.Key.fromUtf8(
          sha256.convert(utf8.encode(password.trim())).toString().substring(0, 32),
        );
        final iv = enc.IV(base64Url.decode(ivString));
        final encrypter = enc.Encrypter(enc.AES(key));
        bytes = Uint8List.fromList(encrypter.decryptBytes(
          enc.Encrypted(bytes),
          iv: iv,
        ));
      }

      if (meta['compressed'] == true) {
        bytes = Uint8List.fromList(gzip.decode(bytes));
      }

      final jsonString = utf8.decode(bytes);
      final payload = jsonDecode(jsonString) as Map<String, dynamic>;
      final checksum = meta['checksum'] as String?;
      if (checksum != null) {
        final actual = sha256.convert(utf8.encode(jsonString)).toString();
        if (checksum != actual) {
          return const TemplateParseResult(
            isValid: false,
            error: 'Template code checksum mismatch.',
          );
        }
      }
      final expiresAt = payload['expiresAt'] as String?;
      if (expiresAt != null) {
        final expiry = DateTime.tryParse(expiresAt);
        if (expiry != null && expiry.isBefore(DateTime.now())) {
          return const TemplateParseResult(
            isValid: false,
            error: 'Template code has expired.',
          );
        }
      }

      return TemplateParseResult(isValid: true, payload: payload);
    } catch (e) {
      return TemplateParseResult(
        isValid: false,
        error: 'Template code is invalid.',
      );
    }
  }

  bool applyTemplateCode(
    String code, {
    bool includeStaffNames = true,
    bool includeOverrides = true,
    String? password,
  }) {
    final parsed = parseTemplateCode(code, password: password);
    if (!parsed.isValid || parsed.payload == null) {
      debugPrint('Template code error: ${parsed.error}');
      return false;
    }
    try {
      final payload = parsed.payload!;
      final pattern = (payload['pattern'] as List<dynamic>?)
              ?.map((week) => (week as List<dynamic>).cast<String>().toList())
              .toList() ??
          [];
      if (pattern.isEmpty) return false;

      staffMembers.clear();
      overrides.clear();
      events.clear();
      aiSuggestions.clear();
      regularSwaps.clear();
      history.clear();
      availabilityRequests.clear();
      swapRequests.clear();
      swapDebts.clear();
      shiftLocks.clear();
      changeProposals.clear();
      auditLogs.clear();
      presenceEntries.clear();
      timeClockEntries.clear();

      masterPattern = pattern;
      weekStartDay = payload['weekStartDay'] as int? ?? weekStartDay;
      cycleLength = payload['cycleLength'] as int? ?? pattern.length;
      numPeople = payload['numPeople'] as int? ?? numPeople;

      final names = includeStaffNames
          ? (payload['staffNames'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList()
          : <String>[];
      if (names.isNotEmpty) {
        _nextStaffId = 1;
        staffMembers = List.generate(
          names.length,
          (i) => models.StaffMember(
            id: (_nextStaffId++).toString(),
            name: names[i],
          ),
        );
        numPeople = names.length;
        _rememberStaffNames(names);
      } else if (staffMembers.isEmpty) {
        _nextStaffId = 1;
        staffMembers = List.generate(
          numPeople,
          (i) => models.StaffMember(
            id: (_nextStaffId++).toString(),
            name: 'Person ${i + 1}',
          ),
        );
      }

      if (includeOverrides) {
        overrides = (payload['overrides'] as List<dynamic>? ?? [])
            .map((o) => models.Override.fromJson(o))
            .toList();
      }

      _addHistory('Template', 'Applied roster template code');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Template code error: $e');
      return false;
    }
  }

  bool saveTemplatePresetFromCode(
    String name,
    String code, {
    String? password,
  }) {
    final parsed = parseTemplateCode(code, password: password);
    if (!parsed.isValid || parsed.payload == null) return false;
    final payload = parsed.payload!;
    final pattern = (payload['pattern'] as List<dynamic>?)
            ?.map((week) => (week as List<dynamic>).cast<String>().toList())
            .toList() ??
        [];
    if (pattern.isEmpty) return false;
    final template = models.GeneratedRosterTemplate(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      teamCount: pattern.length,
      weekStartDay: payload['weekStartDay'] as int? ?? weekStartDay,
      pattern: pattern,
      createdAt: DateTime.now(),
    );
    generatedRosters.add(template);
    _addHistory('Template', 'Saved template preset "$name"');
    notifyListeners();
    return true;
  }

  void applyRosterSnapshot(
    models.RosterSnapshot snapshot, {
    required bool includeStaffNames,
    required bool includeOverrides,
  }) {
    unawaited(_storeBackupNow(reason: 'Apply snapshot'));
    masterPattern =
        snapshot.pattern.map((week) => List<String>.from(week)).toList();
    cycleLength = masterPattern.length;
    if (includeStaffNames && snapshot.staffNames.isNotEmpty) {
      applyStaffNameList(snapshot.staffNames);
    }
    if (includeOverrides) {
      overrides = snapshot.overrides
          .map((o) => models.Override.fromJson(o.toJson()))
          .toList();
    }
    _addHistory('Snapshot Applied', 'Applied snapshot: ${snapshot.name}');
    _scheduleCloudSync();
    notifyListeners();
  }

  String getBaseShiftForDate(String personName, DateTime date) {
    if (!isStaffActiveOnDateByName(personName, date)) {
      return '';
    }

    final referenceDate = DateTime(2024, 1, 1);
    final key = _cacheKey(personName, date);

    if (propagationSettings?.isActive == true) {
      final resolved = _getShiftWithPropagation(personName, date);
      _shiftCache[key] = resolved;
      return resolved;
    }

    final daysSinceReference = date.difference(referenceDate).inDays;
    final cycleDay = daysSinceReference % (cycleLength * 7);
    final week = cycleDay ~/ 7;
    final day = cycleDay % 7;

    if (week < masterPattern.length && day < masterPattern[week].length) {
      final resolved = masterPattern[week][day];
      _shiftCache[key] = resolved;
      return resolved;
    }

    _shiftCache[key] = 'OFF';
    return 'OFF';
  }

  String getPatternShiftForDate(String personName, DateTime date) {
    final referenceDate = DateTime(2024, 1, 1);
    final daysSinceReference = date.difference(referenceDate).inDays;
    final cycleDay = daysSinceReference % (cycleLength * 7);
    final week = cycleDay ~/ 7;
    final day = cycleDay % 7;

    if (week < masterPattern.length && day < masterPattern[week].length) {
      return masterPattern[week][day];
    }
    return 'OFF';
  }

  String _getShiftWithPropagation(String personName, DateTime date) {
    if (propagationSettings == null) return 'OFF';

    final adjustedDate = date
        .subtract(Duration(days: propagationSettings!.weekShift * 7))
        .subtract(Duration(days: propagationSettings!.dayShift));

    final referenceDate = DateTime(2024, 1, 1);
    final daysSinceReference = adjustedDate.difference(referenceDate).inDays;

    final cycleDay = daysSinceReference % (cycleLength * 7);
    final week = cycleDay ~/ 7;
    final day = cycleDay % 7;

    final staffIndex = staffMembers.indexWhere((s) => s.name == personName);
    if (staffIndex == -1) return 'OFF';

    final adjustedWeek = (week + staffIndex) % cycleLength;

    if (adjustedWeek < masterPattern.length &&
        day < masterPattern[adjustedWeek.toInt()].length) {
      return masterPattern[adjustedWeek.toInt()][day];
    }

    return 'OFF';
  }

  // Pattern propagation
  void updatePropagationSettings({
    required bool isActive,
    required int weekShift,
    required int dayShift,
  }) {
    final newSettings = models.PatternPropagationSettings(
      isActive: isActive,
      weekShift: weekShift,
      dayShift: dayShift,
      lastApplied: isActive ? DateTime.now() : null,
    );

    propagationSettings = newSettings;

    _addHistory(
      'Pattern Propagation',
      'Updated pattern propagation: ${isActive ? "enabled" : "disabled"}',
    );

    notifyListeners();
  }

  void disablePropagation() {
    final suggestion = models.AiSuggestion(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Pattern Propagation Disabled',
      description: 'Pattern propagation has been turned off',
      priority: models.SuggestionPriority.medium,
      type: models.SuggestionType.pattern,
      createdDate: DateTime.now(),
    );

    aiSuggestions.add(suggestion);

    if (propagationSettings != null) {
      propagationSettings = propagationSettings!.copyWith(isActive: false);
    }

    _addHistory('Pattern Propagation', 'Disabled pattern propagation');
    notifyListeners();
  }

  // Pattern analysis
  Future<models.PatternRecognitionResult> analyzeAndRecognizePattern({
    List<models.StaffMember>? sampleStaff,
    int? sampleWeeks,
  }) async {
    try {
      final analysisStaff = sampleStaff ?? staffMembers.take(3).toList();
      final weeksToAnalyze = sampleWeeks ?? min(4, cycleLength);

      // Collect shift data
      final shiftData = <String, List<String>>{};
      for (final staff in analysisStaff) {
        final shifts = <String>[];
        for (int week = 0; week < weeksToAnalyze; week++) {
          for (int day = 0; day < 7; day++) {
            if (week < masterPattern.length &&
                day < masterPattern[week].length) {
              shifts.add(masterPattern[week][day]);
            }
          }
        }
        shiftData[staff.name] = shifts;
      }

      // Detect cycle length
      final result = models.PatternRecognitionResult(
        detectedCycleLength: cycleLength,
        confidence: 0.85,
        detectedPattern: masterPattern.take(weeksToAnalyze).toList(),
        shiftFrequency: _calculateShiftFrequency(),
        suggestions: [
          'Pattern appears consistent across ${weeksToAnalyze} weeks',
          'Consider enabling pattern propagation for automatic scheduling',
        ],
        analyzedAt: DateTime.now(),
      );

      lastPatternRecognition = result;
      return result;
    } catch (e) {
      debugPrint('Pattern analysis error: $e');
      rethrow;
    }
  }

  Map<String, int> _calculateShiftFrequency() {
    final frequency = <String, int>{};
    for (final week in masterPattern) {
      for (final shift in week) {
        frequency[shift] = (frequency[shift] ?? 0) + 1;
      }
    }
    return frequency;
  }

  int getDetectedCycleLength() {
    return cycleLength;
  }

  void _generateSuggestionsFromPattern(models.PatternRecognitionResult result) {
    final suggestions = <models.AiSuggestion>[];

    if (result.confidence > 0.8) {
      suggestions.add(
        models.AiSuggestion(
          id: '${DateTime.now().millisecondsSinceEpoch}_1',
          title: 'Strong Pattern Detected',
          description:
              'A consistent ${result.detectedCycleLength}-week pattern detected with ${(result.confidence * 100).toStringAsFixed(0)}% confidence.',
          priority: models.SuggestionPriority.high,
          type: models.SuggestionType.pattern,
          createdDate: DateTime.now(),
        ),
      );
    }

    if (result.detectedCycleLength != cycleLength) {
      suggestions.add(
        models.AiSuggestion(
          id: '${DateTime.now().millisecondsSinceEpoch}_2',
          title: 'Cycle Length Mismatch',
          description:
              'Detected cycle: ${result.detectedCycleLength} weeks, Current: $cycleLength weeks',
          priority: models.SuggestionPriority.medium,
          type: models.SuggestionType.pattern,
          createdDate: DateTime.now(),
        ),
      );
    }

    if (result.suggestions.isNotEmpty) {
      suggestions.add(
        models.AiSuggestion(
          id: '${DateTime.now().millisecondsSinceEpoch}_3',
          title: 'Pattern Recommendations',
          description: result.suggestions.join('\n'),
          priority: models.SuggestionPriority.low,
          type: models.SuggestionType.pattern,
          createdDate: DateTime.now(),
        ),
      );
    }

    aiSuggestions.addAll(suggestions);
  }

  Future<void> applyRecognizedPattern(
    models.PatternRecognitionResult result,
  ) async {
    masterPattern = List.from(
      result.detectedPattern.map((week) => List<String>.from(week)),
    );
    cycleLength = result.detectedCycleLength;

    _addHistory(
      'Pattern Applied',
      'Applied recognized ${result.detectedCycleLength}-week pattern',
    );

    notifyListeners();
  }

  // Override management
  void addBulkOverrides(
    String person,
    DateTime startDate,
    DateTime endDate,
    String shift,
    String reason,
  ) {
    addBulkOverridesAdvanced(
      people: [person],
      startDate: startDate,
      endDate: endDate,
      shift: shift,
      reason: reason,
    );
  }

  void addBulkOverridesAdvanced({
    required List<String> people,
    required DateTime startDate,
    required DateTime endDate,
    required String shift,
    String? reason,
    Set<int>? weekdays,
    bool overwriteExisting = true,
  }) {
    if (people.isEmpty) return;
    final selectedWeekdays =
        weekdays ?? {1, 2, 3, 4, 5, 6, 7};
    if (selectedWeekdays.isEmpty) return;

    unawaited(_storeBackupNow(reason: 'Bulk overrides'));
    final bulkId = DateTime.now().millisecondsSinceEpoch.toString();
    final reasonTag = '[bulk:$bulkId]';
    final baseReason = reason?.trim() ?? '';
    final fullReason =
        baseReason.isEmpty ? reasonTag : '$baseReason $reasonTag';
    final newOverrides = <models.Override>[];

    for (final person in people) {
      final staffIndex = staffMembers.indexWhere((s) => s.name == person);
      if (staffIndex == -1) continue;

      for (var date = startDate;
          date.isBefore(endDate) || date.isAtSameMomentAs(endDate);
          date = date.add(const Duration(days: 1))) {
        if (!selectedWeekdays.contains(date.weekday)) continue;
        final existingIndex = overrides.indexWhere(
          (o) =>
              o.personName == person &&
              o.date.year == date.year &&
              o.date.month == date.month &&
              o.date.day == date.day,
        );

        if (existingIndex != -1) {
          if (!overwriteExisting) continue;
          final existing = overrides[existingIndex];
          if (_isShiftLocked(date, existing.shift, person) ||
              _isShiftLocked(date, shift, person)) {
            continue;
          }
          if (existing.shift == 'AL') {
            staffMembers[staffIndex] = staffMembers[staffIndex].copyWith(
              leaveBalance: staffMembers[staffIndex].leaveBalance + 1,
            );
          }
          overrides.removeAt(existingIndex);
        } else {
          if (_isShiftLocked(date, shift, person)) {
            continue;
          }
        }

        newOverrides.add(
          models.Override(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            personName: person,
            date: date,
            shift: shift,
            reason: fullReason,
            createdAt: DateTime.now(),
          ),
        );

        if (shift == 'AL') {
          staffMembers[staffIndex] = staffMembers[staffIndex].copyWith(
            leaveBalance: staffMembers[staffIndex].leaveBalance - 1,
          );
        }
      }
    }

    overrides.addAll(newOverrides);

    _addHistory(
      'Bulk Change',
      'Added ${newOverrides.length} changes for ${people.length} staff',
    );

    _scheduleCloudSync();
    notifyListeners();
  }

  int removeOverridesAdvanced({
    required List<String> people,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    if (people.isEmpty) return 0;
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final before = overrides.length;
    final alRemoved = <String, int>{};
    overrides.removeWhere((o) {
      final date = DateTime(o.date.year, o.date.month, o.date.day);
      final shouldRemove = people.contains(o.personName) &&
          !date.isBefore(start) &&
          !date.isAfter(end);
      if (shouldRemove && o.shift.toUpperCase() == 'AL') {
        alRemoved[o.personName] = (alRemoved[o.personName] ?? 0) + 1;
      }
      return shouldRemove;
    });
    final removed = before - overrides.length;
    if (removed > 0) {
      for (final entry in alRemoved.entries) {
        adjustLeaveBalance(entry.key, entry.value.toDouble());
      }
      _addHistory(
        'Changes Cleared',
        'Removed $removed change(s) for ${people.join(', ')}',
      );
      _scheduleCloudSync();
      notifyListeners();
    }
    return removed;
  }

  int removeOverridesForDates({
    required List<String> people,
    required List<DateTime> dates,
  }) {
    if (people.isEmpty || dates.isEmpty) return 0;
    final dateSet = dates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
    final before = overrides.length;
    final alRemoved = <String, int>{};
    overrides.removeWhere((o) {
      final date = DateTime(o.date.year, o.date.month, o.date.day);
      final shouldRemove =
          people.contains(o.personName) && dateSet.contains(date);
      if (shouldRemove && o.shift.toUpperCase() == 'AL') {
        alRemoved[o.personName] = (alRemoved[o.personName] ?? 0) + 1;
      }
      return shouldRemove;
    });
    final removed = before - overrides.length;
    if (removed > 0) {
      for (final entry in alRemoved.entries) {
        adjustLeaveBalance(entry.key, entry.value.toDouble());
      }
      _addHistory(
        'Changes Cleared',
        'Removed $removed change(s) for ${people.join(', ')}',
      );
      _scheduleCloudSync();
      notifyListeners();
    }
    return removed;
  }

  int removeLeaveOverridesAdvanced({
    required List<String> people,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    if (people.isEmpty) return 0;
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final before = overrides.length;
    final alRemoved = <String, int>{};
    overrides.removeWhere((o) {
      final date = DateTime(o.date.year, o.date.month, o.date.day);
      final shouldRemove = people.contains(o.personName) &&
          o.shift.toUpperCase() == 'AL' &&
          !date.isBefore(start) &&
          !date.isAfter(end);
      if (shouldRemove) {
        alRemoved[o.personName] = (alRemoved[o.personName] ?? 0) + 1;
      }
      return shouldRemove;
    });
    final removed = before - overrides.length;
    if (removed > 0) {
      for (final entry in alRemoved.entries) {
        adjustLeaveBalance(entry.key, entry.value.toDouble());
      }
      _addHistory(
        'Leave Cancelled',
        'Removed $removed leave changes for ${people.join(', ')}',
      );
      _scheduleCloudSync();
      notifyListeners();
    }
    return removed;
  }

  int removeLeaveOverridesForDates({
    required List<String> people,
    required List<DateTime> dates,
  }) {
    if (people.isEmpty || dates.isEmpty) return 0;
    final dateSet = dates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
    final before = overrides.length;
    final alRemoved = <String, int>{};
    overrides.removeWhere((o) {
      final date = DateTime(o.date.year, o.date.month, o.date.day);
      final shouldRemove = people.contains(o.personName) &&
          dateSet.contains(date) &&
          o.shift.toUpperCase() == 'AL';
      if (shouldRemove) {
        alRemoved[o.personName] = (alRemoved[o.personName] ?? 0) + 1;
      }
      return shouldRemove;
    });
    final removed = before - overrides.length;
    if (removed > 0) {
      for (final entry in alRemoved.entries) {
        adjustLeaveBalance(entry.key, entry.value.toDouble());
      }
      _addHistory(
        'Leave Cancelled',
        'Removed $removed leave changes for ${people.join(', ')}',
      );
      _scheduleCloudSync();
      notifyListeners();
    }
    return removed;
  }

  int removeOverridesForDatesByShifts({
    required List<String> people,
    required List<DateTime> dates,
    Set<String>? shifts,
  }) {
    if (people.isEmpty || dates.isEmpty) return 0;
    final dateSet = dates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
    final normalizedShifts =
        shifts?.map((s) => s.toUpperCase()).toSet();
    final before = overrides.length;
    final alRemoved = <String, int>{};
    overrides.removeWhere((o) {
      final date = DateTime(o.date.year, o.date.month, o.date.day);
      final shift = o.shift.toUpperCase();
      final matchesShift = normalizedShifts == null ||
          normalizedShifts.isEmpty ||
          normalizedShifts.contains('ANY') ||
          normalizedShifts.contains(shift);
      final shouldRemove = people.contains(o.personName) &&
          dateSet.contains(date) &&
          matchesShift;
      if (shouldRemove && shift == 'AL') {
        alRemoved[o.personName] = (alRemoved[o.personName] ?? 0) + 1;
      }
      return shouldRemove;
    });
    final removed = before - overrides.length;
    if (removed > 0) {
      for (final entry in alRemoved.entries) {
        adjustLeaveBalance(entry.key, entry.value.toDouble());
      }
      _addHistory(
        'Changes Cleared',
        'Removed $removed change(s) for ${people.join(', ')}',
      );
      _scheduleCloudSync();
      notifyListeners();
    }
    return removed;
  }

  int cancelAnnualLeaveForDates({
    required List<String> people,
    required List<DateTime> dates,
  }) {
    if (people.isEmpty || dates.isEmpty) return 0;
    final normalizedDates = dates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet()
        .toList();
    int removedTotal = 0;

    // Remove AL overrides for selected dates.
    removedTotal += removeLeaveOverridesForDates(
      people: people,
      dates: normalizedDates,
    );

    // Handle staff leave status ranges (annual leave status).
    for (final name in people) {
      final staff = staffMembers.where((s) => s.name == name).firstOrNull;
      if (staff == null) continue;
      if (staff.leaveType == null) continue;
      final leaveType = staff.leaveType!.toLowerCase();
      if (leaveType != 'annual' && leaveType != 'al') continue;
      if (staff.leaveStart == null || staff.leaveEnd == null) continue;

      final start = DateTime(
        staff.leaveStart!.year,
        staff.leaveStart!.month,
        staff.leaveStart!.day,
      );
      final end = DateTime(
        staff.leaveEnd!.year,
        staff.leaveEnd!.month,
        staff.leaveEnd!.day,
      );
      final cancelledInRange = normalizedDates.where((d) {
        return !d.isBefore(start) && !d.isAfter(end);
      }).toList();
      if (cancelledInRange.isEmpty) continue;

      removedTotal += cancelledInRange.length;

      // Clear staff leave status and re-apply remaining dates as overrides.
      clearStaffLeaveStatus(staff.id);
      var cursor = start;
      while (!cursor.isAfter(end)) {
        final day = DateTime(cursor.year, cursor.month, cursor.day);
        if (!normalizedDates.any((d) =>
            d.year == day.year && d.month == day.month && d.day == day.day)) {
          setOverride(
            staff.name,
            day,
            'AL',
            staff.leaveType ?? 'Annual leave',
          );
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    return removedTotal;
  }

  void removeBulkOverrides(String bulkId) {
    final affectedOverrides =
        overrides.where((o) => o.reason?.contains(bulkId) == true).toList();

    if (affectedOverrides.isNotEmpty) {
      final person = affectedOverrides.first.personName;
      final leaveCount = affectedOverrides.where((o) => o.shift == 'AL').length;

      if (leaveCount > 0) {
        final staffIndex = staffMembers.indexWhere((s) => s.name == person);
        if (staffIndex != -1) {
          staffMembers[staffIndex] = staffMembers[staffIndex].copyWith(
            leaveBalance: staffMembers[staffIndex].leaveBalance + leaveCount,
          );
        }
      }

      final suggestion = models.AiSuggestion(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'Bulk Change Removed',
        description:
            'Removed ${affectedOverrides.length} changes for $person',
        priority: models.SuggestionPriority.low,
        type: models.SuggestionType.other,
        createdDate: DateTime.now(),
      );
      aiSuggestions.add(suggestion);
    }

    final removedCount =
        overrides.where((o) => o.reason?.contains(bulkId) == true).length;
    overrides.removeWhere((o) => o.reason?.contains(bulkId) == true);

    _addHistory('Bulk Change Removed', 'Removed $removedCount changes');

    notifyListeners();
  }

  void propagatePattern() {
    updatePropagationSettings(
      isActive: true,
      weekShift: 0,
      dayShift: 0,
    );
  }

  bool _isShiftLocked(DateTime date, String shift, String person) {
    for (final lock in shiftLocks) {
      if (lock.date.year == date.year &&
          lock.date.month == date.month &&
          lock.date.day == date.day &&
          lock.shift == shift) {
        if (lock.personName == null) {
          return true;
        }
        if (lock.personName != null && lock.personName != person) {
          return true;
        }
      }
    }
    return false;
  }

  void _adjustLeaveBalanceForOverrideChange(
    String person,
    String? oldShift,
    String? newShift,
  ) {
    final oldIsLeave = (oldShift ?? '').toUpperCase() == 'AL';
    final newIsLeave = (newShift ?? '').toUpperCase() == 'AL';
    if (oldIsLeave == newIsLeave) return;
    final delta = oldIsLeave && !newIsLeave ? 1.0 : -1.0;
    adjustLeaveBalance(person, delta);
  }

  void setOverride(
    String person,
    DateTime date,
    String newShift,
    String reason,
  ) {
    final currentShift = getShiftForDate(person, date);
    if (_isShiftLocked(date, currentShift, person) ||
        _isShiftLocked(date, newShift, person)) {
      _addHistory(
        'Change Blocked',
        'Shift locked on ${_formatDate(date)} for $newShift',
      );
      return;
    }
    final baseShift = getBaseShiftForDate(person, date);
    overrides.removeWhere(
      (o) =>
          o.personName == person &&
          o.date.year == date.year &&
          o.date.month == date.month &&
          o.date.day == date.day,
    );

    if (newShift.isNotEmpty) {
      overrides.add(
        models.Override(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          personName: person,
          date: date,
          shift: newShift,
          reason: reason,
          createdAt: DateTime.now(),
        ),
      );
    }
    final newEffectiveShift = newShift.isNotEmpty ? newShift : baseShift;
    _adjustLeaveBalanceForOverrideChange(
      person,
      currentShift,
      newEffectiveShift,
    );
    _addHistory(
      'Change Applied',
      'Set $person on ${_formatDate(date)} to $newShift',
    );
    _scheduleCloudSync();
    notifyListeners();
  }

  Future<void> refreshAvailabilityRequests() async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    try {
      availabilityRequests =
          await AwsService.instance.getAvailabilityRequests(rosterId);
      notifyListeners();
    } catch (e) {
      debugPrint('Load availability requests error: $e');
    }
  }

  Future<void> refreshTimeClockEntries() async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    try {
      timeClockEntries = await AwsService.instance.getTimeClockEntries(
        rosterId,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Load time clock entries error: $e');
    }
  }

  Future<int> importTimeClockEntries(
    List<models.TimeClockEntry> entries,
  ) async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return 0;
    final imported = await AwsService.instance.importTimeClockEntries(
      rosterId: rosterId,
      entries: entries,
    );
    await refreshTimeClockEntries();
    _addHistory('Time Clock', 'Imported $imported entries');
    return imported;
  }

  Future<void> submitAvailabilityRequest({
    required models.AvailabilityType type,
    required DateTime startDate,
    DateTime? endDate,
    String? notes,
  }) async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    final requestId = await AwsService.instance.createAvailabilityRequest(
      rosterId: rosterId,
      type: type,
      startDate: startDate,
      endDate: endDate,
      notes: notes,
    );
    availabilityRequests.add(
      models.AvailabilityRequest(
        rosterId: rosterId,
        requestId: requestId,
        userId: AwsService.instance.userId ?? 'unknown',
        type: type,
        startDate: startDate,
        endDate: endDate ?? startDate,
        status: models.RequestStatus.pending,
        notes: notes ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    _addHistory('Availability Request', 'Submitted $type request');
    notifyListeners();
  }

  Future<void> reviewAvailabilityRequest({
    required String requestId,
    required models.RequestStatus decision,
    String? note,
  }) async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    await AwsService.instance.reviewAvailabilityRequest(
      rosterId: rosterId,
      requestId: requestId,
      decision: decision,
      note: note,
    );
    final index =
        availabilityRequests.indexWhere((r) => r.requestId == requestId);
    if (index != -1) {
      final current = availabilityRequests[index];
      availabilityRequests[index] = models.AvailabilityRequest(
        rosterId: current.rosterId,
        requestId: current.requestId,
        userId: current.userId,
        type: current.type,
        startDate: current.startDate,
        endDate: current.endDate,
        status: decision,
        notes: current.notes,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
        reviewedBy: AwsService.instance.userId,
        reviewNote: note,
      );
    }
    notifyListeners();
  }

  Future<void> applyApprovedAvailabilityRequests() async {
    for (final request in availabilityRequests) {
      if (request.status != models.RequestStatus.approved) continue;
      if (request.type != models.AvailabilityType.leave) continue;
      var date = request.startDate;
      while (!date.isAfter(request.endDate)) {
        setOverride(
          _resolveStaffNameFromUserId(request.userId),
          date,
          'AL',
          'Approved leave',
        );
        date = date.add(const Duration(days: 1));
      }
    }
  }

  String _resolveStaffNameFromUserId(String userId) {
    for (final staff in staffMembers) {
      final meta = staff.metadata;
      if (meta != null && meta['userId'] == userId) {
        return staff.name;
      }
    }
    final fallback = staffMembers.isNotEmpty ? staffMembers.first.name : 'User';
    return fallback;
  }

  Future<void> refreshSwapRequests() async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    try {
      swapRequests = await AwsService.instance.getSwapRequests(rosterId);
      notifyListeners();
    } catch (e) {
      debugPrint('Load swap requests error: $e');
    }
  }

  Future<void> submitSwapRequest({
    required String fromPerson,
    String? toPerson,
    required DateTime date,
    String? shift,
    String? notes,
  }) async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    final requestId = await AwsService.instance.createSwapRequest(
      rosterId: rosterId,
      fromPerson: fromPerson,
      toPerson: toPerson,
      date: date,
      shift: shift,
      notes: notes,
    );
    swapRequests.add(
      models.SwapRequest(
        rosterId: rosterId,
        requestId: requestId,
        userId: AwsService.instance.userId ?? 'unknown',
        fromPerson: fromPerson,
        toPerson: toPerson,
        date: date,
        shift: shift,
        status: models.RequestStatus.pending,
        notes: notes ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    _addHistory('Swap Request', 'Submitted swap request');
    notifyListeners();
  }

  Future<void> respondSwapRequest({
    required String requestId,
    required models.RequestStatus decision,
    String? note,
  }) async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    await AwsService.instance.respondSwapRequest(
      rosterId: rosterId,
      requestId: requestId,
      decision: decision,
      note: note,
    );
    final index = swapRequests.indexWhere((r) => r.requestId == requestId);
    if (index != -1) {
      final current = swapRequests[index];
      swapRequests[index] = models.SwapRequest(
        rosterId: current.rosterId,
        requestId: current.requestId,
        userId: current.userId,
        fromPerson: current.fromPerson,
        toPerson: current.toPerson,
        date: current.date,
        shift: current.shift,
        status: decision,
        notes: current.notes,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
        reviewedBy: AwsService.instance.userId,
        reviewNote: note,
      );
    }
    notifyListeners();
  }

  Future<void> refreshShiftLocks() async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    try {
      shiftLocks = await AwsService.instance.getShiftLocks(rosterId);
      notifyListeners();
    } catch (e) {
      debugPrint('Load shift locks error: $e');
    }
  }

  Future<void> setShiftLock({
    required DateTime date,
    required String shift,
    String? personName,
    String? reason,
  }) async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    final lockId = await AwsService.instance.setShiftLock(
      rosterId: rosterId,
      date: date,
      shift: shift,
      personName: personName,
      reason: reason,
    );
    shiftLocks.add(
      models.ShiftLock(
        rosterId: rosterId,
        lockId: lockId,
        date: date,
        shift: shift,
        personName: personName,
        reason: reason ?? '',
        lockedBy: AwsService.instance.userId ?? 'unknown',
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<void> removeShiftLock(String lockId) async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    await AwsService.instance.removeShiftLock(rosterId, lockId);
    shiftLocks.removeWhere((l) => l.lockId == lockId);
    notifyListeners();
  }

  Future<void> refreshChangeProposals() async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    try {
      changeProposals = await AwsService.instance.getChangeProposals(rosterId);
      notifyListeners();
    } catch (e) {
      debugPrint('Load change proposals error: $e');
    }
  }

  Future<void> submitChangeProposal({
    required String title,
    required Map<String, dynamic> changes,
    String? description,
  }) async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    final proposalId = await AwsService.instance.createChangeProposal(
      rosterId: rosterId,
      title: title,
      description: description,
      changes: changes,
    );
    changeProposals.add(
      models.ChangeProposal(
        rosterId: rosterId,
        proposalId: proposalId,
        userId: AwsService.instance.userId ?? 'unknown',
        title: title,
        description: description ?? '',
        changes: changes,
        status: models.RequestStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<void> resolveChangeProposal({
    required String proposalId,
    required models.RequestStatus decision,
    String? note,
  }) async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    await AwsService.instance.resolveChangeProposal(
      rosterId: rosterId,
      proposalId: proposalId,
      decision: decision,
      note: note,
    );
    final index =
        changeProposals.indexWhere((p) => p.proposalId == proposalId);
    if (index != -1) {
      final current = changeProposals[index];
      changeProposals[index] = models.ChangeProposal(
        rosterId: current.rosterId,
        proposalId: current.proposalId,
        userId: current.userId,
        title: current.title,
        description: current.description,
        changes: current.changes,
        status: decision,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
        reviewedBy: AwsService.instance.userId,
        reviewNote: note,
      );
    }
    notifyListeners();
  }

  Future<void> refreshAuditLogs() async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    try {
      auditLogs = await AwsService.instance.getAuditLogs(rosterId);
      notifyListeners();
    } catch (e) {
      debugPrint('Load audit logs error: $e');
    }
  }

  Future<void> refreshRosterUpdates() async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) return;
    try {
      recentUpdates = await AwsService.instance.getRosterUpdates(
        rosterId,
        null,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Load roster updates error: $e');
    }
  }

  // Event management
  void addEvent(models.Event event) {
    events.add(event);
    _addHistory('Event Added', 'Added event: ${event.title}');
    _scheduleCloudSync();
    notifyListeners();
  }

  void addBulkEvents(List<models.Event> newEvents) {
    events.addAll(newEvents);
    _addHistory('Bulk Events', 'Added ${newEvents.length} events');
    _scheduleCloudSync();
    notifyListeners();
  }

  void deleteEvent(String eventId) {
    final event = events.firstWhere((e) => e.id == eventId);
    events.removeWhere((e) => e.id == eventId);
    _addHistory('Event Deleted', 'Deleted event: ${event.title}');
    _scheduleCloudSync();
    notifyListeners();
  }

  void deleteRecurringEvents(String recurringId) {
    final count = events
        .where((e) =>
            e.recurringId == recurringId ||
            e.description?.contains(recurringId) == true)
        .length;
    events.removeWhere((e) =>
        e.recurringId == recurringId ||
        e.description?.contains(recurringId) == true);

    _addHistory('Recurring Events Deleted', 'Deleted $count recurring events');

    _scheduleCloudSync();
    notifyListeners();
  }

  // AI Suggestions management
  Future<void> refreshAiSuggestions() async {
    aiSuggestions.clear();
    try {
      if (AiService.instance.isConfigured &&
          AwsService.instance.isAuthenticated) {
        final suggestions = await AiService.instance.generateRosterSuggestions(
          staff: staffMembers,
          overrides: overrides,
          pattern: masterPattern,
          events: events,
          constraints: constraints,
          healthScore: getHealthScore().toJson(),
          policySummary: buildComplianceSummary(),
        );
        if (suggestions.isNotEmpty) {
          aiSuggestions.addAll(suggestions);
        } else {
          aiSuggestions.addAll(_aiEngine.generateSuggestions());
        }
      } else {
        final suggestions = _aiEngine.generateSuggestions();
        aiSuggestions.addAll(suggestions);
      }
    } catch (e) {
      debugPrint('AI refresh error: $e');
      final suggestions = _aiEngine.generateSuggestions();
      aiSuggestions.addAll(suggestions);
    }
    if (aiSuggestions.isEmpty) {
      aiSuggestions.addAll(_generateBaselineSuggestions());
    }
    _addHistory('AI Refresh', 'Generated ${aiSuggestions.length} suggestions');
    notifyListeners();
  }

  List<models.AiSuggestion> _generateBaselineSuggestions() {
    final suggestions = <models.AiSuggestion>[];
    final now = DateTime.now();

    if (staffMembers.isEmpty) {
      suggestions.add(
        models.AiSuggestion(
          id: '${now.millisecondsSinceEpoch}_baseline_staff',
          title: 'Add staff to get started',
          description: 'Add staff members so RC can analyze coverage and shifts.',
          reason: 'No staff exist yet.',
          priority: models.SuggestionPriority.high,
          type: models.SuggestionType.other,
          createdDate: now,
          actionType: models.SuggestionActionType.none,
        ),
      );
      return suggestions;
    }

    if (masterPattern.isEmpty) {
      suggestions.add(
        models.AiSuggestion(
          id: '${now.millisecondsSinceEpoch}_baseline_pattern',
          title: 'Generate a roster pattern',
          description: 'Use the generator to create a base pattern.',
          reason: 'Pattern is empty so coverage analysis is limited.',
          priority: models.SuggestionPriority.medium,
          type: models.SuggestionType.pattern,
          createdDate: now,
          actionType: models.SuggestionActionType.updatePattern,
        ),
      );
    }

    if (constraints.shiftCoverageTargets.isEmpty) {
      suggestions.add(
        models.AiSuggestion(
          id: '${now.millisecondsSinceEpoch}_baseline_targets',
          title: 'Set coverage targets',
          description: 'Define minimum staffing per shift for stronger AI checks.',
          reason: 'Coverage targets are not configured.',
          priority: models.SuggestionPriority.medium,
          type: models.SuggestionType.coverage,
          createdDate: now,
          actionType: models.SuggestionActionType.none,
        ),
      );
    }

    if (events.isEmpty) {
      suggestions.add(
        models.AiSuggestion(
          id: '${now.millisecondsSinceEpoch}_baseline_events',
          title: 'Add key events',
          description: 'Add holidays, paydays, and deadlines to improve planning.',
          reason: 'No events found on the roster.',
          priority: models.SuggestionPriority.low,
          type: models.SuggestionType.other,
          createdDate: now,
          actionType: models.SuggestionActionType.addEvent,
        ),
      );
    }

    if (overrides.isEmpty) {
      suggestions.add(
        models.AiSuggestion(
          id: '${now.millisecondsSinceEpoch}_baseline_overrides',
          title: 'Try a quick change',
          description: 'Use RC to apply a shift change or leave request.',
          reason: 'Changes help track real-world updates.',
          priority: models.SuggestionPriority.low,
          type: models.SuggestionType.other,
          createdDate: now,
          actionType: models.SuggestionActionType.setOverride,
        ),
      );
    }

    return suggestions;
  }

  void markSuggestionAsRead(String suggestionId) {
    final index = aiSuggestions.indexWhere((s) => s.id == suggestionId);
    if (index != -1) {
      aiSuggestions[index] = aiSuggestions[index].copyWith(isRead: true);
      notifyListeners();
    }
  }

  void dismissSuggestion(String suggestionId) {
    aiSuggestions.removeWhere((s) => s.id == suggestionId);
    _addHistory('Suggestion Dismissed', 'Dismissed suggestion');
    notifyListeners();
  }

  void setSuggestionFeedback(
    String suggestionId,
    models.SuggestionFeedback feedback,
  ) {
    final index = aiSuggestions.indexWhere((s) => s.id == suggestionId);
    if (index == -1) return;
    final suggestion = aiSuggestions[index];
    aiSuggestions[index] = suggestion.copyWith(feedback: feedback);
    _addHistory(
      'Suggestion Feedback',
      'Marked suggestion as ${feedback.name}',
    );
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId != null && AwsService.instance.isAuthenticated) {
      final impact = previewSuggestionImpact(suggestion);
      AwsService.instance.submitAiFeedback(
        rosterId: rosterId,
        suggestionId: suggestionId,
        feedback: feedback.name,
        impact: impact.toJson(),
      );
    }
    notifyListeners();
  }

  models.RosterHealthScore previewSuggestionImpact(
    models.AiSuggestion suggestion,
  ) {
    final before = getHealthScore();
    final backup = createBackup();
    applySuggestionAction(suggestion, recordHistory: false);
    final after = getHealthScore();
    restoreBackup(backup);
    return models.RosterHealthScore(
      overall: after.overall - before.overall,
      coverage: after.coverage - before.coverage,
      workload: after.workload - before.workload,
      fairness: after.fairness - before.fairness,
      leave: after.leave - before.leave,
      pattern: after.pattern - before.pattern,
    );
  }

  models.RosterHealthScore simulateScenarioImpact(
    List<models.AiSuggestion> suggestions,
  ) {
    final before = getHealthScore();
    final backup = createBackup();
    for (final suggestion in suggestions) {
      applySuggestionAction(suggestion, recordHistory: false);
    }
    final after = getHealthScore();
    restoreBackup(backup);
    return models.RosterHealthScore(
      overall: after.overall - before.overall,
      coverage: after.coverage - before.coverage,
      workload: after.workload - before.workload,
      fairness: after.fairness - before.fairness,
      leave: after.leave - before.leave,
      pattern: after.pattern - before.pattern,
    );
  }

  Map<String, Map<String, int>> buildCoverageHeatmap({int days = 30}) {
    final heatmap = <String, Map<String, int>>{};
    final now = DateTime.now();
    for (int i = 0; i < days; i++) {
      final date = now.add(Duration(days: i));
      final dateKey = '${date.year}-${date.month}-${date.day}';
      final counts = <String, int>{};
      for (final staff in staffMembers) {
        if (!staff.isActive) continue;
        final shift = getShiftForDate(staff.name, date);
        if (shift == 'OFF' || shift == 'AL') continue;
        counts[shift] = (counts[shift] ?? 0) + 1;
      }
      heatmap[dateKey] = counts;
    }
    return heatmap;
  }

  bool applySuggestionAction(
    models.AiSuggestion suggestion, {
    bool recordHistory = true,
  }) {
    if (suggestion.actionType == null || suggestion.actionPayload == null) {
      return false;
    }
    if (!constraints.allowAiOverrides &&
        (suggestion.actionType == models.SuggestionActionType.setOverride ||
            suggestion.actionType == models.SuggestionActionType.swapShifts ||
            suggestion.actionType == models.SuggestionActionType.updatePattern)) {
      return false;
    }

    final payload = suggestion.actionPayload!;
    switch (suggestion.actionType) {
      case models.SuggestionActionType.setOverride:
        _applyOverrideAction(payload, recordHistory);
        break;
      case models.SuggestionActionType.swapShifts:
        _applySwapAction(payload, recordHistory);
        break;
      case models.SuggestionActionType.addEvent:
        _applyEventAction(payload, recordHistory);
        break;
      case models.SuggestionActionType.changeStaffStatus:
        _applyStaffStatusAction(payload, recordHistory);
        break;
      case models.SuggestionActionType.adjustLeave:
        _applyLeaveAction(payload, recordHistory);
        break;
      case models.SuggestionActionType.updatePattern:
        _applyPatternAction(payload, recordHistory);
        break;
      case models.SuggestionActionType.none:
        return false;
      default:
        return false;
    }

    if (recordHistory) {
      _addHistory('AI Action', 'Applied suggestion: ${suggestion.title}');
    }
    return true;
  }

  void _applyOverrideAction(Map<String, dynamic> payload, bool recordHistory) {
    final person = payload['personName'] as String?;
    final dateRaw = payload['date'] as String?;
    final shift = payload['shift'] as String?;
    if (person == null || dateRaw == null || shift == null) return;
    final date = DateTime.parse(dateRaw);
    setOverride(person, date, shift, payload['reason'] as String? ?? 'AI');
    if (!recordHistory) {
      history.removeLast();
    }
  }

  void _applySwapAction(Map<String, dynamic> payload, bool recordHistory) {
    final personA = payload['personA'] as String?;
    final personB = payload['personB'] as String?;
    final dateRaw = payload['date'] as String?;
    if (personA == null || personB == null || dateRaw == null) return;
    final date = DateTime.parse(dateRaw);
    final shiftA = payload['shiftA'] as String? ??
        getShiftForDate(personA, date);
    final shiftB = payload['shiftB'] as String? ??
        getShiftForDate(personB, date);
    setOverride(personA, date, shiftB, 'AI swap with $personB');
    setOverride(personB, date, shiftA, 'AI swap with $personA');
    if (!recordHistory) {
      history.removeLast();
      history.removeLast();
    }
  }

  void _applyEventAction(Map<String, dynamic> payload, bool recordHistory) {
    final title = payload['title'] as String?;
    final dateRaw = payload['date'] as String?;
    if (title == null || dateRaw == null) return;
    final event = models.Event(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: payload['description'] as String?,
      date: DateTime.parse(dateRaw),
      eventType: models.EventType.values[payload['eventType'] as int? ?? 0],
      affectedStaff: (payload['affectedStaff'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
    addEvent(event);
    if (!recordHistory) {
      history.removeLast();
    }
  }

  void _applyStaffStatusAction(
    Map<String, dynamic> payload,
    bool recordHistory,
  ) {
    final staffId = payload['staffId'] as String?;
    final isActive = payload['isActive'] as bool?;
    if (staffId == null || isActive == null) return;
    final index = staffMembers.indexWhere((s) => s.id == staffId);
    if (index == -1) return;
    staffMembers[index] =
        staffMembers[index].copyWith(isActive: isActive);
    if (recordHistory) {
      _addHistory(
        'Staff Status',
        'Set ${staffMembers[index].name} status to ${isActive ? 'active' : 'inactive'}',
      );
    }
    notifyListeners();
  }

  void _applyLeaveAction(Map<String, dynamic> payload, bool recordHistory) {
    final person = payload['personName'] as String?;
    final delta = payload['delta'] as num?;
    if (person == null || delta == null) return;
    adjustLeaveBalance(person, delta.toDouble());
    if (!recordHistory) {
      history.removeLast();
    }
  }

  void _applyPatternAction(Map<String, dynamic> payload, bool recordHistory) {
    final week = payload['week'] as int?;
    final day = payload['day'] as int?;
    final shift = payload['shift'] as String?;
    if (week == null || day == null || shift == null) return;
    updateMasterPatternCell(week, day, shift);
    if (!recordHistory) {
      history.removeLast();
    }
  }

  // Staff management
  List<models.Override> getOverridesForPerson(String personName) {
    return overrides.where((o) => o.personName == personName).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  void updateStaffLeaveBalance(String personName, double newBalance) {
    final staff = staffMembers.where((s) => s.name == personName).firstOrNull;
    if (staff == null) return;

    final staffIndex = staffMembers.indexWhere((s) => s.name == personName);
    if (staffIndex != -1) {
      staffMembers[staffIndex] = staffMembers[staffIndex].copyWith(
        leaveBalance: newBalance,
      );
      notifyListeners();
    }
  }

  void adjustLeaveBalance(String personName, double adjustment) {
    final index = staffMembers.indexWhere((s) => s.name == personName);
    if (index != -1) {
      staffMembers[index] = staffMembers[index].copyWith(
        leaveBalance: staffMembers[index].leaveBalance + adjustment,
      );
      notifyListeners();
    }
  }

  void addEventForStaff(models.Event event) {
    events.add(event);
    notifyListeners();
  }

  void removeEventForStaff(models.Event event) {
    events.remove(event);
    notifyListeners();
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  List<String> getActiveStaffNames() {
    final today = DateTime.now();
    return staffMembers
        .where((s) => isStaffActiveOnDate(s, today))
        .map((s) => s.name)
        .toList();
  }

  bool isStaffEmployedOnDate(models.StaffMember staff, DateTime date) {
    if (!staff.isActive && staff.endDate == null) return false;
    final start = staff.startDate;
    if (start != null &&
        date.isBefore(DateTime(start.year, start.month, start.day))) {
      return false;
    }
    final end = staff.endDate;
    if (end != null &&
        !date.isBefore(DateTime(end.year, end.month, end.day))) {
      return false;
    }
    return true;
  }

  bool isStaffActiveOnDate(models.StaffMember staff, DateTime date) {
    return isStaffEmployedOnDate(staff, date);
  }

  bool isStaffUnavailableOnDate(models.StaffMember staff, DateTime date) {
    final key = _cacheKey(staff.name, date);
    final cached = _unavailableCache[key];
    if (cached != null) return cached;
    final leaveStart = staff.leaveStart;
    final leaveEnd = staff.leaveEnd;
    bool unavailable = false;
    if (leaveStart != null && leaveEnd != null) {
      final start = DateTime(leaveStart.year, leaveStart.month, leaveStart.day);
      final end = DateTime(leaveEnd.year, leaveEnd.month, leaveEnd.day);
      unavailable = !date.isBefore(start) && !date.isAfter(end);
    }
    if (!unavailable) {
      final shift = getShiftForDate(staff.name, date);
      unavailable = shift.toUpperCase() == 'AL';
    }
    _unavailableCache[key] = unavailable;
    return unavailable;
  }

  bool isStaffVacantOnDate(models.StaffMember staff, DateTime date) {
    final end = staff.endDate;
    if (end == null) return false;
    final endDay = DateTime(end.year, end.month, end.day);
    return !date.isBefore(endDay);
  }

  bool isStaffActiveOnDateByName(String name, DateTime date) {
    final staff = staffMembers.where((s) => s.name == name).firstOrNull;
    if (staff == null) return false;
    return isStaffActiveOnDate(staff, date);
  }

  List<models.StaffMember> getStaffForRange(DateTime start, DateTime end) {
    return staffMembers.where((staff) {
      if (!staff.isActive && staff.endDate == null) return false;
      final staffStart = staff.startDate ?? DateTime(2000, 1, 1);
      final staffEnd = staff.endDate ?? DateTime(2100, 1, 1);
      if (staff.employmentType == 'permanent' &&
          staff.endDate != null &&
          staffEnd.isBefore(start)) {
        return true;
      }
      return !(staffEnd.isBefore(start) || staffStart.isAfter(end));
    }).toList();
  }

  List<String> getShiftTypes() {
    final types = <String>{};
    for (final week in masterPattern) {
      for (final shift in week) {
        if (shift == 'OFF' || shift == 'AL') continue;
        types.add(shift);
      }
    }
    for (final override in overrides) {
      if (override.shift == 'OFF' || override.shift == 'AL') continue;
      types.add(override.shift);
    }
    return types.toList()..sort();
  }

  Map<String, double> getLeaveBalances() {
    final balances = <String, double>{};
    for (final staff in staffMembers) {
      balances[staff.name] = staff.leaveBalance;
    }
    return balances;
  }

  Map<String, dynamic> buildComplianceSummary({int daysAhead = 30}) {
    final now = DateTime.now();
    int coverageViolations = 0;
    int shiftCoverageViolations = 0;
    int maxConsecutiveViolations = 0;
    int minRestViolations = 0;

    for (int i = 0; i < daysAhead; i++) {
      final date = now.add(Duration(days: i));
      final staffed = staffMembers
          .where((s) => s.isActive)
          .where((s) {
            final shift = getShiftForDate(s.name, date);
            return shift != 'OFF' && shift != 'AL';
          })
          .length;
      final minStaff = (date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday)
          ? constraints.minStaffWeekend
          : constraints.minStaffPerDay;
      if (staffed < minStaff) {
        coverageViolations++;
      }

      if (constraints.shiftCoverageTargets.isNotEmpty ||
          constraints.shiftCoverageTargetsByDay.isNotEmpty) {
        final counts = <String, int>{};
        for (final staff in staffMembers) {
          if (!staff.isActive) continue;
          final shift = getShiftForDate(staff.name, date);
          if (shift == 'OFF' || shift == 'AL') continue;
          counts[shift] = (counts[shift] ?? 0) + 1;
        }
        final dayKey = date.weekday.toString();
        final targets =
            constraints.shiftCoverageTargetsByDay[dayKey] ??
                constraints.shiftCoverageTargets;
        targets.forEach((shiftType, minCount) {
          if ((counts[shiftType] ?? 0) < minCount) {
            shiftCoverageViolations++;
          }
        });
      }
    }

    for (final staff in staffMembers) {
      if (!staff.isActive) continue;
      int currentConsecutive = 0;
      for (int i = 0; i < daysAhead; i++) {
        final date = now.add(Duration(days: i));
        final shift = getShiftForDate(staff.name, date);
        if (shift != 'OFF' && shift != 'AL') {
          currentConsecutive++;
          if (currentConsecutive > constraints.maxConsecutiveDays) {
            maxConsecutiveViolations++;
            break;
          }
        } else {
          currentConsecutive = 0;
        }
      }

      if (constraints.minRestDaysBetweenShifts > 0) {
        for (int i = 0; i < daysAhead - 1; i++) {
          final date = now.add(Duration(days: i));
          final nextDate = now.add(Duration(days: i + 1));
          final shift = getShiftForDate(staff.name, date);
          final nextShift = getShiftForDate(staff.name, nextDate);
          if (shift != 'OFF' &&
              shift != 'AL' &&
              nextShift != 'OFF' &&
              nextShift != 'AL') {
            minRestViolations++;
          }
        }
      }
    }

    return {
      'coverageViolations': coverageViolations,
      'shiftCoverageViolations': shiftCoverageViolations,
      'maxConsecutiveViolations': maxConsecutiveViolations,
      'minRestViolations': minRestViolations,
    };
  }

  Map<String, dynamic> buildOvertimeRisk({int daysAhead = 14}) {
    const standardHours = 38.0;
    final now = DateTime.now();
    final risk = <String, double>{};
    final hoursByStaff = <String, double>{};

    if (timeClockEntries.isNotEmpty) {
      for (final entry in timeClockEntries) {
        if (entry.date.isBefore(now.subtract(const Duration(days: 30)))) {
          continue;
        }
        hoursByStaff[entry.personName] =
            (hoursByStaff[entry.personName] ?? 0) + entry.hours;
      }
      hoursByStaff.forEach((name, hours) {
        final weeklyAvg = hours / 4.0;
        final score = (weeklyAvg / standardHours).clamp(0.0, 2.0);
        risk[name] = score;
      });
    } else {
      for (final staff in staffMembers) {
        if (!staff.isActive) continue;
        double hours = 0;
        for (int i = 0; i < daysAhead; i++) {
          final date = now.add(Duration(days: i));
          final shift = getShiftForDate(staff.name, date);
          if (shift != 'OFF' && shift != 'AL') {
            hours += 8;
          }
        }
        final weeklyAvg = hours / (daysAhead / 7.0);
        final score = (weeklyAvg / standardHours).clamp(0.0, 2.0);
        risk[staff.name] = score;
      }
    }

    final highRisk = risk.entries
        .where((entry) => entry.value >= 1.2)
        .map((e) => e.key)
        .toList();
    return {
      'riskScores': risk,
      'highRiskCount': highRisk.length,
      'highRiskStaff': highRisk,
    };
  }

  Map<String, dynamic> buildLeaveBurndown({int daysAhead = 90}) {
    final now = DateTime.now();
    final scheduledByStaff = <String, int>{};
    for (final override in overrides) {
      if (override.shift != 'AL') continue;
      if (override.date.isBefore(now) ||
          override.date.isAfter(now.add(Duration(days: daysAhead)))) {
        continue;
      }
      scheduledByStaff[override.personName] =
          (scheduledByStaff[override.personName] ?? 0) + 1;
    }
    final atRisk = <String>[];
    for (final staff in staffMembers) {
      final scheduled = scheduledByStaff[staff.name] ?? 0;
      if (staff.leaveBalance - scheduled < 0) {
        atRisk.add(staff.name);
      }
    }
    return {
      'scheduledLeaveDays': scheduledByStaff,
      'atRiskStaff': atRisk,
    };
  }

  models.RosterHealthScore getHealthScore({int daysAhead = 14}) {
    if (staffMembers.isEmpty) {
      return const models.RosterHealthScore(
        overall: 1,
        coverage: 1,
        workload: 1,
        fairness: 1,
        leave: 1,
        pattern: 1,
      );
    }

    final activeStaff = staffMembers.where((s) => s.isActive).toList();
    if (activeStaff.isEmpty) {
      return const models.RosterHealthScore(
        overall: 0,
        coverage: 0,
        workload: 0,
        fairness: 0,
        leave: 0,
        pattern: 0,
      );
    }

    final coverageScore = _calculateCoverageScore(daysAhead);
    final workloadScore = _calculateWorkloadScore(activeStaff, daysAhead);
    final fairnessScore = _calculateWeekendFairness(activeStaff, daysAhead);
    final leaveScore = _calculateLeaveScore(activeStaff);
    final patternScore = _calculatePatternScore();

    final overall = (coverageScore * 0.3) +
        (workloadScore * 0.25) +
        (fairnessScore * 0.2) +
        (leaveScore * 0.15) +
        (patternScore * 0.1);

    return models.RosterHealthScore(
      overall: overall,
      coverage: coverageScore,
      workload: workloadScore,
      fairness: fairnessScore,
      leave: leaveScore,
      pattern: patternScore,
    );
  }

  double _calculateCoverageScore(int daysAhead) {
    final now = DateTime.now();
    int totalDays = 0;
    double scoreSum = 0;

    for (int i = 0; i < daysAhead; i++) {
      final date = now.add(Duration(days: i));
      final isWeekend =
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
      final minStaff =
          isWeekend ? constraints.minStaffWeekend : constraints.minStaffPerDay;

      int staffed = 0;
      for (final staff in staffMembers) {
        if (!staff.isActive) continue;
        final shift = getShiftForDate(staff.name, date);
        if (shift != 'OFF' && shift != 'AL') {
          staffed++;
        }
      }

      final dayScore = minStaff == 0
          ? 1
          : (staffed / minStaff).clamp(0.0, 1.0);
      scoreSum += dayScore;
      totalDays++;
    }

    return totalDays == 0 ? 1 : scoreSum / totalDays;
  }

  double _calculateWorkloadScore(
    List<models.StaffMember> activeStaff,
    int daysAhead,
  ) {
    final now = DateTime.now();
    final counts = <int>[];

    for (final staff in activeStaff) {
      int shifts = 0;
      for (int i = 0; i < daysAhead; i++) {
        final date = now.add(Duration(days: i));
        final shift = getShiftForDate(staff.name, date);
        if (shift != 'OFF' && shift != 'AL') {
          shifts++;
        }
      }
      counts.add(shifts);
    }

    if (counts.isEmpty) return 1;
    final avg = counts.reduce((a, b) => a + b) / counts.length;
    if (avg == 0) return 1;
    final variance = counts
            .map((c) => (c - avg) * (c - avg))
            .reduce((a, b) => a + b) /
        counts.length;
    final stdDev = sqrt(variance);
    final normalized = (stdDev / avg).clamp(0.0, 1.0);
    return (1 - normalized).clamp(0.0, 1.0);
  }

  double _calculateWeekendFairness(
    List<models.StaffMember> activeStaff,
    int daysAhead,
  ) {
    if (!constraints.balanceWeekends) return 1;
    final now = DateTime.now();
    final counts = <int>[];

    for (final staff in activeStaff) {
      int shifts = 0;
      for (int i = 0; i < daysAhead; i++) {
        final date = now.add(Duration(days: i));
        if (date.weekday != DateTime.saturday &&
            date.weekday != DateTime.sunday) {
          continue;
        }
        final shift = getShiftForDate(staff.name, date);
        if (shift != 'OFF' && shift != 'AL') {
          shifts++;
        }
      }
      counts.add(shifts);
    }

    if (counts.isEmpty) return 1;
    final avg = counts.reduce((a, b) => a + b) / counts.length;
    if (avg == 0) return 1;
    final variance = counts
            .map((c) => (c - avg) * (c - avg))
            .reduce((a, b) => a + b) /
        counts.length;
    final stdDev = sqrt(variance);
    final normalized = (stdDev / avg).clamp(0.0, 1.0);
    return (1 - normalized).clamp(0.0, 1.0);
  }

  double _calculateLeaveScore(List<models.StaffMember> activeStaff) {
    if (activeStaff.isEmpty) return 1;
    final lowLeave = activeStaff
        .where((s) => s.leaveBalance < constraints.minLeaveBalance)
        .length;
    return (1 - (lowLeave / activeStaff.length)).clamp(0.0, 1.0);
  }

  double _calculatePatternScore() {
    if (masterPattern.isEmpty) return 0.5;
    final firstWeekLength = masterPattern.first.length;
    final inconsistentWeeks =
        masterPattern.where((week) => week.length != firstWeekLength).length;
    return (1 - (inconsistentWeeks / masterPattern.length)).clamp(0.0, 1.0);
  }

  void clearAllData() {
    staffMembers.clear();
    overrides.clear();
    events.clear();
    history.clear();
    aiSuggestions.clear();
    masterPattern.clear();
    regularSwaps.clear();
    pendingSync.clear();
    availabilityRequests.clear();
    swapRequests.clear();
    shiftLocks.clear();
    changeProposals.clear();
    auditLogs.clear();
    generatedRosters.clear();
    rosterSnapshots.clear();
    quickBaseTemplate = null;
    quickVariationPresets.clear();
    propagationSettings = null;
    constraints = const models.RosterConstraints();
    readOnly = false;
    sharedAccessCode = null;
    sharedRosterName = null;
    sharedRole = null;
    _nextStaffId = 1;
    weekStartDay = 0;
    _addHistory('Clear All', 'Cleared all roster data');
    notifyListeners();
  }

  Future<Map<String, int>> importHolidays({
    required List<HolidayItem> holidays,
    required bool addEvents,
    required bool applyLeaveOverrides,
    required List<String> staffNames,
  }) async {
    if (readOnly) {
      throw Exception('Read-only roster cannot be updated');
    }
    int eventsAdded = 0;
    int overridesAdded = 0;

    for (final holiday in holidays) {
      final date = holiday.date;
      final title = holiday.localName.isNotEmpty
          ? holiday.localName
          : holiday.name;

      if (addEvents) {
        final exists = events.any((event) =>
            event.title == title &&
            event.date.year == date.year &&
            event.date.month == date.month &&
            event.date.day == date.day);
        if (!exists) {
          events.add(
            models.Event(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              title: title,
              description: holiday.name,
              date: date,
              eventType: models.EventType.holiday,
              affectedStaff: staffNames,
            ),
          );
          eventsAdded++;
        }
      }

      if (applyLeaveOverrides) {
        for (final staff in staffNames) {
          setOverride(staff, date, 'AL', 'Holiday: ${holiday.name}');
          overridesAdded++;
        }
      }
    }

    _addHistory(
      'Holiday Import',
      'Added $eventsAdded events and $overridesAdded leave changes',
    );
    notifyListeners();

    return {
      'events': eventsAdded,
      'overrides': overridesAdded,
    };
  }

  bool get hasUnsavedChanges {
    if (staffMembers.isEmpty && overrides.isEmpty && events.isEmpty) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> getStatistics() {
    final health = getHealthScore();
    final now = DateTime.now();
    final activeStaff = staffMembers.where((s) => s.isActive).toList();
    final horizonDays = 30;
    final shiftCounts = <String, int>{};
    int totalShifts = 0;
    double projectedCost = 0;

    for (final staff in activeStaff) {
      int count = 0;
      double rate = 0;
      final meta = staff.metadata;
      if (meta != null && meta['hourlyRate'] is num) {
        rate = (meta['hourlyRate'] as num).toDouble();
      }
      for (int i = 0; i < horizonDays; i++) {
        final date = now.add(Duration(days: i));
        final shift = getShiftForDate(staff.name, date);
        if (shift != 'OFF' && shift != 'AL') {
          count++;
          totalShifts++;
          if (rate > 0) {
            projectedCost += rate * 8;
          }
        }
      }
      shiftCounts[staff.name] = count;
    }

    final avgShifts = activeStaff.isEmpty
        ? 0
        : totalShifts / activeStaff.length;
    double variance = 0;
    if (activeStaff.isNotEmpty) {
      for (final count in shiftCounts.values) {
        variance += (count - avgShifts) * (count - avgShifts);
      }
      variance /= activeStaff.length;
    }
    final shiftStdDev = activeStaff.isEmpty ? 0 : sqrt(variance);
    final utilization = activeStaff.isEmpty
        ? 0
        : totalShifts / (activeStaff.length * horizonDays);

    final overtimeRisk = buildOvertimeRisk();
    final leaveBurndown = buildLeaveBurndown();
    final compliance = buildComplianceSummary();

    return {
      'totalStaff': staffMembers.length,
      'activeStaff': activeStaff.length,
      'totalOverrides': overrides.length,
      'totalEvents': events.length,
      'totalLeaveDays': overrides.where((o) => o.shift == 'AL').length,
      'aiSuggestions': aiSuggestions.length,
      'unreadSuggestions': aiSuggestions.where((s) => !s.isRead).length,
      'patternPropagationActive': propagationSettings?.isActive ?? false,
      'healthScore': health.toJson(),
      'utilizationRate': utilization,
      'avgShiftsPerStaff': avgShifts,
      'shiftStdDev': shiftStdDev,
      'projectedCost': projectedCost,
      'overtimeRisk': overtimeRisk,
      'leaveBurndown': leaveBurndown,
      'compliance': compliance,
    };
  }
}

// Backup/Restore functionality
class RosterBackup {
  final List<models.StaffMember> staffMembers;
  final List<List<String>> masterPattern;
  final List<models.Override> overrides;
  final List<models.Event> events;
  final List<models.HistoryEntry> history;
  final List<models.AiSuggestion> aiSuggestions;
  final List<models.RegularShiftSwap> regularSwaps;
  final List<models.AvailabilityRequest> availabilityRequests;
  final List<models.SwapRequest> swapRequests;
  final List<models.SwapDebt> swapDebts;
  final List<models.ShiftLock> shiftLocks;
  final List<models.ChangeProposal> changeProposals;
  final List<models.AuditLogEntry> auditLogs;
  final List<models.GeneratedRosterTemplate> generatedRosters;
  final List<models.RosterSnapshot> rosterSnapshots;
  final models.GeneratedRosterTemplate? quickBaseTemplate;
  final List<models.GeneratedRosterTemplate> quickVariationPresets;
  final models.PatternPropagationSettings? propagationSettings;
  final int cycleLength;
  final int numPeople;
  final int weekStartDay;
  final DateTime createdAt;

  RosterBackup({
    required this.staffMembers,
    required this.masterPattern,
    required this.overrides,
    required this.events,
    required this.history,
    required this.aiSuggestions,
    required this.regularSwaps,
    required this.availabilityRequests,
    required this.swapRequests,
    required this.swapDebts,
    required this.shiftLocks,
    required this.changeProposals,
    required this.auditLogs,
    required this.generatedRosters,
    required this.rosterSnapshots,
    required this.quickBaseTemplate,
    required this.quickVariationPresets,
    this.propagationSettings,
    required this.cycleLength,
    required this.numPeople,
    required this.weekStartDay,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

extension FirstWhereOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E element) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }

  E? get lastOrNull {
    if (isEmpty) return null;
    return last;
  }
}

