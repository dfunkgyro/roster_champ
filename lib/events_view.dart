import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'providers.dart';
import 'dialogs.dart';
import 'models.dart' as models;
import 'services/holiday_service.dart';
import 'services/public_event_service.dart';
import 'services/dst_service.dart';

Color _eventColorForType(models.EventType type) {
  switch (type) {
    case models.EventType.holiday:
      return Colors.red;
    case models.EventType.training:
      return Colors.blue;
    case models.EventType.meeting:
      return Colors.purple;
    case models.EventType.deadline:
      return Colors.orange;
    case models.EventType.birthday:
      return Colors.pink;
    case models.EventType.anniversary:
      return Colors.green;
    case models.EventType.payday:
      return Colors.teal;
    case models.EventType.religious:
      return Colors.deepPurple;
    case models.EventType.cultural:
      return Colors.deepOrange;
    case models.EventType.sports:
      return Colors.teal;
    default:
      return Colors.grey;
  }
}

class EventsView extends ConsumerStatefulWidget {
  const EventsView({super.key});

  @override
  ConsumerState<EventsView> createState() => _EventsViewState();
}

class _EventsViewState extends ConsumerState<EventsView> {
  bool _loadingOverlay = false;
  List<models.Event> _overlayEvents = [];

  @override
  void initState() {
    super.initState();
    _loadOverlayEvents();
  }

  @override
  void didUpdateWidget(covariant EventsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadOverlayEvents();
  }

  Future<void> _loadOverlayEvents() async {
    if (_loadingOverlay) return;
    setState(() => _loadingOverlay = true);
    try {
      final settings = ref.read(settingsProvider);
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(now.year + 1, now.month, now.day);

      final holidays = await HolidayService.instance.getHolidaysRange(
        countryCode: settings.holidayCountryCode,
        additionalCountries: settings.additionalHolidayCountries,
        start: start,
        end: end,
        allowedTypes: settings.holidayTypes,
      );
      final publicEventMap = await PublicEventService.instance.getPublicEvents(
        settings: settings,
        start: start,
        end: end,
      );

      final overlay = <models.Event>[];
      for (final item in holidays.values) {
        overlay.add(
          models.Event(
            id: 'holiday-${item.date.toIso8601String()}-${item.name.hashCode}',
            title: item.localName.isNotEmpty ? item.localName : item.name,
            description: item.types.isNotEmpty
                ? item.types.join(', ')
                : 'Holiday',
            date: item.date,
            eventType: models.EventType.holiday,
          ),
        );
      }

      for (final entry in publicEventMap.entries) {
        overlay.addAll(entry.value);
      }

      if (settings.dstAdjustmentsEnabled) {
        var cursor = start;
        while (!cursor.isAfter(end)) {
          final delta = DstService.dayDeltaMinutes(cursor);
          if (delta != 0) {
            final label = DstService.deltaLabel(cursor) ?? 'DST change';
            overlay.add(
              models.Event(
                id: 'dst-${cursor.toIso8601String()}',
                title: label,
                description: 'Daylight saving time change',
                date: cursor,
                eventType: models.EventType.custom,
              ),
            );
          }
          cursor = cursor.add(const Duration(days: 1));
        }
      }

      overlay.sort((a, b) => a.date.compareTo(b.date));
      if (mounted) {
        setState(() => _overlayEvents = overlay);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _overlayEvents = []);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingOverlay = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final events = roster.events;
    final isReadOnly = roster.readOnly;

    Widget emptyState() {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Events',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Add events like payday, training, or holidays',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 16),
            if (!isReadOnly)
              FilledButton.icon(
                onPressed: () => _openAddEvent(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add Event'),
              ),
          ],
        ),
      );
    }

    final sortedEvents = List<models.Event>.from(events)
      ..sort((a, b) => a.date.compareTo(b.date));

    if (events.isEmpty && _overlayEvents.isEmpty) {
      return emptyState();
    }

    return Column(
      children: [
        if (!isReadOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openAddEvent(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Event'),
                  ),
                ),
              ],
            ),
          ),
        if (_loadingOverlay)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedEvents.length + (_overlayEvents.isEmpty ? 0 : 1 + _overlayEvents.length),
            itemBuilder: (context, index) {
              if (index < sortedEvents.length) {
                final event = sortedEvents[index];
                return _EventCard(event: event);
              }
              final overlayIndex = index - sortedEvents.length;
              if (overlayIndex == 0) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    'Holiday & Observance Overlays',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }
              final overlayEvent = _overlayEvents[overlayIndex - 1];
              return _OverlayEventCard(event: overlayEvent);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openAddEvent(BuildContext context, WidgetRef ref) async {
    await showDialog(
      context: context,
      builder: (context) => AddEventDialog(
        onAddEvents: (events) {
          if (events.length == 1) {
            ref.read(rosterProvider).addEvent(events.first);
          } else {
            ref.read(rosterProvider).addBulkEvents(events);
          }
        },
      ),
    );
  }
}

