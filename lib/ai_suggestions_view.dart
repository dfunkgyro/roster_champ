import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'providers.dart';
import 'models.dart' as models;
import 'roster_generator_view.dart';
import 'services/time_service.dart';
import 'services/weather_service.dart';
import 'services/holiday_service.dart';
import 'services/observance_service.dart';
import 'aws_service.dart';
import 'dialogs.dart';

class AiSuggestionsView extends ConsumerStatefulWidget {
  const AiSuggestionsView({super.key});

  @override
  ConsumerState<AiSuggestionsView> createState() => _AiSuggestionsViewState();
}

class _AiSuggestionsViewState extends ConsumerState<AiSuggestionsView> {
  final TextEditingController _commandController = TextEditingController();

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final suggestions = roster.aiSuggestions;

    final sortedSuggestions = List<models.AiSuggestion>.from(suggestions)
      ..sort((a, b) {
        if (a.isRead != b.isRead) return a.isRead ? 1 : -1;
        return b.priority.index.compareTo(a.priority.index);
      });

    if (sortedSuggestions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAiCommandPanel(context),
          const SizedBox(height: 12),
          _buildEmptyState(context),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedSuggestions.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildAiCommandPanel(context);
        }
        if (index == 1) {
          return _ScenarioImpactCard(
            suggestions: sortedSuggestions,
          );
        }
        final suggestion = sortedSuggestions[index - 2];
        return _SuggestionCard(suggestion: suggestion);
      },
    );
  }

  Widget _buildAiCommandPanel(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final rosterLabel =
        roster.sharedRosterName ?? AwsService.instance.currentRosterId ?? 'Current';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RC Assistant',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Roster: $rosterLabel | Staff: ${roster.staffMembers.length} | Week start: ${roster.weekStartDay}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commandController,
              decoration: const InputDecoration(
                hintText: 'e.g. Add payday every 2 weeks for 8 future + 4 past',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _handleAiCommand(context),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CommandChip(
                  label: 'Add payday every 2 weeks',
                  onTap: () => _runCommand(
                    context,
                    'add event payday every 2 weeks future 8 past 4',
                  ),
                ),
                _CommandChip(
                  label: 'How do I add events?',
                  onTap: () => _runCommand(context, 'how do i add events'),
                ),
                _CommandChip(
                  label: 'Add meeting tomorrow',
                  onTap: () => _runCommand(context, 'add event meeting tomorrow'),
                ),
                _CommandChip(
                  label: 'Set Jack to N today',
                  onTap: () => _runCommand(context, 'set jack n today'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => _handleAiCommand(context),
                child: const Text('Run'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No AI Suggestions',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap refresh to generate suggestions',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ],
      ),
    );
  }

  void _runCommand(BuildContext context, String text) {
    _commandController.text = text;
    _handleAiCommand(context);
  }

  void _handleAiCommand(BuildContext context) {
    final raw = _commandController.text.trim();
    if (raw.isEmpty) return;
    final text = raw.toLowerCase();

    if (text.contains('hello') ||
        text.contains('hi') ||
        text.contains('hey') ||
        text.contains('how are you')) {
      _respondWithRC(
        context,
        'Hello! I can help with rosters, events, time, and weather. '
            'Ask me anything and I will tie it back to your schedule.',
      );
      return;
    }

    if (text.contains('how do i') || text.contains('how to') || text.contains('help')) {
      _showAiHelp(context);
      return;
    }

    if (text.contains('create roster') ||
        text.contains('generate roster') ||
        text.contains('build roster')) {
      _handleRosterCommand(context, raw);
      return;
    }

    if (text.contains('time') || text.contains('date')) {
      _handleTimeCommand(context);
      return;
    }

    if (text.contains('weather')) {
      _handleWeatherCommand(context);
      return;
    }

    if (text.startsWith('when is') || text.contains('when is ')) {
      _handleWhenIsCommand(context, raw);
      return;
    }

    if (text.contains('shift')) {
      _handleShiftQuery(context, raw);
      return;
    }

    if (text.contains('delete event') || text.contains('remove event')) {
      _handleDeleteEventCommand(context, raw);
      return;
    }

    if (text.contains('event') || text.contains('payday')) {
      _handleEventCommand(context, raw);
      return;
    }

    if (text.contains('set ') || text.contains('override')) {
      _handleSetShiftCommand(context, raw);
      return;
    }

    _respondWithRC(
      context,
      "I did not catch that. I can help with roster, events, time, weather, or a quick 'when is ...' question.",
    );
  }

  void _handleRosterCommand(BuildContext context, String raw) {
    final text = raw.toLowerCase();
    final staffMatch =
        RegExp(r'(\\d{1,3})\\s*(staff|people|person)')
            .firstMatch(text);
    final cycleMatch =
        RegExp(r'(\\d{1,2})\\s*(week|weeks)')
            .firstMatch(text);
    final weekStartMatch = RegExp(r'week\\s*start\\s*(\\w+)')
        .firstMatch(text);

    int? staffCount;
    int? cycleLength;
    int? weekStartDay;

    if (staffMatch != null) {
      staffCount = int.tryParse(staffMatch.group(1)!);
    }
    if (cycleMatch != null) {
      cycleLength = int.tryParse(cycleMatch.group(1)!);
    }
    if (weekStartMatch != null) {
      final label = weekStartMatch.group(1)!;
      const days = {
        'sun': 0,
        'sunday': 0,
        'mon': 1,
        'monday': 1,
        'tue': 2,
        'tues': 2,
        'tuesday': 2,
        'wed': 3,
        'wednesday': 3,
        'thu': 4,
        'thur': 4,
        'thursday': 4,
        'fri': 5,
        'friday': 5,
        'sat': 6,
        'saturday': 6,
      };
      weekStartDay = days[label];
    }

    _showRosterWizard(
      context,
      staffCount: staffCount,
      cycleLength: cycleLength,
      weekStartDay: weekStartDay,
    );
  }

  Future<void> _handleTimeCommand(BuildContext context) async {
    final settings = ref.read(settingsProvider);
    try {
      final info = await TimeService.instance.getTime(settings.timeZone);
      _respondWithRC(
        context,
        'Time in ${info.timezone}: ${DateFormat('MMM d, HH:mm').format(info.dateTime)}. '
            'Want it shown on the roster?',
      );
    } catch (_) {
      final now = DateTime.now();
      _respondWithRC(
        context,
        'Local time: ${DateFormat('MMM d, HH:mm').format(now)}. '
            'Want it shown on the roster?',
      );
    }
  }

  Future<void> _handleWeatherCommand(BuildContext context) async {
    final settings = ref.read(settingsProvider);
    if (settings.siteLat == null || settings.siteLon == null) {
      _respondWithRC(
        context,
        'Set a site location in Settings to show weather.',
      );
      return;
    }
    try {
      final map = await WeatherService.instance.getWeekly(
        lat: settings.siteLat!,
        lon: settings.siteLon!,
      );
      final today = DateTime.now();
      final key = DateTime(today.year, today.month, today.day);
      final day = map[key];
      if (day == null) {
        throw Exception('Weather unavailable.');
      }
      _respondWithRC(
        context,
        'Weather today: ${day.minTemp.toStringAsFixed(0)} deg - '
            '${day.maxTemp.toStringAsFixed(0)} deg, rain '
            '${day.precipChance.toStringAsFixed(0)}%. '
            'I can overlay weather on the roster.',
      );
    } catch (e) {
      _respondWithRC(context, 'Weather unavailable: $e');
    }
  }

  void _handleShiftQuery(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    final staff = roster.staffMembers.map((s) => s.name).toList();
    String? matched;
    for (final name in staff) {
      if (raw.toLowerCase().contains(name.toLowerCase())) {
        matched = name;
        break;
      }
    }
    if (matched == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff name not recognized.')),
      );
      return;
    }
    final date = _parseDateFromText(raw) ?? DateTime.now();
    final shift = roster.getShiftForDate(matched, date);
    _respondWithRC(
      context,
      '$matched is on $shift for ${DateFormat('MMM d, yyyy').format(date)}.',
    );
  }

  models.EventType _inferEventType(String text, String title) {
    final lowered = text.toLowerCase();
    if (lowered.contains('payday')) return models.EventType.payday;
    if (lowered.contains('ramadan') || lowered.contains('easter') || lowered.contains('diwali') || lowered.contains('hanukkah') || lowered.contains('eid')) {
      return models.EventType.religious;
    }
    if (lowered.contains('carnival') || lowered.contains('festival') || lowered.contains('lunar new year') || lowered.contains('chinese new year') || lowered.contains('mardi gras')) {
      return models.EventType.cultural;
    }
    if (lowered.contains('world cup') || lowered.contains('super bowl') || lowered.contains('olympic') || lowered.contains('final') || lowered.contains('grand prix')) {
      return models.EventType.sports;
    }
    if (lowered.contains('meeting')) return models.EventType.meeting;
    if (lowered.contains('training')) return models.EventType.training;
    if (lowered.contains('deadline') || lowered.contains('due')) return models.EventType.deadline;
    if (lowered.contains('birthday')) return models.EventType.birthday;
    if (lowered.contains('anniversary')) return models.EventType.anniversary;
    if (lowered.contains('holiday')) return models.EventType.holiday;
    return models.EventType.general;
  }

  void _handleEventCommand(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    final text = raw.toLowerCase();
    final now = DateTime.now();

    String? title;
    if (text.contains('payday')) {
      title = 'Payday';
    } else if (text.contains('meeting')) {
      title = 'Meeting';
    } else if (text.contains('training')) {
      title = 'Training';
    } else if (text.contains('holiday')) {
      title = 'Holiday';
    }

    DateTime date = DateTime(now.year, now.month, now.day);
    if (text.contains('tomorrow')) {
      date = date.add(const Duration(days: 1));
    } else {
      final parsed = _parseDateFromText(text);
      if (parsed != null) {
        date = parsed;
      }
    }

    if (title == null ||
        text.contains('add event') ||
        text.contains('create event') ||
        text == 'event') {
      showDialog(
        context: context,
        builder: (context) => AddEventDialog(
          initialDate: date,
          initialTitle: title,
          onAddEvents: (events) {
            if (events.length == 1) {
              roster.addEvent(events.first);
            } else {
              roster.addBulkEvents(events);
            }
          },
        ),
      );
      return;
    }

    final effectiveTitle = title ?? 'Event';

    final intervalMatch = RegExp(r'every\\s+(\\d+)\\s*(day|days|week|weeks)')
        .firstMatch(text);
    int interval = 1;
    bool weekly = true;
    if (intervalMatch != null) {
      interval = int.tryParse(intervalMatch.group(1)!) ?? 1;
      weekly = intervalMatch.group(2)!.startsWith('week');
    }
    final futureMatch = RegExp(r'future\\s+(\\d+)').firstMatch(text);
    final pastMatch = RegExp(r'past\\s+(\\d+)').firstMatch(text);
    final wantsInfinity = text.contains('infinite') || text.contains('forever');
    final futureCount = futureMatch != null
        ? int.parse(futureMatch.group(1)!)
        : wantsInfinity
            ? (weekly ? 520 : 3650)
            : 8;
    final pastCount = pastMatch != null
        ? int.parse(pastMatch.group(1)!)
        : wantsInfinity
            ? (weekly ? 520 : 3650)
            : 0;

    final stepDays = (weekly ? 7 : 1) * interval;
    final events = <models.Event>[];
    final recurringId = DateTime.now().millisecondsSinceEpoch.toString();

    void addEvent(DateTime d) {
      events.add(
        models.Event(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: effectiveTitle,
          date: d,
          eventType: _inferEventType(text, effectiveTitle),
          recurringId: intervalMatch != null ? recurringId : null,
        ),
      );
    }

    addEvent(date);
    if (intervalMatch != null) {
      for (var i = 1; i <= futureCount; i++) {
        addEvent(date.add(Duration(days: stepDays * i)));
      }
      for (var i = 1; i <= pastCount; i++) {
        addEvent(date.subtract(Duration(days: stepDays * i)));
      }
    }

    if (events.length == 1) {
      _confirmAction(
        context,
        title: 'Add event',
        message:
            'Add "${events.first.title}" on ${DateFormat('MMM d, yyyy').format(events.first.date)}?',
        onConfirm: () => roster.addEvent(events.first),
      );
    } else {
      _confirmAction(
        context,
        title: 'Add recurring events',
        message:
            'Add ${events.length} events for "$effectiveTitle" from '
            '${DateFormat('MMM d, yyyy').format(events.first.date)}?',
        onConfirm: () => roster.addBulkEvents(events),
      );
    }

    if (wantsInfinity) {
      _respondWithRC(
        context,
        'Added a large recurring range. Use future/past counts to adjust.',
      );
    }
    _respondWithRC(
      context,
      'Queued ${events.length} event(s): $effectiveTitle.',
    );
  }

  DateTime? _parseDateFromText(String text) {
    final lowered = text.toLowerCase();
    final isoMatch = RegExp(r'(\\d{4})-(\\d{2})-(\\d{2})').firstMatch(lowered);
    if (isoMatch != null) {
      return DateTime(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
      );
    }
    final slashMatch =
        RegExp(r'(\\d{1,2})[/-](\\d{1,2})[/-](\\d{4})').firstMatch(lowered);
    if (slashMatch != null) {
      return DateTime(
        int.parse(slashMatch.group(3)!),
        int.parse(slashMatch.group(2)!),
        int.parse(slashMatch.group(1)!),
      );
    }
    final monthNames = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final match = RegExp(
      r'(\\d{1,2})(?:st|nd|rd|th)?\\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)(?:\\s*(\\d{4}))?',
    )
        .firstMatch(lowered);
    if (match != null) {
      final day = int.parse(match.group(1)!);
      final month = monthNames[match.group(2)!]!;
      final year = match.group(3) != null
          ? int.parse(match.group(3)!)
          : DateTime.now().year;
      return DateTime(year, month, day);
    }
    final reverseMatch = RegExp(
      r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\\s*(\\d{1,2})(?:st|nd|rd|th)?(?:\\s*(\\d{4}))?',
    ).firstMatch(lowered);
    if (reverseMatch != null) {
      final day = int.parse(reverseMatch.group(2)!);
      final month = monthNames[reverseMatch.group(1)!]!;
      final year = reverseMatch.group(3) != null
          ? int.parse(reverseMatch.group(3)!)
          : DateTime.now().year;
      return DateTime(year, month, day);
    }
    return null;
  }

  void _showAiHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI Help'),
        content: const Text(
          'Try commands like:\\n'
          '- "Add payday every 2 weeks future 8 past 4"\\n'
          '- "Add meeting tomorrow"\\n'
          '- "Delete event payday"\\n'
          '- "Set Jack N today"\\n'
          '- "Create roster 16 staff 8 weeks start monday"\\n'
          '- "How do I add events?"\\n\\n'
          'You can also add events from the Events tab or by tapping a date in the roster.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _handleDeleteEventCommand(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    final text = raw.toLowerCase();
    final matches = roster.events.where((event) {
      return text.contains(event.title.toLowerCase());
    }).toList();

    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matching event found.')),
      );
      return;
    }
    _confirmAction(
      context,
      title: 'Delete events',
      message: 'Delete ${matches.length} event(s)?',
      onConfirm: () {
        for (final event in matches) {
          roster.deleteEvent(event.id);
        }
      },
    );
  }

  Future<void> _handleWhenIsCommand(BuildContext context, String raw) async {
    final query = raw.toLowerCase().replaceFirst('when is', '').trim();
    if (query.isEmpty) {
      _respondWithRC(context, 'Tell me the event name.');
      return;
    }

    final today = DateTime.now();
    final fixedDates = <String, DateTime Function(int)>{
      'valentines day': (y) => DateTime(y, 2, 14),
      'valentine': (y) => DateTime(y, 2, 14),
      'christmas': (y) => DateTime(y, 12, 25),
      'new year': (y) => DateTime(y, 1, 1),
      'halloween': (y) => DateTime(y, 10, 31),
    };

    for (final entry in fixedDates.entries) {
      if (query.contains(entry.key)) {
        var date = entry.value(today.year);
        if (date.isBefore(today)) {
          date = entry.value(today.year + 1);
        }
        _respondWithRC(
          context,
          '${entry.key[0].toUpperCase()}${entry.key.substring(1)} is on '
              '${DateFormat('MMM d, yyyy').format(date)}. '
              'I can add it to your roster.',
        );
        return;
      }
    }

    final roster = ref.read(rosterProvider);
    final eventMatch = roster.events.firstWhere(
      (e) => e.title.toLowerCase().contains(query),
      orElse: () => models.Event(
        id: '',
        title: '',
        date: DateTime(1900),
      ),
    );
    if (eventMatch.id.isNotEmpty) {
      _respondWithRC(
        context,
        '${eventMatch.title} is on ${DateFormat('MMM d, yyyy').format(eventMatch.date)}.',
      );
      return;
    }

    final settings = ref.read(settingsProvider);
    final holidays = await HolidayService.instance.getHolidays(
      countryCode: settings.holidayCountryCode,
      year: today.year,
    );
    final holidayMatch = holidays.firstWhere(
      (h) =>
          h.name.toLowerCase().contains(query) ||
          h.localName.toLowerCase().contains(query),
      orElse: () => HolidayItem(
        date: DateTime(1900),
        name: '',
        localName: '',
        types: const [],
      ),
    );
    if (holidayMatch.name.isNotEmpty) {
      _respondWithRC(
        context,
        '${holidayMatch.localName} is on '
            '${DateFormat('MMM d, yyyy').format(holidayMatch.date)}. '
            'I can add it to your roster.',
      );
      return;
    }

    if (settings.calendarificApiKey.trim().isNotEmpty) {
      final observances = await ObservanceService.instance.getObservances(
        apiKey: settings.calendarificApiKey,
        countryCode: settings.holidayCountryCode,
        year: today.year,
        types: settings.observanceTypes,
      );
      final obsMatch = observances.firstWhere(
        (o) => o.localName.toLowerCase().contains(query),
        orElse: () => HolidayItem(
          date: DateTime(1900),
          name: '',
          localName: '',
          types: const [],
        ),
      );
      if (obsMatch.name.isNotEmpty) {
        _respondWithRC(
          context,
          '${obsMatch.localName} is on '
              '${DateFormat('MMM d, yyyy').format(obsMatch.date)}. '
              'I can add it to your roster.',
        );
        return;
      }
    }

    _respondWithRC(
      context,
      "I could not find '$query' in your roster or holiday sources. "
          'You can add it as an event.',
    );
  }

  void _respondWithRC(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('RC: $message'),
      ),
    );
  }

  Future<void> _showRosterWizard(
    BuildContext context, {
    int? staffCount,
    int? cycleLength,
    int? weekStartDay,
  }) async {
    final roster = ref.read(rosterProvider);
    final staffController = TextEditingController(
      text: staffCount?.toString() ?? roster.numPeople.toString(),
    );
    final cycleController = TextEditingController(
      text: cycleLength?.toString() ?? roster.cycleLength.toString(),
    );
    int startDay = weekStartDay ?? roster.weekStartDay;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Roster Wizard'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: staffController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of staff',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cycleController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cycle length (weeks)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: startDay,
              decoration: const InputDecoration(labelText: 'Week start'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Sunday')),
                DropdownMenuItem(value: 1, child: Text('Monday')),
                DropdownMenuItem(value: 2, child: Text('Tuesday')),
                DropdownMenuItem(value: 3, child: Text('Wednesday')),
                DropdownMenuItem(value: 4, child: Text('Thursday')),
                DropdownMenuItem(value: 5, child: Text('Friday')),
                DropdownMenuItem(value: 6, child: Text('Saturday')),
              ],
              onChanged: (value) {
                if (value != null) {
                  startDay = value;
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final staff = int.tryParse(staffController.text.trim()) ?? 0;
              final cycle = int.tryParse(cycleController.text.trim()) ?? 0;
              if (staff < 1 || cycle < 1) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter valid values.')),
                );
                return;
              }
              roster.setWeekStartDay(startDay);
              roster.initializeRoster(cycle, staff, keepExistingData: false);
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RosterGeneratorView(),
                ),
              );
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _handleSetShiftCommand(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    if (roster.readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read-only roster cannot be edited.')),
      );
      return;
    }
    final text = raw.toLowerCase();
    final staff = roster.staffMembers.map((s) => s.name).toList();
    String? matched;
    for (final name in staff) {
      if (text.contains(name.toLowerCase())) {
        matched = name;
        break;
      }
    }
    if (matched == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff name not recognized.')),
      );
      return;
    }

    final date = _parseDateFromText(text) ?? DateTime.now();
    final shiftMatch =
        RegExp(r'\\b(d12|n12|d|n|l|off|r|e|c1|c2|c3|c4|c)\\b')
            .firstMatch(text);
    if (shiftMatch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift code not recognized.')),
      );
      return;
    }
    final shift = shiftMatch.group(1)!.toUpperCase();
    _confirmAction(
      context,
      title: 'Set shift',
      message:
          'Set $matched to $shift on ${DateFormat('MMM d, yyyy').format(date)}?',
      onConfirm: () =>
          roster.setOverride(matched!, date, shift, 'AI command'),
    );
  }

  Future<void> _showSetShiftWizard(
    BuildContext context, {
    String? initialStaff,
    DateTime? initialDate,
    String? initialShift,
  }) async {
    final roster = ref.read(rosterProvider);
    final staff = roster.staffMembers.map((s) => s.name).toList();
    if (staff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add staff before setting shifts.')),
      );
      return;
    }
    String staffName = initialStaff ?? staff.first;
    DateTime date = initialDate ?? DateTime.now();
    final shiftController =
        TextEditingController(text: initialShift ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: staffName,
              items: staff
                  .map(
                    (name) => DropdownMenuItem(
                      value: name,
                      child: Text(name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  staffName = value;
                }
              },
              decoration: const InputDecoration(labelText: 'Staff member'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Date'),
              subtitle: Text(DateFormat('MMM d, yyyy').format(date)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime.now().subtract(const Duration(days: 730)),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (picked != null) {
                  date = picked;
                }
              },
            ),
            TextField(
              controller: shiftController,
              decoration: const InputDecoration(
                labelText: 'Shift code',
                hintText: 'e.g. D, N, D12, N12, OFF',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final shift = shiftController.text.trim().toUpperCase();
      if (shift.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a shift code.')),
        );
        return;
      }
      roster.setOverride(staffName, date, shift, 'AI command');
    }
  }

  Future<void> _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onConfirm();
    }
  }
}

