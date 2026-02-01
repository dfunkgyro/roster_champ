import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/roster.dart';

class ShiftPickerDialog extends StatelessWidget {
  final String employeeName;
  final DateTime date;
  final String currentShift;
  final Map<String, ShiftCode> shiftCodes;
  final Function(String) onShiftSelected;

  const ShiftPickerDialog({
    super.key,
    required this.employeeName,
    required this.date,
    required this.currentShift,
    required this.shiftCodes,
    required this.onShiftSelected,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.edit_calendar, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit Shift',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        employeeName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Date display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateFormat.format(date),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Current shift indicator
            Text(
              'Current: $currentShift (${shiftCodes[currentShift]?.name ?? "Unknown"})',
              style: TextStyle(color: Colors.grey[600]),
            ),

            const SizedBox(height: 12),

            // Shift options grid
            const Text(
              'Select new shift:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),

            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: shiftCodes.entries.map((entry) {
                    final isSelected = entry.key == currentShift;
                    final color = _parseColor(entry.value.color);
                    final textColor = color.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white;

                    return InkWell(
                      onTap: () {
                        onShiftSelected(entry.key);
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 80,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey[300]!,
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.3),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              entry.key,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              entry.value.name,
                              style: TextStyle(
                                color: textColor.withOpacity(0.8),
                                fontSize: 9,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Cancel button
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String colorString) {
    try {
      final hex = colorString.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }
}

/// A bulk shift editor dialog for updating multiple days at once
class BulkShiftEditorDialog extends StatefulWidget {
  final String employeeName;
  final String employeeId;
  final DateTime startDate;
  final DateTime endDate;
  final Map<String, ShiftCode> shiftCodes;
  final Function(DateTime start, DateTime end, String shiftCode) onApply;

  const BulkShiftEditorDialog({
    super.key,
    required this.employeeName,
    required this.employeeId,
    required this.startDate,
    required this.endDate,
    required this.shiftCodes,
    required this.onApply,
  });

  @override
  State<BulkShiftEditorDialog> createState() => _BulkShiftEditorDialogState();
}

class _BulkShiftEditorDialogState extends State<BulkShiftEditorDialog> {
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  String _selectedShift = 'R';

  @override
  void initState() {
    super.initState();
    _rangeStart = widget.startDate;
    _rangeEnd = widget.endDate;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Bulk Edit: ${widget.employeeName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range selection
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start Date'),
            subtitle: Text(_formatDate(_rangeStart)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () => _selectDate(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('End Date'),
            subtitle: Text(_formatDate(_rangeEnd)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () => _selectDate(false),
          ),
          const Divider(),

          // Shift selection
          const Text(
            'Apply Shift:',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedShift,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: widget.shiftCodes.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text('${e.key} - ${e.value.name}'),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedShift = value);
              }
            },
          ),

          const SizedBox(height: 12),

          // Preview
          Text(
            'This will update ${_rangeEnd.difference(_rangeStart).inDays + 1} day(s)',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onApply(_rangeStart, _rangeEnd, _selectedShift);
            Navigator.pop(context);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Future<void> _selectDate(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _rangeStart : _rangeEnd,
      firstDate: widget.startDate,
      lastDate: widget.endDate,
    );

    if (date != null) {
      setState(() {
        if (isStart) {
          _rangeStart = date;
          if (_rangeEnd.isBefore(_rangeStart)) {
            _rangeEnd = _rangeStart;
          }
        } else {
          _rangeEnd = date;
          if (_rangeStart.isAfter(_rangeEnd)) {
            _rangeStart = _rangeEnd;
          }
        }
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
