import 'package:uuid/uuid.dart';
import '../models.dart';

/// Service for managing shift templates and providing pre-configured patterns
class ShiftTemplateService {
  static final ShiftTemplateService instance = ShiftTemplateService._internal();
  ShiftTemplateService._internal();

  final _uuid = const Uuid();

  /// Get all built-in shift templates
  List<ShiftTemplate> getBuiltInTemplates() {
    return [
      _createHealthcare12HourRotation(),
      _createHealthcare4on4off(),
      _createRetail223Pattern(),
      _createHospitality553Pattern(),
      _createManufacturing3Shift(),
      _createManufacturing4Shift(),
      _createEducationWeekly(),
      _createHealthcareWeekend(),
      _createRetail5on2off(),
      _createHospitality4on3off(),
    ];
  }

  /// Get templates by category
  List<ShiftTemplate> getTemplatesByCategory(ShiftTemplateCategory category) {
    return getBuiltInTemplates()
        .where((template) => template.category == category)
        .toList();
  }

  /// Healthcare: 12-Hour Day/Night Rotation (2 weeks)
  ShiftTemplate _createHealthcare12HourRotation() {
    return ShiftTemplate(
      id: _uuid.v4(),
      name: '12-Hour Day/Night Rotation',
      description:
          'Common healthcare pattern with 12-hour shifts rotating between days and nights. 2-week cycle.',
      category: ShiftTemplateCategory.healthcare,
      cycleLengthWeeks: 2,
      pattern: [
        // Week 1
        ['D', 'D', 'OFF', 'OFF', 'N', 'N', 'OFF'], // Person 1
        ['OFF', 'D', 'D', 'OFF', 'OFF', 'N', 'N'], // Person 2
        ['N', 'OFF', 'D', 'D', 'OFF', 'OFF', 'N'], // Person 3
        ['N', 'N', 'OFF', 'D', 'D', 'OFF', 'OFF'], // Person 4
      ],
      isBuiltIn: true,
      metadata: {
        'shift_hours': {'D': 12, 'N': 12},
        'recommended_staff': 4,
        'provides_24_7_coverage': true,
      },
    );
  }

  /// Healthcare: 4 on 4 off pattern
  ShiftTemplate _createHealthcare4on4off() {
    return ShiftTemplate(
      id: _uuid.v4(),
      name: '4 On 4 Off Pattern',
      description:
          'Work 4 days, off 4 days. Popular in healthcare for work-life balance. 2-week cycle.',
      category: ShiftTemplateCategory.healthcare,
      cycleLengthWeeks: 2,
      pattern: [
        // Week 1
        ['D', 'D', 'D', 'D', 'OFF', 'OFF', 'OFF'],
        ['OFF', 'D', 'D', 'D', 'D', 'OFF', 'OFF'],
        ['OFF', 'OFF', 'D', 'D', 'D', 'D', 'OFF'],
        ['OFF', 'OFF', 'OFF', 'D', 'D', 'D', 'D'],
      ],
      isBuiltIn: true,
      metadata: {
        'shift_hours': {'D': 12},
        'recommended_staff': 4,
        'provides_24_7_coverage': false,
      },
    );
  }

  /// Retail: 2-2-3 Pattern (Dupont Schedule)
  ShiftTemplate _createRetail223Pattern() {
    return ShiftTemplate(
      id: _uuid.v4(),
      name: '2-2-3 Dupont Schedule',
      description:
          'Work 2 days, off 2 days, work 3 days. Repeats every 4 weeks with rotating shifts.',
      category: ShiftTemplateCategory.retail,
      cycleLengthWeeks: 4,
      pattern: [
        // Week 1
        ['D', 'D', 'OFF', 'OFF', 'D', 'D', 'D'],
        ['OFF', 'OFF', 'D', 'D', 'OFF', 'OFF', 'OFF'],
        ['D', 'D', 'D', 'OFF', 'OFF', 'D', 'D'],
        ['OFF', 'OFF', 'OFF', 'D', 'D', 'OFF', 'OFF'],
      ],
      isBuiltIn: true,
      metadata: {
        'shift_hours': {'D': 8},
        'recommended_staff': 4,
        'provides_24_7_coverage': true,
      },
    );
  }

  /// Hospitality: 5-5-3 Pattern
  ShiftTemplate _createHospitality553Pattern() {
    return ShiftTemplate(
      id: _uuid.v4(),
      name: '5-5-3 Hospitality Pattern',
      description:
          'Work 5 days, off 5 days, work 3 days. Great for hospitality industry.',
      category: ShiftTemplateCategory.hospitality,
      cycleLengthWeeks: 3,
      pattern: [
        ['D', 'D', 'D', 'D', 'D', 'OFF', 'OFF'],
        ['OFF', 'OFF', 'D', 'D', 'D', 'D', 'D'],
        ['D', 'D', 'OFF', 'OFF', 'OFF', 'D', 'D'],
        ['OFF', 'OFF', 'OFF', 'D', 'D', 'OFF', 'OFF'],
      ],
      isBuiltIn: true,
      metadata: {
        'shift_hours': {'D': 8},
        'recommended_staff': 4,
        'provides_24_7_coverage': false,
      },
    );
  }

