import 'dart:convert';
import 'package:http/http.dart' as http;

class CountryInfo {
  final String code;
  final String name;
  final String region;
  final String flag;
  final List<String> timezones;
  final double? lat;
  final double? lon;

  const CountryInfo({
    required this.code,
    required this.name,
    required this.region,
    required this.flag,
    required this.timezones,
    required this.lat,
    required this.lon,
  });
}

class CountryService {
  CountryService._internal();
  static final CountryService instance = CountryService._internal();

  List<CountryInfo>? _cache;
  DateTime? _lastFetch;

  Future<List<CountryInfo>> getCountries() async {
    final now = DateTime.now();
    if (_cache != null &&
        _lastFetch != null &&
        now.difference(_lastFetch!) < const Duration(hours: 6)) {
      return _cache!;
    }
    final url = Uri.parse(
      'https://restcountries.com/v3.1/all?fields=name,cca2,flag,region,timezones,latlng',
    );
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('Country list error: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    final countries = data
        .map((item) {
          final map = item as Map<String, dynamic>;
          final code = map['cca2']?.toString() ?? '';
          if (code.length != 2) return null;
          final name = (map['name'] as Map?)?['common']?.toString() ?? code;
          final flag = map['flag']?.toString() ?? '';
          final region = map['region']?.toString() ?? '';
          final tz = (map['timezones'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[];
          final latlng = (map['latlng'] as List?)
                  ?.map((e) => (e as num).toDouble())
                  .toList() ??
              const <double>[];
          final lat = latlng.isNotEmpty ? latlng[0] : null;
          final lon = latlng.length > 1 ? latlng[1] : null;
          return CountryInfo(
            code: code,
            name: name,
            region: region,
            flag: flag,
            timezones: tz,
            lat: lat,
            lon: lon,
          );
        })
        .whereType<CountryInfo>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _cache = countries;
    _lastFetch = now;
    return countries;
  }
}
