import 'dart:convert';
import 'package:http/http.dart' as http;

class HolidayCountry {
  final String code;
  final String name;

  const HolidayCountry({required this.code, required this.name});
}

class HolidayItem {
  final DateTime date;
  final String name;
  final String localName;
  final List<String> types;

  const HolidayItem({
    required this.date,
    required this.name,
    required this.localName,
    required this.types,
  });
}

class HolidayService {
  HolidayService._internal();
  static final HolidayService instance = HolidayService._internal();

  static const String _baseUrl = 'https://date.nager.at/api/v3';
  List<HolidayCountry>? _cachedCountries;

  Future<List<HolidayCountry>> getCountries() async {
    if (_cachedCountries != null) {
      return _cachedCountries!;
    }
    final response = await http.get(Uri.parse('$_baseUrl/AvailableCountries'));
    if (response.statusCode != 200) {
      throw Exception('Holiday countries error: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    final countries = decoded
        .map((item) => HolidayCountry(
              code: item['countryCode'] as String,
              name: item['name'] as String,
            ))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _cachedCountries = countries;
    return countries;
  }

  Future<List<HolidayItem>> getHolidays({
    required String countryCode,
    required int year,
  }) async {
    final url = Uri.parse('$_baseUrl/PublicHolidays/$year/$countryCode');
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('Holiday list error: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((item) {
      final typesRaw = item['types'] as List<dynamic>? ?? [];
      return HolidayItem(
        date: DateTime.parse(item['date'] as String),
        name: item['name'] as String,
        localName: item['localName'] as String? ?? item['name'] as String,
        types: typesRaw.map((t) => t.toString()).toList(),
      );
    }).toList();
  }
}
