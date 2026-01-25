import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'models.dart' as models;

class LeaveManagementView extends ConsumerStatefulWidget {
  const LeaveManagementView({super.key});

  @override
  ConsumerState<LeaveManagementView> createState() =>
      _LeaveManagementViewState();
}

class _LeaveManagementViewState extends ConsumerState<LeaveManagementView> {
  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final canApprove = roster.activeRoster?.role != 'staff';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Leave Management',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ElevatedButton.icon(
              onPressed: () => _showNewLeaveDialog(context, roster),
              icon: const Icon(Icons.add),
              label: const Text('Request Leave'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildLeaveBalances(roster),
        const SizedBox(height: 20),
        _buildRequestsSection(context, roster, canApprove),
        const SizedBox(height: 20),
        _buildPlannerSection(roster),
        const SizedBox(height: 20),
        _buildLeavePolicySection(context, roster),
        const SizedBox(height: 20),
        _buildRecurringSection(context, roster),
      ],
    );
  }

  Widget _buildLeaveBalances(RosterNotifier roster) {
    if (roster.staffMembers.isEmpty) {
      return const Card(
        child: ListTile(
          title: Text('No staff yet'),
          subtitle: Text('Add staff to manage leave balances.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leave Balances',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildBulkEntitlementEditor(roster),
            const SizedBox(height: 8),
            ...roster.staffMembers.map((staff) {
              final taken =
                  roster.getApprovedLeaveDaysFor(staff.name).toDouble();
              final remaining = staff.annualLeaveEntitlement - taken;
              return ListTile(
                title: Text(staff.name),
                subtitle: Text(
                    'Entitlement: ${staff.annualLeaveEntitlement.toStringAsFixed(1)} days'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Taken: ${taken.toStringAsFixed(1)}'),
                        Text('Remaining: ${remaining.toStringAsFixed(1)}'),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit entitlement',
                      onPressed: () => _editEntitlement(
                        context,
                        roster,
                        staff.name,
                        staff.annualLeaveEntitlement,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsSection(
    BuildContext context,
    RosterNotifier roster,
    bool canApprove,
  ) {
    final pending =
        roster.leaveRequests.where((r) => r.status == 'pending').toList();
    final approved =
        roster.leaveRequests.where((r) => r.status == 'approved').toList();
    final declined =
        roster.leaveRequests.where((r) => r.status == 'declined').toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leave Requests',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildRequestGroup(context, roster, 'Pending', pending, canApprove),
            _buildRequestGroup(
                context, roster, 'Approved', approved, false),
            _buildRequestGroup(
                context, roster, 'Declined', declined, false),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestGroup(
    BuildContext context,
    RosterNotifier roster,
    String title,
    List<models.LeaveRequest> requests,
    bool canApprove,
  ) {
    return ExpansionTile(
      title: Text('$title (${requests.length})'),
      children: requests.isEmpty
          ? [
              const ListTile(
                title: Text('No requests'),
              )
            ]
          : requests
              .map((request) => ListTile(
                    title: Text(
                        '${request.staffName} • ${_formatLeaveType(request.type)}'),
                    subtitle: Text(
                      '${_formatDate(request.startDate)} - ${_formatDate(request.endDate)}',
                    ),
                    trailing: request.status == 'pending'
                        ? (canApprove
                            ? Wrap(
                                spacing: 8,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.check_circle,
                                        color: Colors.green),
                                    onPressed: () => roster.approveLeaveRequest(
                                      request.id,
                                      approvedBy:
                                          roster.activeRoster?.role ?? 'manager',
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.cancel,
                                        color: Colors.red),
                                    onPressed: () => roster.declineLeaveRequest(
                                      request.id,
                                      approvedBy:
                                          roster.activeRoster?.role ?? 'manager',
                                    ),
                                  ),
                                ],
                              )
                            : TextButton(
                                onPressed: () =>
                                    roster.cancelLeaveRequest(request.id),
                                child: const Text('Cancel'),
                              ))
                        : null,
                  ))
              .toList(),
    );
  }

  Widget _buildPlannerSection(RosterNotifier roster) {
    final holidays = roster.rosterRules.bankHolidayDates
        .map((d) => DateTime.tryParse(d))
        .whereType<DateTime>()
        .toList()
      ..sort();
    if (holidays.isEmpty) {
      return const Card(
        child: ListTile(
          title: Text('Leave Planner'),
          subtitle: Text('No bank holidays available.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leave Planner',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...holidays.take(10).map((date) {
              final suggestion = _suggestLeaveWindow(date);
              return ListTile(
                leading: const Icon(Icons.celebration),
                title: Text(_formatDate(date)),
                subtitle: Text(suggestion),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildLeavePolicySection(
    BuildContext context,
    RosterNotifier roster,
  ) {
    final blackoutDates = roster.rosterRules.leaveBlackoutDates
        .map((d) => DateTime.tryParse(d))
        .whereType<DateTime>()
        .toList()
      ..sort();
    final maxConcurrent = roster.rosterRules.maxConcurrentLeavePerDay;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leave Policy',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    maxConcurrent == 0
                        ? 'No concurrent leave limit'
                        : 'Max concurrent leave: $maxConcurrent',
                  ),
                ),
                TextButton(
                  onPressed: () => _editLeavePolicy(context, roster),
                  child: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: blackoutDates.isEmpty
                  ? [const Text('No blackout dates')]
                  : blackoutDates
                      .map((date) => Chip(
                            label: Text(_formatDate(date)),
                            onDeleted: () => _removeBlackout(roster, date),
                          ))
                      .toList(),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _addBlackout(context, roster),
              icon: const Icon(Icons.add),
              label: const Text('Add blackout date'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecurringSection(
    BuildContext context,
    RosterNotifier roster,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recurring Leave Rules',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (roster.recurringLeaveRules.isEmpty)
              const Text('No recurring leave rules yet.')
            else
              ...roster.recurringLeaveRules.map((rule) => ListTile(
                    title: Text(
                        '${rule.staffName} • ${_formatLeaveType(rule.type)}'),
                    subtitle: Text(
                      '${rule.startDay}/${rule.startMonth} - ${rule.endDay}/${rule.endMonth}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          roster.removeRecurringLeaveRule(rule.id),
                    ),
                  )),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showRecurringDialog(context, roster),
                  icon: const Icon(Icons.add),
                  label: const Text('Add rule'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _generateRecurring(context, roster),
                  icon: const Icon(Icons.repeat),
                  label: const Text('Generate for year'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNewLeaveDialog(
    BuildContext context,
    RosterNotifier roster,
  ) async {
    if (roster.staffMembers.isEmpty) return;
    String staffName = roster.staffMembers.first.name;
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    String type = 'annual_leave';
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New Leave Request'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: staffName,
                  items: roster.staffMembers
                      .map((s) =>
                          DropdownMenuItem(value: s.name, child: Text(s.name)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => staffName = value ?? staffName),
                  decoration: const InputDecoration(
                    labelText: 'Staff member',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: type,
                  items: const [
                    DropdownMenuItem(
                        value: 'annual_leave', child: Text('Annual Leave')),
                    DropdownMenuItem(
                        value: 'long_term_sick', child: Text('Long-Term Sick')),
                    DropdownMenuItem(
                        value: 'sabbatical', child: Text('Sabbatical')),
                    DropdownMenuItem(
                        value: 'secondment', child: Text('Secondment')),
                    DropdownMenuItem(
                        value: 'training', child: Text('Training')),
                  ],
                  onChanged: (value) => setState(() => type = value ?? type),
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  title: Text('Start: ${_formatDate(startDate)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                    );
                    if (picked != null) {
                      setState(() => startDate = picked);
                    }
                  },
                ),
                ListTile(
                  title: Text('End: ${_formatDate(endDate)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: endDate,
                      firstDate: startDate,
                      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                    );
                    if (picked != null) {
                      setState(() => endDate = picked);
                    }
                  },
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final request = models.LeaveRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      staffName: staffName,
      startDate: startDate,
      endDate: endDate,
      type: type,
      status: 'pending',
      requestedBy: roster.activeRoster?.role ?? 'staff',
      createdAt: DateTime.now(),
      notes: notesController.text.trim().isEmpty
          ? null
          : notesController.text.trim(),
    );
    final warnings = roster.validateLeaveRequest(request);
    if (warnings.isNotEmpty) {
      final proceed = await _confirmWarnings(context, warnings);
      if (!proceed) return;
    }
    roster.addLeaveRequest(request);
  }

  Future<bool> _confirmWarnings(
    BuildContext context,
    List<String> warnings,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave warnings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: warnings.map((w) => Text('- $w')).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Proceed'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _editLeavePolicy(
    BuildContext context,
    RosterNotifier roster,
  ) async {
    final controller = TextEditingController(
      text: roster.rosterRules.maxConcurrentLeavePerDay.toString(),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave policy'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Max concurrent leave per day (0 for none)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true) {
      final value = int.tryParse(controller.text.trim()) ?? 0;
      roster.updateRosterRules(
        roster.rosterRules.copyWith(maxConcurrentLeavePerDay: value),
      );
    }
  }

  Future<void> _addBlackout(
    BuildContext context,
    RosterNotifier roster,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    final key = DateTime(picked.year, picked.month, picked.day).toIso8601String();
    final updated = List<String>.from(roster.rosterRules.leaveBlackoutDates);
    if (!updated.contains(key)) {
      updated.add(key);
      roster.updateRosterRules(
        roster.rosterRules.copyWith(leaveBlackoutDates: updated),
      );
    }
  }

  void _removeBlackout(RosterNotifier roster, DateTime date) {
    final key = DateTime(date.year, date.month, date.day).toIso8601String();
    final updated = List<String>.from(roster.rosterRules.leaveBlackoutDates)
      ..remove(key);
    roster.updateRosterRules(
      roster.rosterRules.copyWith(leaveBlackoutDates: updated),
    );
  }

  Future<void> _showRecurringDialog(
    BuildContext context,
    RosterNotifier roster,
  ) async {
    if (roster.staffMembers.isEmpty) return;
    String staffName = roster.staffMembers.first.name;
    String type = 'annual_leave';
    DateTime start = DateTime(DateTime.now().year, 1, 1);
    DateTime end = DateTime(DateTime.now().year, 1, 1);
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Recurring Leave Rule'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: staffName,
                  items: roster.staffMembers
                      .map((s) => DropdownMenuItem(
                          value: s.name, child: Text(s.name)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => staffName = value ?? staffName),
                  decoration: const InputDecoration(
                    labelText: 'Staff member',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: type,
                  items: const [
                    DropdownMenuItem(
                        value: 'annual_leave', child: Text('Annual Leave')),
                    DropdownMenuItem(
                        value: 'long_term_sick', child: Text('Long-Term Sick')),
                    DropdownMenuItem(
                        value: 'sabbatical', child: Text('Sabbatical')),
                    DropdownMenuItem(
                        value: 'secondment', child: Text('Secondment')),
                    DropdownMenuItem(
                        value: 'training', child: Text('Training')),
                  ],
                  onChanged: (value) => setState(() => type = value ?? type),
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  title: Text(
                      'Start: ${start.day}/${start.month}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: start,
                      firstDate: DateTime(DateTime.now().year, 1, 1),
                      lastDate: DateTime(DateTime.now().year, 12, 31),
                    );
                    if (picked != null) {
                      setState(() => start = picked);
                    }
                  },
                ),
                ListTile(
                  title: Text(
                      'End: ${end.day}/${end.month}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: end,
                      firstDate: DateTime(DateTime.now().year, 1, 1),
                      lastDate: DateTime(DateTime.now().year, 12, 31),
                    );
                    if (picked != null) {
                      setState(() => end = picked);
                    }
                  },
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    roster.addRecurringLeaveRule(models.RecurringLeaveRule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      staffName: staffName,
      startMonth: start.month,
      startDay: start.day,
      endMonth: end.month,
      endDay: end.day,
      type: type,
      notes: notesController.text.trim().isEmpty
          ? null
          : notesController.text.trim(),
    ));
  }

  Future<void> _generateRecurring(
    BuildContext context,
    RosterNotifier roster,
  ) async {
    final controller =
        TextEditingController(text: DateTime.now().year.toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate recurring leave'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Year',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final year = int.tryParse(controller.text.trim()) ?? DateTime.now().year;
    final count = roster.generateRecurringLeaveRequests(year);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Generated $count requests for $year')),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatLeaveType(String type) {
    switch (type) {
      case 'annual_leave':
        return 'Annual Leave';
      case 'long_term_sick':
        return 'Long-Term Sick';
      case 'sabbatical':
        return 'Sabbatical';
      case 'secondment':
        return 'Secondment';
      case 'training':
        return 'Training';
      default:
        return type;
    }
  }

  String _suggestLeaveWindow(DateTime holiday) {
    switch (holiday.weekday) {
      case DateTime.monday:
        return 'Consider taking Fri to Sun for a 4-day break.';
      case DateTime.friday:
        return 'Consider taking Mon to Thu for a 4-day break.';
      case DateTime.thursday:
        return 'Take Fri for a long weekend.';
      case DateTime.tuesday:
        return 'Take Mon or Wed to stretch the break.';
      default:
        return 'Add leave around this date to extend time off.';
    }
  }

  Widget _buildBulkEntitlementEditor(RosterNotifier roster) {
    final controller = TextEditingController();
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Set entitlement for all staff',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            final value = double.tryParse(controller.text.trim());
            if (value == null) return;
            roster.updateAllLeaveEntitlements(value);
            controller.clear();
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Future<void> _editEntitlement(
    BuildContext context,
    RosterNotifier roster,
    String staffName,
    double currentEntitlement,
  ) async {
    final controller =
        TextEditingController(text: currentEntitlement.toStringAsFixed(1));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit entitlement - $staffName'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Entitlement days',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final value = double.tryParse(controller.text.trim());
      if (value == null) return;
      roster.updateLeaveEntitlement(staffName, value);
    }
  }
}
