import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_controller.dart';
import 'providers.dart';
import 'roster_catalog.dart';
import 'supabase_service.dart';
import 'models.dart';

class RosterSelectionScreen extends ConsumerStatefulWidget {
  const RosterSelectionScreen({super.key});

  @override
  ConsumerState<RosterSelectionScreen> createState() =>
      _RosterSelectionScreenState();
}

class _RosterSelectionScreenState extends ConsumerState<RosterSelectionScreen> {
  bool _loadingInvites = false;
  List<RosterInvite> _invites = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authSession = ref.read(authProvider).session;
      if (authSession != null) {
        ref
            .read(rosterCatalogProvider.notifier)
            .loadCatalog(authSession.userId, isGuest: authSession.isGuest);
        if (!authSession.isGuest) {
          _loadInvites();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authSession = ref.watch(authProvider).session;
    if (authSession == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to continue')),
      );
    }

    final catalog = ref.watch(rosterCatalogProvider);
    final catalogController = ref.read(rosterCatalogProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Roster'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).signOut(),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: catalog.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!authSession.isGuest) _buildInvitesSection(),
                  Text(
                    authSession.isGuest
                        ? 'Guest rosters'
                        : 'Your rosters',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: catalog.rosters.isEmpty
                        ? const Center(
                            child: Text('No rosters yet. Create one to start.'),
                          )
                        : ListView.separated(
                            itemCount: catalog.rosters.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final roster = catalog.rosters[index];
                              return ListTile(
                                title: Text(roster.displayName),
                                subtitle: Text(
                                  'Updated ${roster.updatedAt.toLocal().toString().substring(0, 16)}',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _confirmDelete(
                                    context,
                                    authSession.userId,
                                    authSession.isGuest,
                                    roster.id,
                                    roster.source,
                                  ),
                                ),
                                onTap: () async {
                                  await catalogController.setActiveRoster(
                                    authSession.userId,
                                    roster.id,
                                  );
                                  await ref
                                      .read(rosterProvider.notifier)
                                      .setActiveRoster(
                                        roster,
                                        authSession.userId,
                                      );
                                  if (mounted &&
                                      Navigator.of(context).canPop()) {
                                    Navigator.of(context).pop();
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateRosterDialog(
          context,
          authSession.userId,
          authSession.isGuest,
        ),
        icon: const Icon(Icons.add),
        label: const Text('New Roster'),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String ownerId, bool isGuest,
      String rosterId, String rosterSource) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text(rosterSource == 'cloud' ? 'Leave roster' : 'Delete roster'),
        content: Text(rosterSource == 'cloud'
            ? 'You will lose access to this roster.'
            : 'This removes the roster from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(rosterCatalogProvider.notifier)
                  .removeRoster(ownerId, rosterId, isGuest);
              final updatedRoster =
                  ref.read(rosterCatalogProvider).activeRoster;
              if (updatedRoster != null) {
                await ref
                    .read(rosterProvider.notifier)
                    .setActiveRoster(updatedRoster, ownerId);
              }
              if (mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showCreateRosterDialog(
      BuildContext context, String ownerId, bool isGuest) {
    final companyController = TextEditingController();
    final departmentController = TextEditingController();
    final teamController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create roster'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: companyController,
                decoration: const InputDecoration(
                  labelText: 'Company name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: departmentController,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: teamController,
                decoration: const InputDecoration(
                  labelText: 'Team (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (companyController.text.trim().isEmpty ||
                  departmentController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Company and department are required.'),
                  ),
                );
                return;
              }
              final roster = await ref
                  .read(rosterCatalogProvider.notifier)
                  .addRoster(
                    ownerId: ownerId,
                    companyName: companyController.text,
                    departmentName: departmentController.text,
                    teamName: teamController.text,
                    isGuest: isGuest,
                  );
              await ref
                  .read(rosterProvider.notifier)
                  .setActiveRoster(roster, ownerId);
              if (mounted) Navigator.of(ctx).pop();
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Widget _buildInvitesSection() {
    if (_loadingInvites) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: LinearProgressIndicator(),
      );
    }
    if (_invites.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pending invites',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._invites.map(
              (invite) => ListTile(
                title: Text('Roster invite (${invite.role})'),
                subtitle: Text(invite.rosterId),
                trailing: ElevatedButton(
                  onPressed: () => _acceptInvite(invite),
                  child: const Text('Accept'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadInvites() async {
    setState(() => _loadingInvites = true);
    try {
      final api = SupabaseRosterApi();
      final invites = await api.fetchInvitesForUser();
      if (mounted) {
        setState(() => _invites = invites);
      }
    } finally {
      if (mounted) setState(() => _loadingInvites = false);
    }
  }

  Future<void> _acceptInvite(RosterInvite invite) async {
    final authSession = ref.read(authProvider).session;
    if (authSession == null) return;
    final api = SupabaseRosterApi();
    await api.acceptInvite(invite.id);
    await ref
        .read(rosterCatalogProvider.notifier)
        .loadCatalog(authSession.userId, isGuest: authSession.isGuest);
    await _loadInvites();
  }
}
