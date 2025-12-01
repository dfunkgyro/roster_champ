import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers.dart';
import 'models.dart' as models;
import 'dialogs.dart';

class RosterView extends ConsumerStatefulWidget {
  const RosterView({super.key});

  @override
  ConsumerState<RosterView> createState() => _RosterViewState();
}

class _RosterViewState extends ConsumerState<RosterView> {
  DateTime _currentWeekStart = DateTime.now();
  final ScrollController _scrollController = ScrollController();
  final Map<String, TextEditingController> _nameControllers = {};

  // Color system matching pattern editor
  // Update the shift colors in the RosterView to match pattern editor
  final Map<String, Color> _shiftColors = {
    'D': Colors.blue,
    'N': Colors.purple,
    'L': Colors.orange,
    'OFF': Colors.grey,
    'R': Colors.green,
    'E': Colors.lightBlue,
    'N12': Colors.deepPurple,
    'C': Colors.teal,
    'C1': Colors.teal[300]!,
    'C2': Colors.teal[400]!,
    'C3': Colors.teal[600]!,
    'C4': Colors.teal[800]!,
  };

  @override
  void dispose() {
    _scrollController.dispose();
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final settings = ref.watch(settingsProvider);

    if (roster.getActiveStaffNames().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Roster Data',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Initialize a roster to get started',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showInitializeDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Initialize Roster'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildWeekNavigator(context),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: _buildRosterTable(context, roster, settings),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekNavigator(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () {
              setState(() {
                _currentWeekStart =
                    _currentWeekStart.subtract(const Duration(days: 7));
              });
            },
          ),
          Column(
            children: [
              Text(
                'Week of ${DateFormat('MMM d, yyyy').format(_currentWeekStart)}',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _getWeekRange(),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () {
              setState(() {
                _currentWeekStart =
                    _currentWeekStart.add(const Duration(days: 7));
              });
            },
          ),
        ],
      ),
    );
  }

  String _getWeekRange() {
    final weekEnd = _currentWeekStart.add(const Duration(days: 6));
    return '${DateFormat('MMM d').format(_currentWeekStart)} - ${DateFormat('MMM d').format(weekEnd)}';
  }

  Widget _buildRosterTable(
    BuildContext context,
    RosterNotifier roster,
    models.AppSettings settings,
  ) {
    final staff = roster.getActiveStaffNames();
    final days =
        List.generate(7, (i) => _currentWeekStart.add(Duration(days: i)));

    return DataTable(
      headingRowColor: WidgetStateProperty.resolveWith(
        (states) =>
            Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      ),
      border: TableBorder.all(
        color: Theme.of(context).dividerColor,
        width: 1,
      ),
      columns: [
        DataColumn(
          label: SizedBox(
            width: 140,
            child: Row(
              children: [
                Text(
                  'Staff',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.edit_rounded,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        ...days.map((day) {
          final isToday = _isSameDay(day, DateTime.now());
          return DataColumn(
            label: SizedBox(
              width: 80,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('EEE').format(day),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: isToday
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    DateFormat('MMM d').format(day),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isToday
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (isToday)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
      rows: staff.map((personName) {
        final staffMember = roster.staffMembers.firstWhere(
          (s) => s.name == personName,
          orElse: () => models.StaffMember(
            id: '',
            name: personName,
            isActive: true,
            leaveBalance: 31.0, // Updated to 31.0 days
          ),
        );

        _nameControllers[personName] ??=
            TextEditingController(text: personName);

        return DataRow(
          cells: [
            DataCell(
              SizedBox(
                width: 140,
                child: Row(
                  children: [
                    Icon(
                      staffMember.isActive
                          ? Icons.person_rounded
                          : Icons.person_off_rounded,
                      size: 16,
                      color: staffMember.isActive ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _nameControllers[personName]!,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                        ),
                        onSubmitted: (newName) {
                          if (newName.trim().isNotEmpty &&
                              newName != personName) {
                            final index = roster.staffMembers
                                .indexWhere((s) => s.name == personName);
                            if (index != -1) {
                              ref
                                  .read(rosterProvider)
                                  .renameStaff(index, newName.trim());
                            }
                          } else {
                            _nameControllers[personName]!.text = personName;
                          }
                        },
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, size: 16),
                      onSelected: (value) {
                        switch (value) {
                          case 'leave':
                            _showLeaveDialog(personName);
                            break;
                          case 'overrides':
                            _showStaffOverrides(personName);
                            break;
                          case 'toggle':
                            final index = roster.staffMembers
                                .indexWhere((s) => s.name == personName);
                            if (index != -1) {
                              ref.read(rosterProvider).toggleStaffStatus(index);
                            }
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'leave',
                          child: ListTile(
                            leading: Icon(Icons.beach_access_rounded),
                            title: Text('Manage Leave'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'overrides',
                          child: ListTile(
                            leading: Icon(Icons.edit_calendar_rounded),
                            title: Text('View Overrides'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'toggle',
                          child: ListTile(
                            leading: Icon(staffMember.isActive
                                ? Icons.person_off_rounded
                                : Icons.person_rounded),
                            title: Text(staffMember.isActive
                                ? 'Deactivate'
                                : 'Activate'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ...days.map((day) {
              final shift = roster.getShiftForDate(personName, day);
              final isToday = _isSameDay(day, DateTime.now());
              final shiftColor =
                  _shiftColors[shift.toUpperCase()] ?? Colors.grey;

              return DataCell(
                InkWell(
                  onTap: () => _showShiftOptions(context, personName, day),
                  child: Container(
                    width: 80,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: shiftColor.withOpacity(0.15),
                      border: Border.all(
                        color: shiftColor,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: isToday
                          ? [
                              BoxShadow(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.3),
                                blurRadius: 4,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          shift,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: shiftColor,
                            fontSize: 14,
                          ),
                        ),
                        if (shift == 'L')
                          Icon(
                            Icons.beach_access_rounded,
                            size: 12,
                            color: shiftColor,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      }).toList(),
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  void _showShiftOptions(
      BuildContext context, String personName, DateTime date) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '${DateFormat('EEE, MMM d').format(date)} - $personName',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Add Override'),
              subtitle: const Text('Set custom shift for this day'),
              onTap: () {
                Navigator.pop(context);
                _showAddOverrideDialog(personName, date);
              },
            ),
            ListTile(
              leading: const Icon(Icons.date_range_rounded),
              title: const Text('Bulk Override'),
              subtitle: const Text('Set overrides for multiple days'),
              onTap: () {
                Navigator.pop(context);
                _showBulkOverrideDialog(personName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('View Details'),
              subtitle: const Text('See shift information and history'),
              onTap: () {
                Navigator.pop(context);
                _showDayDetails(personName, date);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddOverrideDialog(String personName, DateTime date) async {
    await showDialog(
      context: context,
      builder: (context) => AddOverrideDialog(
        person: personName,
        date: date,
        onAdd: (shift, reason) {
          ref.read(rosterProvider).setOverride(personName, date, shift, reason);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Override added successfully')),
          );
        },
      ),
    );
  }

  Future<void> _showBulkOverrideDialog(String personName) async {
    await showDialog(
      context: context,
      builder: (context) => BulkOverrideDialog(
        person: personName,
        onAdd: (startDate, endDate, shift, reason) {
          ref.read(rosterProvider).addBulkOverrides(
                personName,
                startDate,
                endDate,
                shift,
                reason,
              );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Bulk override added for ${endDate.difference(startDate).inDays + 1} days',
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDayDetails(String personName, DateTime date) {
    final roster = ref.read(rosterProvider);
    final shift = roster.getShiftForDate(personName, date);
    final override = roster.overrides.firstWhere(
      (o) =>
          o.personName == personName &&
          o.date.year == date.year &&
          o.date.month == date.month &&
          o.date.day == date.day,
      orElse: () => models.Override(
        id: '',
        personName: '',
        date: DateTime.now(),
        shift: '',
        createdAt: DateTime.now(),
      ),
    );

    final shiftColor = _shiftColors[shift.toUpperCase()] ?? Colors.grey;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            '$personName - ${DateFormat('EEE, MMM d, yyyy').format(date)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: shiftColor.withOpacity(0.2),
                  border: Border.all(color: shiftColor, width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    shift,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: shiftColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              title: const Text('Scheduled Shift'),
              subtitle: Text(
                shift,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: shiftColor,
                ),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            if (override.id.isNotEmpty) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.edit_calendar_rounded),
                title: const Text('Override Applied'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shift: ${override.shift}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _shiftColors[override.shift.toUpperCase()] ??
                            Colors.grey,
                      ),
                    ),
                    if (override.reason != null)
                      Text('Reason: ${override.reason}'),
                    Text(
                      'Added: ${DateFormat('MMM d, yyyy').format(override.createdAt)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                contentPadding: EdgeInsets.zero,
              ),
              TextButton.icon(
                onPressed: () {
                  roster.overrides.removeWhere((o) => o.id == override.id);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Override removed')),
                  );
                  roster.notifyListeners();
                },
                icon: const Icon(Icons.delete_rounded, color: Colors.red),
                label: const Text('Remove Override',
                    style: TextStyle(color: Colors.red)),
              ),
            ] else ...[
              const Divider(),
              Text(
                'No overrides applied',
                style: GoogleFonts.inter(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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

  void _showLeaveDialog(String personName) {
    final roster = ref.read(rosterProvider);
    final staffMember = roster.staffMembers.firstWhere(
      (s) => s.name == personName,
      orElse: () => models.StaffMember(
        id: '',
        name: personName,
        isActive: true,
        leaveBalance: 31.0, // Updated to 31.0 days
      ),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Manage Leave - $personName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Current Leave Balance: ${staffMember.leaveBalance.toStringAsFixed(1)} days',
              style: GoogleFonts.inter(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      roster.adjustLeaveBalance(personName, 1.0);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Leave day added')),
                      );
                    },
                    child: const Text('+1 Day'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      roster.adjustLeaveBalance(personName, -1.0);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Leave day deducted')),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    child: const Text('-1 Day'),
                  ),
                ),
              ],
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

  void _showStaffOverrides(String personName) {
    final roster = ref.read(rosterProvider);
    final overrides = roster.getOverridesForPerson(personName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Overrides - $personName'),
        content: SizedBox(
          width: double.maxFinite,
          child: overrides.isEmpty
              ? const Text('No overrides found')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: overrides.length,
                  itemBuilder: (context, index) {
                    final override = overrides[index];
                    final shiftColor =
                        _shiftColors[override.shift.toUpperCase()] ??
                            Colors.grey;

                    return ListTile(
                      leading: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: shiftColor.withOpacity(0.2),
                          border: Border.all(color: shiftColor, width: 2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            override.shift,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: shiftColor,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      title:
                          Text(DateFormat('MMM d, yyyy').format(override.date)),
                      subtitle: override.reason != null
                          ? Text(override.reason!)
                          : null,
                      trailing: IconButton(
                        icon:
                            const Icon(Icons.delete_rounded, color: Colors.red),
                        onPressed: () {
                          roster.overrides
                              .removeWhere((o) => o.id == override.id);
                          Navigator.pop(context);
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Override Removed'),
                              content: const Text(
                                  'The override has been removed successfully.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                          roster.notifyListeners();
                        },
                      ),
                    );
                  },
                ),
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

  Future<void> _showInitializeDialog() async {
    await showDialog(
      context: context,
      builder: (context) => InitializeRosterDialog(
        onInitialize: (cycle, people) {
          ref.read(rosterProvider).initializeRoster(cycle, people);
        },
      ),
    );
  }
}
