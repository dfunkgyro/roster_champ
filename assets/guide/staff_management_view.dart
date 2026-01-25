import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'roster_catalog.dart';
import 'auth_controller.dart';
import 'supabase_service.dart';
import 'models.dart';

class StaffManagementView extends ConsumerStatefulWidget {
  const StaffManagementView({super.key});

  @override
  ConsumerState<StaffManagementView> createState() =>
      _StaffManagementViewState();
}

class _StaffManagementViewState extends ConsumerState<StaffManagementView> {
  String _company = '';
  String _department = '';
  String _team = '';
  String? _rosterId;
  bool _loadingMembers = false;
  List<RosterMember> _members = [];
  String _inviteRole = 'staff';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMembers());
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(rosterCatalogProvider);
    final roster = catalog.activeRoster;
    final rosterNotifier = ref.watch(rosterProvider);
    final authSession = ref.watch(authProvider).session;

    if (roster != null && roster.id != _rosterId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _rosterId = roster.id;
          _company = roster.companyName;
          _department = roster.departmentName;
          _team = roster.teamName;
        });
        _loadMembers();
      });
    }

    if (roster == null || authSession == null) {
      return const Center(child: Text('Select a roster to manage staff.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Roster Details',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextFormField(
                  key: ValueKey('company_${_rosterId ?? ''}'),
                  decoration: const InputDecoration(
                    labelText: 'Company name',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _company,
                  onChanged: (value) => _company = value,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: ValueKey('department_${_rosterId ?? ''}'),
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _department,
                  onChanged: (value) => _department = value,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: ValueKey('team_${_rosterId ?? ''}'),
                  decoration: const InputDecoration(
                    labelText: 'Team (optional)',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _team,
                  onChanged: (value) => _team = value,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () async {
                      final updated = roster.copyWith(
                        companyName: _company,
                        departmentName: _department,
                        teamName: _team,
                        updatedAt: DateTime.now(),
                      );
                      await ref.read(rosterCatalogProvider.notifier).updateRoster(
                            authSession.userId,
                            updated,
                            authSession.isGuest,
                          );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Roster updated')),
                        );
                      }
                    },
                    child: const Text('Save details'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (roster.source == 'cloud') ...[
          _buildAccessSection(context, roster),
          const SizedBox(height: 24),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Staff Management',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddStaffDialog(context),
              icon: const Icon(Icons.person_add),
              label: const Text('Add staff'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildBulkEntitlementCard(context),
        const SizedBox(height: 8),
        if (rosterNotifier.staffMembers.isEmpty)
          const Center(child: Text('No staff members yet.'))
        else
          ...rosterNotifier.staffMembers.asMap().entries.map((entry) {
            final index = entry.key;
            final staff = entry.value;
            return Card(
              child: ListTile(
                title: Text(staff.name),
                subtitle: Text(
                  staff.isActive
                      ? 'Active • ${staff.leaveBalance.toStringAsFixed(1)} days leave'
                      : 'Inactive',
                ),
                leading: Switch(
                  value: staff.isActive,
                  onChanged: (_) =>
                      rosterNotifier.toggleStaffStatus(index),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () =>
                          _showEditStaffDialog(context, staff.name, index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          rosterNotifier.removeStaffMember(staff.name),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildAccessSection(BuildContext context, RosterMeta roster) {
    final canInvite = roster.role == 'admin' || roster.role == 'manager';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Roster Access',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (_loadingMembers)
          const LinearProgressIndicator()
        else if (_members.isEmpty)
          const Text('No members found.')
        else
          ..._members.map(
            (member) => ListTile(
              leading: const Icon(Icons.verified_user),
              title: Text(member.userId),
              subtitle: Text('${member.role} • ${member.status}'),
            ),
          ),
        if (canInvite) ...[
          const Divider(),
          _buildInviteCard(context, roster),
        ],
      ],
    );
  }

  Widget _buildBulkEntitlementCard(BuildContext context) {
    final controller = TextEditingController(text: '31');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Annual Leave Entitlement',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Set entitlement for all staff',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () {
                  final value = double.tryParse(controller.text.trim());
                  if (value == null) return;
                  ref
                      .read(rosterProvider.notifier)
                      .updateAllLeaveEntitlements(value);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Entitlements updated')),
                  );
                },
                child: const Text('Apply to all'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteCard(BuildContext context, RosterMeta roster) {
    final emailController = TextEditingController();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invite member',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _inviteRole,
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(value: 'manager', child: Text('Manager')),
                DropdownMenuItem(value: 'staff', child: Text('Staff')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _inviteRole = value);
                }
              },
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () async {
                  final email = emailController.text.trim();
                  if (email.isEmpty) return;
                  final api = SupabaseRosterApi();
                  await api.inviteMember(
                    rosterId: roster.id,
                    email: email,
                    role: _inviteRole,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invite sent')),
                    );
                  }
                },
                child: const Text('Send invite'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadMembers() async {
    final roster = ref.read(rosterCatalogProvider).activeRoster;
    if (roster == null || roster.source != 'cloud') return;
    setState(() => _loadingMembers = true);
    try {
      final api = SupabaseRosterApi();
      final members = await api.fetchMembers(roster.id);
      if (mounted) {
        setState(() => _members = members);
      }
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  void _showAddStaffDialog(BuildContext context) {
    final nameController = TextEditingController();
    final entitlementController = TextEditingController(text: '31');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add staff member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: entitlementController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Annual leave entitlement',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final entitlement =
                  double.tryParse(entitlementController.text) ?? 25.0;
              ref
                  .read(rosterProvider.notifier)
                  .addStaffMember(nameController.text, entitlement);
              Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(
      BuildContext context, String currentName, int index) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename staff member'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ref
                  .read(rosterProvider.notifier)
                  .updateStaffName(index, controller.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showEditStaffDialog(
      BuildContext context, String currentName, int index) {
    final rosterNotifier = ref.read(rosterProvider.notifier);
    final staff = rosterNotifier.staffMembers[index];
    final nameController = TextEditingController(text: staff.name);
    final entitlementController = TextEditingController(
      text: staff.annualLeaveEntitlement.toStringAsFixed(1),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit staff details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: entitlementController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Annual leave entitlement',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty && newName != currentName) {
                rosterNotifier.updateStaffName(index, newName);
              }
              final entitlement =
                  double.tryParse(entitlementController.text.trim());
              if (entitlement != null) {
                rosterNotifier.updateLeaveEntitlement(
                  newName.isNotEmpty ? newName : currentName,
                  entitlement,
                );
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
