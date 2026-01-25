import 'dart:convert';
import 'package:http/http.dart' as http;

class TimeInfo {
  final DateTime dateTime;
  final String timezone;

  const TimeInfo({required this.dateTime, required this.timezone});
}

class TimeService {
  TimeService._internal();
  static final TimeService instance = TimeService._internal();

  final Map<String, TimeInfo> _cache = {};
  final Map<String, DateTime> _cacheTime = {};

  Future<TimeInfo> getTime(String timezone) async {
    if (timezone.isEmpty) {
      throw Exception('Timezone not set');
    }
    final now = DateTime.now();
    final cached = _cache[timezone];
    final cachedAt = _cacheTime[timezone];
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < const Duration(minutes: 10)) {
      return cached;
    }
    final url = Uri.parse('https://worldtimeapi.org/api/timezone/$timezone');
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('Time API error: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final dateTime = DateTime.parse(data['datetime'] as String);
    final info = TimeInfo(dateTime: dateTime, timezone: timezone);
    _cache[timezone] = info;
    _cacheTime[timezone] = now;
    return info;
  }
}
