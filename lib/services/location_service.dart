import 'dart:convert';
import 'package:http/http.dart' as http;

class LocationResult {
  final String name;
  final double lat;
  final double lon;

  const LocationResult({
    required this.name,
    required this.lat,
    required this.lon,
  });
}

class LocationService {
  LocationService._internal();
  static final LocationService instance = LocationService._internal();

  Future<List<LocationResult>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeQueryComponent(query)}'
      '&format=json&limit=5',
    );
    final response = await http.get(
      url,
      headers: const {'User-Agent': 'RosterChamp/1.0'},
    );
    if (response.statusCode != 200) {
      throw Exception('Location search error: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((item) {
          final map = item as Map<String, dynamic>;
          final name = map['display_name']?.toString() ?? '';
          final lat = double.tryParse(map['lat']?.toString() ?? '');
          final lon = double.tryParse(map['lon']?.toString() ?? '');
          if (name.isEmpty || lat == null || lon == null) return null;
          return LocationResult(name: name, lat: lat, lon: lon);
        })
        .whereType<LocationResult>()
        .toList();
  }
}
