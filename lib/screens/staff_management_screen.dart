import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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

  @override
  void dispose() {
    _addStaffController.dispose();
    for (final controller in _editControllers.values) {
      controller.dispose();
    }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddStaffDialog,
            tooltip: 'Add Staff Member',
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary cards
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

          // Staff list
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddStaffDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Staff'),
      ),
    );
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
