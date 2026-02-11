import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import 'analytics_service.dart';

class AdaptiveLearningService {
  AdaptiveLearningService._internal();

  static final AdaptiveLearningService instance =
      AdaptiveLearningService._internal();

  static const _correctionsKey = 'adaptive_shift_corrections';
  static const _eventsKey = 'adaptive_learning_events';
  static const _maxEvents = 200;

  Future<void> recordShiftCorrections(
    Map<String, String> mapping,
    AppSettings settings,
  ) async {
    if (!settings.adaptiveLearningEnabled || mapping.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await _loadCorrectionCounts(prefs);
    mapping.forEach((raw, normalized) {
      final rawKey = raw.trim().toUpperCase();
      final normalizedKey = normalized.trim().toUpperCase();
      if (rawKey.isEmpty || normalizedKey.isEmpty) return;
      final bucket = current.putIfAbsent(rawKey, () => {});
      bucket[normalizedKey] = (bucket[normalizedKey] ?? 0) + 1;
    });
    await prefs.setString(_correctionsKey, jsonEncode(current));

    if (settings.adaptiveLearningGlobalOptIn) {
      await _enqueueGlobalEvent(
        {
          'type': 'shift_corrections',
          'data': mapping,
        },
      );
    }
  }

  Future<void> recordSmartFillUsage(AppSettings settings) async {
    if (!settings.adaptiveLearningEnabled) return;
    if (settings.adaptiveLearningGlobalOptIn) {
      await _enqueueGlobalEvent({'type': 'smart_fill'});
    }
  }

  Future<void> recordBulkReplace(
    String from,
    String to,
    AppSettings settings,
  ) async {
    if (!settings.adaptiveLearningEnabled) return;
    if (settings.adaptiveLearningGlobalOptIn) {
      await _enqueueGlobalEvent(
        {
          'type': 'bulk_replace',
          'data': {'from': from, 'to': to},
        },
      );
    }
  }

  Future<void> recordLayoutSignature(
    String signature,
    AppSettings settings,
  ) async {
    if (!settings.adaptiveLearningEnabled) return;
    if (settings.adaptiveLearningGlobalOptIn) {
      await _enqueueGlobalEvent(
        {
          'type': 'layout_signature',
          'data': {'signature': signature},
        },
      );
    }
  }

  Future<Map<String, Map<String, int>>> loadLocalCorrections() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadCorrectionCounts(prefs);
  }

  Future<Map<String, String>> buildMappingForUnknown(
    Set<String> unknownCodes,
    AppSettings settings,
  ) async {
    if (!settings.adaptiveLearningEnabled || unknownCodes.isEmpty) return {};
    final counts = await loadLocalCorrections();
    final mapping = <String, String>{};
    for (final code in unknownCodes) {
      final options = counts[code];
      if (options == null || options.isEmpty) continue;
      final sorted = options.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      mapping[code] = sorted.first.key;
    }
    return mapping;
  }

  Future<void> clearLocalLearning() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_correctionsKey);
    await prefs.remove(_eventsKey);
  }

  Future<void> _enqueueGlobalEvent(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_eventsKey);
    final events = raw == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    events.insert(0, {
      'timestamp': DateTime.now().toIso8601String(),
      ...payload,
    });
    if (events.length > _maxEvents) {
      events.removeRange(_maxEvents, events.length);
    }
    await prefs.setString(_eventsKey, jsonEncode(events));
    AnalyticsService.instance.trackEvent(
      'adaptive_learning',
      type: 'learning',
      properties: payload,
    );
  }

  Future<Map<String, Map<String, int>>> _loadCorrectionCounts(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_correctionsKey);
    if (raw == null || raw.isEmpty) return {};
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final result = <String, Map<String, int>>{};
    data.forEach((key, value) {
      final bucket = <String, int>{};
      (value as Map).forEach((k, v) {
        bucket[k.toString()] = (v as num).toInt();
      });
      result[key] = bucket;
    });
    return result;
  }
}
