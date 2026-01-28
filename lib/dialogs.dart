import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart' as models;

class InitializeRosterDialog extends StatefulWidget {
  final Function(int cycleLength, int numPeople) onInitialize;

  const InitializeRosterDialog({
    super.key,
    required this.onInitialize,
  });

  @override
  State<InitializeRosterDialog> createState() => _InitializeRosterDialogState();
}

class _InitializeRosterDialogState extends State<InitializeRosterDialog> {
  final _cycleLengthController = TextEditingController(text: '16');
  final _numPeopleController = TextEditingController(text: '16');

  @override
  void dispose() {
    _cycleLengthController.dispose();
    _numPeopleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Initialize Roster'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _cycleLengthController,
            decoration: const InputDecoration(
              labelText: 'Cycle Length (weeks)',
              hintText: 'e.g., 16',
              suffixText: 'weeks',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _numPeopleController,
            decoration: const InputDecoration(
              labelText: 'Number of Staff',
              hintText: 'e.g., 16',
              suffixText: 'people',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
            final cycleLength = int.tryParse(_cycleLengthController.text) ?? 16;
            final numPeople = int.tryParse(_numPeopleController.text) ?? 16;

            if (cycleLength > 0 &&
                cycleLength <= 52 &&
                numPeople > 0 &&
                numPeople <= 100) {
              widget.onInitialize(cycleLength, numPeople);
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Please enter valid values (cycle: 1-52, people: 1-100)'),
                ),
              );
            }
          },
          child: const Text('Initialize'),
        ),
      ],
    );
  }
}

class AddEventDialog extends StatefulWidget {
  final Function(List<models.Event>) onAddEvents;
  final DateTime? initialDate;
  final String? initialTitle;

  const AddEventDialog({
    super.key,
    required this.onAddEvents,
    this.initialDate,
    this.initialTitle,
  });

  @override
  State<AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<AddEventDialog> {
  late final TextEditingController _titleController;
  final _descriptionController = TextEditingController();
  late DateTime _selectedDate;
  models.EventType _selectedType = models.EventType.general;
  bool _isRecurring = false;
  int _repeatInterval = 1;
  bool _repeatWeekly = true;
  int _pastOccurrences = 0;
  int _futureOccurrences = 8;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Event'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Event Title',
                hintText: 'Enter event title',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                hintText: 'Enter event description',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Date'),
              subtitle: Text(
                '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
              ),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (date != null) {
                  setState(() => _selectedDate = date);
                }
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<models.EventType>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Event Type',
              ),
              items: models.EventType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(_getEventTypeName(type)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedType = value);
                }
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeat event'),
              value: _isRecurring,
              onChanged: (value) {
                setState(() => _isRecurring = value);
              },
            ),
            if (_isRecurring) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Repeat every',
                      ),
                      onChanged: (value) {
                        final parsed = int.tryParse(value.trim());
                        if (parsed != null && parsed > 0) {
                          _repeatInterval = parsed;
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<bool>(
                    value: _repeatWeekly,
                    items: const [
                      DropdownMenuItem(
                        value: true,
                        child: Text('Weeks'),
                      ),
                      DropdownMenuItem(
                        value: false,
                        child: Text('Days'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _repeatWeekly = value);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Past occurrences',
                        helperText: 'e.g. 4',
                      ),
                      onChanged: (value) {
                        final parsed = int.tryParse(value.trim());
                        if (parsed != null && parsed >= 0) {
                          _pastOccurrences = parsed;
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Future occurrences',
                        helperText: 'e.g. 8',
                      ),
                      onChanged: (value) {
                        final parsed = int.tryParse(value.trim());
                        if (parsed != null && parsed >= 0) {
                          _futureOccurrences = parsed;
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_titleController.text.trim().isNotEmpty) {
              final description = _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim();
              final baseId = DateTime.now().millisecondsSinceEpoch.toString();
              final events = <models.Event>[];
              final recurringId = _isRecurring ? baseId : null;

              void addEvent(DateTime date) {
                events.add(
                  models.Event(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    title: _titleController.text.trim(),
                    description: description,
                    date: date,
                    eventType: _selectedType,
                    recurringId: recurringId,
                  ),
                );
              }

              addEvent(_selectedDate);

              if (_isRecurring) {
                final stepDays =
                    (_repeatWeekly ? 7 : 1) * _repeatInterval.clamp(1, 365);
                for (var i = 1; i <= _pastOccurrences; i++) {
                  addEvent(_selectedDate.subtract(Duration(days: stepDays * i)));
                }
                for (var i = 1; i <= _futureOccurrences; i++) {
                  addEvent(_selectedDate.add(Duration(days: stepDays * i)));
                }
              }

              widget.onAddEvents(events);
              Navigator.pop(context);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }

  String _getEventTypeName(models.EventType type) {
    switch (type) {
      case models.EventType.general:
        return 'General';
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
    }
  }
}

class AddOverrideDialog extends StatefulWidget {
  final String person;
  final DateTime date;
  final Function(String newShift, String reason) onAdd;

  const AddOverrideDialog({
    super.key,
    required this.person,
    required this.date,
    required this.onAdd,
  });

  @override
  State<AddOverrideDialog> createState() => _AddOverrideDialogState();
}

class _AddOverrideDialogState extends State<AddOverrideDialog> {
  final _shiftController = TextEditingController();
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _shiftController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Override for ${widget.person}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Date: ${widget.date.day}/${widget.date.month}/${widget.date.year}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _shiftController,
            decoration: const InputDecoration(
              labelText: 'New Shift',
              hintText: 'e.g., D, N, L, OFF',
            ),
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(
              labelText: 'Reason (Optional)',
              hintText: 'e.g., Requested leave',
            ),
            maxLines: 2,
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
            if (_shiftController.text.trim().isNotEmpty) {
              widget.onAdd(
                _shiftController.text.trim().toUpperCase(),
                _reasonController.text.trim(),
              );
              Navigator.pop(context);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class BulkOverrideDialog extends StatefulWidget {
  final String person;
  final Function(
      DateTime startDate, DateTime endDate, String shift, String reason) onAdd;

  const BulkOverrideDialog({
    super.key,
    required this.person,
    required this.onAdd,
  });

  @override
  State<BulkOverrideDialog> createState() => _BulkOverrideDialogState();
}

class _BulkOverrideDialogState extends State<BulkOverrideDialog> {
  final _shiftController = TextEditingController();
  final _reasonController = TextEditingController();
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));

  @override
  void dispose() {
    _shiftController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Bulk Override for ${widget.person}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Start Date'),
              subtitle: Text(
                  '${_startDate.day}/${_startDate.month}/${_startDate.year}'),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (date != null) {
                  setState(() => _startDate = date);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('End Date'),
              subtitle:
                  Text('${_endDate.day}/${_endDate.month}/${_endDate.year}'),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _endDate,
                  firstDate: _startDate,
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (date != null) {
                  setState(() => _endDate = date);
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _shiftController,
              decoration: const InputDecoration(
                labelText: 'Shift',
                hintText: 'e.g., L (for leave)',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g., Annual leave',
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_shiftController.text.trim().isNotEmpty &&
                _reasonController.text.trim().isNotEmpty) {
              widget.onAdd(
                _startDate,
                _endDate,
                _shiftController.text.trim().toUpperCase(),
                _reasonController.text.trim(),
              );
              Navigator.pop(context);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