class _CommandChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CommandChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _ScenarioImpactCard extends ConsumerWidget {
  final List<models.AiSuggestion> suggestions;

  const _ScenarioImpactCard({required this.suggestions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.auto_graph_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Scenario Planning',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () {
                final delta = ref
                    .read(rosterProvider)
                    .simulateScenarioImpact(suggestions);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Scenario Impact'),
                    content: _ImpactSummary(delta: delta),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Simulate'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImpactSummary extends StatelessWidget {
  final models.RosterHealthScore delta;

  const _ImpactSummary({required this.delta});

  @override
  Widget build(BuildContext context) {
    String format(double value) =>
        value >= 0 ? '+${value.toStringAsFixed(2)}' : value.toStringAsFixed(2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Overall: ${format(delta.overall)}'),
        Text('Coverage: ${format(delta.coverage)}'),
        Text('Workload: ${format(delta.workload)}'),
        Text('Fairness: ${format(delta.fairness)}'),
        Text('Leave: ${format(delta.leave)}'),
        Text('Pattern: ${format(delta.pattern)}'),
      ],
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  final models.AiSuggestion suggestion;

  const _SuggestionCard({required this.suggestion});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priorityColor = _getPriorityColor(suggestion.priority);
    final isReadOnly = ref.watch(rosterProvider).readOnly;
    final hasAction = suggestion.actionType != null &&
        suggestion.actionType != models.SuggestionActionType.none &&
        suggestion.actionPayload != null &&
        !isReadOnly;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: suggestion.isRead ? 1 : 3,
      child: InkWell(
        onTap: () {
          if (!suggestion.isRead) {
            ref.read(rosterProvider).markSuggestionAsRead(suggestion.id);
          }
          _showSuggestionDetails(context, ref);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: priorityColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: priorityColor),
                    ),
                    child: Text(
                      suggestion.priority.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: priorityColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!suggestion.isRead)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    DateFormat('MMM d').format(suggestion.createdDate),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                suggestion.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                suggestion.description,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                ),
              ),
              if (suggestion.affectedStaff != null &&
                  suggestion.affectedStaff!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: suggestion.affectedStaff!.map((staff) {
                    return Chip(
                      label: Text(staff),
                      labelStyle: const TextStyle(fontSize: 12),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      ref.read(rosterProvider).dismissSuggestion(suggestion.id);
                    },
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Dismiss'),
                  ),
                  if (hasAction) const SizedBox(width: 8),
                  if (hasAction)
                    FilledButton.icon(
                      onPressed: () => _applySuggestion(context, ref),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Apply'),
                    ),
                ],
              ),
              if (suggestion.impactScore != null ||
                  suggestion.confidence != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (suggestion.impactScore != null)
                      _buildMetaChip(
                        context,
                        'Impact ${(suggestion.impactScore! * 100).toStringAsFixed(0)}%',
                        Icons.trending_up,
                      ),
                    const SizedBox(width: 8),
                    if (suggestion.confidence != null)
                      _buildMetaChip(
                        context,
                        'Confidence ${(suggestion.confidence! * 100).toStringAsFixed(0)}%',
                        Icons.verified,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getPriorityColor(models.SuggestionPriority priority) {
    switch (priority) {
      case models.SuggestionPriority.low:
        return Colors.blue;
      case models.SuggestionPriority.medium:
        return Colors.orange;
      case models.SuggestionPriority.high:
        return Colors.red;
      case models.SuggestionPriority.critical:
        return Colors.purple;
    }
  }

  void _showSuggestionDetails(BuildContext context, WidgetRef ref) {
    final impactDelta = ref
        .read(rosterProvider)
        .previewSuggestionImpact(suggestion);
    final isReadOnly = ref.read(rosterProvider).readOnly;
    final hasAction = suggestion.actionType != null &&
        suggestion.actionType != models.SuggestionActionType.none &&
        suggestion.actionPayload != null &&
        !isReadOnly;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(suggestion.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(suggestion.description),
              if (suggestion.reason != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Why this helps',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(suggestion.reason!),
              ],
              const SizedBox(height: 12),
              _buildImpactDelta(impactDelta),
              const SizedBox(height: 16),
              if (suggestion.affectedStaff != null &&
                  suggestion.affectedStaff!.isNotEmpty) ...[
                const Text(
                  'Affected Staff:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...suggestion.affectedStaff!.map((staff) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.person, size: 16),
                          const SizedBox(width: 8),
                          Text(staff),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Priority: ${suggestion.priority.name}',
                    style: TextStyle(
                      color: _getPriorityColor(suggestion.priority),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    DateFormat('MMM d, yyyy').format(suggestion.createdDate),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(rosterProvider).dismissSuggestion(suggestion.id);
            },
            child: const Text('Dismiss'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(rosterProvider)
                  .setSuggestionFeedback(
                    suggestion.id,
                    models.SuggestionFeedback.notHelpful,
                  );
              Navigator.pop(context);
            },
            child: const Text('Not Helpful'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(rosterProvider)
                  .setSuggestionFeedback(
                    suggestion.id,
                    models.SuggestionFeedback.helpful,
                  );
              Navigator.pop(context);
            },
            child: const Text('Helpful'),
          ),
          if (hasAction)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _applySuggestion(context, ref);
              },
              child: const Text('Apply'),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
        ],
      ),
    );
  }

  Future<void> _applySuggestion(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply Suggestion?'),
        content: Text(
          'This will apply: ${suggestion.title}\n\n'
          'You can undo the change after applying.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final roster = ref.read(rosterProvider);
      final backup = roster.createBackup();
      final applied = roster.applySuggestionAction(suggestion);
      if (applied) {
        roster.dismissSuggestion(suggestion.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Suggestion applied'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => roster.restoreBackup(backup),
              ),
            ),
          );
        }
      }
    }
  }

  Widget _buildMetaChip(
    BuildContext context,
    String label,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildImpactDelta(models.RosterHealthScore delta) {
    String format(double value) =>
        value >= 0 ? '+${value.toStringAsFixed(2)}' : value.toStringAsFixed(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'KPI Impact',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text('Overall: ${format(delta.overall)}'),
        Text('Coverage: ${format(delta.coverage)}'),
        Text('Workload: ${format(delta.workload)}'),
        Text('Fairness: ${format(delta.fairness)}'),
        Text('Leave: ${format(delta.leave)}'),
        Text('Pattern: ${format(delta.pattern)}'),
      ],
    );
  }
}