  /// Manufacturing: 3-Shift Continuous
  ShiftTemplate _createManufacturing3Shift() {
    return ShiftTemplate(
      id: _uuid.v4(),
      name: '3-Shift Continuous (24/7)',
      description:
          'Classic 3-shift manufacturing pattern covering 24/7 operations. Rotates through morning, evening, and night shifts.',
      category: ShiftTemplateCategory.manufacturing,
      cycleLengthWeeks: 3,
      pattern: [
        // Week 1: Morning shift
        ['D', 'D', 'D', 'D', 'D', 'OFF', 'OFF'],
        // Week 1: Evening shift
        ['E', 'E', 'E', 'E', 'E', 'OFF', 'OFF'],
        // Week 1: Night shift
        ['N', 'N', 'N', 'N', 'N', 'OFF', 'OFF'],
      ],
      isBuiltIn: true,
      metadata: {
        'shift_hours': {'D': 8, 'E': 8, 'N': 8},
        'recommended_staff': 3,
        'provides_24_7_coverage': true,
        'shift_times': {
          'D': '06:00-14:00',
          'E': '14:00-22:00',
          'N': '22:00-06:00',
        },
      },
    );
  }

  /// Manufacturing: 4-Shift Pattern
  ShiftTemplate _createManufacturing4Shift() {
    return ShiftTemplate(
      id: _uuid.v4(),
      name: '4-Shift Continental',
      description:
          'Continental 4-crew pattern. Provides 24/7 coverage with better work-life balance.',
      category: ShiftTemplateCategory.manufacturing,
      cycleLengthWeeks: 8,
      pattern: [
        // Crew 1
        ['D', 'D', 'D', 'D', 'OFF', 'OFF', 'OFF'],
        // Crew 2
        ['E', 'E', 'E', 'E', 'OFF', 'OFF', 'OFF'],
        // Crew 3
        ['N', 'N', 'N', 'N', 'OFF', 'OFF', 'OFF'],
        // Crew 4
        ['OFF', 'OFF', 'OFF', 'OFF', 'D', 'D', 'D'],
      ],
      isBuiltIn: true,
      metadata: {
        'shift_hours': {'D': 8, 'E': 8, 'N': 8},
        'recommended_staff': 4,
        'provides_24_7_coverage': true,
      },
    );
  }

  /// Education: Weekly Pattern
  ShiftTemplate _createEducationWeekly() {
    return ShiftTemplate(
      id: _uuid.v4(),
      name: 'Education Weekly Schedule',
      description:
          'Standard education/office pattern. Monday-Friday work, weekends off.',
      category: ShiftTemplateCategory.education,
      cycleLengthWeeks: 1,
      pattern: [
        ['D', 'D', 'D', 'D', 'D', 'OFF', 'OFF'],
        ['D', 'D', 'D', 'D', 'D', 'OFF', 'OFF'],
        ['D', 'D', 'D', 'D', 'D', 'OFF', 'OFF'],
      ],
      isBuiltIn: true,
      metadata: {
        'shift_hours': {'D': 8},
        'recommended_staff': 3,
        'provides_24_7_coverage': false,
        'notes': 'Suitable for schools, universities, and standard office hours',
      },
    );
  }

  /// Healthcare: Weekend Pattern
  ShiftTemplate _createHealthcareWeekend() {
    return ShiftTemplate(
      id: _uuid.v4(),
      name: 'Weekend Only Schedule',
      description:
          'Work weekends only (12-hour shifts). Designed for weekend-only staff.',
      category: ShiftTemplateCategory.healthcare,
      cycleLengthWeeks: 1,
      pattern: [
        ['OFF', 'OFF', 'OFF', 'OFF', 'OFF', 'D', 'D'],
        ['OFF', 'OFF', 'OFF', 'OFF', 'OFF', 'N', 'N'],
      ],
      isBuiltIn: true,
      metadata: {
        'shift_hours': {'D': 12, 'N': 12},
        'recommended_staff': 2,
        'provides_24_7_coverage': false,
        'notes': 'Weekend coverage only',
      },
    );
  }

  /// Retail: 5 on 2 off
  ShiftTemplate _createRetail5on2off() {
    return ShiftTemplate(
      id: _uuid.v4(),
      name: 'Retail 5 On 2 Off',
      description:
          'Standard retail pattern. Work 5 days, off 2 days with rotating weekend coverage.',
      category: ShiftTemplateCategory.retail,
      cycleLengthWeeks: 2,
      pattern: [
        ['D', 'D', 'D', 'D', 'D', 'OFF', 'OFF'],
        ['OFF', 'OFF', 'D', 'D', 'D', 'D', 'D'],
        ['D', 'D', 'OFF', 'OFF', 'D', 'D', 'D'],
        ['D', 'D', 'D', 'D', 'OFF', 'OFF', 'D'],
      ],
      isBuiltIn: true,
      metadata: {
        'shift_hours': {'D': 8},
        'recommended_staff': 4,
        'provides_24_7_coverage': false,
        'notes': 'Rotates weekend coverage among staff',
      },
    );
  }

