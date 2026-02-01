import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Represents a complete staff roster
class Roster {
  final String id;
  String title;
  DateTime startDate;
  DateTime endDate;
  final Map<String, ShiftCode> shiftCodes;
  final List<Employee> employees;
  DateTime createdAt;
  DateTime updatedAt;

  Roster({
    String? id,
    this.title = 'Staff Roster',
    required this.startDate,
    required this.endDate,
    Map<String, ShiftCode>? shiftCodes,
    List<Employee>? employees,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        shiftCodes = shiftCodes ?? _defaultShiftCodes,
        employees = employees ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static final Map<String, ShiftCode> _defaultShiftCodes = {
    'R': ShiftCode(code: 'R', name: 'Rest', color: '#FFFFFF'),
    'N12': ShiftCode(code: 'N12', name: 'Night 12hr', color: '#E3F2FD'),
    'N': ShiftCode(code: 'N', name: 'Night', color: '#FFFF00'),
    'D': ShiftCode(code: 'D', name: 'Day', color: '#FFEB3B'),
    'E': ShiftCode(code: 'E', name: 'Evening', color: '#FFF9C4'),
    'C': ShiftCode(code: 'C', name: 'Cover', color: '#E8E8E8'),
    'L': ShiftCode(code: 'L', name: 'Late', color: '#FFFFFF'),
    'A/L': ShiftCode(code: 'A/L', name: 'Annual Leave', color: '#FFEB3B'),
    'AD': ShiftCode(code: 'AD', name: 'Admin Day', color: '#E0E0E0'),
    'Tr': ShiftCode(code: 'Tr', name: 'Training', color: '#4CAF50'),
    'Sick': ShiftCode(code: 'Sick', name: 'Sick Leave', color: '#F44336'),
  };

  /// Get all dates in the roster range
  List<DateTime> get dateRange {
    final dates = <DateTime>[];
    var current = startDate;
    while (!current.isAfter(endDate)) {
      dates.add(current);
      current = current.add(const Duration(days: 1));
    }
    return dates;
  }

  /// Get number of days in roster
  int get numberOfDays => endDate.difference(startDate).inDays + 1;

  /// Add a new employee
  void addEmployee(Employee employee) {
    employees.add(employee);
    updatedAt = DateTime.now();
  }

  /// Remove an employee by ID
  bool removeEmployee(String employeeId) {
    final index = employees.indexWhere((e) => e.id == employeeId);
    if (index != -1) {
      employees.removeAt(index);
      updatedAt = DateTime.now();
      return true;
    }
    return false;
  }

  /// Get employee by ID
  Employee? getEmployee(String employeeId) {
    try {
      return employees.firstWhere((e) => e.id == employeeId);
    } catch (_) {
      return null;
    }
  }

  /// Update a shift for an employee
  void updateShift(String employeeId, DateTime date, String shiftCode) {
    final employee = getEmployee(employeeId);
    if (employee != null) {
      employee.setShift(date, shiftCode);
      updatedAt = DateTime.now();
    }
  }

  /// Get all shifts for a specific date
  Map<String, String> getShiftsForDate(DateTime date) {
    final dateKey = _dateToKey(date);
    final shifts = <String, String>{};
    for (final employee in employees) {
      shifts[employee.name] = employee.shifts[dateKey] ?? 'R';
    }
    return shifts;
  }

  /// Add a new shift code
  void addShiftCode(ShiftCode code) {
    shiftCodes[code.code] = code;
    updatedAt = DateTime.now();
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'shiftCodes': shiftCodes.map((k, v) => MapEntry(k, v.toJson())),
      'employees': employees.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Create from JSON
  factory Roster.fromJson(Map<String, dynamic> json) {
    return Roster(
      id: json['id'] as String?,
      title: json['title'] as String? ?? 'Staff Roster',
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      shiftCodes: (json['shiftCodes'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, ShiftCode.fromJson(v as Map<String, dynamic>)),
          ) ??
          _defaultShiftCodes,
      employees: (json['employees'] as List<dynamic>?)
              ?.map((e) => Employee.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  /// Export to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Create from JSON string
  factory Roster.fromJsonString(String jsonString) {
    return Roster.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  static String _dateToKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Represents an employee in the roster
class Employee {
  final String id;
  String name;
  final Map<String, String> shifts; // Date key -> Shift code

  Employee({
    String? id,
    required this.name,
    Map<String, String>? shifts,
  })  : id = id ?? const Uuid().v4(),
        shifts = shifts ?? {};

  /// Get shift for a specific date
  String getShift(DateTime date) {
    final key = _dateToKey(date);
    return shifts[key] ?? 'R';
  }

  /// Set shift for a specific date
  void setShift(DateTime date, String shiftCode) {
    final key = _dateToKey(date);
    shifts[key] = shiftCode;
  }

  /// Fill all dates with a default shift
  void fillDates(DateTime start, DateTime end, String defaultShift) {
    var current = start;
    while (!current.isAfter(end)) {
      setShift(current, defaultShift);
      current = current.add(const Duration(days: 1));
    }
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'shifts': shifts,
    };
  }

  /// Create from JSON
  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as String?,
      name: json['name'] as String,
      shifts: (json['shifts'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as String),
          ) ??
          {},
    );
  }

  static String _dateToKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Represents a shift code definition
class ShiftCode {
  final String code;
  String name;
  String color;

  ShiftCode({
    required this.code,
    required this.name,
    required this.color,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'color': color,
    };
  }

  /// Create from JSON
  factory ShiftCode.fromJson(Map<String, dynamic> json) {
    return ShiftCode(
      code: json['code'] as String,
      name: json['name'] as String,
      color: json['color'] as String,
    );
  }
}
