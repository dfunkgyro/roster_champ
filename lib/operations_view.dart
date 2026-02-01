import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'providers.dart';
import 'models.dart' as models;
import 'roster_generator_view.dart';
import 'aws_service.dart';

class OperationsView extends ConsumerStatefulWidget {
  const OperationsView({super.key});

  @override
  ConsumerState<OperationsView> createState() => _OperationsViewState();
}

class _OperationsViewState extends ConsumerState<OperationsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _refreshAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    final roster = ref.read(rosterProvider);
    if (roster.readOnly) {
      return;
    }
    await Future.wait([
      roster.refreshAvailabilityRequests(),
      roster.refreshSwapRequests(),
      roster.refreshChangeProposals(),
      roster.refreshShiftLocks(),
      roster.refreshAuditLogs(),
      roster.refreshRosterUpdates(),
      roster.refreshTimeClockEntries(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    if (roster.readOnly) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline,
                  size: 60, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Read-only access',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Operations are disabled in shared view.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RosterGeneratorView(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Auto Roster Generator'),
                ),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Availability'),
            Tab(text: 'Swaps'),
            Tab(text: 'Proposals'),
            Tab(text: 'Locks'),
            Tab(text: 'Changes'),
            Tab(text: 'Time Clock'),
            Tab(text: 'Audit'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAvailabilityTab(context, roster),
              _buildSwapsTab(context, roster),
              _buildProposalsTab(context, roster),
              _buildLocksTab(context, roster),
              _buildChangesTab(context, roster),
              _buildTimeClockTab(context, roster),
              _buildAuditTab(context, roster),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChangesTab(BuildContext context, RosterNotifier roster) {
    if (roster.recentUpdates.isEmpty) {
      return const Center(child: Text('No recent changes'));
    }
    return ListView.builder(
      itemCount: roster.recentUpdates.length,
      itemBuilder: (context, index) {
        final update = roster.recentUpdates[index];
        return ListTile(
          leading: const Icon(Icons.timeline),
          title: Text(update.operationType.name),
          subtitle: Text(update.timestamp.toIso8601String()),
          trailing: IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showUpdateDetails(context, update),
          ),
        );
      },
    );
  }

  void _showUpdateDetails(BuildContext context, models.RosterUpdate update) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Details'),
        content: SingleChildScrollView(
          child: Text(const JsonEncoder.withIndent('  ').convert(update.data)),
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

  Widget _buildTimeClockTab(BuildContext context, RosterNotifier roster) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                'Time Clock Entries',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _importTimeClock(context, roster),
                icon: const Icon(Icons.upload_file),
                label: const Text('Import CSV'),
              ),
            ],
          ),
        ),
        Expanded(
          child: roster.timeClockEntries.isEmpty
              ? const Center(child: Text('No time clock data'))
              : ListView.builder(
                  itemCount: roster.timeClockEntries.length,
                  itemBuilder: (context, index) {
                    final entry = roster.timeClockEntries[index];
                    return ListTile(
                      leading: const Icon(Icons.access_time),
                      title: Text(entry.personName),
                      subtitle: Text(
                        '${entry.date.toIso8601String().split('T').first} · ${entry.hours}h',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _importTimeClock(
    BuildContext context,
    RosterNotifier roster,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.single.path;
    if (filePath == null) return;
    final raw = await File(filePath).readAsString();
    final lines = raw.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty);
    final entries = <models.TimeClockEntry>[];
    for (final line in lines.skip(1)) {
      final parts = line.split(',');
      if (parts.length < 3) continue;
      final person = parts[0].trim();
      final date = DateTime.tryParse(parts[1].trim());
      final hours = double.tryParse(parts[2].trim()) ?? 0;
      if (date == null) continue;
      entries.add(
        models.TimeClockEntry(
          rosterId: AwsService.instance.currentRosterId ?? '',
          entryId: '',
          personName: person,
          date: date,
          hours: hours,
          source: 'csv',
        ),
      );
    }
    final imported = await roster.importTimeClockEntries(entries);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $imported time entries')),
      );
    }
  }

  Widget _buildAvailabilityTab(BuildContext context, RosterNotifier roster) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                'Availability Requests',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => roster.applyApprovedAvailabilityRequests(),
                child: const Text('Apply Approved'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _showAvailabilityRequestDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Request'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: roster.availabilityRequests.length,
            itemBuilder: (context, index) {
              final request = roster.availabilityRequests[index];
              return ListTile(
                leading: Icon(
                  request.status == models.RequestStatus.approved
                      ? Icons.check_circle
                      : request.status == models.RequestStatus.denied
                          ? Icons.cancel
                          : Icons.hourglass_bottom,
                ),
                title: Text(
                  '${request.type.name} · ${_formatDate(request.startDate)}',
                ),
                subtitle: Text(request.notes),
                trailing: _buildDecisionButtons(
                  context,
                  onApprove: () => roster.reviewAvailabilityRequest(
                    requestId: request.requestId,
                    decision: models.RequestStatus.approved,
                  ),
                  onDeny: () => roster.reviewAvailabilityRequest(
                    requestId: request.requestId,
                    decision: models.RequestStatus.denied,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSwapsTab(BuildContext context, RosterNotifier roster) {
    return Column(
      children: [
        _buildActionHeader(
          context,
          title: 'Swap Marketplace',
          onPrimary: () => _showSwapRequestDialog(context),
          primaryLabel: 'New Swap',
          onSecondary: () => _showQuickSwapDialog(context),
          secondaryLabel: 'Quick Swap',
        ),
        Expanded(
          child: ListView(
            children: [
              ...roster.swapRequests.map((request) {
                return ListTile(
                  leading: Icon(
                    request.status == models.RequestStatus.approved
                        ? Icons.check_circle
                        : request.status == models.RequestStatus.denied
                            ? Icons.cancel
                            : Icons.swap_horiz,
                  ),
                  title: Text(
                    '${request.fromPerson} -> ${request.toPerson ?? 'Open'}',
                  ),
                  subtitle: Text(
                    '${_formatDate(request.date)} ${request.shift ?? ''}',
                  ),
                  trailing: _buildDecisionButtons(
                    context,
                    onApprove: () => roster.respondSwapRequest(
                      requestId: request.requestId,
                      decision: models.RequestStatus.approved,
                    ),
                    onDeny: () => roster.respondSwapRequest(
                      requestId: request.requestId,
                      decision: models.RequestStatus.denied,
                    ),
                  ),
                );
              }),

              if (roster.regularSwaps.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Regular Swaps',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ...roster.regularSwaps.map((swap) {
                  final endLabel = swap.endDate != null
                      ? _formatDate(swap.endDate!)
                      : 'Open';
                  final weekLabel = swap.weekIndex != null
                      ? 'Week ${swap.weekIndex! + 1}'
                      : 'All weeks';
                  return ListTile(
                    leading: const Icon(Icons.repeat),
                    title: Text('${swap.fromPerson} <-> ${swap.toPerson}'),
                    subtitle: Text(
                      '${swap.fromShift} <-> ${swap.toShift} | $weekLabel | ${_formatDate(swap.startDate)} to $endLabel',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Cancel swap',
                      onPressed: () => roster.removeRegularSwap(swap.id),
                    ),
                  );
                }),
              ],
              if (roster.swapDebts.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Swap Debts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ...roster.swapDebts.map((debt) {
                  final outstanding = debt.daysOwed - debt.daysSettled;
                  return ListTile(
                    leading: Icon(
                      debt.isResolved ? Icons.check_circle : Icons.schedule,
                      color: debt.isResolved
                          ? Colors.green
                          : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      '${debt.fromPerson} owes ${debt.toPerson}',
                    ),
                    subtitle: Text(
                      debt.isIgnored
                          ? 'Ignored by volunteer'
                          : 'Owed: ${debt.daysOwed} | Settled: ${debt.daysSettled} | Remaining: $outstanding',
                    ),
                    trailing: debt.isResolved
                        ? const Icon(Icons.done)
                        : TextButton(
                            onPressed: () => _showDebtSettlementDialog(
                              context,
                              debt,
                            ),
                            child: Text(debt.isIgnored ? 'Settle' : 'Settle'),
                          ),
                    onLongPress: debt.isResolved
                        ? null
                        : () => _showIgnoreDebtDialog(context, debt),
                    onTap: debt.isIgnored
                        ? () => _showRestoreDebtDialog(context, debt)
                        : null,
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProposalsTab(BuildContext context, RosterNotifier roster) {
    return Column(
      children: [
        _buildActionHeader(
          context,
          title: 'Change Proposals',
          onPrimary: () => _showProposalDialog(context),
          primaryLabel: 'Propose',
        ),
        Expanded(
          child: ListView.builder(
            itemCount: roster.changeProposals.length,
            itemBuilder: (context, index) {
              final proposal = roster.changeProposals[index];
              return ListTile(
                leading: Icon(
                  proposal.status == models.RequestStatus.approved
                      ? Icons.check_circle
                      : proposal.status == models.RequestStatus.denied
                          ? Icons.cancel
                          : Icons.rate_review,
                ),
                title: Text(proposal.title),
                subtitle: Text(proposal.description),
                trailing: _buildDecisionButtons(
                  context,
                  onApprove: () => roster.resolveChangeProposal(
                    proposalId: proposal.proposalId,
                    decision: models.RequestStatus.approved,
                  ),
                  onDeny: () => roster.resolveChangeProposal(
                    proposalId: proposal.proposalId,
                    decision: models.RequestStatus.denied,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLocksTab(BuildContext context, RosterNotifier roster) {
    return Column(
      children: [
        _buildActionHeader(
          context,
          title: 'Shift Locks',
          onPrimary: () => _showLockDialog(context),
          primaryLabel: 'Lock Shift',
        ),
        Expanded(
          child: ListView.builder(
            itemCount: roster.shiftLocks.length,
            itemBuilder: (context, index) {
              final lock = roster.shiftLocks[index];
              return ListTile(
                leading: const Icon(Icons.lock),
                title: Text(
                  '${_formatDate(lock.date)} · ${lock.shift}',
                ),
                subtitle: Text(lock.reason),
                trailing: IconButton(
                  icon: const Icon(Icons.lock_open),
                  onPressed: () => roster.removeShiftLock(lock.lockId),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAuditTab(BuildContext context, RosterNotifier roster) {
    return ListView.builder(
      itemCount: roster.auditLogs.length,
      itemBuilder: (context, index) {
        final entry = roster.auditLogs[index];
        return ListTile(
          leading: const Icon(Icons.history),
          title: Text(entry.action),
          subtitle: Text(_formatDate(entry.timestamp)),
        );
      },
    );
  }

  Widget _buildActionHeader(
    BuildContext context, {
    required String title,
    required VoidCallback onPrimary,
    required String primaryLabel,
    VoidCallback? onSecondary,
    String? secondaryLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (onSecondary != null && secondaryLabel != null) ...[
            OutlinedButton.icon(
              onPressed: onSecondary,
              icon: const Icon(Icons.swap_horiz),
              label: Text(secondaryLabel),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.icon(
            onPressed: onPrimary,
            icon: const Icon(Icons.add),
            label: Text(primaryLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildDecisionButtons(
    BuildContext context, {
    required VoidCallback onApprove,
    required VoidCallback onDeny,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.check),
          tooltip: 'Approve',
          onPressed: onApprove,
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Deny',
          onPressed: onDeny,
        ),
      ],
    );
  }

  Future<void> _showAvailabilityRequestDialog(BuildContext context) async {
    final roster = ref.read(rosterProvider);
    final notesController = TextEditingController();
    models.AvailabilityType type = models.AvailabilityType.availability;
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Availability Request'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<models.AvailabilityType>(
                  value: type,
                  items: models.AvailabilityType.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => type = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: startDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (date != null) {
                            setState(() => startDate = date);
                          }
                        },
                        child: Text('Start: ${_formatDate(startDate)}'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: endDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (date != null) {
                            setState(() => endDate = date);
                          }
                        },
                        child: Text('End: ${_formatDate(endDate)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await roster.submitAvailabilityRequest(
                type: type,
                startDate: startDate,
                endDate: endDate,
                notes: notesController.text,
              );
              if (mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSwapRequestDialog(BuildContext context) async {
    final roster = ref.read(rosterProvider);
    final fromController = TextEditingController();
    final toController = TextEditingController();
    final shiftController = TextEditingController();
    DateTime date = DateTime.now();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Swap Request'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fromController,
                  decoration: const InputDecoration(labelText: 'From'),
                ),
                TextField(
                  controller: toController,
                  decoration: const InputDecoration(labelText: 'To (optional)'),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setState(() => date = picked);
                    }
                  },
                  child: Text('Date: ${_formatDate(date)}'),
                ),
                TextField(
                  controller: shiftController,
                  decoration:
                      const InputDecoration(labelText: 'Shift (optional)'),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await roster.submitSwapRequest(
                fromPerson: fromController.text,
                toPerson: toController.text.isEmpty
                    ? null
                    : toController.text,
                date: date,
                shift: shiftController.text.isEmpty
                    ? null
                    : shiftController.text,
              );
              if (mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _showQuickSwapDialog(BuildContext context) async {
    final roster = ref.read(rosterProvider);
    final staff = roster.staffMembers.map((s) => s.name).toList();
    if (staff.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least two staff to swap shifts.')),
      );
      return;
    }
    String fromPerson = staff.first;
    String toPerson = staff.length > 1 ? staff[1] : staff.first;
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    bool isRange = false;
    bool recordDebt = true;
    final reasonController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quick Shift Swap'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: fromPerson,
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
                      fromPerson = value;
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Requester'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: toPerson,
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
                      toPerson = value;
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Volunteer'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Range swap'),
                  subtitle: const Text('Swap over a date range'),
                  value: isRange,
                  onChanged: (value) => setState(() => isRange = value),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Start date'),
                  subtitle: Text(_formatDate(startDate)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setState(() => startDate = picked);
                      if (endDate.isBefore(startDate)) {
                        endDate = startDate;
                      }
                    }
                  },
                ),
                if (isRange)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_available),
                    title: const Text('End date'),
                    subtitle: Text(_formatDate(endDate)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endDate,
                        firstDate: startDate,
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setState(() => endDate = picked);
                      }
                    },
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Record owed days'),
                  subtitle: const Text('Track days owed to the volunteer'),
                  value: recordDebt,
                  onChanged: (value) => setState(() => recordDebt = value),
                ),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (fromPerson == toPerson) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Choose two different staff.')),
                );
                return;
              }
              final reason = reasonController.text.trim().isEmpty
                  ? 'Shift swap'
                  : reasonController.text.trim();
              if (isRange) {
                final applied = roster.applySwapRange(
                  fromPerson: fromPerson,
                  toPerson: toPerson,
                  startDate: startDate,
                  endDate: endDate,
                  reason: reason,
                );
                if (recordDebt && applied > 0) {
                  roster.addSwapDebt(
                    fromPerson: fromPerson,
                    toPerson: toPerson,
                    daysOwed: applied,
                    reason: reason,
                  );
                }
              } else {
                roster.applySwapForDate(
                  fromPerson: fromPerson,
                  toPerson: toPerson,
                  date: startDate,
                  reason: reason,
                );
                if (recordDebt) {
                  roster.addSwapDebt(
                    fromPerson: fromPerson,
                    toPerson: toPerson,
                    daysOwed: 1,
                    reason: reason,
                  );
                }
              }
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDebtSettlementDialog(
    BuildContext context,
    models.SwapDebt debt,
  ) async {
    final roster = ref.read(rosterProvider);
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    final remaining = debt.daysOwed - debt.daysSettled;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settle Swap Debt'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${debt.fromPerson} owes ${debt.toPerson} ($remaining day(s) remaining)',
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Start date'),
                  subtitle: Text(_formatDate(startDate)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setState(() => startDate = picked);
                      if (endDate.isBefore(startDate)) {
                        endDate = startDate;
                      }
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_available),
                  title: const Text('End date'),
                  subtitle: Text(_formatDate(endDate)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: endDate,
                      firstDate: startDate,
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setState(() => endDate = picked);
                    }
                  },
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final dates = <DateTime>[];
              for (var date = startDate;
                  !date.isAfter(endDate);
                  date = date.add(const Duration(days: 1))) {
                if (dates.length >= remaining) break;
                dates.add(date);
              }
              if (dates.isEmpty) {
                Navigator.pop(context);
                return;
              }
              roster.settleSwapDebt(
                debtId: debt.id,
                dates: dates,
              );
              Navigator.pop(context);
            },
            child: const Text('Settle'),
          ),
        ],
      ),
    );
  }

  Future<void> _showIgnoreDebtDialog(
    BuildContext context,
    models.SwapDebt debt,
  ) async {
    final roster = ref.read(rosterProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ignore Swap Debt'),
        content: Text(
          'Mark this debt as ignored? ${debt.fromPerson} will no longer owe ${debt.toPerson}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ignore'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      roster.ignoreSwapDebt(debt.id);
    }
  }

  Future<void> _showRestoreDebtDialog(
    BuildContext context,
    models.SwapDebt debt,
  ) async {
    final roster = ref.read(rosterProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Swap Debt'),
        content: Text(
          'Restore this debt so ${debt.fromPerson} can pay back ${debt.toPerson}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      roster.restoreSwapDebt(debt.id);
    }
  }

  Future<void> _showProposalDialog(BuildContext context) async {
    final roster = ref.read(rosterProvider);
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Proposal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Details'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await roster.submitChangeProposal(
                title: titleController.text,
                description: descriptionController.text,
                changes: {
                  'summary': descriptionController.text,
                },
              );
              if (mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLockDialog(BuildContext context) async {
    final roster = ref.read(rosterProvider);
    final shiftController = TextEditingController();
    final personController = TextEditingController();
    final reasonController = TextEditingController();
    DateTime date = DateTime.now();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lock Shift'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: shiftController,
                  decoration: const InputDecoration(labelText: 'Shift'),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setState(() => date = picked);
                    }
                  },
                  child: Text('Date: ${_formatDate(date)}'),
                ),
                TextField(
                  controller: personController,
                  decoration: const InputDecoration(
                    labelText: 'Person (optional)',
                  ),
                ),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await roster.setShiftLock(
                date: date,
                shift: shiftController.text,
                personName:
                    personController.text.isEmpty ? null : personController.text,
                reason: reasonController.text,
              );
              if (mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Lock'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
