import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherDay {
  final DateTime date;
  final double maxTemp;
  final double minTemp;
  final double precipChance;

  const WeatherDay({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.precipChance,
  });
}

class WeatherService {
  WeatherService._internal();
  static final WeatherService instance = WeatherService._internal();

  WeatherDay? _cachedDay;
  DateTime? _cacheTime;
  Map<DateTime, WeatherDay>? _cacheWeek;
  String? _cacheKey;

  Future<Map<DateTime, WeatherDay>> getWeekly({
    required double lat,
    required double lon,
  }) async {
    final key = '$lat,$lon';
    final now = DateTime.now();
    if (_cacheWeek != null &&
        _cacheKey == key &&
        _cacheTime != null &&
        now.difference(_cacheTime!) < const Duration(minutes: 30)) {
      return _cacheWeek!;
    }
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max'
      '&timezone=auto',
    );
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('Weather API error: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final daily = data['daily'] as Map<String, dynamic>;
    final dates = (daily['time'] as List<dynamic>)
        .map((d) => DateTime.parse(d as String))
        .toList();
    final maxTemps = (daily['temperature_2m_max'] as List<dynamic>)
        .map((v) => (v as num).toDouble())
        .toList();
    final minTemps = (daily['temperature_2m_min'] as List<dynamic>)
        .map((v) => (v as num).toDouble())
        .toList();
    final precip = (daily['precipitation_probability_max'] as List<dynamic>)
        .map((v) => (v as num).toDouble())
        .toList();
    final map = <DateTime, WeatherDay>{};
    for (var i = 0; i < dates.length; i++) {
      map[DateTime(dates[i].year, dates[i].month, dates[i].day)] = WeatherDay(
        date: dates[i],
        maxTemp: maxTemps[i],
        minTemp: minTemps[i],
        precipChance: precip[i],
      );
    }
    _cacheWeek = map;
    _cacheTime = now;
    _cacheKey = key;
    return map;
  }
}
