import 'dart:convert';
import 'package:http/http.dart' as http;

class SportsEventItem {
  final DateTime date;
  final String name;
  final String league;

  const SportsEventItem({
    required this.date,
    required this.name,
    required this.league,
  });
}

class SportsService {
  SportsService._internal();
  static final SportsService instance = SportsService._internal();

  final Map<String, List<SportsEventItem>> _leagueCache = {};

  Future<List<SportsEventItem>> getLeagueEvents({
    required List<String> leagueIds,
    required String apiKey,
  }) async {
    if (apiKey.trim().isEmpty || leagueIds.isEmpty) return [];
    final events = <SportsEventItem>[];
    for (final leagueId in leagueIds) {
      final cached = _leagueCache[leagueId];
      if (cached != null) {
        events.addAll(cached);
        continue;
      }
      final nextUri = Uri.parse(
        'https://www.thesportsdb.com/api/v1/json/$apiKey/eventsnextleague.php?id=$leagueId',
      );
      final pastUri = Uri.parse(
        'https://www.thesportsdb.com/api/v1/json/$apiKey/eventspastleague.php?id=$leagueId',
      );
      final nextResponse = await http.get(nextUri);
      final pastResponse = await http.get(pastUri);
      if (nextResponse.statusCode != 200 || pastResponse.statusCode != 200) {
        throw Exception('Sports events error for league $leagueId');
      }
      final parsed = <SportsEventItem>[];
      parsed.addAll(_parseEvents(nextResponse.body));
      parsed.addAll(_parseEvents(pastResponse.body));
      _leagueCache[leagueId] = parsed;
      events.addAll(parsed);
    }
    return events;
  }

  List<SportsEventItem> _parseEvents(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final rawEvents = decoded['events'] as List<dynamic>? ?? [];
    return rawEvents.map((item) {
      final dateRaw = item['dateEvent'] as String? ?? '';
      return SportsEventItem(
        date: DateTime.parse(dateRaw),
        name: item['strEvent'] as String? ?? 'Sport Event',
        league: item['strLeague'] as String? ?? 'League',
      );
    }).toList();
  }
}
