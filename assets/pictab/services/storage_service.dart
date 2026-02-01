import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/roster.dart';
import '../models/data_table.dart';

/// Service for persisting data locally
class StorageService {
  late SharedPreferences _prefs;
  late Directory _documentsDir;

  static const String _rostersKey = 'saved_rosters';
  static const String _tablesKey = 'saved_tables';
  static const String _settingsKey = 'app_settings';

  /// Initialize the storage service
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _documentsDir = await getApplicationDocumentsDirectory();

    // Create subdirectories if they don't exist
    final rostersDir = Directory('${_documentsDir.path}/rosters');
    final tablesDir = Directory('${_documentsDir.path}/tables');
    final exportsDir = Directory('${_documentsDir.path}/exports');

    if (!await rostersDir.exists()) await rostersDir.create(recursive: true);
    if (!await tablesDir.exists()) await tablesDir.create(recursive: true);
    if (!await exportsDir.exists()) await exportsDir.create(recursive: true);
  }

  // ==================== Roster Storage ====================

  /// Save a roster to storage
  Future<bool> saveRoster(Roster roster) async {
    try {
      final file = File('${_documentsDir.path}/rosters/${roster.id}.json');
      await file.writeAsString(roster.toJsonString());

      // Update roster list in preferences
      final rosterIds = _prefs.getStringList(_rostersKey) ?? [];
      if (!rosterIds.contains(roster.id)) {
        rosterIds.add(roster.id);
        await _prefs.setStringList(_rostersKey, rosterIds);
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Load a roster from storage
  Future<Roster?> loadRoster(String id) async {
    try {
      final file = File('${_documentsDir.path}/rosters/$id.json');
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        return Roster.fromJsonString(jsonString);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get list of saved roster IDs
  List<String> getSavedRosterIds() {
    return _prefs.getStringList(_rostersKey) ?? [];
  }

  /// Load all saved rosters
  Future<List<Roster>> loadAllRosters() async {
    final ids = getSavedRosterIds();
    final rosters = <Roster>[];

    for (final id in ids) {
      final roster = await loadRoster(id);
      if (roster != null) {
        rosters.add(roster);
      }
    }

    return rosters;
  }

  /// Delete a roster from storage
  Future<bool> deleteRoster(String id) async {
    try {
      final file = File('${_documentsDir.path}/rosters/$id.json');
      if (await file.exists()) {
        await file.delete();
      }

      final rosterIds = _prefs.getStringList(_rostersKey) ?? [];
      rosterIds.remove(id);
      await _prefs.setStringList(_rostersKey, rosterIds);

      return true;
    } catch (e) {
      return false;
    }
  }

  // ==================== Table Storage ====================

  /// Save a data table to storage
  Future<bool> saveTable(ExtractedDataTable table) async {
    try {
      final file = File('${_documentsDir.path}/tables/${table.id}.json');
      await file.writeAsString(table.toJsonString());

      final tableIds = _prefs.getStringList(_tablesKey) ?? [];
      if (!tableIds.contains(table.id)) {
        tableIds.add(table.id);
        await _prefs.setStringList(_tablesKey, tableIds);
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Load a data table from storage
  Future<ExtractedDataTable?> loadTable(String id) async {
    try {
      final file = File('${_documentsDir.path}/tables/$id.json');
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        return ExtractedDataTable.fromJson(jsonDecode(jsonString));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Load all saved tables
  Future<List<ExtractedDataTable>> loadAllTables() async {
    final ids = _prefs.getStringList(_tablesKey) ?? [];
    final tables = <ExtractedDataTable>[];

    for (final id in ids) {
      final table = await loadTable(id);
      if (table != null) {
        tables.add(table);
      }
    }

    return tables;
  }

  /// Delete a table from storage
  Future<bool> deleteTable(String id) async {
    try {
      final file = File('${_documentsDir.path}/tables/$id.json');
      if (await file.exists()) {
        await file.delete();
      }

      final tableIds = _prefs.getStringList(_tablesKey) ?? [];
      tableIds.remove(id);
      await _prefs.setStringList(_tablesKey, tableIds);

      return true;
    } catch (e) {
      return false;
    }
  }

  // ==================== Export Functions ====================

  /// Export roster to JSON file
  Future<File?> exportRosterToJson(Roster roster) async {
    try {
      final fileName =
          '${roster.title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${_documentsDir.path}/exports/$fileName');
      await file.writeAsString(roster.toJsonString());
      return file;
    } catch (e) {
      return null;
    }
  }

  /// Export roster to CSV file
  Future<File?> exportRosterToCsv(Roster roster) async {
    try {
      final fileName =
          '${roster.title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File('${_documentsDir.path}/exports/$fileName');

      final buffer = StringBuffer();

      // Header row with dates
      buffer.write('Employee');
      for (final date in roster.dateRange) {
        buffer.write(',${date.day}/${date.month}');
      }
      buffer.writeln();

      // Employee rows
      for (final employee in roster.employees) {
        buffer.write(_escapeCsv(employee.name));
        for (final date in roster.dateRange) {
          buffer.write(',${employee.getShift(date)}');
        }
        buffer.writeln();
      }

      await file.writeAsString(buffer.toString());
      return file;
    } catch (e) {
      return null;
    }
  }

  /// Export table to CSV file
  Future<File?> exportTableToCsv(ExtractedDataTable table) async {
    try {
      final fileName =
          '${table.title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File('${_documentsDir.path}/exports/$fileName');
      await file.writeAsString(table.toCsv());
      return file;
    } catch (e) {
      return null;
    }
  }

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  // ==================== Settings ====================

  /// Save app settings
  Future<bool> saveSettings(Map<String, dynamic> settings) async {
    try {
      await _prefs.setString(_settingsKey, jsonEncode(settings));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Load app settings
  Map<String, dynamic> loadSettings() {
    try {
      final settingsJson = _prefs.getString(_settingsKey);
      if (settingsJson != null) {
        return jsonDecode(settingsJson) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// Get exports directory path
  String get exportsPath => '${_documentsDir.path}/exports';
}
