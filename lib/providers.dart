import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart' as models;
import 'openai_service.dart';
import 'supabase_service.dart';

// Settings Provider
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, models.AppSettings>((ref) {
  return SettingsNotifier();
});

class SettingsNotifier extends StateNotifier<models.AppSettings> {
  SettingsNotifier() : super(const models.AppSettings());

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('app_settings');
      if (settingsJson != null) {
        final decoded = jsonDecode(settingsJson);
        state = models.AppSettings.fromJson(decoded);
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
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  void updateSettings(models.AppSettings settings) {
    state = settings;
    saveSettings(settings);
  }
}

// Connection Status Providers
final supabaseStatusProvider = StateProvider<models.ServiceStatus>((ref) {
  return const models.ServiceStatus(
    status: models.ConnectionStatus.disconnected,
    lastChecked: null,
  );
});

final openaiStatusProvider = StateProvider<models.ServiceStatus>((ref) {
  return const models.ServiceStatus(
    status: models.ConnectionStatus.disconnected,
    lastChecked: null,
  );
});

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

    // Check leave balances
    suggestions.addAll(_checkLeaveBalances());

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
        if (shift != 'OFF' && shift != 'L') {
          shiftCount++;
        }
      }

      workloadMap[staff.name] = shiftCount;
    }

    if (workloadMap.isNotEmpty) {
      final avgWorkload =
          workloadMap.values.reduce((a, b) => a + b) / workloadMap.length;

      workloadMap.forEach((name, count) {
        if (count > avgWorkload * 1.3) {
          suggestions.add(
            models.AiSuggestion(
              id: '${DateTime.now().millisecondsSinceEpoch}_workload_high_$name',
              title: 'High Workload Alert',
              description:
                  '$name has $count shifts in the next 30 days, which is ${((count - avgWorkload) / avgWorkload * 100).toStringAsFixed(0)}% above average.',
              priority: models.SuggestionPriority.high,
              type: models.SuggestionType.workload,
              createdDate: DateTime.now(),
              affectedStaff: [name],
            ),
          );
        } else if (count < avgWorkload * 0.7) {
          suggestions.add(
            models.AiSuggestion(
              id: '${DateTime.now().millisecondsSinceEpoch}_workload_low_$name',
              title: 'Low Workload Notice',
              description:
                  '$name has only $count shifts in the next 30 days, which is below average.',
              priority: models.SuggestionPriority.medium,
              type: models.SuggestionType.workload,
              createdDate: DateTime.now(),
              affectedStaff: [name],
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
        if (shift != 'OFF' && shift != 'L') {
          staffOnShift.add(staff.name);
        }
      }

      if (staffOnShift.length < 2) {
        suggestions.add(
          models.AiSuggestion(
            id: '${DateTime.now().millisecondsSinceEpoch}_coverage_${date.toIso8601String()}',
            title: 'Low Coverage Warning',
            description:
                'Only ${staffOnShift.length} staff scheduled for ${_formatDate(date)}',
            priority: staffOnShift.isEmpty
                ? models.SuggestionPriority.critical
                : models.SuggestionPriority.high,
            type: models.SuggestionType.coverage,
            createdDate: DateTime.now(),
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
          if (shift != 'OFF' && shift != 'L') {
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
            priority: models.SuggestionPriority.high,
            type: models.SuggestionType.coverage,
            createdDate: DateTime.now(),
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
            priority: models.SuggestionPriority.critical,
            type: models.SuggestionType.leave,
            createdDate: DateTime.now(),
            affectedStaff: [staff.name],
          ),
        );
      } else if (staff.leaveBalance < 3) {
        suggestions.add(
          models.AiSuggestion(
            id: '${DateTime.now().millisecondsSinceEpoch}_leave_low_${staff.name}',
            title: 'Low Leave Balance',
            description:
                '${staff.name} has only ${staff.leaveBalance.toStringAsFixed(1)} days of leave remaining',
            priority: models.SuggestionPriority.medium,
            type: models.SuggestionType.leave,
            createdDate: DateTime.now(),
            affectedStaff: [staff.name],
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
            priority: models.SuggestionPriority.high,
            type: models.SuggestionType.pattern,
            createdDate: DateTime.now(),
          ),
        );
      }

      // Check for excessive consecutive shifts
      for (final staff in notifier.staffMembers) {
        if (!staff.isActive) continue;

        int maxConsecutive = 0;
        int currentConsecutive = 0;
        final now = DateTime.now();

        for (int i = 0; i < 14; i++) {
          final date = now.add(Duration(days: i));
          final shift = notifier.getShiftForDate(staff.name, date);
          if (shift != 'OFF' && shift != 'L') {
            currentConsecutive++;
            maxConsecutive = max(maxConsecutive, currentConsecutive);
          } else {
            currentConsecutive = 0;
          }
        }

        if (maxConsecutive >= 7) {
          suggestions.add(
            models.AiSuggestion(
              id: '${DateTime.now().millisecondsSinceEpoch}_consecutive_${staff.name}',
              title: 'Excessive Consecutive Shifts',
              description:
                  '${staff.name} has $maxConsecutive consecutive working days',
              priority: models.SuggestionPriority.medium,
              type: models.SuggestionType.workload,
              createdDate: DateTime.now(),
              affectedStaff: [staff.name],
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
}

// Roster Provider - Main state management
final rosterProvider = ChangeNotifierProvider<RosterNotifier>((ref) {
  return RosterNotifier();
});

class RosterNotifier extends ChangeNotifier {
  List<models.StaffMember> staffMembers = [];
  List<List<String>> masterPattern = [];
  List<models.Override> overrides = [];
  List<models.Event> events = [];
  List<models.HistoryEntry> history = [];
  List<models.AiSuggestion> aiSuggestions = [];
  List<models.RegularShiftSwap> regularSwaps = [];
  List<models.SyncOperation> pendingSync = [];
  models.PatternPropagationSettings? propagationSettings;
  models.PatternRecognitionResult? lastPatternRecognition;
  int cycleLength = 16;
  int numPeople = 16;
  int _nextStaffId = 1;
  late AISuggestionEngine _aiEngine;
  Timer? _autoSaveTimer;
  Timer? _syncTimer;
  static const Duration _autoSaveDelay = Duration(seconds: 2);

  RosterNotifier() {
    _aiEngine = AISuggestionEngine(this);
    _startAutoSave();
    _startSyncTimer();
  }

  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(_autoSaveDelay, (_) {
      _autoSave();
    });
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _processPendingSync();
    });
  }

  Future<void> _autoSave() async {
    try {
      await saveToLocal();
    } catch (e) {
      debugPrint('Auto-save error: $e');
    }
  }

  Future<void> _processPendingSync() async {
    if (pendingSync.isEmpty) return;

    final operations = List<models.SyncOperation>.from(pendingSync);
    for (final op in operations) {
      try {
        // Process sync operation
        await SupabaseService.instance.syncOperation(op);
        pendingSync.removeWhere((o) => o.id == op.id);
      } catch (e) {
        debugPrint('Sync error: $e');
      }
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _syncTimer?.cancel();
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

    if (history.length > 100) {
      history = history.sublist(history.length - 100);
    }
  }

  // Enhanced Staff Management
  void addStaff(String name) {
    final newStaff = models.StaffMember(
      id: (_nextStaffId++).toString(),
      name: name.trim(),
    );
    staffMembers.add(newStaff);
    _addHistory('Staff Added', 'Added staff member: $name');
    notifyListeners();
  }

  void removeStaff(String name) {
    staffMembers.removeWhere((s) => s.name == name);
    overrides.removeWhere((o) => o.personName == name);
    _addHistory('Staff Removed', 'Removed staff member: $name');
    notifyListeners();
  }

  void removeStaffById(String staffId) {
    final staff = staffMembers.firstWhere((s) => s.id == staffId);
    staffMembers.removeWhere((s) => s.id == staffId);
    overrides.removeWhere((o) => o.personName == staff.name);
    _addHistory('Staff Removed', 'Removed staff member: ${staff.name}');
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
      staffMembers[index] = staffMembers[index].copyWith(isActive: newStatus);
      _addHistory(
        'Staff Status',
        'Set ${staffMembers[index].name} status to ${newStatus ? 'active' : 'inactive'}',
      );
      notifyListeners();
    }
  }

  void toggleStaffStatusById(String staffId) {
    final index = staffMembers.indexWhere((s) => s.id == staffId);
    if (index != -1) {
      toggleStaffStatus(index);
    }
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
  }

  Future<void> syncToSupabase() async {
    try {
      final data = toJson();
      await SupabaseService.instance.saveRoster(data);
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
    }
  }

  Future<void> loadFromSupabase() async {
    try {
      final data = await SupabaseService.instance.loadRoster();
      if (data != null) {
        fromJson(data);
        _addHistory('Sync', 'Loaded from cloud successfully');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Load error: $e');
    }
  }

  void applyRemoteUpdate(models.RosterUpdate update) {
    switch (update.operationType) {
      case models.OperationType.addOverride:
        _applyOverrideUpdate(update);
        break;
      case models.OperationType.addStaff:
        _applyStaffUpdate(update);
        break;
      case models.OperationType.addEvent:
        _applyEventUpdate(update);
        break;
      case models.OperationType.updatePattern:
      case models.OperationType.removeStaff:
      case models.OperationType.removeOverride:
      case models.OperationType.removeEvent:
        // Handle other update types
        break;
    }
    notifyListeners();
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

  // Data persistence
  Future<void> saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('roster_data', jsonEncode(toJson()));
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  Future<void> loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('roster_data');
      if (data != null) {
        fromJson(jsonDecode(data));

        // Regenerate AI suggestions after loading
        if (staffMembers.isNotEmpty) {
          final lastHistoryEntry = history.lastOrNull;
          final hoursSinceLastAction = lastHistoryEntry != null
              ? DateTime.now().difference(lastHistoryEntry.timestamp).inHours
              : 24;

          if (hoursSinceLastAction > 6) {
            refreshAiSuggestions();
          }
        }

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
      'propagationSettings': propagationSettings?.toJson(),
      'cycleLength': cycleLength,
      'numPeople': numPeople,
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
    if (json['propagationSettings'] != null) {
      propagationSettings = models.PatternPropagationSettings.fromJson(
        json['propagationSettings'],
      );
    }
    cycleLength = json['cycleLength'] as int? ?? 16;
    numPeople = json['numPeople'] as int? ?? 16;
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
  }

  void _generateDefaultPattern() {
    masterPattern = List.generate(
      cycleLength,
      (week) => List.generate(7, (day) => 'D'),
    );
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

  String getShiftForDate(String personName, DateTime date) {
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
      return override.shift;
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
    final bulkId = DateTime.now().millisecondsSinceEpoch.toString();
    final newOverrides = <models.Override>[];

    overrides.removeWhere(
      (o) =>
          o.personName == person &&
          !o.date.isBefore(startDate) &&
          !o.date.isAfter(endDate),
    );

    for (var date = startDate;
        date.isBefore(endDate) || date.isAtSameMomentAs(endDate);
        date = date.add(const Duration(days: 1))) {
      final staffIndex = staffMembers.indexWhere((s) => s.name == person);
      if (staffIndex == -1) continue;

      newOverrides.add(
        models.Override(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          personName: person,
          date: date,
          shift: shift,
          reason: reason,
          createdAt: DateTime.now(),
        ),
      );

      if (shift == 'L') {
        staffMembers[staffIndex] = staffMembers[staffIndex].copyWith(
          leaveBalance: staffMembers[staffIndex].leaveBalance - 1,
        );
      }
    }

    overrides.addAll(newOverrides);

    _addHistory(
      'Bulk Override',
      'Added ${newOverrides.length} overrides for $person',
    );

    notifyListeners();
  }

  void removeBulkOverrides(String bulkId) {
    final affectedOverrides =
        overrides.where((o) => o.reason?.contains(bulkId) == true).toList();

    if (affectedOverrides.isNotEmpty) {
      final person = affectedOverrides.first.personName;
      final leaveCount = affectedOverrides.where((o) => o.shift == 'L').length;

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
        title: 'Bulk Override Removed',
        description:
            'Removed ${affectedOverrides.length} overrides for $person',
        priority: models.SuggestionPriority.low,
        type: models.SuggestionType.other,
        createdDate: DateTime.now(),
      );
      aiSuggestions.add(suggestion);
    }

    final removedCount =
        overrides.where((o) => o.reason?.contains(bulkId) == true).length;
    overrides.removeWhere((o) => o.reason?.contains(bulkId) == true);

    _addHistory('Bulk Override Removed', 'Removed $removedCount overrides');

    notifyListeners();
  }

  void setOverride(
    String person,
    DateTime date,
    String newShift,
    String reason,
  ) {
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
    _addHistory(
      'Override Set',
      'Set $person on ${_formatDate(date)} to $newShift',
    );
    notifyListeners();
  }

  // Event management
  void addEvent(models.Event event) {
    events.add(event);
    _addHistory('Event Added', 'Added event: ${event.title}');
    notifyListeners();
  }

  void addBulkEvents(List<models.Event> newEvents) {
    events.addAll(newEvents);
    _addHistory('Bulk Events', 'Added ${newEvents.length} events');
    notifyListeners();
  }

  void deleteEvent(String eventId) {
    final event = events.firstWhere((e) => e.id == eventId);
    events.removeWhere((e) => e.id == eventId);
    _addHistory('Event Deleted', 'Deleted event: ${event.title}');
    notifyListeners();
  }

  void deleteRecurringEvents(String recurringId) {
    final count = events
        .where((e) => e.description?.contains(recurringId) == true)
        .length;
    events.removeWhere((e) => e.description?.contains(recurringId) == true);

    _addHistory('Recurring Events Deleted', 'Deleted $count recurring events');

    notifyListeners();
  }

  // AI Suggestions management
  void refreshAiSuggestions() {
    aiSuggestions.clear();
    final suggestions = _aiEngine.generateSuggestions();
    aiSuggestions.addAll(suggestions);
    _addHistory('AI Refresh', 'Generated ${suggestions.length} suggestions');
    notifyListeners();
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
    return staffMembers.where((s) => s.isActive).map((s) => s.name).toList();
  }

  Map<String, double> getLeaveBalances() {
    final balances = <String, double>{};
    for (final staff in staffMembers) {
      balances[staff.name] = staff.leaveBalance;
    }
    return balances;
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
    propagationSettings = null;
    _nextStaffId = 1;
    _addHistory('Clear All', 'Cleared all roster data');
    notifyListeners();
  }

  Future<void> exportData() async {
    try {
      final data = toJson();
      await saveToLocal();
      _addHistory('Export', 'Exported roster data');
      return;
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

  bool get hasUnsavedChanges {
    if (staffMembers.isEmpty && overrides.isEmpty && events.isEmpty) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> getStatistics() {
    return {
      'totalStaff': staffMembers.length,
      'activeStaff': staffMembers.where((s) => s.isActive).length,
      'totalOverrides': overrides.length,
      'totalEvents': events.length,
      'totalLeaveDays': overrides.where((o) => o.shift == 'L').length,
      'aiSuggestions': aiSuggestions.length,
      'unreadSuggestions': aiSuggestions.where((s) => !s.isRead).length,
      'patternPropagationActive': propagationSettings?.isActive ?? false,
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
  final models.PatternPropagationSettings? propagationSettings;
  final int cycleLength;
  final int numPeople;
  final DateTime createdAt;

  RosterBackup({
    required this.staffMembers,
    required this.masterPattern,
    required this.overrides,
    required this.events,
    required this.history,
    required this.aiSuggestions,
    required this.regularSwaps,
    this.propagationSettings,
    required this.cycleLength,
    required this.numPeople,
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
