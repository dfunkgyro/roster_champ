import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models.dart' as models;
import '../aws_service.dart';

class AnalyticsService extends ChangeNotifier {
  AnalyticsService._internal();

  static final AnalyticsService instance = AnalyticsService._internal();
  static const _storageKey = 'analytics_events';
  static const _maxStored = 1500;
  static const _batchSize = 50;

  final List<models.AnalyticsEvent> _events = [];
  bool _initialized = false;
  bool _enabled = true;
  bool _cloudEnabled = true;
  String _sessionId = const Uuid().v4();
  Timer? _flushTimer;

  List<models.AnalyticsEvent> get events => List.unmodifiable(_events);
  bool get enabled => _enabled;
  bool get cloudEnabled => _cloudEnabled;
  String get sessionId => _sessionId;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _loadFromStorage();
  }

  void updateSettings(models.AppSettings settings) {
    _enabled = settings.analyticsEnabled;
    _cloudEnabled = settings.analyticsCloudEnabled;
    if (_cloudEnabled) {
      _scheduleFlush();
    } else {
      _flushTimer?.cancel();
    }
    notifyListeners();
  }

  void trackEvent(
    String name, {
    String type = 'action',
    Map<String, dynamic>? properties,
    String? rosterId,
  }) {
    if (!_enabled) return;
    final event = models.AnalyticsEvent(
      id: '${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4()}',
      name: name,
      type: type,
      timestamp: DateTime.now(),
      userId: AwsService.instance.userId,
      rosterId: rosterId ?? AwsService.instance.currentRosterId,
      sessionId: _sessionId,
      properties: properties ?? const {},
    );
    _events.add(event);
    if (_events.length > _maxStored) {
      _events.removeRange(0, _events.length - _maxStored);
    }
    _persist();
    _scheduleFlush();
    notifyListeners();
  }

  Map<String, int> getTopEvents({int limit = 5}) {
    final counts = <String, int>{};
    for (final event in _events) {
      counts[event.name] = (counts[event.name] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map<String, int>.fromEntries(sorted.take(limit));
  }

  int countSince(Duration duration) {
    final cutoff = DateTime.now().subtract(duration);
    return _events.where((e) => e.timestamp.isAfter(cutoff)).length;
  }

  Future<void> flushToAws() async {
    if (!_cloudEnabled || !_enabled) return;
    if (!AwsService.instance.isConfigured ||
        !AwsService.instance.isAuthenticated) {
      return;
    }
    final pending = _events.where((e) => e.uploadedAt == null).toList();
    if (pending.isEmpty) return;
    final batch = pending.take(_batchSize).toList();
    try {
      await AwsService.instance.sendAnalyticsEvents(batch);
      final now = DateTime.now();
      for (int i = 0; i < _events.length; i++) {
        final event = _events[i];
        if (batch.any((b) => b.id == event.id)) {
          _events[i] = event.copyWith(uploadedAt: now);
        }
      }
      await _persist();
      notifyListeners();
    } catch (e) {
      debugPrint('Analytics upload failed: $e');
    }
  }

  Future<void> clearLocal() async {
    _events.clear();
    await _persist();
    notifyListeners();
  }

  void _scheduleFlush() {
    if (!_cloudEnabled) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 15), () async {
      await flushToAws();
    });
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _events
        ..clear()
        ..addAll(
          list.map(
            (e) => models.AnalyticsEvent.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          ),
        );
    } catch (e) {
      debugPrint('Analytics load error: $e');
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_events.map((e) => e.toJson()).toList()),
    );
  }
}
