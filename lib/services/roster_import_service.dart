import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;

import 'package:roster_champ/services/activity_log_service.dart';

enum ImportDocumentType { roster, table, unknown }

class ImportedRoster {
  ImportedRoster({
    required this.title,
    required this.staff,
    required this.dates,
    required this.assignments,
    required this.confidence,
    required this.documentType,
    required this.documentConfidence,
    required this.rawLines,
    required this.ImportSource,
    required this.ocrSource,
    required this.mlKitLineCount,
    required this.textractLineCount,
  });

  final String title;
  final List<String> staff;
  final List<DateTime> dates;
  final Map<String, Map<DateTime, String>> assignments;
  final Map<String, Map<DateTime, double>> confidence;
  final ImportDocumentType documentType;
  final double documentConfidence;
  final List<String> rawLines;
  final String ImportSource;
  final String ocrSource;
  final int mlKitLineCount;
  final int textractLineCount;
}

class RosterImportService {
  static final RosterImportService instance = RosterImportService._();
  RosterImportService._();

  Future<ImportedRoster> importFile(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.csv') {
      final text = await file.readAsString();
      return importFromCsv(text, title: p.basenameWithoutExtension(file.path));
    }

    ActivityLogService.instance.addError(
      'OCR removed',
      const ['Export your roster as CSV and import it.'],
      details: 'Only CSV import is supported. OCR (image/PDF) was removed.',
    );
    throw UnsupportedError('Only CSV import is supported.');
  }

  Future<ImportedRoster> importFromCsv(
    String text, {
    required String title,
  }) async {
    final rows = const CsvToListConverter().convert(text);
    if (rows.isEmpty) {
      throw FormatException('CSV is empty.');
    }

    final header = rows.first.map((e) => e.toString().trim()).toList();
    if (header.length < 2) {
      throw FormatException('CSV must include staff name column and date columns.');
    }

    final dates = <DateTime>[];
    for (var i = 1; i < header.length; i++) {
      final d = _parseDate(header[i]);
      if (d != null) dates.add(d);
    }
    if (dates.isEmpty) {
      throw FormatException('No date columns detected in CSV header.');
    }

    final staff = <String>[];
    final assignments = <String, Map<DateTime, String>>{};
    final confidence = <String, Map<DateTime, double>>{};

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r].map((e) => e.toString().trim()).toList();
      if (row.isEmpty) continue;
      final name = row[0];
      if (name.isEmpty) continue;
      staff.add(name);
      assignments[name] = <DateTime, String>{};
      confidence[name] = <DateTime, double>{};
      for (var c = 1; c < row.length && c <= dates.length; c++) {
        final v = row[c].trim();
        if (v.isNotEmpty) {
          assignments[name]![dates[c - 1]] = v;
        }
        confidence[name]![dates[c - 1]] = 1.0;
      }
    }

    return ImportedRoster(
      title: title,
      staff: staff,
      dates: dates,
      assignments: assignments,
      confidence: confidence,
      documentType: ImportDocumentType.roster,
      documentConfidence: 1.0,
      rawLines: text.split(RegExp(r'\r?\n')),
      ImportSource: 'csv',
      ocrSource: 'csv',
      mlKitLineCount: 0,
      textractLineCount: 0,
    );
  }

  Future<ImportedRoster> importFromImage(
    File file, {
    required String title,
  }) async {
    ActivityLogService.instance.addError(
      'OCR removed',
      const ['Export your roster as CSV and import it.'],
      details: 'Image import is not supported. OCR was removed.',
    );
    throw UnsupportedError('Image import is not supported.');
  }

  Future<ImportedRoster> importFromPdf(
    File file, {
    required String title,
  }) async {
    ActivityLogService.instance.addError(
      'OCR removed',
      const ['Export your roster as CSV and import it.'],
      details: 'PDF import is not supported. OCR was removed.',
    );
    throw UnsupportedError('PDF import is not supported.');
  }

  Future<List<String>> extractRawLinesFromFile(File file) async {
    if (p.extension(file.path).toLowerCase() == '.csv') {
      final text = await file.readAsString();
      return text.split(RegExp(r'\r?\n'));
    }
    ActivityLogService.instance.addError(
      'OCR removed',
      const ['Export your roster as CSV and import it.'],
      details: 'Raw text extraction is not supported. OCR was removed.',
    );
    return <String>[];
  }

  Future<ImportedRoster> importFromTable(
    List<List<String>> table, {
    required String title,
    required ImportDocumentType documentType,
    required double documentConfidence,
    required List<String> rawLines,
  }) async {
    if (table.isEmpty) {
      throw FormatException('Import table is empty.');
    }
    final header = table.first.map((e) => e.toString().trim()).toList();
    if (header.length < 2) {
      throw FormatException('Table must include staff name column and date columns.');
    }
    final dates = <DateTime>[];
    for (var i = 1; i < header.length; i++) {
      final d = _parseDate(header[i]);
      if (d != null) dates.add(d);
    }
    if (dates.isEmpty) {
      throw FormatException('No date columns detected in table header.');
    }

    final staff = <String>[];
    final assignments = <String, Map<DateTime, String>>{};
    final confidence = <String, Map<DateTime, double>>{};

    for (var r = 1; r < table.length; r++) {
      final row = table[r].map((e) => e.toString().trim()).toList();
      if (row.isEmpty) continue;
      final name = row[0];
      if (name.isEmpty) continue;
      staff.add(name);
      assignments[name] = <DateTime, String>{};
      confidence[name] = <DateTime, double>{};
      for (var c = 1; c < row.length && c <= dates.length; c++) {
        final v = row[c].trim();
        if (v.isNotEmpty) {
          assignments[name]![dates[c - 1]] = v;
        }
        confidence[name]![dates[c - 1]] = 1.0;
      }
    }

    return ImportedRoster(
      title: title,
      staff: staff,
      dates: dates,
      assignments: assignments,
      confidence: confidence,
      documentType: documentType,
      documentConfidence: documentConfidence,
      rawLines: rawLines,
      ImportSource: 'table',
      ocrSource: 'csv',
      mlKitLineCount: 0,
      textractLineCount: 0,
    );
  }

  Map<String, dynamic> toRosterJson(ImportedRoster roster) {
    final now = DateTime.now().toIso8601String();
    final staffMembers = <Map<String, dynamic>>[];
    for (var i = 0; i < roster.staff.length; i++) {
      staffMembers.add({
        'id': '${i + 1}',
        'name': roster.staff[i],
        'isActive': true,
        'leaveBalance': 31.0,
        'employmentType': 'permanent',
        'createdAt': now,
      });
    }

    final overrides = <Map<String, dynamic>>[];
    for (final entry in roster.assignments.entries) {
      final name = entry.key;
      final dates = entry.value;
      for (final dateEntry in dates.entries) {
        final shift = normalizeShiftCode(dateEntry.value);
        if (shift.isEmpty) continue;
        overrides.add({
          'id': '${name}_${dateEntry.key.toIso8601String()}',
          'personName': name,
          'date': dateEntry.key.toIso8601String(),
          'shift': shift,
          'reason': 'import',
          'createdAt': now,
        });
      }
    }

    return {
      'staffMembers': staffMembers,
      'masterPattern': [
        List.generate(7, (_) => 'OFF'),
      ],
      'overrides': overrides,
      'events': [],
      'history': [],
      'aiSuggestions': [],
      'regularSwaps': [],
      'availabilityRequests': [],
      'swapRequests': [],
      'swapDebts': [],
      'shiftLocks': [],
      'changeProposals': [],
      'auditLogs': [],
      'generatedRosters': [],
      'quickVariationPresets': [],
      'quickBaseTemplate': null,
      'propagationSettings': null,
      'cycleLength': 1,
      'numPeople': roster.staff.length,
      'weekStartDay': 1,
    };
  }

  static const Set<String> _knownShifts = {
    'E',
    'D',
    'L',
    'N',
    'D12',
    'N12',
    'AL',
    'R',
    'OFF',
    'SICK',
    'C',
    'C1',
    'C2',
    'C3',
    'C4',
    'TR',
    'TRAINING',
  };

  bool isKnownShift(String raw) {
    return _knownShifts.contains(normalizeShiftCode(raw));
  }

  String normalizeShiftCode(String raw) {
    final cleaned = raw.trim().toUpperCase();
    if (cleaned.isEmpty) return '';
    if (cleaned == 'OFF' || cleaned == 'R' || cleaned == 'REST') return 'R';
    if (cleaned == 'AL' || cleaned == 'A/L' || cleaned.contains('ANNUAL')) {
      return 'AL';
    }
    if (cleaned == 'SICK' || cleaned == 'ILL') return 'SICK';
    if (cleaned.startsWith('N')) return cleaned.contains('12') ? 'N12' : 'N';
    if (cleaned.startsWith('D')) return cleaned.contains('12') ? 'D12' : 'D';
    if (cleaned.startsWith('E')) return 'E';
    if (cleaned.startsWith('L')) return 'L';
    if (cleaned.startsWith('C')) return cleaned;
    if (cleaned.startsWith('TR')) return 'TR';
    return cleaned;
  }

  double confidenceForShift(String normalized, String raw) {
    if (normalized.isEmpty) return 0.0;
    final rawNorm = normalizeShiftCode(raw);
    if (normalized == rawNorm) return 0.95;
    return isKnownShift(normalized) ? 0.8 : 0.6;
  }

  DateTime? _parseDate(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return null;
    final iso = DateTime.tryParse(cleaned);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    final m = RegExp(r'^(\d{1,2})[\/-](\d{1,2})[\/-](\d{2,4})$').firstMatch(cleaned);
    if (m != null) {
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2)!);
      final y = int.parse(m.group(3)!);
      final day = a > 12 ? a : b;
      final month = a > 12 ? b : a;
      final year = y < 100 ? (2000 + y) : y;
      return DateTime(year, month, day);
    }
    return null;
  }
}


