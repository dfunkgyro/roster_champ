import 'dart:convert';
import 'package:http/http.dart' as http;
import 'holiday_service.dart';

class ObservanceService {
  ObservanceService._internal();
  static final ObservanceService instance = ObservanceService._internal();

  static const String _baseUrl = 'https://calendarific.com/api/v2/holidays';
  final Map<String, List<HolidayItem>> _cache = {};

  Future<List<HolidayItem>> getObservances({
    required String apiKey,
    required String countryCode,
    required int year,
    List<String> types = const ['religious', 'observance'],
  }) async {
    if (apiKey.trim().isEmpty) return [];
    final typeParam = types.map((t) => t.toLowerCase()).join(',');
    final cacheKey = '$countryCode-$year-$typeParam';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'api_key': apiKey,
      'country': countryCode,
      'year': year.toString(),
      'type': typeParam,
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Observance list error: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final holidays =
        (decoded['response']?['holidays'] as List<dynamic>? ?? []);
    final items = holidays.map((item) {
      final dateRaw = item['date']?['iso'] as String? ?? '';
      final typesRaw = item['type'] as List<dynamic>? ?? [];
      return HolidayItem(
        date: DateTime.parse(dateRaw),
        name: item['name'] as String? ?? 'Observance',
        localName: item['name'] as String? ?? 'Observance',
        types: typesRaw.map((t) => t.toString()).toList(),
      );
    }).toList();
    _cache[cacheKey] = items;
    return items;
  }
}
