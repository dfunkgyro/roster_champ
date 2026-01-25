import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'providers.dart';

// ============================================================================
// REGULAR SHIFT SWAP MANAGEMENT SCREEN
// ============================================================================

class RegularSwapsScreen extends ConsumerWidget {
  const RegularSwapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // This would connect to your roster provider
    // final roster = ref.watch(rosterProvider);
    final swaps = <RegularShiftSwap>[]; // Replace with actual provider
    final roster = ref.watch(rosterProvider);
    final weekDayOrder = roster.weekDayOrder;
    final weekDayLabels = roster.weekDayLabels;

    String formatWeekDays(List<int> weekDays) {
      if (weekDays.isEmpty) return 'No days selected';
      final labelMap = weekDayLabels.asMap();
      final ordered = weekDayOrder.where(weekDays.contains).toList();
      final displayDays = ordered.isNotEmpty ? ordered : weekDays;
      return displayDays
          .map((day) => labelMap[day] ?? day.toString())
          .join(', ');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Regular Shift Swaps'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: swaps.isEmpty
          ? _buildEmptyState(context, ref, weekDayOrder, weekDayLabels)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: swaps.length,
              itemBuilder: (context, index) => SwapCard(
                swap: swaps[index],
                formatWeekDays: formatWeekDays,
                onToggle: (bool value) {
                  // ref.read(rosterProvider.notifier).toggleRegularSwap(swaps[index].id, value);
                },
                onEdit: () => _showEditSwapDialog(context, ref, swaps[index]),
                onDelete: () => _confirmDeleteSwap(context, ref, swaps[index]),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _showAddSwapDialog(context, ref, weekDayOrder, weekDayLabels),
        icon: const Icon(Icons.add),
        label: const Text('Add Swap'),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    List<int> weekDayOrder,
    List<String> weekDayLabels,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swap_horiz,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Regular Swaps',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Create recurring shift swaps between staff members',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () =>
                _showAddSwapDialog(context, ref, weekDayOrder, weekDayLabels),
            icon: const Icon(Icons.add),
            label: const Text('Create First Swap'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About Regular Swaps'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Regular shift swaps allow two staff members to automatically exchange shifts on specific days.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text('• Choose which days of the week to swap'),
              Text('• Set how often (every cycle, every 2 cycles, etc.)'),
              Text('• Optional end date for temporary swaps'),
              Text('• Toggle swaps on/off without deleting'),
              Text('• Swaps automatically apply to future dates'),
              SizedBox(height: 12),
              Text(
                'Example: Alice and Bob swap every Monday and Friday, every 2nd cycle.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  void _showAddSwapDialog(
    BuildContext context,
    WidgetRef ref,
    List<int> weekDayOrder,
    List<String> weekDayLabels,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AddSwapDialog(
        weekDayOrder: weekDayOrder,
        weekDayLabels: weekDayLabels,
        onAdd: (swap) {
          // ref.read(rosterProvider.notifier).addRegularSwap(swap);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Regular swap created')),
          );
        },
      ),
    );
  }

  void _showEditSwapDialog(
      BuildContext context, WidgetRef ref, RegularShiftSwap swap) {
    showDialog(
      context: context,
      builder: (ctx) => AddSwapDialog(
        existingSwap: swap,
        weekDayOrder: ref.read(rosterProvider).weekDayOrder,
        weekDayLabels: ref.read(rosterProvider).weekDayLabels,
        onAdd: (updatedSwap) {
          // ref.read(rosterProvider.notifier).updateRegularSwap(updatedSwap);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Swap updated')),
          );
        },
      ),
    );
  }

