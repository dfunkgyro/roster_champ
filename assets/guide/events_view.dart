import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'providers.dart';

class EventsView extends ConsumerStatefulWidget {
  const EventsView({super.key});

  @override
  ConsumerState<EventsView> createState() => _EventsViewState();
}

class _EventsViewState extends ConsumerState<EventsView> {
  static const List<String> _countryOptions = [
    'US',
    'GB',
    'IE',
    'CA',
    'AU',
    'NZ',
    'ZA',
    'IN',
    'SG',
    'MY',
    'AE',
    'FR',
    'DE',
    'ES',
    'IT',
    'NL',
    'BE',
    'SE',
    'NO',
    'DK',
    'FI',
    'JP',
    'KR',
  ];

  List<Event> _majorEvents = [];
  final Set<String> _selectedMajorEventIds = {};
  bool _isLoadingMajorEvents = false;
  int _majorEventsYear = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final rosterNotifier = ref.watch(rosterProvider);
    final upcomingEvents = _getUpcomingEvents(rosterNotifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCalendarSettings(context, rosterNotifier),
        const SizedBox(height: 16),
        _buildMajorEventsCard(context, rosterNotifier),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Upcoming Events',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Event'),
              onPressed: () => _showAddEventDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (upcomingEvents.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No upcoming events'),
            ),
          )
        else
          ...upcomingEvents.map((event) => _buildEventCard(context, event)),
      ],
    );
  }

  Widget _buildCalendarSettings(
    BuildContext context,
    RosterNotifier roster,
  ) {
    final paydayCycleController = TextEditingController(
      text: roster.rosterRules.paydayCycleDays.toString(),
    );
    final paydayAnchorController = TextEditingController(
      text: roster.rosterRules.paydayAnchorDate ?? '',
    );
    final bankHolidayController = TextEditingController(
      text: roster.rosterRules.bankHolidayDates.join(', '),
    );
    final bankHolidayCountryController = TextEditingController(
      text: roster.rosterRules.bankHolidayCountryCode ?? '',
    );
    bool highlightPaydays = roster.rosterRules.highlightPaydays;
    bool highlightBankHolidays = roster.rosterRules.highlightBankHolidays;
    String selectedCountry =
        roster.rosterRules.bankHolidayCountryCode ?? 'US';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Calendar Settings',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SwitchListTile(
                title: const Text('Highlight paydays'),
                value: highlightPaydays,
                onChanged: (value) =>
                    setState(() => highlightPaydays = value),
              ),
              TextField(
                controller: paydayCycleController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Payday cycle days (e.g. 28)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: paydayAnchorController,
                      decoration: const InputDecoration(
                        labelText: 'Payday anchor date (YYYY-MM-DD)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 3650)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setState(() {
                          paydayAnchorController.text =
                              _formatDateKey(picked);
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Highlight bank holidays'),
                value: highlightBankHolidays,
                onChanged: (value) =>
                    setState(() => highlightBankHolidays = value),
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedCountry,
                      decoration: const InputDecoration(
                        labelText: 'Country',
                        border: OutlineInputBorder(),
                      ),
                      items: _countryOptions
                          .map((code) => DropdownMenuItem(
                                value: code,
                                child: Text(code),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedCountry = value ?? selectedCountry;
                          bankHolidayCountryController.text = selectedCountry;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.cloud_download),
                    onPressed: () async {
                      final code = bankHolidayCountryController.text
                          .trim()
                          .toUpperCase();
                      if (code.isEmpty) {
                        _showSnack(context, 'Select a country.');
                        return;
                      }
                      try {
                        await roster.refreshBankHolidays(countryCode: code);
                        _showSnack(
                            context, 'Bank holidays updated for $code.');
                        setState(() {
                          bankHolidayController.text =
                              roster.rosterRules.bankHolidayDates.join(', ');
                          highlightBankHolidays =
                              roster.rosterRules.highlightBankHolidays;
                        });
                      } catch (_) {
                        _showSnack(context, 'Failed to load holidays.');
                      }
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: bankHolidayController,
                      decoration: const InputDecoration(
                        labelText: 'Bank holiday dates (YYYY-MM-DD, ...)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 3650)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setState(() {
                          final value = _formatDateKey(picked);
                          bankHolidayController.text =
                              _appendCsvDate(bankHolidayController.text, value);
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () {
                    roster.updateRosterRules(
                      roster.rosterRules.copyWith(
                        highlightPaydays: highlightPaydays,
                        paydayCycleDays:
                            int.tryParse(paydayCycleController.text.trim()) ?? 28,
                        paydayAnchorDate:
                            paydayAnchorController.text.trim().isEmpty
                                ? null
                                : paydayAnchorController.text.trim(),
                        highlightBankHolidays: highlightBankHolidays,
                        bankHolidayDates: bankHolidayController.text
                            .split(',')
                            .map((value) => value.trim())
                            .where((value) => value.isNotEmpty)
                            .toList(),
                        bankHolidayCountryCode:
                            bankHolidayCountryController.text.trim().isEmpty
                                ? null
                                : bankHolidayCountryController.text
                                    .trim()
                                    .toUpperCase(),
                      ),
                    );
                    _showSnack(context, 'Calendar settings saved.');
                  },
                  child: const Text('Save settings'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMajorEventsCard(
    BuildContext context,
    RosterNotifier roster,
  ) {
    final selectedCountry = roster.rosterRules.bankHolidayCountryCode ?? 'US';
    final highlightMajorEvents = roster.rosterRules.highlightMajorEvents;
    final ignored = roster.rosterRules.ignoredMajorEventIds.toSet();
    final visibleEvents =
        _majorEvents.where((e) => !ignored.contains(e.id)).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Major Events (Beta)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              title: const Text('Highlight major events on roster'),
              value: highlightMajorEvents,
              onChanged: (value) {
                roster.updateRosterRules(
                  roster.rosterRules.copyWith(highlightMajorEvents: value),
                );
              },
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedCountry,
                    decoration: const InputDecoration(
                      labelText: 'Country',
                      border: OutlineInputBorder(),
                    ),
                    items: _countryOptions
                        .map((code) => DropdownMenuItem(
                              value: code,
                              child: Text(code),
                            ))
                        .toList(),
                    onChanged: (value) {
                      roster.updateRosterRules(
                        roster.rosterRules.copyWith(
                          bankHolidayCountryCode:
                              (value ?? selectedCountry).toUpperCase(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _majorEventsYear,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      4,
                      (index) => DropdownMenuItem(
                        value: DateTime.now().year + index,
                        child: Text((DateTime.now().year + index).toString()),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => _majorEventsYear = value ?? _majorEventsYear);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoadingMajorEvents
                      ? null
                      : () => _fetchMajorEvents(context, roster, selectedCountry),
                  icon: _isLoadingMajorEvents
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download),
                  label: Text(_isLoadingMajorEvents ? 'Loading...' : 'Fetch'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: visibleEvents.isEmpty
                      ? null
                      : () => _addSelectedMajorEvents(roster, visibleEvents),
                  child: const Text('Add selected'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _selectedMajorEventIds.isEmpty
                      ? null
                      : () => _ignoreSelectedMajorEvents(roster),
                  child: const Text('Hide selected'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isLoadingMajorEvents)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (visibleEvents.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No major events loaded.'),
              )
            else
              ...visibleEvents.map(
                (event) => CheckboxListTile(
                  value: _selectedMajorEventIds.contains(event.id),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedMajorEventIds.add(event.id);
                      } else {
                        _selectedMajorEventIds.remove(event.id);
                      }
                    });
                  },
                  title: Text(event.title),
                  subtitle: Text(DateFormat.yMMMd().format(event.date)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchMajorEvents(
    BuildContext context,
    RosterNotifier roster,
    String countryCode,
  ) async {
    setState(() => _isLoadingMajorEvents = true);
    try {
      final events = await roster.fetchMajorEvents(
        countryCode: countryCode,
        year: _majorEventsYear,
      );
      setState(() {
        _majorEvents = events;
        _selectedMajorEventIds
          ..clear()
          ..addAll(events.map((e) => e.id));
      });
      _showSnack(context, 'Loaded ${events.length} major events.');
    } catch (e) {
      _showSnack(context, 'Failed to load major events.');
    } finally {
      if (mounted) {
        setState(() => _isLoadingMajorEvents = false);
      }
    }
  }

  void _addSelectedMajorEvents(
    RosterNotifier roster,
    List<Event> source,
  ) {
    final selected = source
        .where((event) => _selectedMajorEventIds.contains(event.id))
        .toList();
    if (selected.isEmpty) return;
    roster.addMajorEvents(selected);
    setState(() => _selectedMajorEventIds.clear());
  }

  void _ignoreSelectedMajorEvents(RosterNotifier roster) {
    final ignored = roster.rosterRules.ignoredMajorEventIds.toSet();
    ignored.addAll(_selectedMajorEventIds);
    roster.updateRosterRules(
      roster.rosterRules.copyWith(ignoredMajorEventIds: ignored.toList()),
    );
    setState(() {
      _majorEvents =
          _majorEvents.where((e) => !ignored.contains(e.id)).toList();
      _selectedMajorEventIds.clear();
    });
  }

  String _formatDateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _appendCsvDate(String current, String value) {
    final trimmed = current.trim();
    if (trimmed.isEmpty) return value;
    final parts = trimmed.split(',').map((item) => item.trim()).toList();
    if (!parts.contains(value)) {
      parts.add(value);
    }
    return parts.join(', ');
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<Event> _getUpcomingEvents(RosterNotifier notifier) {
    final now = DateTime.now();
    final list = <Event>[];
    final horizon = now.add(const Duration(days: 365));

    for (final event in notifier.events) {
      if (event.isRecurring && event.recurringIntervalWeeks != null) {
        final intervalWeeks = event.recurringIntervalWeeks ?? 1;
        final endDate = event.recurringEndDate ?? horizon;
        final exceptions = event.recurringExceptions
            .map((e) => DateTime.tryParse(e))
            .whereType<DateTime>()
            .map((e) => DateTime(e.year, e.month, e.day))
            .toSet();
        DateTime current = event.date;

        while (current.isBefore(now)) {
          current = current.add(Duration(days: intervalWeeks * 7));
        }

        while (!current.isAfter(endDate) && !current.isAfter(horizon)) {
          final normalized = DateTime(current.year, current.month, current.day);
          if (!exceptions.contains(normalized)) {
            list.add(Event(
              id: '${event.id}_${current.millisecondsSinceEpoch}',
              title: event.title,
              date: current,
              eventType: event.eventType,
              description: event.description,
              affectedStaff: event.affectedStaff,
              isRecurring: true,
              recurringIntervalWeeks: intervalWeeks,
              recurringEndDate: endDate,
              recurringId: event.id,
              recurringExceptions: event.recurringExceptions,
            ));
          }
          current = current.add(Duration(days: intervalWeeks * 7));
        }
      } else {
        final isToday = event.date.year == now.year &&
            event.date.month == now.month &&
            event.date.day == now.day;
        if (event.date.isAfter(now) || isToday) {
          list.add(event);
        }
      }
    }

    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  Widget _buildEventCard(BuildContext context, Event event) {
    final color = _getEventColor(event.eventType);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(
            _getEventIcon(event.eventType),
            color: Colors.white,
          ),
        ),
        title: Text(
          event.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat.yMMMd().format(event.date)),
            if (event.description != null) Text(event.description!),
            if (event.isRecurring || event.recurringId != null)
              Text(
                'Repeats every ${event.recurringIntervalWeeks ?? 1} week(s)'
                '${event.recurringEndDate != null ? ' until ${DateFormat.yMMMd().format(event.recurringEndDate!)}' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            if (event.affectedStaff.isNotEmpty)
              Text(
                'Affects: ${event.affectedStaff.join(', ')}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _deleteEvent(event),
        ),
      ),
    );
  }

  Color _getEventColor(String eventType) {
    switch (eventType) {
      case 'holiday':
        return Colors.purple;
      case 'major_event':
        return Colors.indigo;
      case 'training':
        return Colors.green;
      case 'meeting':
        return Colors.blue;
      case 'deadline':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _getEventIcon(String eventType) {
    switch (eventType) {
      case 'holiday':
        return Icons.celebration;
      case 'major_event':
        return Icons.local_activity;
      case 'training':
        return Icons.school;
      case 'meeting':
        return Icons.people;
      case 'deadline':
        return Icons.access_alarm;
      default:
        return Icons.event;
    }
  }

  void _showAddEventDialog(BuildContext context) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String selectedType = 'meeting';
    bool isRecurring = false;
    int recurringIntervalWeeks = 1;
    DateTime? recurringEndDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Event Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Event Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'meeting', child: Text('Meeting')),
                    DropdownMenuItem(value: 'training', child: Text('Training')),
                    DropdownMenuItem(value: 'holiday', child: Text('Holiday')),
                    DropdownMenuItem(
                        value: 'major_event', child: Text('Major event')),
                    DropdownMenuItem(value: 'deadline', child: Text('Deadline')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedType = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Date'),
                  subtitle: Text(DateFormat.yMMMd().format(selectedDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Recurring'),
                  value: isRecurring,
                  onChanged: (value) =>
                      setDialogState(() => isRecurring = value),
                ),
                if (isRecurring) ...[
                  DropdownButtonFormField<int>(
                    value: recurringIntervalWeeks,
                    decoration: const InputDecoration(
                      labelText: 'Repeat every',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 week')),
                      DropdownMenuItem(value: 2, child: Text('2 weeks')),
                      DropdownMenuItem(value: 4, child: Text('4 weeks')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => recurringIntervalWeeks = value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    title: const Text('Repeat until'),
                    subtitle: Text(
                      recurringEndDate == null
                          ? 'No end date'
                          : DateFormat.yMMMd().format(recurringEndDate!),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate:
                            recurringEndDate ?? selectedDate.add(const Duration(days: 28)),
                        firstDate: selectedDate,
                        lastDate: selectedDate.add(const Duration(days: 365 * 2)),
                      );
                      if (date != null) {
                        setDialogState(() => recurringEndDate = date);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.isNotEmpty) {
                  final event = Event(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: titleController.text,
                    date: selectedDate,
                    eventType: selectedType,
                    description: descriptionController.text.isEmpty 
                        ? null 
                        : descriptionController.text,
                    affectedStaff: const [],
                    isRecurring: isRecurring,
                    recurringIntervalWeeks:
                        isRecurring ? recurringIntervalWeeks : null,
                    recurringEndDate: isRecurring ? recurringEndDate : null,
                  );
                  ref.read(rosterProvider.notifier).addEvent(event);
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Event added successfully')),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteEvent(Event event) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text(
          event.recurringId != null || event.isRecurring
              ? 'Delete this recurring series or just this occurrence?'
              : 'Are you sure you want to delete "${event.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          if (event.recurringId != null || event.isRecurring)
            TextButton(
              onPressed: () {
                final baseId = event.recurringId ?? event.id;
                ref
                    .read(rosterProvider.notifier)
                    .deleteRecurringEventOccurrence(baseId, event.date);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Occurrence removed')),
                );
              },
              child: const Text('This occurrence'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final baseId = event.recurringId ?? event.id;
              ref.read(rosterProvider.notifier).deleteEvent(baseId);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Event deleted')),
              );
            },
            child: const Text('Delete series'),
          ),
        ],
      ),
    );
  }
}
