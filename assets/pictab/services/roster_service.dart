import 'package:flutter/foundation.dart';
import '../models/roster.dart';

/// Service for managing roster state and operations
class RosterService extends ChangeNotifier {
  Roster? _currentRoster;
  final List<Roster> _savedRosters = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  Roster? get currentRoster => _currentRoster;
  List<Roster> get savedRosters => List.unmodifiable(_savedRosters);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasRoster => _currentRoster != null;

  /// Set the current roster
  void setCurrentRoster(Roster roster) {
    _currentRoster = roster;
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear the current roster
  void clearCurrentRoster() {
    _currentRoster = null;
    notifyListeners();
  }

  /// Create a new empty roster
  Roster createNewRoster({
    required DateTime startDate,
    required DateTime endDate,
    String title = 'New Roster',
  }) {
    final roster = Roster(
      title: title,
      startDate: startDate,
      endDate: endDate,
    );
    _currentRoster = roster;
    notifyListeners();
    return roster;
  }

  /// Add an employee to the current roster
  void addEmployee(String name, {String defaultShift = 'R'}) {
    if (_currentRoster == null) return;

    final employee = Employee(name: name);
    employee.fillDates(
      _currentRoster!.startDate,
      _currentRoster!.endDate,
      defaultShift,
    );

    _currentRoster!.addEmployee(employee);
    notifyListeners();
  }

  /// Remove an employee from the current roster
  void removeEmployee(String employeeId) {
    if (_currentRoster == null) return;
    _currentRoster!.removeEmployee(employeeId);
    notifyListeners();
  }

  /// Update employee name
  void updateEmployeeName(String employeeId, String newName) {
    if (_currentRoster == null) return;
    final employee = _currentRoster!.getEmployee(employeeId);
    if (employee != null) {
      employee.name = newName;
      _currentRoster!.updatedAt = DateTime.now();
      notifyListeners();
    }
  }

  /// Update a shift
  void updateShift(String employeeId, DateTime date, String shiftCode) {
    if (_currentRoster == null) return;
    _currentRoster!.updateShift(employeeId, date, shiftCode);
    notifyListeners();
  }

  /// Bulk update shifts for an employee
  void bulkUpdateShifts(
    String employeeId,
    DateTime startDate,
    DateTime endDate,
    String shiftCode,
  ) {
    if (_currentRoster == null) return;
    final employee = _currentRoster!.getEmployee(employeeId);
    if (employee != null) {
      var current = startDate;
      while (!current.isAfter(endDate)) {
        employee.setShift(current, shiftCode);
        current = current.add(const Duration(days: 1));
      }
      _currentRoster!.updatedAt = DateTime.now();
      notifyListeners();
    }
  }

  /// Add a new shift code
  void addShiftCode(String code, String name, String color) {
    if (_currentRoster == null) return;
    _currentRoster!.addShiftCode(ShiftCode(
      code: code,
      name: name,
      color: color,
    ));
    notifyListeners();
  }

  /// Update roster title
  void updateTitle(String title) {
    if (_currentRoster == null) return;
    _currentRoster!.title = title;
    _currentRoster!.updatedAt = DateTime.now();
    notifyListeners();
  }

  /// Extend roster date range
  void extendDateRange(DateTime newEndDate) {
    if (_currentRoster == null) return;
    if (newEndDate.isAfter(_currentRoster!.endDate)) {
      // Extend all employees' shifts
      for (final employee in _currentRoster!.employees) {
        var current = _currentRoster!.endDate.add(const Duration(days: 1));
        while (!current.isAfter(newEndDate)) {
          employee.setShift(current, 'R');
          current = current.add(const Duration(days: 1));
        }
      }
      _currentRoster!.endDate = newEndDate;
      _currentRoster!.updatedAt = DateTime.now();
      notifyListeners();
    }
  }

  /// Save current roster to list
  void saveCurrentRoster() {
    if (_currentRoster == null) return;

    final existingIndex = _savedRosters.indexWhere((r) => r.id == _currentRoster!.id);
    if (existingIndex != -1) {
      _savedRosters[existingIndex] = _currentRoster!;
    } else {
      _savedRosters.add(_currentRoster!);
    }
    notifyListeners();
  }

  /// Load a saved roster
  void loadRoster(String rosterId) {
    try {
      _currentRoster = _savedRosters.firstWhere((r) => r.id == rosterId);
      notifyListeners();
    } catch (_) {
      _errorMessage = 'Roster not found';
      notifyListeners();
    }
  }

  /// Delete a saved roster
  void deleteRoster(String rosterId) {
    _savedRosters.removeWhere((r) => r.id == rosterId);
    if (_currentRoster?.id == rosterId) {
      _currentRoster = null;
    }
    notifyListeners();
  }

  /// Get statistics for current roster
  Map<String, dynamic> getRosterStatistics() {
    if (_currentRoster == null) {
      return {};
    }

    final roster = _currentRoster!;
    final stats = <String, dynamic>{
      'employeeCount': roster.employees.length,
      'dayCount': roster.numberOfDays,
      'shiftBreakdown': <String, int>{},
      'employeeStats': <String, Map<String, int>>{},
    };

    // Calculate shift breakdown
    final shiftCounts = <String, int>{};
    final employeeShiftCounts = <String, Map<String, int>>{};

    for (final employee in roster.employees) {
      employeeShiftCounts[employee.name] = {};

      for (final date in roster.dateRange) {
        final shift = employee.getShift(date);
        shiftCounts[shift] = (shiftCounts[shift] ?? 0) + 1;
        employeeShiftCounts[employee.name]![shift] =
            (employeeShiftCounts[employee.name]![shift] ?? 0) + 1;
      }
    }

    stats['shiftBreakdown'] = shiftCounts;
    stats['employeeStats'] = employeeShiftCounts;

    return stats;
  }

  /// Get shifts for a specific date
  Map<String, String> getShiftsForDate(DateTime date) {
    if (_currentRoster == null) {
      return {};
    }
    return _currentRoster!.getShiftsForDate(date);
  }

  /// Export roster to JSON string
  String? exportToJson() {
    return _currentRoster?.toJsonString();
  }

  /// Import roster from JSON string
  bool importFromJson(String jsonString) {
    try {
      final roster = Roster.fromJsonString(jsonString);
      _currentRoster = roster;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to import roster: $e';
      notifyListeners();
      return false;
    }
  }

  /// Set loading state
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
