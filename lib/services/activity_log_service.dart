import 'package:flutter/foundation.dart';
import '../models.dart' as models;

class ActivityLogService extends ChangeNotifier {
  ActivityLogService._internal();
  static final ActivityLogService instance = ActivityLogService._internal();

  final List<models.ActivityLogEntry> _entries = [];

  List<models.ActivityLogEntry> get entries => List.unmodifiable(_entries);

  void addEntry(models.ActivityLogEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > 200) {
      _entries.removeRange(200, _entries.length);
    }
    notifyListeners();
  }

  void addInfo(String message, {String? details}) {
    addEntry(models.ActivityLogEntry(
      level: models.ActivityLogLevel.info,
      message: message,
      fixes: const [],
      timestamp: DateTime.now(),
      details: details,
    ));
  }

  void addError(String message, List<String> fixes, {String? details}) {
    addEntry(models.ActivityLogEntry(
      level: models.ActivityLogLevel.error,
      message: message,
      fixes: fixes,
      timestamp: DateTime.now(),
      details: details,
    ));
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
