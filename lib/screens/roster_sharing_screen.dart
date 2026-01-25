import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import '../aws_service.dart';
import 'login_screen.dart';
import '../home_screen.dart';

class RosterSharingScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const RosterSharingScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<RosterSharingScreen> createState() =>
      _RosterSharingScreenState();
}

class _RosterSharingScreenState extends ConsumerState<RosterSharingScreen> {
  final TextEditingController _rosterNameController = TextEditingController();
  final TextEditingController _rosterIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _joinPasswordController = TextEditingController();
  final TextEditingController _accessCodeController = TextEditingController();
  final TextEditingController _maxUsesController = TextEditingController();
  final TextEditingController _customCodeController = TextEditingController();

  bool _isLoading = false;
  List<Map<String, dynamic>> _userRosters = [];
  String? _lastRosterId;
  String? _selectedRosterId;
  String _shareRole = 'viewer';
  int? _shareExpiresInHours;
  String? _generatedCode;
  List<String> _codeSuggestions = [];

  @override
  void initState() {
    super.initState();
    _loadUserRosters();
  }

  @override
  void dispose() {
    _rosterNameController.dispose();
    _rosterIdController.dispose();
    _passwordController.dispose();
    _joinPasswordController.dispose();
    _accessCodeController.dispose();
    _maxUsesController.dispose();
    _customCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadUserRosters() async {
    setState(() => _isLoading = true);
    try {
      _userRosters = await AwsService.instance.getUserRosters();
      _lastRosterId = await AwsService.instance.getLastRosterId();
      _selectedRosterId =
          AwsService.instance.currentRosterId ?? _lastRosterId;
      if (_selectedRosterId == null && _userRosters.isNotEmpty) {
        final roster = _userRosters.first['rosters'] as Map<String, dynamic>;
        _selectedRosterId = roster['id'] as String?;
      }
    } catch (e) {
      debugPrint('Error loading user rosters: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _createRoster() async {
    if (_rosterNameController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final password =
          _passwordController.text.isEmpty ? null : _passwordController.text;
      final rosterId = await AwsService.instance.createRoster(
        _rosterNameController.text,
        password,
      );
      await AwsService.instance.setLastRosterId(rosterId);
      await ref.read(rosterProvider).loadFromAWS();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Roster created successfully')),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating roster: $e')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _joinRoster() async {
    if (_rosterIdController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final password = _joinPasswordController.text.isEmpty
          ? null
          : _joinPasswordController.text;
      await AwsService.instance
          .joinRoster(_rosterIdController.text, password);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Joined roster successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error joining roster: $e')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _createShareCode() async {
    final rosterId = _selectedRosterId;
    if (rosterId == null || rosterId.isEmpty) return;
    final maxUsesRaw = _maxUsesController.text.trim();
    final maxUses =
        maxUsesRaw.isEmpty ? null : int.tryParse(maxUsesRaw);

    setState(() => _isLoading = true);
    try {
      final response = await AwsService.instance.createShareCode(
        rosterId: rosterId,
        role: _shareRole,
        expiresInHours: _shareExpiresInHours,
        maxUses: maxUses,
        customCode: _customCodeController.text.trim().isEmpty
            ? null
            : _customCodeController.text.trim(),
      );
      setState(() {
        _generatedCode = response['code'] as String?;
        _codeSuggestions = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share code created')),
        );
      }
    } catch (e) {
      final body = _parseErrorBody(e);
      if (body != null && body['suggestions'] is List) {
        setState(() {
          _codeSuggestions = (body['suggestions'] as List)
              .map((item) => item.toString())
              .toList();
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              body?['error']?.toString() ?? 'Error creating share code: $e',
            ),
          ),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _openSharedRoster() async {
    final code = _accessCodeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(rosterProvider).loadSharedRosterByCode(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shared roster opened')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening shared roster: $e')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _switchRoster(String rosterId) async {
    final shouldSwitch = await _confirmRosterSwitch(rosterId);
    if (!shouldSwitch) return;

    setState(() => _isLoading = true);
    try {
      AwsService.instance.currentRosterId = rosterId;
      await AwsService.instance.setLastRosterId(rosterId);
      await ref.read(rosterProvider).loadFromAWS();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Roster switched successfully')),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error switching roster: $e')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<bool> _confirmRosterSwitch(String rosterId) async {
    final currentRosterId = AwsService.instance.currentRosterId;
    if (currentRosterId == null || currentRosterId == rosterId) {
      return true;
    }

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Switch roster?'),
            content: const Text(
              'You are about to leave the current roster. '
              'Make sure your changes are synced before switching.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Switch'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Map<String, dynamic>? _getLastRosterMatch() {
    if (_lastRosterId == null) return null;
    for (final entry in _userRosters) {
      final roster = entry['rosters'] as Map<String, dynamic>;
      if (roster['id'] == _lastRosterId) {
        return entry;
      }
    }
    return null;
  }

  Map<String, dynamic>? _parseErrorBody(Object error) {
    final message = error.toString();
    final start = message.indexOf('{');
    final end = message.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    try {
      final body = message.substring(start, end + 1);
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Roster Sharing'),
          actions: [
            IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: 'Account',
              onPressed: _showAccountActions,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.group), text: 'My Rosters'),
              Tab(icon: Icon(Icons.add), text: 'Create'),
              Tab(icon: Icon(Icons.login), text: 'Join'),
              Tab(icon: Icon(Icons.key), text: 'Access Code'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildMyRostersTab(),
            _buildCreateRosterTab(),
            _buildJoinRosterTab(),
            _buildAccessCodeTab(),
          ],
        ),
      ),
    );
  }

  Future<void> _showAccountActions() async {
    final email = AwsService.instance.userEmail ?? 'Signed in';
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(email),
              subtitle: const Text('Account'),
            ),
            ListTile(
              leading: const Icon(Icons.switch_account_outlined),
              title: const Text('Switch User'),
              onTap: () async {
                Navigator.pop(context);
                await _signOutAndReturn();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign Out'),
              onTap: () async {
                Navigator.pop(context);
                await _signOutAndReturn();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _signOutAndReturn() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign out?'),
            content: const Text('You can sign back in at any time.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await AwsService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _buildMyRostersTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final lastRosterEntry = _getLastRosterMatch();
    final rosterEntries = _userRosters.where((entry) {
      final roster = entry['rosters'] as Map<String, dynamic>;
      return roster['id'] != _lastRosterId;
    }).toList();

    if (_userRosters.isEmpty) {
      return const Center(child: Text('No rosters found yet.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (lastRosterEntry != null)
          _buildLastRosterCard(lastRosterEntry['rosters']
              as Map<String, dynamic>),
        ...rosterEntries.map((entry) {
          final roster = entry['rosters'] as Map<String, dynamic>;
          final memberInfo = entry;
          return _buildRosterCard(roster, memberInfo);
        }).toList(),
      ],
    );
  }

  Widget _buildLastRosterCard(Map<String, dynamic> roster) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: const Icon(Icons.history),
        title: Text('Resume: ${roster['name']}'),
        subtitle: Text('Last used roster'),
        trailing: FilledButton(
          onPressed: () => _switchRoster(roster['id'] as String),
          child: const Text('Open'),
        ),
      ),
    );
  }

  Widget _buildRosterCard(
    Map<String, dynamic> roster,
    Map<String, dynamic> memberInfo,
  ) {
    final isActive = AwsService.instance.currentRosterId == roster['id'];
    final isOwner = memberInfo['role'] == 'owner';
    final passwordProtected = roster['password_protected'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          passwordProtected ? Icons.lock_outline : Icons.calendar_today,
        ),
        title: Text(roster['name'] as String),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${roster['id']}'),
            Text('Role: ${memberInfo['role']}'),
            Text(
              'Created: ${DateTime.parse(roster['created_at'] as String).toString().split(' ')[0]}',
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwner)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Delete roster',
                onPressed: _isLoading
                    ? null
                    : () => _deleteRoster(
                          roster['id'] as String,
                          roster['name'] as String,
                        ),
              ),
            if (isActive)
              const Chip(
                label: Text('Active'),
                backgroundColor: Colors.green,
                labelStyle: TextStyle(color: Colors.white),
              )
            else
              FilledButton(
                onPressed: _isLoading
                    ? null
                    : () => _openRosterFromList(roster),
                child: const Text('Open'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRosterFromList(Map<String, dynamic> roster) async {
    final rosterId = roster['id'] as String;
    final passwordProtected = roster['password_protected'] == true;
    String? password;
    if (passwordProtected) {
      password = await _promptRosterPassword();
      if (password == null || password.isEmpty) return;
    }
    setState(() => _isLoading = true);
    try {
      if (passwordProtected) {
        await AwsService.instance.joinRoster(rosterId, password);
      }
      await _switchRoster(rosterId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening roster: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String?> _promptRosterPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Roster password required'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _deleteRoster(String rosterId, String rosterName) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete roster?'),
            content: Text(
              'This will permanently delete "$rosterName" for all members. '
              'This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _isLoading = true);
    try {
      await AwsService.instance.deleteRoster(rosterId);
      if (AwsService.instance.currentRosterId == rosterId) {
        ref.read(rosterProvider).clearAllData();
      }
      await _loadUserRosters();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Roster deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting roster: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildCreateRosterTab() {
    return Builder(
      builder: (context) {
        final tabController = DefaultTabController.of(context);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_userRosters.isNotEmpty)
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: const Text('Open an existing roster'),
                    subtitle:
                        const Text('View and switch to saved rosters first'),
                    trailing: TextButton(
                      onPressed: () => tabController?.animateTo(0),
                      child: const Text('View'),
                    ),
                  ),
                ),
              TextField(
                controller: _rosterNameController,
                decoration: const InputDecoration(
                  labelText: 'Roster Name',
                  hintText: 'Enter roster name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password (Optional)',
                  hintText: 'Set a password for this roster',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _createRoster,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Create Roster'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Creating a roster will make you the owner. Other users can join using the roster ID and password.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildJoinRosterTab() {
    return Builder(
      builder: (context) {
        final tabController = DefaultTabController.of(context);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_userRosters.isNotEmpty)
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: const Text('Open an existing roster'),
                    subtitle:
                        const Text('View and switch to saved rosters first'),
                    trailing: TextButton(
                      onPressed: () => tabController?.animateTo(0),
                      child: const Text('View'),
                    ),
                  ),
                ),
              TextField(
                controller: _rosterIdController,
                decoration: const InputDecoration(
                  labelText: 'Roster ID',
                  hintText: 'Enter roster ID to join',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _joinPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Password (if required)',
                  hintText: 'Enter roster password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _joinRoster,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Join Roster'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ask the roster owner for the roster ID and password to join their roster.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccessCodeTab() {
    final rosterOptions = _userRosters
        .map((entry) => entry['rosters'] as Map<String, dynamic>)
        .toList();
    final canGenerate = rosterOptions.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: ListTile(
            leading: const Icon(Icons.key_rounded),
            title: const Text('Share roster access'),
            subtitle: const Text(
              'Create a unique code for read-only access. Guests can request leave but cannot edit shifts.',
            ),
          ),
        ),
        Text(
          'Generate Access Code',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (canGenerate)
          DropdownButtonFormField<String>(
            value: _selectedRosterId,
            items: rosterOptions
                .map(
                  (roster) => DropdownMenuItem<String>(
                    value: roster['id'] as String,
                    child: Text(roster['name'] as String),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedRosterId = value),
            decoration: const InputDecoration(
              labelText: 'Roster',
              border: OutlineInputBorder(),
            ),
          )
        else
          Text(
            'No rosters available to share yet.',
            style: GoogleFonts.inter(color: Colors.grey[600]),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _shareRole,
          items: const [
            DropdownMenuItem(value: 'viewer', child: Text('Viewer (read-only)')),
            DropdownMenuItem(value: 'editor', child: Text('Editor (signed-in)')),
          ],
          onChanged: (value) => setState(() {
            if (value != null) _shareRole = value;
          }),
          decoration: const InputDecoration(
            labelText: 'Access level',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          value: _shareExpiresInHours,
          items: const [
            DropdownMenuItem(value: null, child: Text('No expiry')),
            DropdownMenuItem(value: 24, child: Text('Expires in 24 hours')),
            DropdownMenuItem(value: 168, child: Text('Expires in 7 days')),
            DropdownMenuItem(value: 720, child: Text('Expires in 30 days')),
          ],
          onChanged: (value) => setState(() => _shareExpiresInHours = value),
          decoration: const InputDecoration(
            labelText: 'Expiry',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _maxUsesController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Max uses (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _customCodeController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Custom code (optional)',
            hintText: 'A-Z and 2-9, 6-12 characters',
            border: OutlineInputBorder(),
          ),
        ),
        if (_codeSuggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Available suggestions',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _codeSuggestions
                .map(
                  (code) => ActionChip(
                    label: Text(code),
                    onPressed: () {
                      setState(() {
                        _customCodeController.text = code;
                        _codeSuggestions = [];
                      });
                    },
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _isLoading || !canGenerate ? null : _createShareCode,
          child: _isLoading
              ? const CircularProgressIndicator()
              : const Text('Generate Code'),
        ),
        if (_generatedCode != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.key),
              title: Text('Access Code: ${_generatedCode!}'),
              subtitle: const Text('Share this code for roster access'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Open Shared Roster',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _accessCodeController,
          decoration: const InputDecoration(
            labelText: 'Access code',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _isLoading ? null : _openSharedRoster,
          child: _isLoading
              ? const CircularProgressIndicator()
              : const Text('Open Roster'),
        ),
        const SizedBox(height: 12),
        Text(
          'Editors must be signed in. Guests always open read-only.',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
