import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'roster_import_service.dart';

class RosterImportTemplate {
  final String id;
  final String name;
  final DateTime startDate;
  final int stepDays;
  final String? signature;

  RosterImportTemplate({
    required this.id,
    required this.name,
    required this.startDate,
    required this.stepDays,
    this.signature,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startDate': startDate.toIso8601String(),
        'stepDays': stepDays,
        'signature': signature,
      };

  static RosterImportTemplate fromJson(Map<String, dynamic> json) =>
      RosterImportTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        stepDays: (json['stepDays'] as num?)?.toInt() ?? 1,
        signature: json['signature'] as String?,
      );
}

class RosterImportHistoryEntry {
  final String id;
  final String title;
  final DateTime createdAt;
  final ImportDocumentType documentType;
  final double documentConfidence;
  final List<List<String>> table;
  final List<String> rawLines;
  final String? signature;
  final List<String> auditLog;

  RosterImportHistoryEntry({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.documentType,
    required this.documentConfidence,
    required this.table,
    required this.rawLines,
    required this.signature,
    required this.auditLog,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'documentType': documentType.name,
        'documentConfidence': documentConfidence,
        'table': table,
        'rawLines': rawLines,
        'signature': signature,
        'auditLog': auditLog,
      };

  static RosterImportHistoryEntry fromJson(Map<String, dynamic> json) =>
      RosterImportHistoryEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        documentType: ImportDocumentType.values.firstWhere(
          (type) => type.name == json['documentType'],
          orElse: () => ImportDocumentType.unknown,
        ),
        documentConfidence:
            (json['documentConfidence'] as num?)?.toDouble() ?? 0.0,
        table: (json['table'] as List<dynamic>? ?? [])
            .map((row) => (row as List<dynamic>)
                .map((cell) => cell.toString())
                .toList())
            .toList(),
        rawLines: (json['rawLines'] as List<dynamic>? ?? [])
            .map((line) => line.toString())
            .toList(),
        signature: json['signature'] as String?,
        auditLog: (json['auditLog'] as List<dynamic>? ?? [])
            .map((entry) => entry.toString())
            .toList(),
      );
}

class RosterImportPrefs {
  static const _templatesKey = 'import_templates';
  static const _historyKey = 'import_history';
  static const _correctionsKey = 'import_corrections';
  static const int _historyLimit = 10;

  static Future<List<RosterImportTemplate>> loadTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_templatesKey);
    if (raw == null || raw.isEmpty) return [];
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .map((entry) =>
            RosterImportTemplate.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveTemplate(RosterImportTemplate template) async {
    final templates = await loadTemplates();
    final updated = [
      template,
      ...templates.where((t) => t.id != template.id),
    ];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _templatesKey,
      jsonEncode(updated.map((t) => t.toJson()).toList()),
    );
  }

  static Future<void> deleteTemplate(String id) async {
    final templates = await loadTemplates();
    final updated = templates.where((t) => t.id != id).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _templatesKey,
      jsonEncode(updated.map((t) => t.toJson()).toList()),
    );
  }

  static Future<List<RosterImportHistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .map((entry) =>
            RosterImportHistoryEntry.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  static Future<void> addHistory(RosterImportHistoryEntry entry) async {
    final history = await loadHistory();
    final updated = [entry, ...history];
    if (updated.length > _historyLimit) {
      updated.removeRange(_historyLimit, updated.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  static Future<Map<String, String>> loadCorrections() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_correctionsKey);
    if (raw == null || raw.isEmpty) return {};
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return data.map((key, value) => MapEntry(key, value.toString()));
  }

  static Future<void> saveCorrections(Map<String, String> corrections) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_correctionsKey, jsonEncode(corrections));
  }

  static Future<void> mergeCorrections(Map<String, String> additions) async {
    if (additions.isEmpty) return;
    final current = await loadCorrections();
    current.addAll(additions);
    await saveCorrections(current);
  }
}
