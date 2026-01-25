import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'providers.dart';
import 'models.dart' as models;

class EventsView extends ConsumerWidget {
  const EventsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(rosterProvider);
    final events = roster.events;

    if (events.isEmpty) {
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
              'Add events to track important dates',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      );
    }

    final sortedEvents = List<models.Event>.from(events)
      ..sort((a, b) => a.date.compareTo(b.date));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedEvents.length,
      itemBuilder: (context, index) {
        final event = sortedEvents[index];
        return _EventCard(event: event);
      },
    );
  }
}

class _EventCard extends ConsumerWidget {
  final models.Event event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _getEventColor(event.eventType);
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
            ],
          ),
        ),
      ),
    );
  }

  Color _getEventColor(models.EventType type) {
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
      default:
        return Colors.grey;
    }
  }

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
    return type.name[0].toUpperCase() + type.name.substring(1);
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
}