class _OverlayEventCard extends StatelessWidget {
  final models.Event event;

  const _OverlayEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final color = _eventColorForType(event.eventType);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(Icons.event, color: color),
        title: Text(event.title),
        subtitle: Text(
          '${DateFormat('MMM d, yyyy').format(event.date)}'
          '${event.description != null && event.description!.isNotEmpty ? ' • ${event.description}' : ''}',
        ),
      ),
    );
  }
}

class _EventCard extends ConsumerWidget {
  final models.Event event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _eventColorForType(event.eventType);
    final isPast = event.date.isBefore(DateTime.now());
    final isReadOnly = ref.watch(rosterProvider).readOnly;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showEventDetails(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _getEventIcon(event.eventType),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            event.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              decoration:
                                  isPast ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEE, MMM d, yyyy').format(event.date),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    if (event.recurringId != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.repeat, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Recurring',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (event.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.description!,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (event.affectedStaff.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Affects: ${event.affectedStaff.join(', ')}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: isReadOnly ? null : () => _confirmDelete(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: isReadOnly ? null : () => _editEvent(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getEventColor(models.EventType type) => _eventColorForType(type);

  Icon _getEventIcon(models.EventType type) {
    switch (type) {
      case models.EventType.holiday:
        return const Icon(Icons.celebration, size: 20, color: Colors.red);
      case models.EventType.training:
        return const Icon(Icons.school, size: 20, color: Colors.blue);
      case models.EventType.meeting:
        return const Icon(Icons.groups, size: 20, color: Colors.purple);
      case models.EventType.deadline:
        return const Icon(Icons.alarm, size: 20, color: Colors.orange);
      case models.EventType.birthday:
        return const Icon(Icons.cake, size: 20, color: Colors.pink);
      case models.EventType.anniversary:
        return const Icon(Icons.favorite, size: 20, color: Colors.green);
      case models.EventType.payday:
        return const Icon(Icons.attach_money, size: 20, color: Colors.teal);
      case models.EventType.religious:
        return const Icon(Icons.temple_hindu, size: 20, color: Colors.deepPurple);
      case models.EventType.cultural:
        return const Icon(Icons.festival, size: 20, color: Colors.deepOrange);
      case models.EventType.sports:
        return const Icon(Icons.sports_soccer, size: 20, color: Colors.teal);
      default:
        return const Icon(Icons.event, size: 20, color: Colors.grey);
    }
  }

  void _showEventDetails(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(DateFormat('EEEE, MMMM d, yyyy').format(event.date)),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(Icons.category),
              title: Text(_getEventTypeName(event.eventType)),
              contentPadding: EdgeInsets.zero,
            ),
            if (event.description != null)
              ListTile(
                leading: const Icon(Icons.description),
                title: Text(event.description!),
                contentPadding: EdgeInsets.zero,
              ),
            if (event.affectedStaff.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.people),
                title: Text(event.affectedStaff.join(', ')),
                contentPadding: EdgeInsets.zero,
              ),
          ],
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

  String _getEventTypeName(models.EventType type) {
    switch (type) {
      case models.EventType.holiday:
        return 'Holiday';
      case models.EventType.training:
        return 'Training';
      case models.EventType.meeting:
        return 'Meeting';
      case models.EventType.deadline:
        return 'Deadline';
      case models.EventType.birthday:
        return 'Birthday';
      case models.EventType.anniversary:
        return 'Anniversary';
      case models.EventType.payday:
        return 'Payday';
      case models.EventType.religious:
        return 'Religious';
      case models.EventType.cultural:
        return 'Cultural';
      case models.EventType.sports:
        return 'Sports';
      case models.EventType.custom:
        return 'Custom';
      case models.EventType.general:
        return 'General';
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event?'),
        content: Text('Delete "${event.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(rosterProvider).deleteEvent(event.id);
    }
  }

  Future<void> _editEvent(BuildContext context, WidgetRef ref) async {
    if (ref.read(rosterProvider).readOnly) return;
    await showDialog(
      context: context,
      builder: (context) => AddEventDialog(
        initialDate: event.date,
        initialTitle: event.title,
        onAddEvents: (events) {
          if (events.isEmpty) return;
          ref.read(rosterProvider).deleteEvent(event.id);
          if (events.length == 1) {
            ref.read(rosterProvider).addEvent(events.first);
          } else {
            ref.read(rosterProvider).addBulkEvents(events);
          }
        },
      ),
    );
  }
}
