import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers.dart';
import '../models.dart' as models;
import '../services/staff_name_store.dart';
import 'package:roster_champ/safe_text_field.dart';

String _formatLeaveLabel(String? leaveType) {
  if (leaveType == null || leaveType.isEmpty) return 'Leave';
  if (leaveType.startsWith('custom:')) {
    final label = leaveType.substring('custom:'.length).trim();
    return label.isEmpty ? 'Custom Leave' : label;
  }
  switch (leaveType) {
    case 'secondment':
      return 'Secondment';
    case 'sick':
      return 'Sick';
    case 'annual':
      return 'Annual Leave';
    default:
      return 'Leave';
  }
}

String? _extractCustomLeaveLabel(String? leaveType) {
  if (leaveType == null) return null;
  if (!leaveType.startsWith('custom:')) return null;
  return leaveType.substring('custom:'.length).trim();
}

class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  ConsumerState<StaffManagementScreen> createState() =>
      _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  final TextEditingController _addStaffController = TextEditingController();
  final Map<String, TextEditingController> _editControllers = {};
  final Map<String, bool> _isEditing = {};
  final ScrollController _tickSheetScroll = ScrollController();
  int _alSummaryYear = DateTime.now().year;
  String? _timesheetStaffId;
  bool _showSummary = false;
  DateTime _timesheetWeekAnchor = DateTime.now();
  int _timesheetWeekEndDay = DateTime.sunday;
  DateTime? _timesheetWeekEndDate;

  @override
  void dispose() {
    _addStaffController.dispose();
    for (final controller in _editControllers.values) {
      controller.dispose();
    }
    _tickSheetScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final staff = roster.staffMembers;
    final activeCount =
        staff.where((s) => roster.isStaffActiveOnDate(s, DateTime.now())).length;
    final inactiveCount = staff.length - activeCount;
    ref.watch(staffNameProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Staff Management'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Staff'),
              Tab(text: 'Tick Sheet'),
              Tab(text: 'Timesheet'),
              Tab(text: 'AL Summary'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddStaffDialog,
              tooltip: 'Add Staff Member',
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildStaffTab(
              context,
              roster,
              staff,
              activeCount,
              inactiveCount,
            ),
            _buildTickSheetTab(context, roster, staff),
            _buildTimesheetTab(context, roster, staff),
            _buildAlSummaryTab(context, roster, staff),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddStaffDialog,
          icon: const Icon(Icons.person_add),
          label: const Text('Add Staff'),
        ),
      ),
    );
  }

  Widget _buildStaffTab(
    BuildContext context,
    RosterNotifier roster,
    List<models.StaffMember> staff,
    int activeCount,
    int inactiveCount,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              _buildSummaryCard(
                context,
                'Total Staff',
                '${staff.length}',
                Icons.people,
                Colors.blue,
              ),
              const SizedBox(width: 12),
              _buildSummaryCard(
                context,
                'Active',
                '$activeCount',
                Icons.check_circle,
                Colors.green,
              ),
              const SizedBox(width: 12),
              _buildSummaryCard(
                context,
                'Inactive',
                '$inactiveCount',
                Icons.person_off,
                Colors.orange,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: staff.length,
            itemBuilder: (context, index) {
              final member = staff[index];
              _editControllers[member.id] ??=
                  TextEditingController(text: member.name);
              _isEditing[member.id] ??= false;

              return _StaffCard(
                staffMember: member,
                editController: _editControllers[member.id]!,
                isEditing: _isEditing[member.id]!,
                onEditStart: () => _startEditing(member.id),
                onEditCancel: () => _cancelEditing(member.id),
                onUpdate: (newName) => _updateStaffName(member.id, newName),
                onToggleStatus: () => _toggleStaffStatus(member.id),
                onDelete: () => _deleteStaff(member.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTickSheetTab(
    BuildContext context,
    RosterNotifier roster,
    List<models.StaffMember> staff,
  ) {
    final today = DateTime.now();
    final theme = Theme.of(context);
    final todayKey = DateTime(today.year, today.month, today.day);
    final start = todayKey.subtract(const Duration(days: 3));
    final days = List.generate(7, (i) => start.add(Duration(days: i)));
    final nameColumnWidth = 170.0;
    final cellWidth = 110.0;
    final gridWidth = nameColumnWidth + (cellWidth * days.length);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Tick Sheet - ${DateFormat('EEE, MMM d').format(todayKey)}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (roster.readOnly)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'View only',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Confirm who actually worked each shift. Tap a shift box to record status or overtime.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _tickSheetScroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _tickSheetScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: gridWidth,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildTickSheetHeader(
                        context,
                        days,
                        nameColumnWidth,
                        cellWidth,
                        todayKey,
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final member = staff[index];
                          return _buildTickSheetRow(
                            context,
                            roster,
                            member,
                            days,
                            nameColumnWidth,
                            cellWidth,
                            todayKey,
                          );
                        },
                        childCount: staff.length,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTickSheetHeader(
    BuildContext context,
    List<DateTime> days,
    double nameColumnWidth,
    double cellWidth,
    DateTime todayKey,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
      child: Row(
        children: [
          SizedBox(
            width: nameColumnWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                'Staff',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          ...days.map((date) {
            final isToday = date == todayKey;
            return SizedBox(
              width: cellWidth,
              child: Column(
                children: [
                  Text(
                    DateFormat('EEE').format(date),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isToday
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight:
                          isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('d MMM').format(date),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isToday
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTickSheetRow(
    BuildContext context,
    RosterNotifier roster,
    models.StaffMember member,
    List<DateTime> days,
    double nameColumnWidth,
    double cellWidth,
    DateTime todayKey,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withOpacity(0.4)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: nameColumnWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Text(
                member.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          ...days.map((date) {
            final shift = roster.getShiftForDate(member.name, date);
            final isWorking =
                shift.isNotEmpty &&
                    shift != 'OFF' &&
                    shift != 'AL' &&
                    shift != 'TOIL';
            final entry = roster.getTickSheetEntry(member.id, date);
            final overtime = entry?.overtimeHours ?? 0;
            final hasOvertime = overtime > 0;
            final statusLabel = _tickStatusLabel(entry?.status);
            final statusColor =
                _tickStatusColor(theme, entry?.status, isWorking || hasOvertime);
            final isToday = date == todayKey;
            final background = isToday
                ? theme.colorScheme.primary.withOpacity(0.08)
                : theme.colorScheme.surface;
            final cellBorder = Border.all(
              color: isWorking
                  ? theme.colorScheme.primary.withOpacity(0.25)
                  : theme.dividerColor.withOpacity(0.4),
            );

            return SizedBox(
              width: cellWidth,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Material(
                  color: background,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _showTickSheetDialog(
                          member,
                          date,
                          shift,
                          entry,
                          roster.readOnly,
                        ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: cellBorder,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            shift.isEmpty ? '-' : shift,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isWorking
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isWorking ? statusLabel : 'Rest',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusColor,
                            ),
                          ),
                          if (overtime > 0) ...[
                            const SizedBox(height: 2),
                            Text(
                              '+${overtime.toStringAsFixed(1)}h OT',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _tickStatusLabel(String? status) {
    switch (status) {
      case 'confirmed':
        return 'Booked on';
      case 'sick':
        return 'Sick';
      case 'absent':
        return 'Absent';
      case 'emergency':
        return 'Emergency';
      case 'overtime':
        return 'Overtime';
      case 'other':
        return 'Other';
      default:
        return 'Pending';
    }
  }

  Color _tickStatusColor(ThemeData theme, String? status, bool isWorking) {
    if (!isWorking) {
      return theme.colorScheme.onSurfaceVariant;
    }
    switch (status) {
      case 'confirmed':
        return Colors.green;
      case 'sick':
        return Colors.orange;
      case 'absent':
        return Colors.redAccent;
      case 'emergency':
        return Colors.deepPurple;
      case 'overtime':
        return Colors.blueAccent;
      case 'other':
        return theme.colorScheme.primary;
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  Future<void> _showTickSheetDialog(
    models.StaffMember member,
    DateTime date,
    String shift,
    models.TickSheetEntry? entry,
    bool readOnly,
  ) async {
    if (readOnly) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Read-only access. Tick sheet updates disabled.'),
          ),
        );
      }
      return;
    }

    final roster = ref.read(rosterProvider);
    final controller = TextEditingController(text: entry?.comment ?? '');
    final overtimeHoursController = TextEditingController(
      text: entry?.overtimeHours?.toStringAsFixed(1) ?? '',
    );
    final overtimeJobController =
        TextEditingController(text: entry?.overtimeJobNumber ?? '');
    final overtimeLocationController =
        TextEditingController(text: entry?.overtimeLocation ?? '');
    final overtimeReasonController =
        TextEditingController(text: entry?.overtimeReason ?? '');
    String selected = entry?.status ?? 'confirmed';
    bool hasOvertime = (entry?.overtimeHours ?? 0) > 0;
    final settings = roster.appSettings;
    bool convertToToil = entry?.convertToToil ??
        (settings.toilEnabled && settings.toilAutoConvertOvertime);
    if (!hasOvertime && (shift == 'OFF' || shift == 'AL' || shift.isEmpty)) {
      selected = entry?.status ?? 'overtime';
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            '${member.name} - ${DateFormat('EEE, MMM d').format(date)}',
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shift: $shift'),
                const SizedBox(height: 12),
                ...[
                  'confirmed',
                  'sick',
                  'absent',
                  'emergency',
                  'overtime',
                  'other',
                ].map(
                  (status) => RadioListTile<String>(
                    value: status,
                    groupValue: selected,
                    title: Text(_tickStatusLabel(status)),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selected = value);
                    },
                    dense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Comment',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: hasOvertime,
                  title: const Text('Overtime'),
                  subtitle: const Text('Log overtime hours for this day'),
                  onChanged: (value) {
                    setState(() => hasOvertime = value);
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                if (hasOvertime) ...[
                  const SizedBox(height: 6),
                  TextField(
                    controller: overtimeHoursController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Overtime hours',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. 2.5',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: overtimeJobController,
                    decoration: const InputDecoration(
                      labelText: 'Job number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: overtimeLocationController,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: overtimeReasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (settings.toilEnabled) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: convertToToil,
                      title: const Text('Convert to TOIL'),
                      subtitle: Text(
                        'Apply ${settings.toilMultiplier.toStringAsFixed(2)}x multiplier',
                      ),
                      onChanged: (value) {
                        setState(() => convertToToil = value);
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            if (entry != null)
              TextButton(
                onPressed: () {
                  roster.clearTickSheetEntry(staffId: member.id, date: date);
                  Navigator.pop(context, true);
                },
                child: const Text('Clear'),
              ),
            FilledButton(
              onPressed: () {
                final hoursValue = hasOvertime
                    ? double.tryParse(overtimeHoursController.text.trim())
                    : null;
                roster.updateTickSheetEntry(
                  staffId: member.id,
                  date: date,
                  status: selected,
                  comment: controller.text.trim().isEmpty
                      ? null
                      : controller.text.trim(),
                  overtimeHours:
                      (hoursValue != null && hoursValue > 0) ? hoursValue : null,
                  overtimeJobNumber: overtimeJobController.text.trim().isEmpty
                      ? null
                      : overtimeJobController.text.trim(),
                  overtimeLocation:
                      overtimeLocationController.text.trim().isEmpty
                          ? null
                          : overtimeLocationController.text.trim(),
                  overtimeReason: overtimeReasonController.text.trim().isEmpty
                      ? null
                      : overtimeReasonController.text.trim(),
                  convertToToil: hasOvertime ? convertToToil : false,
                  startTime: entry?.startTime,
                  endTime: entry?.endTime,
                  breakMinutes: entry?.breakMinutes,
                  paidHours: entry?.paidHours,
                  shiftCode: entry?.shiftCode,
                  taxableActivities: entry?.taxableActivities ?? const [],
                  nonTaxableActivities:
                      entry?.nonTaxableActivities ?? const [],
                  overtimeEntries: entry?.overtimeEntries ?? const [],
                  higherGradeEntries:
                      entry?.higherGradeEntries ?? const [],
                  bonusPayments: entry?.bonusPayments ?? const [],
                );
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    overtimeHoursController.dispose();
    overtimeJobController.dispose();
    overtimeLocationController.dispose();
    overtimeReasonController.dispose();
  }

  Widget _buildTimesheetTab(
    BuildContext context,
    RosterNotifier roster,
    List<models.StaffMember> staff,
  ) {
    final theme = Theme.of(context);
    final weekAnchor = DateTime(
      _timesheetWeekAnchor.year,
      _timesheetWeekAnchor.month,
      _timesheetWeekAnchor.day,
    );
    if (_timesheetWeekEndDate == null) {
      final start = _startOfWeek(weekAnchor, roster.weekStartDay);
      _timesheetWeekEndDate = start.add(const Duration(days: 6));
      _timesheetWeekEndDay = _timesheetWeekEndDate!.weekday;
    }
    final weekEnd = DateTime(
      _timesheetWeekEndDate!.year,
      _timesheetWeekEndDate!.month,
      _timesheetWeekEndDate!.day,
    );
    final weekStart = weekEnd.subtract(const Duration(days: 6));
    final weeks = List.generate(
      4,
      (i) => weekStart.subtract(Duration(days: i * 7)),
    ).reversed.toList();
    if (_timesheetStaffId == null && staff.isNotEmpty) {
      _timesheetStaffId = staff.first.id;
    }
    final selected = staff.firstWhere(
      (s) => s.id == _timesheetStaffId,
      orElse: () => staff.isNotEmpty
          ? staff.first
          : models.StaffMember(id: '', name: ''),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: selected.id.isEmpty ? null : selected.id,
                  hint: const Text('Select staff member'),
                  items: staff
                      .map(
                        (member) => DropdownMenuItem(
                          value: member.id,
                          child: Text(member.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _timesheetStaffId = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: weekEnd,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked == null) return;
                  setState(() {
                    _timesheetWeekEndDate = picked;
                    _timesheetWeekEndDay = picked.weekday;
                    _timesheetWeekAnchor = picked;
                  });
                },
                icon: const Icon(Icons.event),
                label: Text(
                  'Week ending ${DateFormat('MMM d, yyyy').format(weekEnd)}',
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _timesheetWeekEndDay,
                items: const [
                  DropdownMenuItem(value: DateTime.monday, child: Text('Ends Mon')),
                  DropdownMenuItem(value: DateTime.tuesday, child: Text('Ends Tue')),
                  DropdownMenuItem(value: DateTime.wednesday, child: Text('Ends Wed')),
                  DropdownMenuItem(value: DateTime.thursday, child: Text('Ends Thu')),
                  DropdownMenuItem(value: DateTime.friday, child: Text('Ends Fri')),
                  DropdownMenuItem(value: DateTime.saturday, child: Text('Ends Sat')),
                  DropdownMenuItem(value: DateTime.sunday, child: Text('Ends Sun')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  final offset = (value - weekStart.weekday) % 7;
                  setState(() {
                    _timesheetWeekEndDay = value;
                    _timesheetWeekEndDate = weekStart.add(Duration(days: offset));
                    _timesheetWeekAnchor = _timesheetWeekEndDate!;
                  });
                },
              ),
              const SizedBox(width: 12),
              Tooltip(
                message:
                    _showSummary ? 'Hide summary view' : 'Show summary view',
                child: IconButton(
                  icon: Icon(
                    _showSummary ? Icons.table_rows : Icons.table_rows_outlined,
                  ),
                  onPressed: () {
                    setState(() => _showSummary = !_showSummary);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.name.isEmpty ? 'Timesheet' : selected.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    if (_showSummary) ...[
                      SizedBox(
                        height: 220,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Week')),
                              DataColumn(label: Text('Rostered')),
                              DataColumn(label: Text('Booked on')),
                              DataColumn(label: Text('Sick')),
                              DataColumn(label: Text('Absent')),
                              DataColumn(label: Text('Overtime (hrs)')),
                              DataColumn(label: Text('TOIL (hrs)')),
                            ],
                            rows: weeks.map((start) {
                              final summary =
                                  _summarizeWeek(roster, selected, start);
                              return DataRow(
                                cells: [
                                  DataCell(Text(summary['label'] as String)),
                                  DataCell(Text('${summary['rostered']}')),
                                  DataCell(Text('${summary['confirmed']}')),
                                  DataCell(Text('${summary['sick']}')),
                                  DataCell(Text('${summary['absent']}')),
                                  DataCell(
                                    Text(
                                      (summary['overtime'] as double)
                                          .toStringAsFixed(1),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      (summary['toilHours'] as double)
                                          .toStringAsFixed(1),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildTimesheetDetailHeader(
                      context,
                      roster,
                      selected,
                      weekStart,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: _buildTimesheetDetailTable(
                          context,
                          roster,
                          selected,
                          weekStart,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimesheetDetailHeader(
    BuildContext context,
    RosterNotifier roster,
    models.StaffMember member,
    DateTime weekStart,
  ) {
    final meta = member.metadata ?? {};
    final businessUnit = meta['businessUnit']?.toString() ?? '';
    final employeeNumber = meta['employeeNumber']?.toString() ?? '';
    final grade = meta['grade']?.toString() ?? '';
    final jobTitle = meta['jobTitle']?.toString() ?? '';
    final weekEnd = weekStart.add(const Duration(days: 6));

    return Row(
      children: [
        Expanded(
          child: Text(
            'Week ending ${DateFormat('MMM d').format(weekEnd)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _exportWeeklyTimesheetCsv(
            roster,
            member,
            weekStart,
          ),
          icon: const Icon(Icons.table_view),
          label: const Text('Week CSV'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => _exportWeeklyTimesheetPdf(
            roster,
            member,
            weekStart,
          ),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Week PDF'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => _printWeeklyTimesheet(
            roster,
            member,
            weekStart,
          ),
          icon: const Icon(Icons.print),
          label: const Text('Print'),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Previous week',
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            setState(() {
              _timesheetWeekEndDate = weekEnd.subtract(const Duration(days: 7));
              _timesheetWeekAnchor = _timesheetWeekEndDate!;
            });
          },
        ),
        IconButton(
          tooltip: 'Next week',
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            setState(() {
              _timesheetWeekEndDate = weekEnd.add(const Duration(days: 7));
              _timesheetWeekAnchor = _timesheetWeekEndDate!;
            });
          },
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => _editTimesheetMetadata(member),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit profile fields'),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (businessUnit.isNotEmpty) _metaChip('Unit', businessUnit),
              if (employeeNumber.isNotEmpty)
                _metaChip('Employee #', employeeNumber),
              if (grade.isNotEmpty) _metaChip('Grade', grade),
              if (jobTitle.isNotEmpty) _metaChip('Job', jobTitle),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metaChip(String label, String value) {
    return Chip(
      label: Text('$label: $value'),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildTimesheetDetailTable(
    BuildContext context,
    RosterNotifier roster,
    models.StaffMember member,
    DateTime weekStart,
  ) {
    final settings = roster.appSettings;
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final dayData = days.map((date) {
      final shift = roster.getShiftForDate(member.name, date);
      final entry = roster.getTickSheetEntry(member.id, date);
      final activities = entry?.taxableActivities ?? const [];
      final nonTaxable = entry?.nonTaxableActivities ?? const [];
      final activityHours = _sumActivityHours(activities);
      final nonTaxableHours = _sumNonTaxableHours(nonTaxable);
      final overtimeHours =
          _sumOvertimeHours(entry?.overtimeEntries ?? const []);
      final higherGradeHours =
          _sumHigherGradeHours(entry?.higherGradeEntries ?? const []);
      final bonusHours = _sumBonusHours(entry?.bonusPayments ?? const []);
      final shiftCode = entry?.shiftCode ?? shift;
      final defaultStart = settings.shiftStartTimes[shiftCode] ?? '';
      final defaultEnd = settings.shiftEndTimes[shiftCode] ?? '';
      final defaultBreak = settings.shiftBreakMinutes[shiftCode] ?? 0;
      final startTime = entry?.startTime ?? defaultStart;
      final endTime = entry?.endTime ?? defaultEnd;
      final breakMinutes = entry?.breakMinutes ?? defaultBreak;
      final paidHours = entry?.paidHours ??
          _calculatePaidHours(startTime, endTime, breakMinutes);
      final totalHours = activityHours > 0 ? activityHours : paidHours;
      final discrepancy = (totalHours + nonTaxableHours) - paidHours;
      return {
        'date': date,
        'entry': entry,
        'shiftCode': shiftCode,
        'startTime': startTime,
        'endTime': endTime,
        'breakMinutes': breakMinutes,
        'paidHours': paidHours,
        'totalHours': totalHours,
        'nonTaxableHours': nonTaxableHours,
        'overtimeHours': overtimeHours,
        'higherGradeHours': higherGradeHours,
        'bonusHours': bonusHours,
        'discrepancy': discrepancy,
      };
    }).toList();

    final columns = <DataColumn>[
      const DataColumn(label: Text('Details')),
      ...dayData.map(
        (d) => DataColumn(
          label: Text(DateFormat('EEE dd').format(d['date'] as DateTime)),
        ),
      ),
      const DataColumn(label: Text('Total')),
    ];

    DataRow buildRow(
      String label,
      List<Widget> cells,
      Widget totalCell,
    ) {
      return DataRow(
        cells: [
          DataCell(Text(label)),
          ...cells.map((widget) => DataCell(widget)),
          DataCell(totalCell),
        ],
      );
    }

    List<Widget> mapCells(Widget Function(Map<String, dynamic>) builder) {
      return dayData.map((d) => builder(d)).toList();
    }

    final paidTotal = dayData.fold<double>(
      0,
      (sum, d) => sum + (d['paidHours'] as double),
    );
    final taxableTotal = dayData.fold<double>(
      0,
      (sum, d) => sum + (d['totalHours'] as double),
    );
    final nonTaxableTotal = dayData.fold<double>(
      0,
      (sum, d) => sum + (d['nonTaxableHours'] as double),
    );
    final overtimeTotal = dayData.fold<double>(
      0,
      (sum, d) => sum + (d['overtimeHours'] as double),
    );
    final higherTotal = dayData.fold<double>(
      0,
      (sum, d) => sum + (d['higherGradeHours'] as double),
    );
    final bonusTotal = dayData.fold<double>(
      0,
      (sum, d) => sum + (d['bonusHours'] as double),
    );
    final combinedTotal = taxableTotal + nonTaxableTotal;
    final deltaTotal = combinedTotal - paidTotal;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: columns,
        rows: [
          buildRow(
            'Shift',
            mapCells(
              (d) => Text(
                (d['shiftCode'] as String).isEmpty
                    ? '-'
                    : d['shiftCode'] as String,
              ),
            ),
            const Text('-'),
          ),
          buildRow(
            'Start',
            mapCells(
              (d) => SizedBox(
                width: 90,
                child: TextFormField(
                  initialValue: d['startTime'] as String,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'HH:MM',
                  ),
                  onFieldSubmitted: (value) {
                    _updateTimesheetEntry(
                      roster,
                      member,
                      d['date'] as DateTime,
                      d['shiftCode'] as String,
                      value,
                      d['endTime'] as String,
                      d['breakMinutes'] as int,
                    );
                  },
                ),
              ),
            ),
            const Text('-'),
          ),
          buildRow(
            'End',
            mapCells(
              (d) => SizedBox(
                width: 90,
                child: TextFormField(
                  initialValue: d['endTime'] as String,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'HH:MM',
                  ),
                  onFieldSubmitted: (value) {
                    _updateTimesheetEntry(
                      roster,
                      member,
                      d['date'] as DateTime,
                      d['shiftCode'] as String,
                      d['startTime'] as String,
                      value,
                      d['breakMinutes'] as int,
                    );
                  },
                ),
              ),
            ),
            const Text('-'),
          ),
          buildRow(
            'Break (min)',
            mapCells(
              (d) => SizedBox(
                width: 80,
                child: TextFormField(
                  initialValue: (d['breakMinutes'] as int).toString(),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (value) {
                    final parsed =
                        int.tryParse(value) ?? (d['breakMinutes'] as int);
                    _updateTimesheetEntry(
                      roster,
                      member,
                      d['date'] as DateTime,
                      d['shiftCode'] as String,
                      d['startTime'] as String,
                      d['endTime'] as String,
                      parsed,
                    );
                  },
                ),
              ),
            ),
            const Text('-'),
          ),
          buildRow(
            'Paid hrs',
            mapCells(
              (d) => Text((d['paidHours'] as double).toStringAsFixed(2)),
            ),
            Text(paidTotal.toStringAsFixed(2)),
          ),
          buildRow(
            'Taxable hrs',
            mapCells(
              (d) => Row(
                children: [
                  Text((d['totalHours'] as double).toStringAsFixed(2)),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Edit activities',
                    icon: const Icon(Icons.playlist_add),
                    onPressed: () => _editTaxableActivities(
                      roster,
                      member,
                      d['date'] as DateTime,
                      d['entry'] as models.TickSheetEntry?,
                      d['paidHours'] as double,
                    ),
                  ),
                ],
              ),
            ),
            Text(taxableTotal.toStringAsFixed(2)),
          ),
          buildRow(
            'Non-taxable hrs',
            mapCells(
              (d) => Row(
                children: [
                  Text((d['nonTaxableHours'] as double).toStringAsFixed(2)),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Edit non-taxable activities',
                    icon: const Icon(Icons.playlist_add_check),
                    onPressed: () => _editNonTaxableActivities(
                      roster,
                      member,
                      d['date'] as DateTime,
                      d['entry'] as models.TickSheetEntry?,
                    ),
                  ),
                ],
              ),
            ),
            Text(nonTaxableTotal.toStringAsFixed(2)),
          ),
          buildRow(
            'Overtime',
            mapCells(
              (d) => Row(
                children: [
                  Text((d['overtimeHours'] as double).toStringAsFixed(2)),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Edit overtime',
                    icon: const Icon(Icons.timelapse),
                    onPressed: () => _editOvertimeEntries(
                      roster,
                      member,
                      d['date'] as DateTime,
                      d['entry'] as models.TickSheetEntry?,
                      d['paidHours'] as double,
                    ),
                  ),
                ],
              ),
            ),
            Text(overtimeTotal.toStringAsFixed(2)),
          ),
          buildRow(
            'Higher grade',
            mapCells(
              (d) => Row(
                children: [
                  Text((d['higherGradeHours'] as double).toStringAsFixed(2)),
                  const SizedBox(width: 6),
                  if ((d['higherGradeHours'] as double) > 0 &&
                      (member.metadata?['grade']?.toString().isNotEmpty ??
                          false))
                    Icon(
                      Icons.flag_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Edit higher grade',
                    icon: const Icon(Icons.workspace_premium),
                    onPressed: () => _editHigherGradeEntries(
                      roster,
                      member,
                      d['date'] as DateTime,
                      d['entry'] as models.TickSheetEntry?,
                    ),
                  ),
                ],
              ),
            ),
            Text(higherTotal.toStringAsFixed(2)),
          ),
          buildRow(
            'Bonus',
            mapCells(
              (d) => Row(
                children: [
                  Text((d['bonusHours'] as double).toStringAsFixed(2)),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Edit bonus payments',
                    icon: const Icon(Icons.card_giftcard),
                    onPressed: () => _editBonusPayments(
                      roster,
                      member,
                      d['date'] as DateTime,
                      d['entry'] as models.TickSheetEntry?,
                    ),
                  ),
                ],
              ),
            ),
            Text(bonusTotal.toStringAsFixed(2)),
          ),
          buildRow(
            'Status',
            mapCells(
              (d) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((d['entry'] as models.TickSheetEntry?)?.status ?? '-'),
                  if ((d['discrepancy'] as double).abs() > 0.01)
                    Text(
                      'Delta ${(d['discrepancy'] as double).toStringAsFixed(2)}h',
                      style: TextStyle(
                        color: (d['discrepancy'] as double).abs() > 0.5
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Combined ${combinedTotal.toStringAsFixed(2)}h',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (deltaTotal.abs() > 0.01)
                  Text(
                    'Delta ${deltaTotal.toStringAsFixed(2)}h',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  double _calculatePaidHours(
    String startTime,
    String endTime,
    int breakMinutes,
  ) {
    final start = _parseTime(startTime);
    final end = _parseTime(endTime);
    if (start == null || end == null) return 0;
    var diff = end.difference(start);
    if (diff.isNegative) {
      diff = diff + const Duration(hours: 24);
    }
    final totalMinutes = diff.inMinutes - breakMinutes;
    return (totalMinutes <= 0 ? 0 : totalMinutes / 60.0);
  }

  DateTime? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return DateTime(2000, 1, 1, h, m);
  }

  void _updateTimesheetEntry(
    RosterNotifier roster,
    models.StaffMember member,
    DateTime date,
    String shiftCode,
    String startTime,
    String endTime,
    int breakMinutes,
  ) {
    final paidHours = _calculatePaidHours(startTime, endTime, breakMinutes);
    final existing = roster.getTickSheetEntry(member.id, date);
    roster.updateTickSheetEntry(
      staffId: member.id,
      date: date,
      status: existing?.status ?? 'confirmed',
      comment: existing?.comment,
      overtimeHours: existing?.overtimeHours,
      overtimeJobNumber: existing?.overtimeJobNumber,
      overtimeLocation: existing?.overtimeLocation,
      overtimeReason: existing?.overtimeReason,
      convertToToil: existing?.convertToToil ?? false,
      startTime: startTime.trim(),
      endTime: endTime.trim(),
      breakMinutes: breakMinutes,
      paidHours: paidHours,
      shiftCode: shiftCode,
      taxableActivities: existing?.taxableActivities ?? const [],
      nonTaxableActivities: existing?.nonTaxableActivities ?? const [],
      overtimeEntries: existing?.overtimeEntries ?? const [],
      higherGradeEntries: existing?.higherGradeEntries ?? const [],
      bonusPayments: existing?.bonusPayments ?? const [],
    );

    final settingsNotifier = ref.read(settingsProvider.notifier);
    final settings = ref.read(settingsProvider);
    final normalizedShift = shiftCode.trim().toUpperCase();
    if (normalizedShift.isNotEmpty &&
        normalizedShift != 'OFF' &&
        normalizedShift != 'AL' &&
        normalizedShift != 'TOIL') {
      final updatedStartTimes = Map<String, String>.from(settings.shiftStartTimes)
        ..[normalizedShift] = startTime.trim();
      final updatedEndTimes = Map<String, String>.from(settings.shiftEndTimes)
        ..[normalizedShift] = endTime.trim();
      final updatedBreaks =
          Map<String, int>.from(settings.shiftBreakMinutes)
            ..[normalizedShift] = breakMinutes;
      settingsNotifier.updateSettings(
        settings.copyWith(
          shiftStartTimes: updatedStartTimes,
          shiftEndTimes: updatedEndTimes,
          shiftBreakMinutes: updatedBreaks,
        ),
      );
    }
  }

  double _sumActivityHours(List<models.TaxableActivity> activities) {
    return activities.fold<double>(0, (sum, a) => sum + a.hours);
  }

  double _sumNonTaxableHours(List<models.NonTaxableActivity> activities) {
    return activities.fold<double>(0, (sum, a) => sum + a.hours);
  }

  double _sumOvertimeHours(List<models.OvertimeEntry> entries) {
    return entries.fold<double>(0, (sum, e) => sum + e.hours);
  }

  double _sumHigherGradeHours(List<models.HigherGradeEntry> entries) {
    return entries.fold<double>(0, (sum, e) => sum + e.hours);
  }

  double _sumBonusHours(List<models.BonusPaymentEntry> entries) {
    return entries.fold<double>(0, (sum, e) => sum + e.hours);
  }

  List<Map<String, dynamic>> _buildWeeklyDetailRows(
    RosterNotifier roster,
    models.StaffMember member,
    DateTime weekStart,
  ) {
    final settings = roster.appSettings;
    final rows = <Map<String, dynamic>>[];
    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final shift = roster.getShiftForDate(member.name, date);
      final entry = roster.getTickSheetEntry(member.id, date);
      final activities = entry?.taxableActivities ?? const [];
      final nonTaxable = entry?.nonTaxableActivities ?? const [];
      final activityHours = _sumActivityHours(activities);
      final nonTaxableHours = _sumNonTaxableHours(nonTaxable);
      final overtimeHours =
          _sumOvertimeHours(entry?.overtimeEntries ?? const []);
      final higherGradeHours =
          _sumHigherGradeHours(entry?.higherGradeEntries ?? const []);
      final bonusHours = _sumBonusHours(entry?.bonusPayments ?? const []);
      final shiftCode = entry?.shiftCode ?? shift;
      final defaultStart = settings.shiftStartTimes[shiftCode] ?? '';
      final defaultEnd = settings.shiftEndTimes[shiftCode] ?? '';
      final defaultBreak = settings.shiftBreakMinutes[shiftCode] ?? 0;
      final startTime = entry?.startTime ?? defaultStart;
      final endTime = entry?.endTime ?? defaultEnd;
      final breakMinutes = entry?.breakMinutes ?? defaultBreak;
      final paidHours = entry?.paidHours ??
          _calculatePaidHours(startTime, endTime, breakMinutes);
      final totalHours = activityHours > 0 ? activityHours : paidHours;
      final discrepancy = (totalHours + nonTaxableHours) - paidHours;

      rows.add({
        'date': date,
        'shift': shiftCode,
        'start': startTime,
        'end': endTime,
        'break': breakMinutes,
        'paid': paidHours,
        'taxable': totalHours,
        'nonTaxable': nonTaxableHours,
        'overtime': overtimeHours,
        'higherGrade': higherGradeHours,
        'bonus': bonusHours,
        'status': entry?.status ?? '-',
        'discrepancy': discrepancy,
      });
    }
    return rows;
  }

  Future<void> _exportWeeklyTimesheetCsv(
    RosterNotifier roster,
    models.StaffMember member,
    DateTime weekStart,
  ) async {
    final rows = <List<String>>[];
    rows.add([
      'Day',
      'Shift',
      'Start',
      'End',
      'Break',
      'Paid',
      'Taxable',
      'NonTaxable',
      'Overtime',
      'HigherGrade',
      'Bonus',
      'Status',
      'Discrepancy',
    ]);
    final detailRows = _buildWeeklyDetailRows(roster, member, weekStart);
    double totalPaid = 0;
    double totalTaxable = 0;
    double totalNonTaxable = 0;
    double totalOvertime = 0;
    double totalHigherGrade = 0;
    double totalBonus = 0;
    double totalCombined = 0;

    for (final row in detailRows) {
      final paid = row['paid'] as double;
      final taxable = row['taxable'] as double;
      final nonTaxable = row['nonTaxable'] as double;
      final overtime = row['overtime'] as double;
      final higher = row['higherGrade'] as double;
      final bonus = row['bonus'] as double;
      final discrepancy = row['discrepancy'] as double;
      rows.add([
        DateFormat('EEE dd').format(row['date'] as DateTime),
        row['shift'].toString(),
        row['start'].toString(),
        row['end'].toString(),
        row['break'].toString(),
        paid.toStringAsFixed(2),
        taxable.toStringAsFixed(2),
        nonTaxable.toStringAsFixed(2),
        overtime.toStringAsFixed(2),
        higher.toStringAsFixed(2),
        bonus.toStringAsFixed(2),
        row['status'].toString(),
        discrepancy.toStringAsFixed(2),
      ]);
      totalPaid += paid;
      totalTaxable += taxable;
      totalNonTaxable += nonTaxable;
      totalOvertime += overtime;
      totalHigherGrade += higher;
      totalBonus += bonus;
      totalCombined += taxable + nonTaxable;
    }

    rows.add([
      'Total',
      '',
      '',
      '',
      '',
      totalPaid.toStringAsFixed(2),
      totalTaxable.toStringAsFixed(2),
      totalNonTaxable.toStringAsFixed(2),
      totalOvertime.toStringAsFixed(2),
      totalHigherGrade.toStringAsFixed(2),
      totalBonus.toStringAsFixed(2),
      'Combined',
      totalCombined.toStringAsFixed(2),
    ]);

    final csv = rows.map((row) => row.join(',')).join('\n');
    final fileName =
        'timesheet_week_${member.name}_${DateFormat('yyyyMMdd').format(weekStart)}.csv';
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Weekly Timesheet CSV',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (outputFile == null) return;
    if (!outputFile.endsWith('.csv')) {
      outputFile = '$outputFile.csv';
    }
    final file = File(outputFile);
    await file.writeAsString(csv);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV exported to: ${file.path}')),
      );
    }
  }

  Future<void> _exportWeeklyTimesheetPdf(
    RosterNotifier roster,
    models.StaffMember member,
    DateTime weekStart,
  ) async {
    final doc = pw.Document();
    final detailRows = _buildWeeklyDetailRows(roster, member, weekStart);
    final headers = [
      'Day',
      'Shift',
      'Start',
      'End',
      'Break',
      'Paid',
      'Taxable',
      'NonTaxable',
      'Overtime',
      'HigherGrade',
      'Bonus',
      'Status',
      'Δ',
    ];
    final data = detailRows.map((row) {
      return [
        DateFormat('EEE dd').format(row['date'] as DateTime),
        row['shift'].toString(),
        row['start'].toString(),
        row['end'].toString(),
        row['break'].toString(),
        (row['paid'] as double).toStringAsFixed(2),
        (row['taxable'] as double).toStringAsFixed(2),
        (row['nonTaxable'] as double).toStringAsFixed(2),
        (row['overtime'] as double).toStringAsFixed(2),
        (row['higherGrade'] as double).toStringAsFixed(2),
        (row['bonus'] as double).toStringAsFixed(2),
        row['status'].toString(),
        (row['discrepancy'] as double).toStringAsFixed(2),
      ];
    }).toList();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Weekly Timesheet - ${member.name}',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Week ${DateFormat('MMM d').format(weekStart)} - ${DateFormat('MMM d').format(weekStart.add(const Duration(days: 6)))}',
            ),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headers: headers,
              data: data,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 3,
              ),
            ),
          ],
        ),
      ),
    );

    final fileName =
        'timesheet_week_${member.name}_${DateFormat('yyyyMMdd').format(weekStart)}.pdf';
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Weekly Timesheet PDF',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (outputFile == null) return;
    if (!outputFile.endsWith('.pdf')) {
      outputFile = '$outputFile.pdf';
    }
    final file = File(outputFile);
    await file.writeAsBytes(await doc.save());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF exported to: ${file.path}')),
      );
    }
  }

  Future<void> _printWeeklyTimesheet(
    RosterNotifier roster,
    models.StaffMember member,
    DateTime weekStart,
  ) async {
    final doc = pw.Document();
    final detailRows = _buildWeeklyDetailRows(roster, member, weekStart);
    final headers = [
      'Day',
      'Shift',
      'Start',
      'End',
      'Break',
      'Paid',
      'Taxable',
      'NonTaxable',
      'Overtime',
      'HigherGrade',
      'Bonus',
      'Status',
      'Δ',
    ];
    final data = detailRows.map((row) {
      return [
        DateFormat('EEE dd').format(row['date'] as DateTime),
        row['shift'].toString(),
        row['start'].toString(),
        row['end'].toString(),
        row['break'].toString(),
        (row['paid'] as double).toStringAsFixed(2),
        (row['taxable'] as double).toStringAsFixed(2),
        (row['nonTaxable'] as double).toStringAsFixed(2),
        (row['overtime'] as double).toStringAsFixed(2),
        (row['higherGrade'] as double).toStringAsFixed(2),
        (row['bonus'] as double).toStringAsFixed(2),
        row['status'].toString(),
        (row['discrepancy'] as double).toStringAsFixed(2),
      ];
    }).toList();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Weekly Timesheet - ${member.name}',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Week ${DateFormat('MMM d').format(weekStart)} - ${DateFormat('MMM d').format(weekStart.add(const Duration(days: 6)))}',
            ),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headers: headers,
              data: data,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 3,
              ),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name:
          'Weekly Timesheet - ${member.name} (${DateFormat('yyyyMMdd').format(weekStart)})',
    );
  }

  Future<void> _editTaxableActivities(
    RosterNotifier roster,
    models.StaffMember member,
    DateTime date,
    models.TickSheetEntry? entry,
    double paidHours,
  ) async {
    final activities =
        entry?.taxableActivities.map((a) => a).toList() ?? <models.TaxableActivity>[];
    final codeController = TextEditingController();
    final descController = TextEditingController();
    final hoursController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              'Work activities - ${member.name} (${DateFormat('EEE dd').format(date)})',
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activities.isEmpty)
                    const Text('No activities recorded yet.')
                  else
                    ...activities.asMap().entries.map((entryRow) {
                      final activity = entryRow.value;
                      return ListTile(
                        title: Text('${activity.code} · ${activity.description}'),
                        subtitle: Text('${activity.hours.toStringAsFixed(2)} hrs'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            setState(() => activities.removeAt(entryRow.key));
                          },
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: null,
                    decoration: const InputDecoration(
                      labelText: 'Job / Order code',
                      border: OutlineInputBorder(),
                    ),
                    items: roster.jobCodeLibrary
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.code,
                            child: Text('${item.code} · ${item.description}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final found = roster.jobCodeLibrary.firstWhere(
                        (e) => e.code == value,
                        orElse: () => models.JobCodeEntry(
                          code: value,
                          description: '',
                          createdAt: DateTime.now(),
                        ),
                      );
                      codeController.text = found.code;
                      descController.text = found.description;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hoursController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Hours',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          final hours = double.tryParse(hoursController.text.trim());
                          if (hours == null || hours <= 0) return;
                          final code = codeController.text.trim();
                          if (code.isEmpty) return;
                          final desc = descController.text.trim();
                          setState(() {
                            activities.add(
                              models.TaxableActivity(
                                code: code,
                                description: desc,
                                hours: hours,
                              ),
                            );
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add activity'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          final code = codeController.text.trim();
                          if (code.isEmpty) return;
                          roster.addJobCode(
                            code: code,
                            description: descController.text.trim(),
                          );
                        },
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Save code'),
                      ),
                    ],
                  ),
                  if (roster.jobCodeLibrary.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Manage saved codes',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    ...roster.jobCodeLibrary.map(
                      (item) => ListTile(
                        dense: true,
                        title: Text(item.code),
                        subtitle: item.description.isEmpty
                            ? null
                            : Text(item.description),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            setState(() => roster.removeJobCode(item.code));
                          },
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Total recorded hours: ${_sumActivityHours(activities).toStringAsFixed(2)} (paid hrs ${paidHours.toStringAsFixed(2)})',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () {
                  roster.updateTickSheetEntry(
                    staffId: member.id,
                    date: date,
                    status: entry?.status ?? 'confirmed',
                    comment: entry?.comment,
                    overtimeHours: entry?.overtimeHours,
                    overtimeJobNumber: entry?.overtimeJobNumber,
                    overtimeLocation: entry?.overtimeLocation,
                    overtimeReason: entry?.overtimeReason,
                    convertToToil: entry?.convertToToil ?? false,
                    startTime: entry?.startTime,
                    endTime: entry?.endTime,
                    breakMinutes: entry?.breakMinutes,
                    paidHours: entry?.paidHours,
                    shiftCode: entry?.shiftCode,
                    taxableActivities: activities,
                    nonTaxableActivities:
                        entry?.nonTaxableActivities ?? const [],
                    overtimeEntries: entry?.overtimeEntries ?? const [],
                    higherGradeEntries:
                        entry?.higherGradeEntries ?? const [],
                    bonusPayments: entry?.bonusPayments ?? const [],
                  );
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    codeController.dispose();
    descController.dispose();
    hoursController.dispose();
  }

  Future<void> _editNonTaxableActivities(
    RosterNotifier roster,
    models.StaffMember member,
    DateTime date,
    models.TickSheetEntry? entry,
  ) async {
    final activities =
        entry?.nonTaxableActivities.map((a) => a).toList() ??
            <models.NonTaxableActivity>[];
    final typeController = TextEditingController();
    final codeController = TextEditingController();
    final descController = TextEditingController();
    final hoursController = TextEditingController();
    final types = const [
      'Annual Leave (AL)',
      'Sick Leave',
      'Time Off in Lieu (TOIL)',
      'Paternity Leave',
      'Jury Duty',
      'Moving Home',
      'Trade Union Duties',
      'Training',
      'Management Briefing',
      'Shift Change',
      'Alternative Duties',
    ];

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              'Non-taxable activities - ${member.name} (${DateFormat('EEE dd').format(date)})',
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activities.isEmpty)
                    const Text('No non-taxable activities recorded yet.')
                  else
                    ...activities.asMap().entries.map((entryRow) {
                      final activity = entryRow.value;
                      final label = activity.code?.isNotEmpty == true
                          ? '${activity.type} · ${activity.code}'
                          : activity.type;
                      return ListTile(
                        title: Text(label),
                        subtitle: Text(
                          '${activity.hours.toStringAsFixed(2)} hrs${activity.description?.isNotEmpty == true ? ' · ${activity.description}' : ''}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            setState(() => activities.removeAt(entryRow.key));
                          },
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: null,
                    decoration: const InputDecoration(
                      labelText: 'Activity type',
                      border: OutlineInputBorder(),
                    ),
                    items: types
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      typeController.text = value;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: typeController,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Order / classification code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hoursController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Hours',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          final hours =
                              double.tryParse(hoursController.text.trim());
                          if (hours == null || hours <= 0) return;
                          final type = typeController.text.trim();
                          if (type.isEmpty) return;
                          setState(() {
                            activities.add(
                              models.NonTaxableActivity(
                                type: type,
                                code: codeController.text.trim().isEmpty
                                    ? null
                                    : codeController.text.trim(),
                                description: descController.text.trim().isEmpty
                                    ? null
                                    : descController.text.trim(),
                                hours: hours,
                              ),
                            );
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add activity'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Total non-taxable hours: ${_sumNonTaxableHours(activities).toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () {
                  roster.updateTickSheetEntry(
                    staffId: member.id,
                    date: date,
                    status: entry?.status ?? 'confirmed',
                    comment: entry?.comment,
                    overtimeHours: entry?.overtimeHours,
                    overtimeJobNumber: entry?.overtimeJobNumber,
                    overtimeLocation: entry?.overtimeLocation,
                    overtimeReason: entry?.overtimeReason,
                    convertToToil: entry?.convertToToil ?? false,
                    startTime: entry?.startTime,
                    endTime: entry?.endTime,
                    breakMinutes: entry?.breakMinutes,
                    paidHours: entry?.paidHours,
                    shiftCode: entry?.shiftCode,
                    taxableActivities:
                        entry?.taxableActivities ?? const [],
                    nonTaxableActivities: activities,
                    overtimeEntries: entry?.overtimeEntries ?? const [],
                    higherGradeEntries:
                        entry?.higherGradeEntries ?? const [],
                    bonusPayments: entry?.bonusPayments ?? const [],
                  );
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    typeController.dispose();
    codeController.dispose();
    descController.dispose();
    hoursController.dispose();
  }

  Future<void> _editOvertimeEntries(
    RosterNotifier roster,
    models.StaffMember member,
    DateTime date,
    models.TickSheetEntry? entry,
    double paidHours,
  ) async {
    final entries =
        entry?.overtimeEntries.map((e) => e).toList() ?? <models.OvertimeEntry>[];
    final hoursController = TextEditingController();
    final reasonController = TextEditingController();
    final jobController = TextEditingController();
    final typeController = TextEditingController();
    final types = const ['time-and-a-half', 'double time', 'standard'];

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'Overtime - ${member.name} (${DateFormat('EEE dd').format(date)})',
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entries.isEmpty)
                  const Text('No overtime recorded yet.')
                else
                  ...entries.asMap().entries.map((row) {
                    final item = row.value;
                    return ListTile(
                      title: Text('${item.hours.toStringAsFixed(2)} hrs'),
                      subtitle: Text(
                        [
                          if (item.overtimeType?.isNotEmpty == true)
                            item.overtimeType,
                          if (item.reason?.isNotEmpty == true) item.reason,
                          if (item.jobCode?.isNotEmpty == true)
                            'Job ${item.jobCode}',
                        ].join(' · '),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => entries.removeAt(row.key)),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                TextField(
                  controller: hoursController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Overtime hours',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: jobController,
                  decoration: const InputDecoration(
                    labelText: 'Job / order number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: null,
                  decoration: const InputDecoration(
                    labelText: 'Overtime type',
                    border: OutlineInputBorder(),
                  ),
                  items: types
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    typeController.text = value;
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: typeController,
                  decoration: const InputDecoration(
                    labelText: 'Type (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    final hours = double.tryParse(hoursController.text.trim());
                    if (hours == null || hours <= 0) return;
                    entries.add(
                      models.OvertimeEntry(
                        hours: hours,
                        reason: reasonController.text.trim().isEmpty
                            ? null
                            : reasonController.text.trim(),
                        jobCode: jobController.text.trim().isEmpty
                            ? null
                            : jobController.text.trim(),
                        overtimeType: typeController.text.trim().isEmpty
                            ? null
                            : typeController.text.trim(),
                      ),
                    );
                    setState(() {});
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add overtime'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Total overtime: ${_sumOvertimeHours(entries).toStringAsFixed(2)} hrs (paid hrs ${paidHours.toStringAsFixed(2)})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                roster.updateTickSheetEntry(
                  staffId: member.id,
                  date: date,
                  status: entry?.status ?? 'confirmed',
                  comment: entry?.comment,
                  overtimeHours: entry?.overtimeHours,
                  overtimeJobNumber: entry?.overtimeJobNumber,
                  overtimeLocation: entry?.overtimeLocation,
                  overtimeReason: entry?.overtimeReason,
                  convertToToil: entry?.convertToToil ?? false,
                  startTime: entry?.startTime,
                  endTime: entry?.endTime,
                  breakMinutes: entry?.breakMinutes,
                  paidHours: entry?.paidHours,
                  shiftCode: entry?.shiftCode,
                  taxableActivities: entry?.taxableActivities ?? const [],
                  nonTaxableActivities:
                      entry?.nonTaxableActivities ?? const [],
                  overtimeEntries: entries,
                  higherGradeEntries:
                      entry?.higherGradeEntries ?? const [],
                  bonusPayments: entry?.bonusPayments ?? const [],
                );
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    hoursController.dispose();
    reasonController.dispose();
    jobController.dispose();
    typeController.dispose();
  }

  Future<void> _editHigherGradeEntries(
    RosterNotifier roster,
    models.StaffMember member,
    DateTime date,
    models.TickSheetEntry? entry,
  ) async {
    final entries =
        entry?.higherGradeEntries.map((e) => e).toList() ?? <models.HigherGradeEntry>[];
    final gradeController = TextEditingController();
    final jobController = TextEditingController();
    final hoursController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'Higher grade - ${member.name} (${DateFormat('EEE dd').format(date)})',
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entries.isEmpty)
                  const Text('No higher grade hours recorded.')
                else
                  ...entries.asMap().entries.map((row) {
                    final item = row.value;
                    final label = item.jobCode?.isNotEmpty == true
                        ? '${item.grade} · ${item.jobCode}'
                        : item.grade;
                    return ListTile(
                      title: Text(label),
                      subtitle:
                          Text('${item.hours.toStringAsFixed(2)} hrs'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => entries.removeAt(row.key)),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                TextField(
                  controller: gradeController,
                  decoration: const InputDecoration(
                    labelText: 'Higher grade classification',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: jobController,
                  decoration: const InputDecoration(
                    labelText: 'Job / order number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: hoursController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Hours',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    final hours = double.tryParse(hoursController.text.trim());
                    if (hours == null || hours <= 0) return;
                    final grade = gradeController.text.trim();
                    if (grade.isEmpty) return;
                    entries.add(
                      models.HigherGradeEntry(
                        grade: grade,
                        hours: hours,
                        jobCode: jobController.text.trim().isEmpty
                            ? null
                            : jobController.text.trim(),
                      ),
                    );
                    setState(() {});
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add higher grade'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Total higher grade: ${_sumHigherGradeHours(entries).toStringAsFixed(2)} hrs',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                roster.updateTickSheetEntry(
                  staffId: member.id,
                  date: date,
                  status: entry?.status ?? 'confirmed',
                  comment: entry?.comment,
                  overtimeHours: entry?.overtimeHours,
                  overtimeJobNumber: entry?.overtimeJobNumber,
                  overtimeLocation: entry?.overtimeLocation,
                  overtimeReason: entry?.overtimeReason,
                  convertToToil: entry?.convertToToil ?? false,
                  startTime: entry?.startTime,
                  endTime: entry?.endTime,
                  breakMinutes: entry?.breakMinutes,
                  paidHours: entry?.paidHours,
                  shiftCode: entry?.shiftCode,
                  taxableActivities: entry?.taxableActivities ?? const [],
                  nonTaxableActivities:
                      entry?.nonTaxableActivities ?? const [],
                  overtimeEntries: entry?.overtimeEntries ?? const [],
                  higherGradeEntries: entries,
                  bonusPayments: entry?.bonusPayments ?? const [],
                );
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    gradeController.dispose();
    jobController.dispose();
    hoursController.dispose();
  }

  Future<void> _editBonusPayments(
    RosterNotifier roster,
    models.StaffMember member,
    DateTime date,
    models.TickSheetEntry? entry,
  ) async {
    final entries =
        entry?.bonusPayments.map((e) => e).toList() ?? <models.BonusPaymentEntry>[];
    final descController = TextEditingController();
    final codeController = TextEditingController();
    final jobController = TextEditingController();
    final hoursController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'Bonus payments - ${member.name} (${DateFormat('EEE dd').format(date)})',
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entries.isEmpty)
                  const Text('No bonus payments recorded.')
                else
                  ...entries.asMap().entries.map((row) {
                    final item = row.value;
                    return ListTile(
                      title: Text(item.description),
                      subtitle: Text(
                        '${item.hours.toStringAsFixed(2)} hrs${item.code?.isNotEmpty == true ? ' · ${item.code}' : ''}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => entries.removeAt(row.key)),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: 'Classification code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: jobController,
                  decoration: const InputDecoration(
                    labelText: 'Job / order number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: hoursController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Hours or value',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    final hours = double.tryParse(hoursController.text.trim());
                    if (hours == null || hours <= 0) return;
                    final desc = descController.text.trim();
                    if (desc.isEmpty) return;
                    entries.add(
                      models.BonusPaymentEntry(
                        description: desc,
                        hours: hours,
                        code: codeController.text.trim().isEmpty
                            ? null
                            : codeController.text.trim(),
                        jobCode: jobController.text.trim().isEmpty
                            ? null
                            : jobController.text.trim(),
                      ),
                    );
                    setState(() {});
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add bonus'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Total bonus hours: ${_sumBonusHours(entries).toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                roster.updateTickSheetEntry(
                  staffId: member.id,
                  date: date,
                  status: entry?.status ?? 'confirmed',
                  comment: entry?.comment,
                  overtimeHours: entry?.overtimeHours,
                  overtimeJobNumber: entry?.overtimeJobNumber,
                  overtimeLocation: entry?.overtimeLocation,
                  overtimeReason: entry?.overtimeReason,
                  convertToToil: entry?.convertToToil ?? false,
                  startTime: entry?.startTime,
                  endTime: entry?.endTime,
                  breakMinutes: entry?.breakMinutes,
                  paidHours: entry?.paidHours,
                  shiftCode: entry?.shiftCode,
                  taxableActivities: entry?.taxableActivities ?? const [],
                  nonTaxableActivities:
                      entry?.nonTaxableActivities ?? const [],
                  overtimeEntries: entry?.overtimeEntries ?? const [],
                  higherGradeEntries:
                      entry?.higherGradeEntries ?? const [],
                  bonusPayments: entries,
                );
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    descController.dispose();
    codeController.dispose();
    jobController.dispose();
    hoursController.dispose();
  }

  Future<void> _editTimesheetMetadata(models.StaffMember member) async {
    final meta = member.metadata ?? {};
    final businessUnit =
        TextEditingController(text: meta['businessUnit']?.toString() ?? '');
    final employeeNumber =
        TextEditingController(text: meta['employeeNumber']?.toString() ?? '');
    final grade =
        TextEditingController(text: meta['grade']?.toString() ?? '');
    final jobTitle =
        TextEditingController(text: meta['jobTitle']?.toString() ?? '');

    final roster = ref.read(rosterProvider);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Staff profile - ${member.name}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: businessUnit,
                decoration: const InputDecoration(
                  labelText: 'Business unit',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: employeeNumber,
                decoration: const InputDecoration(
                  labelText: 'Employee number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: grade,
                decoration: const InputDecoration(
                  labelText: 'Grade',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: jobTitle,
                decoration: const InputDecoration(
                  labelText: 'Job title',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final updated = Map<String, dynamic>.from(member.metadata ?? {})
        ..['businessUnit'] = businessUnit.text.trim()
        ..['employeeNumber'] = employeeNumber.text.trim()
        ..['grade'] = grade.text.trim()
        ..['jobTitle'] = jobTitle.text.trim();
      roster.updateStaffMetadata(member.id, updated);
    }

    businessUnit.dispose();
    employeeNumber.dispose();
    grade.dispose();
    jobTitle.dispose();
  }

  DateTime _startOfWeek(DateTime date, int weekStartDay) {
    final normalized = DateTime(date.year, date.month, date.day);
    final target = weekStartDay == 0 ? DateTime.monday : weekStartDay;
    final diff = (normalized.weekday - target) % 7;
    return normalized.subtract(Duration(days: diff));
  }

  bool _isWorkingShiftCode(String shift) {
    final normalized = shift.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    return normalized != 'OFF' && normalized != 'AL' && normalized != 'TOIL';
  }

  Map<String, dynamic> _summarizeWeek(
    RosterNotifier roster,
    models.StaffMember member,
    DateTime weekStart,
  ) {
    int rostered = 0;
    int confirmed = 0;
    int sick = 0;
    int absent = 0;
    double overtime = 0;
    double toilHours = 0;
    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final shift = roster.getShiftForDate(member.name, date);
      final isWorking = _isWorkingShiftCode(shift);
      if (isWorking) rostered += 1;
      final entry = roster.getTickSheetEntry(member.id, date);
      if (entry != null) {
        switch (entry.status) {
          case 'confirmed':
            confirmed += 1;
            break;
          case 'sick':
            sick += 1;
            break;
          case 'absent':
            absent += 1;
            break;
          default:
            break;
        }
        overtime += entry.overtimeHours ?? 0;
        toilHours += entry.toilHours ?? 0;
      }
    }
    final label =
        '${DateFormat('MMM d').format(weekStart)} - ${DateFormat('MMM d').format(weekStart.add(const Duration(days: 6)))}';
    return {
      'label': label,
      'rostered': rostered,
      'confirmed': confirmed,
      'sick': sick,
      'absent': absent,
      'overtime': overtime,
      'toilHours': toilHours,
    };
  }

  Widget _buildAlSummaryTab(
    BuildContext context,
    RosterNotifier roster,
    List<models.StaffMember> staff,
  ) {
    final theme = Theme.of(context);
    final yearOptions = List.generate(5, (i) => DateTime.now().year - 2 + i);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Annual Leave Summary',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              DropdownButton<int>(
                value: _alSummaryYear,
                items: yearOptions
                    .map(
                      (year) => DropdownMenuItem(
                        value: year,
                        child: Text(year.toString()),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _alSummaryYear = value);
                },
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _exportAlSummaryCsv(staff),
                icon: const Icon(Icons.table_view),
                label: const Text('CSV'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _exportAlSummaryPdf(staff),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Snapshot of leave allowances and scheduled leave for current staff.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Personnel')),
                  DataColumn(label: Text('Rolled over')),
                  DataColumn(label: Text('Entitlement')),
                  DataColumn(label: Text('Total allowance')),
                  DataColumn(label: Text('Outstanding leave')),
                  DataColumn(label: Text('Pending leave')),
                  DataColumn(label: Text('Leave balance')),
                  DataColumn(label: Text('Forecast balance')),
                  DataColumn(label: Text('Edit')),
                ],
                rows: staff.map((member) {
                  final rolledOver =
                      _leaveRolledOver(member, year: _alSummaryYear, roster: roster);
                  final entitlement =
                      _leaveEntitlement(member, year: _alSummaryYear);
                  final totalAllowance = rolledOver + entitlement;
                  final outstanding =
                      _scheduledLeaveDays(member, year: _alSummaryYear, roster: roster);
                  final pending =
                      _pendingLeaveDays(member, year: _alSummaryYear, roster: roster);
                  final forecast =
                      _forecastLeaveBalance(member, year: _alSummaryYear, roster: roster);
                  return DataRow(
                    cells: [
                      DataCell(Text(member.name)),
                      DataCell(Text(rolledOver.toStringAsFixed(1))),
                      DataCell(Text(entitlement.toStringAsFixed(1))),
                      DataCell(Text(totalAllowance.toStringAsFixed(1))),
                      DataCell(Text(outstanding.toStringAsFixed(1))),
                      DataCell(Text(pending.toStringAsFixed(1))),
                      DataCell(Text(member.leaveBalance.toStringAsFixed(1))),
                      DataCell(
                        Row(
                          children: [
                            Text(
                              forecast.toStringAsFixed(1),
                              style: TextStyle(
                                color: forecast < 0
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (forecast < 0) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: theme.colorScheme.error,
                              ),
                            ],
                          ],
                        ),
                      ),
                      DataCell(
                        IconButton(
                          tooltip: 'Edit annual leave',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editLeaveSummary(member),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editLeaveSummary(models.StaffMember member) async {
    final roster = ref.read(rosterProvider);
    final rolledController = TextEditingController(
      text: _leaveRolledOver(
        member,
        year: _alSummaryYear,
        roster: roster,
      ).toStringAsFixed(1),
    );
    final entitlementController = TextEditingController(
      text: _leaveEntitlement(member, year: _alSummaryYear).toStringAsFixed(1),
    );
    final capController = TextEditingController(
      text: _leaveCarryoverCap(member).toStringAsFixed(1),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Annual leave - ${member.name}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: rolledController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Rolled over (days)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: entitlementController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Entitlement (days)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: capController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Carryover cap (days)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final rolled = double.tryParse(rolledController.text.trim());
      final entitlement = double.tryParse(entitlementController.text.trim());
      final cap = double.tryParse(capController.text.trim());
      final meta = Map<String, dynamic>.from(member.metadata ?? {});
      final rolledMap =
          Map<String, dynamic>.from(meta['leaveRolledOverByYear'] as Map? ?? {});
      final entitlementMap = Map<String, dynamic>.from(
        meta['leaveEntitlementByYear'] as Map? ?? {},
      );
      if (rolled != null) {
        rolledMap[_alSummaryYear.toString()] = rolled;
      }
      if (entitlement != null) {
        entitlementMap[_alSummaryYear.toString()] = entitlement;
      }
      roster.updateStaffMetadata(
        member.id,
        {
          'leaveRolledOverByYear': rolledMap,
          'leaveEntitlementByYear': entitlementMap,
          'leaveRolledOver': rolled,
          'leaveEntitlement': entitlement,
          if (cap != null) 'leaveCarryoverCap': cap,
        },
      );
    }

    rolledController.dispose();
    entitlementController.dispose();
    capController.dispose();
  }

  Future<void> _exportAlSummaryCsv(List<models.StaffMember> staff) async {
    final rows = <List<String>>[];
    rows.add([
      'Personnel',
      'Rolled over',
      'Entitlement',
      'Total allowance',
      'Outstanding leave',
      'Pending leave',
      'Leave balance',
      'Forecast balance',
    ]);
    final roster = ref.read(rosterProvider);
    for (final member in staff) {
      final rolled =
          _leaveRolledOver(member, year: _alSummaryYear, roster: roster);
      final entitlement = _leaveEntitlement(member, year: _alSummaryYear);
      final total = rolled + entitlement;
      final outstanding =
          _scheduledLeaveDays(member, year: _alSummaryYear, roster: roster);
      final pending =
          _pendingLeaveDays(member, year: _alSummaryYear, roster: roster);
      final forecast =
          _forecastLeaveBalance(member, year: _alSummaryYear, roster: roster);
      rows.add([
        member.name,
        rolled.toStringAsFixed(1),
        entitlement.toStringAsFixed(1),
        total.toStringAsFixed(1),
        outstanding.toStringAsFixed(1),
        pending.toStringAsFixed(1),
        member.leaveBalance.toStringAsFixed(1),
        forecast.toStringAsFixed(1),
      ]);
    }

    final csv = rows.map((row) => row.join(',')).join('\n');
    final fileName = 'al_summary_${_alSummaryYear}.csv';
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Export AL Summary CSV',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (outputFile == null) return;
    if (!outputFile.endsWith('.csv')) {
      outputFile = '$outputFile.csv';
    }
    final file = File(outputFile);
    await file.writeAsString(csv);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV exported to: ${file.path}')),
      );
    }
  }

  Future<void> _exportAlSummaryPdf(List<models.StaffMember> staff) async {
    final roster = ref.read(rosterProvider);
    final doc = pw.Document();
    final headers = [
      'Personnel',
      'Rolled over',
      'Entitlement',
      'Total',
      'Outstanding',
      'Pending',
      'Leave balance',
      'Forecast',
    ];
    final data = staff.map((member) {
      final rolled =
          _leaveRolledOver(member, year: _alSummaryYear, roster: roster);
      final entitlement = _leaveEntitlement(member, year: _alSummaryYear);
      final total = rolled + entitlement;
      final outstanding =
          _scheduledLeaveDays(member, year: _alSummaryYear, roster: roster);
      final pending =
          _pendingLeaveDays(member, year: _alSummaryYear, roster: roster);
      final forecast =
          _forecastLeaveBalance(member, year: _alSummaryYear, roster: roster);
      return [
        member.name,
        rolled.toStringAsFixed(1),
        entitlement.toStringAsFixed(1),
        total.toStringAsFixed(1),
        outstanding.toStringAsFixed(1),
        pending.toStringAsFixed(1),
        member.leaveBalance.toStringAsFixed(1),
        forecast.toStringAsFixed(1),
      ];
    }).toList();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Annual Leave Summary (${_alSummaryYear})',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headers: headers,
              data: data,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
            ),
          ],
        ),
      ),
    );

    final fileName = 'al_summary_${_alSummaryYear}.pdf';
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Export AL Summary PDF',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (outputFile == null) return;
    if (!outputFile.endsWith('.pdf')) {
      outputFile = '$outputFile.pdf';
    }
    final file = File(outputFile);
    await file.writeAsBytes(await doc.save());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF exported to: ${file.path}')),
      );
    }
  }

  Future<void> _exportTimesheetCsv(
    models.StaffMember member,
    List<DateTime> weeks,
  ) async {
    final roster = ref.read(rosterProvider);
    final rows = <List<String>>[];
    rows.add([
      'Week',
      'Rostered',
      'Booked on',
      'Sick',
      'Absent',
      'Overtime (hrs)',
      'TOIL (hrs)',
    ]);
    for (final start in weeks) {
      final summary = _summarizeWeek(roster, member, start);
      rows.add([
        summary['label'].toString(),
        summary['rostered'].toString(),
        summary['confirmed'].toString(),
        summary['sick'].toString(),
        summary['absent'].toString(),
        (summary['overtime'] as double).toStringAsFixed(1),
        (summary['toilHours'] as double).toStringAsFixed(1),
      ]);
    }
    final csv = rows.map((row) => row.join(',')).join('\n');
    final fileName = 'timesheet_${member.name}_${DateTime.now().millisecondsSinceEpoch}.csv';
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Timesheet CSV',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (outputFile == null) return;
    if (!outputFile.endsWith('.csv')) {
      outputFile = '$outputFile.csv';
    }
    final file = File(outputFile);
    await file.writeAsString(csv);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV exported to: ${file.path}')),
      );
    }
  }

  Future<void> _exportTimesheetPdf(
    models.StaffMember member,
    List<DateTime> weeks,
  ) async {
    final roster = ref.read(rosterProvider);
    final doc = pw.Document();
    final headers = [
      'Week',
      'Rostered',
      'Booked on',
      'Sick',
      'Absent',
      'Overtime (hrs)',
      'TOIL (hrs)',
    ];
    final data = weeks.map((start) {
      final summary = _summarizeWeek(roster, member, start);
      return [
        summary['label'].toString(),
        summary['rostered'].toString(),
        summary['confirmed'].toString(),
        summary['sick'].toString(),
        summary['absent'].toString(),
        (summary['overtime'] as double).toStringAsFixed(1),
        (summary['toilHours'] as double).toStringAsFixed(1),
      ];
    }).toList();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Timesheet - ${member.name}',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headers: headers,
              data: data,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
            ),
          ],
        ),
      ),
    );

    final fileName = 'timesheet_${member.name}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Timesheet PDF',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (outputFile == null) return;
    if (!outputFile.endsWith('.pdf')) {
      outputFile = '$outputFile.pdf';
    }
    final file = File(outputFile);
    await file.writeAsBytes(await doc.save());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF exported to: ${file.path}')),
      );
    }
  }

  double? _readLeaveRolledOverMeta(
    models.StaffMember member, {
    required int year,
  }) {
    final meta = member.metadata ?? {};
    final perYear = meta['leaveRolledOverByYear'];
    if (perYear is Map) {
      final value = perYear[year.toString()];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
    }
    final value = meta['leaveRolledOver'];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  double _leaveCarryoverCap(models.StaffMember member) {
    final meta = member.metadata ?? {};
    final value = meta['leaveCarryoverCap'];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 5.0;
    return 5.0;
  }

  double _leaveRolledOver(
    models.StaffMember member, {
    required int year,
    required RosterNotifier roster,
  }) {
    final fromMeta = _readLeaveRolledOverMeta(member, year: year);
    if (fromMeta != null) return fromMeta;

    final prevYear = year - 1;
    if (prevYear < 1970) return 0;

    final cap = _leaveCarryoverCap(member);
    final prevRolledMeta =
        _readLeaveRolledOverMeta(member, year: prevYear) ?? 0;
    final prevEntitlement = _leaveEntitlement(member, year: prevYear);
    final prevOutstanding = _scheduledLeaveDays(
      member,
      year: prevYear,
      roster: roster,
    );
    final prevRemaining =
        (prevRolledMeta + prevEntitlement - prevOutstanding)
            .clamp(0, double.infinity)
            .toDouble();
    return prevRemaining > cap ? cap : prevRemaining;
  }

  double _leaveEntitlement(models.StaffMember member, {required int year}) {
    final meta = member.metadata ?? {};
    final perYear = meta['leaveEntitlementByYear'];
    if (perYear is Map) {
      final value = perYear[year.toString()];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 31.0;
    }
    final value = meta['leaveEntitlement'];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 31.0;
    final base = _baseEntitlementForType(member.employmentType);
    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year, 12, 31);
    if (member.startDate != null && member.startDate!.isAfter(yearEnd)) {
      return 0;
    }
    if (member.endDate != null && member.endDate!.isBefore(yearStart)) {
      return 0;
    }
    final effectiveStart = (member.startDate != null &&
            member.startDate!.isAfter(yearStart))
        ? member.startDate!
        : yearStart;
    final effectiveEnd = (member.endDate != null &&
            member.endDate!.isBefore(yearEnd))
        ? member.endDate!
        : yearEnd;
    if (effectiveEnd.isBefore(effectiveStart)) return 0;
    final totalDays = yearEnd.difference(yearStart).inDays + 1;
    final workedDays = effectiveEnd.difference(effectiveStart).inDays + 1;
    final prorata = workedDays / totalDays;
    return base * prorata;
  }

  double _baseEntitlementForType(String employmentType) {
    final normalized = employmentType.toLowerCase();
    if (normalized.contains('part')) return 20.0;
    if (normalized.contains('casual') ||
        normalized.contains('contract') ||
        normalized.contains('temp')) {
      return 0;
    }
    if (normalized.contains('probation')) return 15.0;
    return 31.0;
  }

  bool _matchesLeaveRequestForMember(
    models.AvailabilityRequest request,
    models.StaffMember member,
  ) {
    if (request.userId == member.id) return true;
    final meta = member.metadata ?? {};
    for (final key in const [
      'userId',
      'authId',
      'cognitoId',
      'email',
      'username',
    ]) {
      final value = meta[key];
      if (value is String && value.isNotEmpty && value == request.userId) {
        return true;
      }
    }
    final guest = request.guestName?.toLowerCase();
    if (guest != null && guest.isNotEmpty) {
      return guest == member.name.toLowerCase();
    }
    return false;
  }

  double _scheduledLeaveDays(
    models.StaffMember member, {
    required int year,
    required RosterNotifier roster,
  }) {
    final dates = <String>{};
    void addRange(DateTime start, DateTime end) {
      var cursor = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);
      while (!cursor.isAfter(last)) {
        if (cursor.year == year) {
          dates.add(DateFormat('yyyy-MM-dd').format(cursor));
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    if (member.leaveStart != null && member.leaveEnd != null) {
      final type = member.leaveType ?? '';
      final isAnnual = type == 'annual' || type == 'leave';
      if (isAnnual || type.startsWith('custom:')) {
        addRange(member.leaveStart!, member.leaveEnd!);
      }
    }

    for (final override in roster.overrides) {
      if (override.personName != member.name) continue;
      if (override.shift.toUpperCase() != 'AL') continue;
      final date = DateTime(
        override.date.year,
        override.date.month,
        override.date.day,
      );
      if (date.year != year) continue;
      dates.add(DateFormat('yyyy-MM-dd').format(date));
    }

    for (final request in roster.availabilityRequests) {
      if (request.status != models.RequestStatus.approved) continue;
      if (request.type != models.AvailabilityType.leave) continue;
      if (!_matchesLeaveRequestForMember(request, member)) continue;
      addRange(request.startDate, request.endDate);
    }

    return dates.length.toDouble();
  }

  double _pendingLeaveDays(
    models.StaffMember member, {
    required int year,
    required RosterNotifier roster,
  }) {
    final dates = <String>{};
    void addRange(DateTime start, DateTime end) {
      var cursor = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);
      while (!cursor.isAfter(last)) {
        if (cursor.year == year) {
          dates.add(DateFormat('yyyy-MM-dd').format(cursor));
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    for (final request in roster.availabilityRequests) {
      if (request.status != models.RequestStatus.pending) continue;
      if (request.type != models.AvailabilityType.leave) continue;
      if (!_matchesLeaveRequestForMember(request, member)) continue;
      addRange(request.startDate, request.endDate);
    }

    return dates.length.toDouble();
  }

  double _scheduledLeaveFutureDays(
    models.StaffMember member, {
    required int year,
    required RosterNotifier roster,
  }) {
    final today = DateTime.now();
    final dates = <String>{};

    void addRange(DateTime start, DateTime end) {
      var cursor = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);
      if (cursor.isBefore(today)) {
        cursor = DateTime(today.year, today.month, today.day);
      }
      while (!cursor.isAfter(last)) {
        if (cursor.year == year) {
          dates.add(DateFormat('yyyy-MM-dd').format(cursor));
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    if (member.leaveStart != null && member.leaveEnd != null) {
      final type = member.leaveType ?? '';
      final isAnnual = type == 'annual' || type == 'leave';
      if (isAnnual || type.startsWith('custom:')) {
        addRange(member.leaveStart!, member.leaveEnd!);
      }
    }

    for (final override in roster.overrides) {
      if (override.personName != member.name) continue;
      if (override.shift.toUpperCase() != 'AL') continue;
      final date = DateTime(
        override.date.year,
        override.date.month,
        override.date.day,
      );
      if (date.isBefore(today)) continue;
      if (date.year != year) continue;
      dates.add(DateFormat('yyyy-MM-dd').format(date));
    }

    for (final request in roster.availabilityRequests) {
      if (request.status != models.RequestStatus.approved) continue;
      if (request.type != models.AvailabilityType.leave) continue;
      if (!_matchesLeaveRequestForMember(request, member)) continue;
      addRange(request.startDate, request.endDate);
    }

    return dates.length.toDouble();
  }

  double _forecastLeaveBalance(
    models.StaffMember member, {
    required int year,
    required RosterNotifier roster,
  }) {
    final remainingScheduled =
        _scheduledLeaveFutureDays(member, year: year, roster: roster);
    return member.leaveBalance - remainingScheduled;
  }

  Widget _buildSummaryCard(BuildContext context, String title, String value,
      IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onBackground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddStaffDialog() {
    final nameStore = ref.read(staffNameProvider);
    DateTime startDate = DateTime.now();
    String employmentType = 'permanent';
    DateTime? endDate;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
        title: const Text('Add Staff Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Autocomplete<String>(
              optionsBuilder: (value) {
                final query = value.text.trim().toLowerCase();
                if (query.isEmpty) return const Iterable<String>.empty();
                return nameStore.names.where(
                  (name) => name.toLowerCase().contains(query),
                );
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                _addStaffController.value = controller.value;
                return SafeTextField(
                  controller: _addStaffController,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Staff Name',
                    hintText: 'Enter staff member name',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                );
              },
              onSelected: (selection) {
                _addStaffController.text = selection;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: employmentType,
              decoration: const InputDecoration(
                labelText: 'Employment type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'permanent', child: Text('Permanent')),
                DropdownMenuItem(value: 'temporary', child: Text('Temporary')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  employmentType = value;
                  if (employmentType == 'permanent') {
                    endDate = null;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Start date'),
                const Spacer(),
                OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate,
                      firstDate: DateTime(DateTime.now().year - 10),
                      lastDate: DateTime(DateTime.now().year + 10),
                    );
                    if (picked != null) {
                      setState(() => startDate = picked);
                    }
                  },
                  child: Text(DateFormat('MMM d, yyyy').format(startDate)),
                ),
              ],
            ),
            if (employmentType == 'temporary') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('End date'),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endDate ?? startDate,
                        firstDate: startDate,
                        lastDate: DateTime(DateTime.now().year + 10),
                      );
                      if (picked != null) {
                        setState(() => endDate = picked);
                      }
                    },
                    child: Text(endDate == null
                        ? 'Select'
                        : DateFormat('MMM d, yyyy').format(endDate!)),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (_addStaffController.text.trim().isNotEmpty) {
                final name = _addStaffController.text.trim();
                final roster = ref.read(rosterProvider);
                roster.addStaff(name);
                final created = roster.staffMembers
                    .where((s) => s.name == name)
                    .lastOrNull;
                if (created != null) {
                  roster.setStaffStartDate(created.id, startDate);
                  roster.setStaffEmploymentType(created.id, employmentType);
                  if (employmentType == 'temporary' && endDate != null) {
                    roster.setStaffEndDate(created.id, endDate);
                  }
                }
                nameStore.addName(name);
                _addStaffController.clear();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Staff member added successfully')),
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

  void _startEditing(String staffId) {
    setState(() {
      _isEditing[staffId] = true;
    });
  }

  void _cancelEditing(String staffId) {
    setState(() {
      _isEditing[staffId] = false;
      // Reset controller to original name
      final staffMember = ref.read(rosterProvider).staffMembers.firstWhere(
            (s) => s.id == staffId,
            orElse: () => models.StaffMember(id: '', name: ''),
          );
      _editControllers[staffId]!.text = staffMember.name;
    });
  }

  void _updateStaffName(String staffId, String newName) {
    if (newName.trim().isNotEmpty) {
      final name = newName.trim();
      ref.read(rosterProvider).renameStaffById(staffId, name);
      ref.read(staffNameProvider).addName(name);
      setState(() {
        _isEditing[staffId] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff name updated successfully')),
      );
    } else {
      _cancelEditing(staffId);
    }
  }

  void _toggleStaffStatus(String staffId) {
    ref.read(rosterProvider).toggleStaffStatusById(staffId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Staff status updated')),
    );
  }

  void _deleteStaff(String staffId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Employment?'),
        content: const Text(
            'This will set an end date for the staff member. Past rosters remain intact and you can clear the end date later if needed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(rosterProvider).removeStaffById(staffId);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Staff employment ended successfully')),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End'),
          ),
        ],
      ),
    );
  }
}

class _StaffCard extends ConsumerWidget {
  final models.StaffMember staffMember;
  final TextEditingController editController;
  final bool isEditing;
  final VoidCallback onEditStart;
  final VoidCallback onEditCancel;
  final Function(String) onUpdate;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  const _StaffCard({
    required this.staffMember,
    required this.editController,
    required this.isEditing,
    required this.onEditStart,
    required this.onEditCancel,
    required this.onUpdate,
    required this.onToggleStatus,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(rosterProvider);
    final overrides = roster.getOverridesForPerson(staffMember.name);
    final nameStore = ref.watch(staffNameProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  staffMember.isActive ? Icons.person : Icons.person_off,
                  color: staffMember.isActive ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: isEditing
                      ? Autocomplete<String>(
                          optionsBuilder: (value) {
                            final query = value.text.trim().toLowerCase();
                            if (query.isEmpty) {
                              return const Iterable<String>.empty();
                            }
                            return nameStore.names.where(
                              (name) => name.toLowerCase().contains(query),
                            );
                          },
                          fieldViewBuilder: (context, controller, focusNode,
                              onFieldSubmitted) {
                            editController.value = controller.value;
                            return SafeTextField(
                              controller: editController,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                isDense: true,
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.check, size: 18),
                                      onPressed: () =>
                                          onUpdate(editController.text),
                                      tooltip: 'Save',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: onEditCancel,
                                      tooltip: 'Cancel',
                                    ),
                                  ],
                                ),
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              autofocus: true,
                              onSubmitted: onUpdate,
                            );
                          },
                          onSelected: (selection) {
                            editController.text = selection;
                          },
                        )
                      : GestureDetector(
                          onTap: onEditStart,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.transparent),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    staffMember.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.edit,
                                    size: 16, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                ),
                if (!isEditing) ...[
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onEditStart();
                          break;
                        case 'startDate':
                          _showStartDateDialog(context, roster, staffMember);
                          break;
                        case 'endDate':
                          _showEndDateDialog(context, roster, staffMember);
                          break;
                        case 'clearEnd':
                          roster.setStaffEndDate(staffMember.id, null);
                          break;
                        case 'leaveStatus':
                          _showLeaveStatusDialog(
                              context, roster, staffMember);
                          break;
                        case 'clearLeave':
                          roster.clearStaffLeaveStatus(staffMember.id);
                          break;
                        case 'leave':
                          _showLeaveDialog(context, staffMember.name);
                          break;
                        case 'overrides':
                          _showStaffOverrides(context, staffMember.name);
                          break;
                        case 'preferences':
                          _showPreferencesDialog(context, staffMember);
                          break;
                        case 'toggle':
                          onToggleStatus();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit),
                          title: Text('Edit Name'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'startDate',
                        child: ListTile(
                          leading: Icon(Icons.event_available),
                          title: Text('Set Start Date'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'endDate',
                        child: ListTile(
                          leading: Icon(Icons.event_busy),
                          title: Text('Set End Date'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'clearEnd',
                        child: ListTile(
                          leading: Icon(Icons.event_repeat),
                          title: Text('Clear End Date'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'leaveStatus',
                        child: ListTile(
                          leading: Icon(Icons.airline_seat_recline_extra),
                          title: Text('Set Leave/Secondment'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'clearLeave',
                        child: ListTile(
                          leading: Icon(Icons.event_available),
                          title: Text('Clear Leave/Secondment'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'leave',
                        child: ListTile(
                          leading: Icon(Icons.beach_access),
                          title: Text('Manage Leave'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'overrides',
                        child: ListTile(
                          leading: Icon(Icons.edit_calendar),
                          title: Text('View Changes'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'preferences',
                        child: ListTile(
                          leading: Icon(Icons.tune),
                          title: Text('Preferences'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: ListTile(
                          leading: Icon(staffMember.isActive
                              ? Icons.person_off
                              : Icons.person),
                          title: Text(
                              staffMember.isActive ? 'Deactivate' : 'Activate'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.person_off, color: Colors.red),
                          title: Text('End Employment',
                              style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildInfoChip(
                  context,
                  Icons.account_balance_wallet,
                  '${staffMember.leaveBalance.toStringAsFixed(1)} days leave',
                ),
                const SizedBox(width: 8),
                _buildInfoChip(
                  context,
                  Icons.edit_calendar,
                  '${overrides.length} changes',
                ),
                const SizedBox(width: 8),
                _buildInfoChip(
                  context,
                  Icons.badge,
                  staffMember.employmentType == 'temporary'
                      ? 'Temporary'
                      : 'Permanent',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.event_available,
                    size: 14, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Start: ${staffMember.startDate != null ? DateFormat('MMM d, yyyy').format(staffMember.startDate!) : 'Not set'}',
                  style: GoogleFonts.inter(fontSize: 12),
                ),
                const SizedBox(width: 12),
                Icon(Icons.event_busy,
                    size: 14, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 6),
                Text(
                  'End: ${staffMember.endDate != null ? DateFormat('MMM d, yyyy').format(staffMember.endDate!) : 'Active'}',
                  style: GoogleFonts.inter(fontSize: 12),
                ),
              ],
            ),
            if (staffMember.leaveType != null &&
                staffMember.leaveStart != null &&
                staffMember.leaveEnd != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.airline_seat_recline_extra,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '${_formatLeaveLabel(staffMember.leaveType)}: ${DateFormat('MMM d, yyyy').format(staffMember.leaveStart!)} → ${DateFormat('MMM d, yyyy').format(staffMember.leaveEnd!)}',
                    style: GoogleFonts.inter(fontSize: 12),
                  ),
                ],
              ),
            ],
            if (!staffMember.isActive) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange),
                ),
                child: Text(
                  'Inactive',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(BuildContext context, IconData icon, String text) {
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
          Text(
            text,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _showStartDateDialog(
    BuildContext context,
    RosterNotifier roster,
    models.StaffMember staff,
  ) async {
    final now = DateTime.now();
    final initial = staff.startDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      roster.setStaffStartDate(staff.id, picked);
    }
  }

  Future<void> _showEndDateDialog(
    BuildContext context,
    RosterNotifier roster,
    models.StaffMember staff,
  ) async {
    final now = DateTime.now();
    final initial = staff.endDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      roster.setStaffEndDate(staff.id, picked);
    }
  }

  Future<void> _showLeaveStatusDialog(
    BuildContext context,
    RosterNotifier roster,
    models.StaffMember staff,
  ) async {
    String leaveType = staff.leaveType ?? 'leave';
    String customLabel = _extractCustomLeaveLabel(leaveType) ?? '';
    if (leaveType.startsWith('custom:')) {
      leaveType = 'custom';
    }
    DateTime startDate = staff.leaveStart ?? DateTime.now();
    DateTime endDate = staff.leaveEnd ?? DateTime.now().add(const Duration(days: 7));
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Set Leave/Secondment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: leaveType,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'leave', child: Text('Leave')),
                  DropdownMenuItem(value: 'annual', child: Text('Annual Leave')),
                  DropdownMenuItem(value: 'sick', child: Text('Sick')),
                  DropdownMenuItem(value: 'secondment', child: Text('Secondment')),
                  DropdownMenuItem(value: 'custom', child: Text('Custom')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => leaveType = value);
                },
              ),
              if (leaveType == 'custom') ...[
                const SizedBox(height: 12),
                SafeTextField(
                  decoration: const InputDecoration(
                    labelText: 'Custom leave label',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Compassionate Leave',
                  ),
                  onChanged: (value) => setState(() => customLabel = value),
                  controller: TextEditingController(text: customLabel),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Start date'),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate,
                        firstDate: DateTime(DateTime.now().year - 10),
                        lastDate: DateTime(DateTime.now().year + 10),
                      );
                      if (picked != null) {
                        setState(() => startDate = picked);
                      }
                    },
                    child: Text(DateFormat('MMM d, yyyy').format(startDate)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('End date'),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endDate,
                        firstDate: startDate,
                        lastDate: DateTime(DateTime.now().year + 10),
                      );
                      if (picked != null) {
                        setState(() => endDate = picked);
                      }
                    },
                    child: Text(DateFormat('MMM d, yyyy').format(endDate)),
                  ),
                ],
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
                final effectiveType = leaveType == 'custom'
                    ? 'custom:${customLabel.trim()}'
                    : leaveType;
                roster.setStaffLeaveStatus(
                  staffId: staff.id,
                  leaveType: effectiveType,
                  startDate: startDate,
                  endDate: endDate,
                );
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLeaveDialog(BuildContext context, String personName) {
    final roster = ProviderScope.containerOf(context).read(rosterProvider);
    final staffMember = roster.staffMembers.firstWhere(
      (s) => s.name == personName,
      orElse: () => models.StaffMember(
        id: '',
        name: personName,
        isActive: true,
        leaveBalance: 31.0,
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

  void _showStaffOverrides(BuildContext context, String personName) {
    final roster = ProviderScope.containerOf(context).read(rosterProvider);
    final overrides = roster.getOverridesForPerson(personName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Changes - $personName'),
        content: SizedBox(
          width: double.maxFinite,
          child: overrides.isEmpty
              ? const Text('No changes found')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: overrides.length,
                  itemBuilder: (context, index) {
                    final override = overrides[index];
                    return ListTile(
                      leading: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Text(
                            override.shift,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      title: Text(override.date.toString().split(' ')[0]),
                      subtitle: override.reason != null
                          ? Text(override.reason!)
                          : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          roster.overrides
                              .removeWhere((o) => o.id == override.id);
                          Navigator.pop(context);
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Change Removed'),
                              content: const Text(
                                  'The change has been removed successfully.'),
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

  void _showPreferencesDialog(
    BuildContext context,
    models.StaffMember staffMember,
  ) {
    final roster = ProviderScope.containerOf(context).read(rosterProvider);
    final current =
        staffMember.preferences ?? const models.StaffPreferences();
    final dayLabels = const [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    final selectedDays = current.preferredDaysOff.toSet();
    final preferredShiftsController = TextEditingController(
      text: current.preferredShifts.join(', '),
    );
    final maxShiftsController = TextEditingController(
      text: current.maxShiftsPerWeek?.toString() ?? '',
    );
    final minRestController = TextEditingController(
      text: current.minRestDaysBetweenShifts?.toString() ?? '',
    );
    final notesController = TextEditingController(text: current.notes ?? '');
    bool avoidWeekends = current.avoidWeekends;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Preferences - ${staffMember.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preferred Days Off',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: List.generate(7, (index) {
                    final weekday = index + 1;
                    final isSelected = selectedDays.contains(weekday);
                    return FilterChip(
                      label: Text(dayLabels[index]),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            selectedDays.add(weekday);
                          } else {
                            selectedDays.remove(weekday);
                          }
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 12),
                SafeTextField(
                  controller: preferredShiftsController,
                  decoration: const InputDecoration(
                    labelText: 'Preferred Shifts',
                    hintText: 'e.g., D, N, OFF',
                  ),
                ),
                const SizedBox(height: 12),
                SafeTextField(
                  controller: maxShiftsController,
                  decoration: const InputDecoration(
                    labelText: 'Max Shifts Per Week',
                    hintText: 'e.g., 5',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                SafeTextField(
                  controller: minRestController,
                  decoration: const InputDecoration(
                    labelText: 'Min Rest Days',
                    hintText: 'e.g., 1',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Avoid Weekends'),
                  value: avoidWeekends,
                  onChanged: (value) {
                    setState(() => avoidWeekends = value);
                  },
                ),
                const SizedBox(height: 8),
                SafeTextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Optional notes',
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
                final preferredShifts = preferredShiftsController.text
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                final maxShifts =
                    int.tryParse(maxShiftsController.text.trim());
                final minRest =
                    int.tryParse(minRestController.text.trim());
                final updated = models.StaffPreferences(
                  preferredDaysOff: selectedDays.toList()..sort(),
                  preferredShifts: preferredShifts,
                  maxShiftsPerWeek: maxShifts,
                  minRestDaysBetweenShifts: minRest,
                  avoidWeekends: avoidWeekends,
                  notes: notesController.text.trim().isEmpty
                      ? null
                      : notesController.text.trim(),
                );
                roster.updateStaffPreferencesById(staffMember.id, updated);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
