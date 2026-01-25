import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StaffNameStore extends ChangeNotifier {
  StaffNameStore._internal();
  static final StaffNameStore instance = StaffNameStore._internal();

  static const _maxNames = 200;
  List<String> _names = [];
  String _key = 'staff_name_history_guest';

  List<String> get names => List.unmodifiable(_names);

  Future<void> loadForUser({String? userId, String? email}) async {
    final key = _buildKey(userId: userId, email: email);
    if (key == _key && _names.isNotEmpty) return;
    _key = key;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    _names = _dedupe(raw);
    notifyListeners();
  }

  Future<void> addName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final updated = [trimmed, ..._names];
    _names = _dedupe(updated).take(_maxNames).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _names);
    notifyListeners();
  }

  Future<void> addNames(Iterable<String> names) async {
    final updated = [...names, ..._names]
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    _names = _dedupe(updated).take(_maxNames).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _names);
    notifyListeners();
  }

  String _buildKey({String? userId, String? email}) {
    final token = (userId?.trim().isNotEmpty ?? false)
        ? userId!.trim()
        : (email?.trim().isNotEmpty ?? false)
            ? email!.trim()
            : 'guest';
    return 'staff_name_history_$token';
  }

  List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final key = value.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(value);
    }
    return result;
  }
}
