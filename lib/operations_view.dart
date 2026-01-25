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
        ),
        Expanded(
          child: ListView.builder(
            itemCount: roster.swapRequests.length,
            itemBuilder: (context, index) {
              final request = roster.swapRequests[index];
              return ListTile(
                leading: Icon(
                  request.status == models.RequestStatus.approved
                      ? Icons.check_circle
                      : request.status == models.RequestStatus.denied
                          ? Icons.cancel
                          : Icons.swap_horiz,
                ),
                title: Text(
                  '${request.fromPerson} → ${request.toPerson ?? 'Open'}',
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
            },
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
  }) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
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