  void _confirmDeleteSwap(
      BuildContext context, WidgetRef ref, RegularShiftSwap swap) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Swap?'),
        content: Text(
          'Remove the regular swap between ${swap.staffMember1} and ${swap.staffMember2}?\n\nThis will also remove all future swaps generated by this rule.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // ref.read(rosterProvider.notifier).removeRegularSwap(swap.id);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🗑️ Swap deleted')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SWAP CARD WIDGET
// ============================================================================

class SwapCard extends StatelessWidget {
  final RegularShiftSwap swap;
  final String Function(List<int>) formatWeekDays;
  final Function(bool) onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const SwapCard({
    super.key,
    required this.swap,
    required this.formatWeekDays,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: swap.isActive ? 2 : 1,
      child: ListTile(
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Switch(
              value: swap.isActive,
              onChanged: onToggle,
              activeColor: Colors.green,
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                swap.staffMember1,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.swap_horiz, size: 20),
            Expanded(
              child: Text(
                swap.staffMember2,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(formatWeekDays(swap.weekDays)),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.repeat, size: 14),
                const SizedBox(width: 4),
                Text('Every ${swap.cycleFrequency} cycle(s)'),
              ],
            ),
            if (swap.endDate != null)
              Row(
                children: [
                  const Icon(Icons.event_busy, size: 14),
                  const SizedBox(width: 4),
                  Text('Until ${DateFormat.yMMMd().format(swap.endDate!)}'),
                ],
              ),
            if (swap.notes != null && swap.notes!.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.note, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      swap.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: onEdit,
              tooltip: 'Edit Swap',
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
              onPressed: onDelete,
              tooltip: 'Delete Swap',
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

// ============================================================================
// ADD/EDIT SWAP DIALOG
// ============================================================================

class AddSwapDialog extends StatefulWidget {
  final RegularShiftSwap? existingSwap;
  final List<int> weekDayOrder;
  final List<String> weekDayLabels;
  final Function(RegularShiftSwap) onAdd;

  const AddSwapDialog({
    super.key,
    this.existingSwap,
    required this.weekDayOrder,
    required this.weekDayLabels,
    required this.onAdd,
  });

  @override
  State<AddSwapDialog> createState() => _AddSwapDialogState();
}

class _AddSwapDialogState extends State<AddSwapDialog> {
  String? staff1;
  String? staff2;
  final selectedDays = <int>{};
  int cycleFrequency = 1;
  DateTime? endDate;
  final notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existingSwap != null) {
      staff1 = widget.existingSwap!.staffMember1;
      staff2 = widget.existingSwap!.staffMember2;
      selectedDays.addAll(widget.existingSwap!.weekDays);
      cycleFrequency = widget.existingSwap!.cycleFrequency;
      endDate = widget.existingSwap!.endDate;
      notesController.text = widget.existingSwap!.notes ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // In real implementation, get from provider
    final activeStaff = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve'];

    return AlertDialog(
      title: Text(widget.existingSwap == null ? 'Add Regular Swap' : 'Edit Swap'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: staff1,
                items: activeStaff
                    .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                    .toList(),
                onChanged: (value) => setState(() => staff1 = value),
                decoration: const InputDecoration(
                  labelText: 'First Staff Member',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: staff2,
                items: activeStaff
                    .where((name) => name != staff1)
                    .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                    .toList(),
                onChanged: (value) => setState(() => staff2 = value),
                decoration: const InputDecoration(
                  labelText: 'Second Staff Member',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Swap on days:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.weekDayOrder.map((day) {
                  final dayName = widget.weekDayLabels[day];
                  return FilterChip(
                    label: Text(dayName),
                    selected: selectedDays.contains(day),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          selectedDays.add(day);
                        } else {
                          selectedDays.remove(day);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: cycleFrequency,
                items: [1, 2, 3, 4]
                    .map((cycles) => DropdownMenuItem(
                          value: cycles,
                          child: Text('Every $cycles cycle(s)'),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => cycleFrequency = value!),
                decoration: const InputDecoration(
                  labelText: 'Frequency',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                title: const Text('Set end date'),
                value: endDate != null,
                onChanged: (value) {
                  setState(() {
                    endDate = value == true
                        ? DateTime.now().add(const Duration(days: 90))
                        : null;
                  });
                },
              ),
              if (endDate != null) ...[
                ListTile(
                  title: Text('End date: ${DateFormat.yMMMd().format(endDate!)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: endDate!,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (date != null) {
                      setState(() => endDate = date);
                    }
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: staff1 != null && staff2 != null && selectedDays.isNotEmpty
              ? () {
                  final swap = RegularShiftSwap(
                    id: widget.existingSwap?.id ??
                        DateTime.now().millisecondsSinceEpoch.toString(),
                    staffMember1: staff1!,
                    staffMember2: staff2!,
                    weekDays: selectedDays.toList()..sort(),
                    cycleFrequency: cycleFrequency,
                    startDate: widget.existingSwap?.startDate ?? DateTime.now(),
                    endDate: endDate,
                    notes: notesController.text.isEmpty ? null : notesController.text,
                  );
                  widget.onAdd(swap);
                  Navigator.of(context).pop();
                }
              : null,
          child: Text(widget.existingSwap == null ? 'Add Swap' : 'Save Changes'),
        ),
      ],
    );
  }
}
