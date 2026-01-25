import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart' as models;
import 'config/env_loader.dart';
import 'aws_service.dart';

class AiService {
  static final AiService _instance = AiService._internal();
  static AiService get instance => _instance;

  AiService._internal();

  bool _initialized = false;
  String? _apiUrl;

  Future<void> initialize() async {
    try {
      await EnvLoader.instance.load();
      _apiUrl = EnvLoader.instance.get('AWS_API_URL');
      if (_apiUrl == null || _apiUrl!.isEmpty) {
        debugPrint('AI API URL not set in .env file');
        _initialized = false;
      } else {
        _initialized = true;
        debugPrint('AI service initialized');
      }
    } catch (e) {
      debugPrint('AI initialization error: $e');
      _initialized = false;
    }
  }

  Future<bool> checkConnection() async {
    try {
      if (_apiUrl == null || _apiUrl!.isEmpty) {
        return false;
      }
      final response = await http
          .get(Uri.parse('$_apiUrl/health'))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('AI connection check failed: $e');
      return false;
    }
  }

  bool get isConfigured => _apiUrl != null && _apiUrl!.isNotEmpty;

  Future<List<models.AiSuggestion>> generateRosterSuggestions({
    required List<models.StaffMember> staff,
    required List<models.Override> overrides,
    required List<List<String>> pattern,
    required List<models.Event> events,
    required models.RosterConstraints constraints,
    required Map<String, dynamic> healthScore,
    Map<String, dynamic>? policySummary,
  }) async {
    if (!_initialized || _apiUrl == null) {
      throw Exception('AI service not properly initialized');
    }

    try {
      final url = Uri.parse('$_apiUrl/ai/suggestions');
      final payload = jsonEncode({
          'staff': staff.map((s) => s.toJson()).toList(),
          'overrides': overrides.map((o) => o.toJson()).toList(),
          'pattern': pattern,
          'events': events.map((e) => e.toJson()).toList(),
          'constraints': constraints.toJson(),
          'healthScore': healthScore,
          'policySummary': policySummary ?? {},
        });
      final headers =
          await AwsService.instance.signedHeaders('POST', url, payload);
      final response = await http.post(
        url,
        headers: headers,
        body: payload,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (data['suggestions'] as List<dynamic>? ?? []);
        final now = DateTime.now();
        return list.map((item) {
          final map = item as Map<String, dynamic>;
          return models.AiSuggestion(
            id: map['id'] as String? ??
                'ai_${now.millisecondsSinceEpoch}_${list.indexOf(item)}',
            title: map['title'] as String? ?? 'AI Suggestion',
            description: map['description'] as String? ?? '',
            reason: map['reason'] as String?,
            priority: models.SuggestionPriority
                .values[(map['priority'] as int?) ?? 0],
            type:
                models.SuggestionType.values[(map['type'] as int?) ?? 0],
            createdDate: now,
            affectedStaff: (map['affectedStaff'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList(),
            actionType: map['actionType'] != null
                ? models.SuggestionActionType
                    .values[map['actionType'] as int]
                : null,
            actionPayload: map['actionPayload'] as Map<String, dynamic>?,
            impactScore: (map['impactScore'] as num?)?.toDouble(),
            confidence: (map['confidence'] as num?)?.toDouble(),
            metrics: map['metrics'] as Map<String, dynamic>?,
          );
        }).toList();
      } else {
        throw Exception('AI API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('AI API call failed: $e');
      return [];
    }
  }

  Future<models.PatternRecognitionResult?> analyzePattern({
    required List<List<String>> pattern,
    required List<models.StaffMember> staff,
  }) async {
    return null;
  }

  Future<String> generateRosterDescription({
    required List<models.StaffMember> staff,
    required int cycleLength,
    required Map<String, dynamic> statistics,
  }) async {
    return 'Roster analysis unavailable';
  }
}
