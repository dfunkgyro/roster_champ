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
  static final Map<int, DateTime> _chineseNewYearDates = {
    1990: DateTime(1990, 1, 27),
    1991: DateTime(1991, 2, 15),
    1992: DateTime(1992, 2, 4),
    1993: DateTime(1993, 1, 23),
    1994: DateTime(1994, 2, 10),
    1995: DateTime(1995, 1, 31),
    1996: DateTime(1996, 2, 19),
    1997: DateTime(1997, 2, 7),
    1998: DateTime(1998, 1, 28),
    1999: DateTime(1999, 2, 16),
    2000: DateTime(2000, 2, 5),
    2001: DateTime(2001, 1, 24),
    2002: DateTime(2002, 2, 12),
    2003: DateTime(2003, 2, 1),
    2004: DateTime(2004, 1, 22),
    2005: DateTime(2005, 2, 9),
    2006: DateTime(2006, 1, 29),
    2007: DateTime(2007, 2, 18),
    2008: DateTime(2008, 2, 7),
    2009: DateTime(2009, 1, 26),
    2010: DateTime(2010, 2, 14),
    2011: DateTime(2011, 2, 3),
    2012: DateTime(2012, 1, 23),
    2013: DateTime(2013, 2, 10),
    2014: DateTime(2014, 1, 31),
    2015: DateTime(2015, 2, 19),
    2016: DateTime(2016, 2, 8),
    2017: DateTime(2017, 1, 28),
    2018: DateTime(2018, 2, 16),
    2019: DateTime(2019, 2, 5),
    2020: DateTime(2020, 1, 25),
    2021: DateTime(2021, 2, 12),
    2022: DateTime(2022, 2, 1),
    2023: DateTime(2023, 1, 22),
    2024: DateTime(2024, 2, 10),
    2025: DateTime(2025, 1, 29),
    2026: DateTime(2026, 2, 17),
    2027: DateTime(2027, 2, 6),
    2028: DateTime(2028, 1, 26),
    2029: DateTime(2029, 2, 13),
    2030: DateTime(2030, 2, 3),
    2031: DateTime(2031, 1, 23),
    2032: DateTime(2032, 2, 11),
    2033: DateTime(2033, 1, 31),
    2034: DateTime(2034, 2, 19),
    2035: DateTime(2035, 2, 8),
    2036: DateTime(2036, 1, 28),
    2037: DateTime(2037, 2, 15),
    2038: DateTime(2038, 2, 4),
    2039: DateTime(2039, 1, 24),
    2040: DateTime(2040, 2, 12),
    2041: DateTime(2041, 2, 1),
    2042: DateTime(2042, 1, 22),
    2043: DateTime(2043, 2, 10),
    2044: DateTime(2044, 1, 30),
    2045: DateTime(2045, 2, 17),
    2046: DateTime(2046, 2, 6),
    2047: DateTime(2047, 1, 26),
    2048: DateTime(2048, 2, 14),
    2049: DateTime(2049, 2, 2),
    2050: DateTime(2050, 1, 23),
  };

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
    final hasIndia = countries.any((c) => c.code.toUpperCase() == 'IN');
    if (!hasIndia) {
      countries.add(const HolidayCountry(code: 'IN', name: 'India'));
    }
    final hasTrinidad = countries.any((c) => c.code.toUpperCase() == 'TT');
    if (!hasTrinidad) {
      countries.add(const HolidayCountry(code: 'TT', name: 'Trinidad and Tobago'));
    }
    countries.sort((a, b) => a.name.compareTo(b.name));
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
    final holidays = decoded.map((item) {
      final typesRaw = item['types'] as List<dynamic>? ?? [];
      return HolidayItem(
        date: DateTime.parse(item['date'] as String),
        name: item['name'] as String,
        localName: item['localName'] as String? ?? item['name'] as String,
        types: typesRaw.map((t) => t.toString()).toList(),
      );
    }).toList();

    _addChineseNewYear(holidays, year);
    return holidays;
  }

  void _addChineseNewYear(List<HolidayItem> holidays, int year) {
    final date = _chineseNewYearDates[year];
    if (date == null) return;
    final exists = holidays.any((item) {
      final name = item.name.toLowerCase();
      final local = item.localName.toLowerCase();
      return name.contains('chinese new year') ||
          name.contains('lunar new year') ||
          local.contains('chinese new year') ||
          local.contains('lunar new year');
    });
    if (exists) return;
    holidays.add(
      HolidayItem(
        date: date,
        name: 'Chinese New Year',
        localName: 'Chinese New Year',
        types: const ['Public', 'Cultural', 'Universal'],
      ),
    );
  }
}
