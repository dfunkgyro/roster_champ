import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart' as models;

class PublicEventService {
  PublicEventService._internal();
  static final PublicEventService instance = PublicEventService._internal();

  static const _ukBankHolidayUrl = 'https://www.gov.uk/bank-holidays.json';
  static const _openHolidaysBase = 'https://openholidaysapi.org/PublicHolidays';

  Map<String, dynamic>? _ukCache;
  final Map<String, List<models.Event>> _openHolidaysCache = {};

  Future<Map<String, List<models.Event>>> getPublicEvents({
    required models.AppSettings settings,
    required DateTime start,
    required DateTime end,
  }) async {
    final map = <String, List<models.Event>>{};
    final countries = <String>{
      settings.holidayCountryCode.toUpperCase(),
      ...settings.additionalHolidayCountries.map((c) => c.toUpperCase()),
      ...settings.autoHolidayCountries.map((c) => c.toUpperCase()),
    };

    if (countries.contains('GB') || countries.contains('UK')) {
      final ukEvents = await _getUkBankHolidays(start, end);
      _merge(map, ukEvents);
    }

    const dach = {'DE', 'AT', 'CH'};
    final dachTargets = countries.intersection(dach);
    for (final code in dachTargets) {
      final holidays = await _getOpenHolidays(code, start, end);
      _merge(map, holidays);
    }

    return map;
  }

  void _merge(
    Map<String, List<models.Event>> target,
    Map<String, List<models.Event>> source,
  ) {
    source.forEach((key, events) {
      target.putIfAbsent(key, () => []).addAll(events);
    });
  }

  Future<Map<String, List<models.Event>>> _getUkBankHolidays(
    DateTime start,
    DateTime end,
  ) async {
    try {
      _ukCache ??= await _fetchUkBankHolidays();
      final map = <String, List<models.Event>>{};
      if (_ukCache == null) return map;
      final regions = [
        'england-and-wales',
        'scotland',
        'northern-ireland',
      ];
      for (final region in regions) {
        final regionData = _ukCache![region] as Map<String, dynamic>?;
        final events = regionData?['events'] as List<dynamic>? ?? [];
        for (final item in events) {
          final date = DateTime.parse(item['date'] as String);
          if (date.isBefore(start) || date.isAfter(end)) continue;
          final title = item['title'] as String? ?? 'Bank Holiday';
          final event = models.Event(
            id: 'uk-$region-${date.toIso8601String()}',
            title: title,
            description: 'UK Bank Holiday ($region)',
            date: date,
            eventType: models.EventType.holiday,
          );
          final key = _dateKey(date);
          map.putIfAbsent(key, () => []).add(event);
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>?> _fetchUkBankHolidays() async {
    final response = await http.get(Uri.parse(_ukBankHolidayUrl));
    if (response.statusCode != 200) return null;
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, List<models.Event>>> _getOpenHolidays(
    String countryCode,
    DateTime start,
    DateTime end,
  ) async {
    final map = <String, List<models.Event>>{};
    final years = <int>{start.year, end.year};
    for (final year in years) {
      final cacheKey = '$countryCode-$year';
      final cached = _openHolidaysCache[cacheKey];
      if (cached != null) {
        for (final event in cached) {
          if (!event.date.isBefore(start) && !event.date.isAfter(end)) {
            final key = _dateKey(event.date);
            map.putIfAbsent(key, () => []).add(event);
          }
        }
        continue;
      }
      final validFrom = DateTime(year, 1, 1).toIso8601String().split('T').first;
      final validTo = DateTime(year, 12, 31).toIso8601String().split('T').first;
      final uri = Uri.parse(
        '$_openHolidaysBase?countryIsoCode=$countryCode&validFrom=$validFrom&validTo=$validTo',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) continue;
      final decoded = jsonDecode(response.body) as List<dynamic>;
      final yearEvents = <models.Event>[];
      for (final item in decoded) {
        final dateRaw = item['startDate'] as String? ?? '';
        if (dateRaw.isEmpty) continue;
        final date = DateTime.parse(dateRaw);
        final name = item['name'] as String? ?? 'Public Holiday';
        final localName = item['localName'] as String? ?? name;
        final event = models.Event(
          id: 'oh-$countryCode-${date.toIso8601String()}',
          title: localName,
          description: '$name ($countryCode)',
          date: date,
          eventType: models.EventType.holiday,
        );
        final key = _dateKey(date);
        yearEvents.add(event);
        if (!date.isBefore(start) && !date.isAfter(end)) {
          map.putIfAbsent(key, () => []).add(event);
        }
      }
      _openHolidaysCache[cacheKey] = yearEvents;
    }
    return map;
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