  /// Hospitality: 4 on 3 off
  ShiftTemplate _createHospitality4on3off() {
    return ShiftTemplate(
      id: _uuid.v4(),
      name: 'Hospitality 4 On 3 Off',
      description:
          'Work 4 days (including mixed day/evening shifts), off 3 days.',
      category: ShiftTemplateCategory.hospitality,
      cycleLengthWeeks: 2,
      pattern: [
        ['D', 'D', 'E', 'E', 'OFF', 'OFF', 'OFF'],
        ['OFF', 'OFF', 'OFF', 'D', 'D', 'E', 'E'],
        ['E', 'E', 'OFF', 'OFF', 'OFF', 'D', 'D'],
        ['OFF', 'D', 'D', 'E', 'E', 'OFF', 'OFF'],
      ],
      isBuiltIn: true,
      metadata: {
        'shift_hours': {'D': 8, 'E': 8},
        'recommended_staff': 4,
        'provides_24_7_coverage': false,
        'shift_times': {
          'D': '06:00-14:00',
          'E': '14:00-22:00',
        },
      },
    );
  }

  /// Apply a template to generate a roster pattern
  List<List<String>> applyTemplate(
    ShiftTemplate template,
    int numberOfWeeks,
    List<String> staffNames,
  ) {
    final result = <List<String>>[];
    final cycleLength = template.cycleLengthWeeks;
    final pattern = template.pattern;

    // Calculate how many full cycles we need
    final fullCycles = (numberOfWeeks / cycleLength).ceil();

    // Generate pattern for each staff member
    for (int staffIndex = 0; staffIndex < staffNames.length; staffIndex++) {
      final weekPattern = <String>[];

      // Use modulo to cycle through template pattern
      final templateIndex = staffIndex % pattern.length;

      for (int cycle = 0; cycle < fullCycles; cycle++) {
        // Add the week pattern from template
        weekPattern.addAll(pattern[templateIndex]);
      }

      // Trim to exact number of weeks requested
      final totalDays = numberOfWeeks * 7;
      result.add(weekPattern.take(totalDays).toList());
    }

    return result;
  }

  /// Get template description with details
  String getTemplateDetailedDescription(ShiftTemplate template) {
    final buffer = StringBuffer();
    buffer.writeln(template.description);
    buffer.writeln();
    buffer.writeln('Category: ${template.category.name.toUpperCase()}');
    buffer.writeln('Cycle Length: ${template.cycleLengthWeeks} week(s)');

    if (template.metadata != null) {
      final meta = template.metadata!;

      if (meta.containsKey('shift_hours')) {
        buffer.writeln('\nShift Duration:');
        final hours = meta['shift_hours'] as Map<String, dynamic>;
        hours.forEach((shift, duration) {
          buffer.writeln('  $shift: $duration hours');
        });
      }

      if (meta.containsKey('recommended_staff')) {
        buffer.writeln(
            '\nRecommended Staff: ${meta['recommended_staff']} people');
      }

      if (meta.containsKey('provides_24_7_coverage')) {
        buffer.writeln(
            '24/7 Coverage: ${meta['provides_24_7_coverage'] ? "Yes" : "No"}');
      }

      if (meta.containsKey('shift_times')) {
        buffer.writeln('\nShift Times:');
        final times = meta['shift_times'] as Map<String, dynamic>;
        times.forEach((shift, time) {
          buffer.writeln('  $shift: $time');
        });
      }

      if (meta.containsKey('notes')) {
        buffer.writeln('\nNotes: ${meta['notes']}');
      }
    }

    return buffer.toString();
  }

  /// Create a custom template
  ShiftTemplate createCustomTemplate({
    required String name,
    required String description,
    required ShiftTemplateCategory category,
    required List<List<String>> pattern,
    required int cycleLengthWeeks,
    Map<String, dynamic>? metadata,
  }) {
    return ShiftTemplate(
      id: _uuid.v4(),
      name: name,
      description: description,
      category: category,
      pattern: pattern,
      cycleLengthWeeks: cycleLengthWeeks,
      metadata: metadata,
      isBuiltIn: false,
    );
  }

  /// Validate that a pattern is consistent
  bool validatePattern(List<List<String>> pattern) {
    if (pattern.isEmpty) return false;

    // Check that all rows have the same length
    final firstRowLength = pattern.first.length;
    if (!pattern.every((row) => row.length == firstRowLength)) {
      return false;
    }

    // Check that row length is divisible by 7 (complete weeks)
    if (firstRowLength % 7 != 0) {
      return false;
    }

    return true;
  }
}
