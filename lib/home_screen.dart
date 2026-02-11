import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'roster_view.dart';
import 'stats_view.dart';
import 'events_view.dart';
import 'ai_suggestions_view.dart';
import 'settings_view.dart';
import 'operations_view.dart';
import 'roster_generator_view.dart';
import 'activity_log_view.dart';
import 'system_view.dart';
import 'analytics_view.dart';
import 'screens/staff_management_screen.dart';
import 'screens/pattern_editor_screen.dart';
import 'screens/login_screen.dart';
import 'screens/roster_sharing_screen.dart';
import 'import_roster_screen.dart';
import 'providers.dart';
import 'models.dart' as models;
import 'dialogs.dart';
import 'aws_service.dart';
import 'utils/error_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roster_champ/safe_text_field.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final bool isGuestMode;
  final VoidCallback? onExitGuestMode;

  const HomeScreen({
    super.key,
    this.isGuestMode = false,
    this.onExitGuestMode,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;
  bool _didInitialRosterSnap = false;
  bool _chromeHidden = false;
  models.AppLayoutStyle? _lastLayoutStyle;
  final GlobalKey<RosterViewState> _rosterViewKey =
      GlobalKey<RosterViewState>();
  final TextEditingController _commandController = TextEditingController();
  Timer? _autoSyncTimer;
  bool _requestedMicPermission = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 10, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentIndex = _tabController.index;
        });
        if (_tabController.index == 0) {
          _rosterViewKey.currentState?.snapToTodayOnFocus();
        }
      }
    });
    _configureAutoSync(ref.read(settingsProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowOnboarding();
      _requestMicPermissionOnce();
      if (!_didInitialRosterSnap) {
        _rosterViewKey.currentState?.snapToTodayOnFocus();
        _didInitialRosterSnap = true;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commandController.dispose();
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestMicPermissionOnce() async {
    if (_requestedMicPermission) return;
    _requestedMicPermission = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyAsked = prefs.getBool('micPermissionAsked') ?? false;
      if (alreadyAsked) return;
      final status = await Permission.microphone.status;
      if (!status.isGranted) {
        await Permission.microphone.request();
      }
      await prefs.setBool('micPermissionAsked', true);
    } catch (_) {
      // Ignore permission errors; voice can still be enabled later.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<models.AppSettings>(settingsProvider, (_, next) {
      _configureAutoSync(next);
    });
    final roster = ref.watch(rosterProvider);
    final settings = ref.watch(settingsProvider);

    if (_lastLayoutStyle != settings.layoutStyle) {
      final shouldHide = settings.layoutStyle ==
              models.AppLayoutStyle.sophisticated ||
          settings.layoutStyle == models.AppLayoutStyle.ambience;
      _chromeHidden = shouldHide;
      _lastLayoutStyle = settings.layoutStyle;
    }

    final hideChrome = _chromeHidden &&
        (settings.layoutStyle == models.AppLayoutStyle.sophisticated ||
            settings.layoutStyle == models.AppLayoutStyle.ambience);

    return Scaffold(
      appBar: hideChrome
          ? null
          : AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Text(
              'Roster Champion',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (widget.isGuestMode) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange),
                ),
                child: Text(
                  'Guest',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[700],
                  ),
                ),
              ),
            ],
            if (roster.readOnly) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue),
                ),
                child: Text(
                  'Shared View',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Connection status indicator removed in favor of activity log
          if (widget.isGuestMode)
            TextButton.icon(
              onPressed: widget.onExitGuestMode,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.groups),
                onPressed: _showPresenceList,
                tooltip: 'Live Presence',
              ),
              if (roster.presenceEntries.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${roster.presenceEntries.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          if (roster.pendingSync.isNotEmpty)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.cloud_upload),
                  onPressed: _showOfflineQueue,
                  tooltip: 'Offline Queue',
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${roster.pendingSync.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: _showAccountActions,
            tooltip: 'Account',
          ),
          // Sync button (only show if not guest mode)
          if (!widget.isGuestMode && !roster.readOnly)
            IconButton(
              icon: const Icon(Icons.sync_rounded),
              onPressed: _syncData,
              tooltip: 'Sync Data',
            ),
          // More menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              switch (value) {
                case 'signup':
                case 'exit_guest':
                  await _showSignUpPrompt();
                  break;
                case 'staff':
                  await _navigateToStaffManagement();
                  break;
                case 'pattern':
                  await _navigateToPatternEditor();
                  break;
                case 'activity_log':
                  await _openActivityLog();
                  break;
                case 'bulk_edit':
                  await _showBulkEditDialog();
                  break;
                case 'switch_roster':
                  await _openRosterSwitcher();
                  break;
                case 'initialize':
                  await _showInitializeDialog();
                  break;
                case 'export':
                  await _exportData();
                  break;
                case 'export_csv':
                  await _exportRosterCsv();
                  break;
                case 'export_pdf':
                  await _exportRosterPdf();
                  break;
                case 'export_png':
                  await _exportRosterPng();
                  break;
                case 'export_jpg':
                  await _exportRosterJpg();
                  break;
                case 'export_ics':
                  await _exportCalendarIcs();
                  break;
                case 'export_cloud':
                  await _exportToCloud();
                  break;
                case 'import':
                  await _importData();
                  break;
                case 'clear':
                  await _clearData();
                  break;
                case 'logout':
                  await _logout();
                  break;
                case 'account':
                  _tabController.animateTo(6);
                  break;
                case 'back_start':
                  widget.onExitGuestMode?.call();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (widget.isGuestMode) ...[
                const PopupMenuItem(
                  value: 'signup',
                  child: ListTile(
                    leading: Icon(Icons.person_add),
                    title: Text('Create Account'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
              ],
              if (!roster.readOnly)
                const PopupMenuItem(
                  value: 'staff',
                  child: ListTile(
                    leading: Icon(Icons.people_alt_rounded),
                    title: Text('Manage Staff'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (!roster.readOnly)
                const PopupMenuItem(
                  value: 'pattern',
                  child: ListTile(
                    leading: Icon(Icons.pattern_rounded),
                    title: Text('Edit Pattern'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'activity_log',
                child: ListTile(
                  leading: Icon(Icons.history_rounded),
                  title: Text('Activity Log'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!roster.readOnly)
                const PopupMenuItem(
                  value: 'bulk_edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_calendar_outlined),
                    title: Text('Bulk Edit Shifts'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuDivider(),
              if (!widget.isGuestMode) ...[
                const PopupMenuItem(
                  value: 'switch_roster',
                  child: ListTile(
                    leading: Icon(Icons.folder_open_rounded),
                    title: Text('Switch Roster'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              const PopupMenuItem(
                value: 'account',
                child: ListTile(
                  leading: Icon(Icons.manage_accounts),
                  title: Text('Account'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!roster.readOnly)
                const PopupMenuItem(
                  value: 'initialize',
                  child: ListTile(
                    leading: Icon(Icons.restart_alt_rounded),
                    title: Text('Reinitialize Roster'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.upload_rounded),
                  title: Text('Export Data'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!widget.isGuestMode && !roster.readOnly)
                const PopupMenuItem(
                  value: 'export_cloud',
                  child: ListTile(
                    leading: Icon(Icons.cloud_upload_rounded),
                    title: Text('Export to Cloud'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'export_csv',
                child: ListTile(
                  leading: Icon(Icons.table_view_rounded),
                  title: Text('Export Roster CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_pdf',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('Export Roster PDF'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_png',
                child: ListTile(
                  leading: Icon(Icons.image_outlined),
                  title: Text('Export Roster PNG'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_jpg',
                child: ListTile(
                  leading: Icon(Icons.image_rounded),
                  title: Text('Export Roster JPG'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_ics',
                child: ListTile(
                  leading: Icon(Icons.calendar_month_rounded),
                  title: Text('Export Calendar (ICS)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!roster.readOnly)
                const PopupMenuItem(
                  value: 'import',
                  child: ListTile(
                    leading: Icon(Icons.download_rounded),
                    title: Text('Import Data'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuDivider(),
              if (widget.isGuestMode) ...[
                const PopupMenuItem(
                  value: 'back_start',
                  child: ListTile(
                    leading: Icon(Icons.arrow_back),
                    title: Text('Back to Start'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'exit_guest',
                  child: ListTile(
                    leading: Icon(Icons.login),
                    title: Text('Sign In / Create Account'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ] else ...[
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout_rounded),
                    title: Text('Logout'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              if (!roster.readOnly)
                const PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    leading:
                        Icon(Icons.delete_forever_rounded, color: Colors.red),
                    title: Text('Clear All Data',
                        style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.calendar_view_month_rounded), text: 'Roster'),
              Tab(icon: Icon(Icons.psychology_rounded), text: 'AI Insights'),
              Tab(icon: Icon(Icons.workspaces_rounded), text: 'Operations'),
              Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Stats'),
              Tab(icon: Icon(Icons.people_alt_rounded), text: 'Staff'),
              Tab(icon: Icon(Icons.event_rounded), text: 'Events'),
              Tab(icon: Icon(Icons.settings_rounded), text: 'Settings'),
              Tab(icon: Icon(Icons.analytics_rounded), text: 'Analytics'),
              Tab(icon: Icon(Icons.memory_rounded), text: 'System'),
              Tab(icon: Icon(Icons.search_rounded), text: 'Commands'),
            ],
          ),
        ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              RosterView(key: _rosterViewKey),
              const AiSuggestionsView(),
              const OperationsView(),
              const StatsView(),
              const StaffManagementScreen(),
              const EventsView(),
              const SettingsView(),
              const AnalyticsView(),
              const SystemView(),
              _CommandCenterView(
                actions: _buildCommandActions(roster.readOnly),
                onOpenPalette: _showCommandPalette,
              ),
            ],
          ),
          if (settings.layoutStyle == models.AppLayoutStyle.sophisticated ||
              settings.layoutStyle == models.AppLayoutStyle.ambience)
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: FloatingActionButton.small(
                  heroTag: 'chromeToggle',
                  onPressed: () {
                    setState(() => _chromeHidden = !_chromeHidden);
                  },
                  child: Icon(
                    _chromeHidden ? Icons.menu_open : Icons.menu,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  Widget? _buildFAB(BuildContext context) {
    return null;
  }

  Future<void> _syncData() async {
    if (widget.isGuestMode) {
      _showSignUpPrompt();
      return;
    }
    if (ref.read(rosterProvider).readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read-only roster cannot be synced')),
      );
      return;
    }

    try {
      final roster = ref.read(rosterProvider);
      final conflict = await roster.checkForSyncConflict();
      if (conflict != null && mounted) {
        final choice = await _showConflictResolutionDialog(
          context,
          roster.toJson(),
          conflict.remoteData,
          conflict.lastModifiedBy,
        );
        if (choice == 'remote') {
          roster.applyRemoteData(
            conflict.remoteData,
            conflict.remoteVersion,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Loaded cloud version'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      await roster.syncToAWS();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data synced successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, e);
      }
    }
  }

  void _configureAutoSync(models.AppSettings settings) {
    _autoSyncTimer?.cancel();
    if (widget.isGuestMode ||
        !settings.autoSync ||
        !AwsService.instance.isConfigured ||
        ref.read(rosterProvider).readOnly) {
      return;
    }

    // Auto-sync is intentionally throttled for responsiveness.
    final interval = Duration(minutes: settings.syncInterval);
    _autoSyncTimer = Timer.periodic(interval, (_) {
      ref.read(rosterProvider).autoSyncToAWS();
    });
  }

  Future<void> _maybeShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('onboarding_complete') ?? false;
    if (completed || !mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Welcome to Roster Champion'),
        content: const Text(
          'Quick start:\n'
          '1) Add staff and set preferences\n'
          '2) Edit the roster pattern\n'
          '3) Use Operations to manage approvals and swaps\n'
          '4) Review AI suggestions and health score',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              await prefs.setBool('onboarding_complete', true);
              if (mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Get Started'),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToStaffManagement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StaffManagementScreen()),
    );
  }

  Future<void> _navigateToPatternEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PatternEditorScreen()),
    );
  }

  Future<void> _openRosterSwitcher() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RosterSharingScreen(initialTabIndex: 0),
      ),
    );
  }

  Future<void> _showInitializeDialog() async {
    final roster = ref.read(rosterProvider);
    if (roster.hasUnsavedChanges) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reinitialize roster?'),
          content: const Text(
            'This will reset the roster and replace your current data. '
            'Consider exporting a backup first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Reinitialize'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await showDialog(
      context: context,
      builder: (context) => InitializeRosterDialog(
        onInitialize: (cycle, people) {
          ref.read(rosterProvider).initializeRoster(cycle, people);
        },
      ),
    );
  }

  Future<void> _showCommandPalette() async {
    final actions = _buildCommandActions(ref.read(rosterProvider).readOnly);
    _commandController.clear();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final query = _commandController.text.toLowerCase();
          final filtered = actions.where((action) {
            return action.label.toLowerCase().contains(query) ||
                action.keywords.any((k) => k.contains(query));
          }).toList();

          return AlertDialog(
            title: const Text('Command Palette'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SafeTextField(
                    controller: _commandController,
                    decoration: const InputDecoration(
                      hintText: 'Type a command...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final action = filtered[index];
                        return ListTile(
                          leading: Icon(action.icon),
                          title: Text(action.label),
                          enabled: action.enabled,
                          onTap: action.enabled
                              ? () {
                                  Navigator.pop(context);
                                  action.onExecute();
                                }
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<_CommandAction> _buildCommandActions(bool readOnly) {
    return [
      _CommandAction(
        label: 'Open Roster',
        icon: Icons.calendar_view_month_rounded,
        keywords: const ['roster', 'calendar', 'schedule'],
        onExecute: () => _tabController.animateTo(0),
      ),
      _CommandAction(
        label: 'AI Insights',
        icon: Icons.psychology_rounded,
        keywords: const ['ai', 'insights', 'suggestions'],
        onExecute: () => _tabController.animateTo(1),
      ),
      _CommandAction(
        label: 'Open Operations',
        icon: Icons.workspaces_rounded,
        keywords: const ['operations', 'approvals', 'conflicts'],
        onExecute: () => _tabController.animateTo(2),
      ),
      _CommandAction(
        label: 'Open Stats',
        icon: Icons.bar_chart_rounded,
        keywords: const ['stats', 'kpi', 'metrics'],
        onExecute: () => _tabController.animateTo(3),
      ),
      _CommandAction(
        label: 'Open Staff',
        icon: Icons.people_alt_rounded,
        keywords: const ['staff', 'team', 'people'],
        onExecute: () => _tabController.animateTo(4),
      ),
      _CommandAction(
        label: 'Open Events',
        icon: Icons.event_rounded,
        keywords: const ['events', 'holiday', 'calendar'],
        onExecute: () => _tabController.animateTo(5),
      ),
      _CommandAction(
        label: 'Open Settings',
        icon: Icons.settings_rounded,
        keywords: const ['settings', 'preferences'],
        onExecute: () => _tabController.animateTo(6),
      ),
      _CommandAction(
        label: 'Manage Staff',
        icon: Icons.people_alt_rounded,
        keywords: const ['staff', 'people', 'team'],
        onExecute: _navigateToStaffManagement,
        enabled: !readOnly,
      ),
      _CommandAction(
        label: 'Edit Pattern',
        icon: Icons.pattern_rounded,
        keywords: const ['pattern', 'cycle', 'shift'],
        onExecute: _navigateToPatternEditor,
        enabled: !readOnly,
      ),
      _CommandAction(
        label: 'Bulk Edit Shifts',
        icon: Icons.edit_calendar_outlined,
        keywords: const ['bulk', 'override', 'shifts'],
        onExecute: _showBulkEditDialog,
        enabled: !readOnly,
      ),
      _CommandAction(
        label: 'Activity Log',
        icon: Icons.history_rounded,
        keywords: const ['activity', 'errors', 'log'],
        onExecute: _openActivityLog,
      ),
      _CommandAction(
        label: 'Roster Sharing',
        icon: Icons.folder_open_rounded,
        keywords: const ['share', 'roster', 'access'],
        onExecute: _openRosterSwitcher,
        enabled: !widget.isGuestMode,
      ),
      _CommandAction(
        label: 'Live Presence',
        icon: Icons.groups,
        keywords: const ['presence', 'collaborators', 'live'],
        onExecute: _showPresenceList,
      ),
      _CommandAction(
        label: 'Offline Queue',
        icon: Icons.cloud_upload,
        keywords: const ['offline', 'queue', 'pending'],
        onExecute: _showOfflineQueue,
      ),
      _CommandAction(
        label: 'Analytics',
        icon: Icons.analytics_rounded,
        keywords: const ['analytics', 'metrics', 'insights'],
        onExecute: () => _tabController.animateTo(7),
      ),
      _CommandAction(
        label: 'System Status',
        icon: Icons.memory_rounded,
        keywords: const ['system', 'status', 'aws'],
        onExecute: () => _tabController.animateTo(8),
      ),
      _CommandAction(
        label: 'Auto Roster Generator',
        icon: Icons.auto_awesome,
        keywords: const ['auto', 'generator', 'pattern'],
        onExecute: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const RosterGeneratorView(),
            ),
          );
        },
      ),
      _CommandAction(
        label: 'Add Event',
        icon: Icons.event_rounded,
        keywords: const ['event', 'holiday'],
        onExecute: _showAddEventDialog,
      ),
      _CommandAction(
        label: 'Import Roster',
        icon: Icons.upload_file_rounded,
        keywords: const ['import', 'csv'],
        onExecute: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ImportRosterScreen()),
          );
        },
      ),
      _CommandAction(
        label: 'Initialize Roster',
        icon: Icons.restart_alt_rounded,
        keywords: const ['initialize', 'reset'],
        onExecute: _showInitializeDialog,
        enabled: !readOnly,
      ),
      _CommandAction(
        label: 'Switch Roster',
        icon: Icons.folder_open_rounded,
        keywords: const ['switch', 'roster'],
        onExecute: _openRosterSwitcher,
        enabled: !widget.isGuestMode,
      ),
      _CommandAction(
        label: 'Sync Data',
        icon: Icons.sync_rounded,
        keywords: const ['sync', 'cloud'],
        onExecute: _syncData,
        enabled: !widget.isGuestMode && !readOnly,
      ),
      _CommandAction(
        label: 'Export Roster CSV',
        icon: Icons.table_view_rounded,
        keywords: const ['export', 'csv'],
        onExecute: _exportRosterCsv,
      ),
      _CommandAction(
        label: 'Export Roster PDF',
        icon: Icons.picture_as_pdf_outlined,
        keywords: const ['export', 'pdf'],
        onExecute: _exportRosterPdf,
      ),
      _CommandAction(
        label: 'Export Roster PNG',
        icon: Icons.image_outlined,
        keywords: const ['export', 'png', 'image'],
        onExecute: _exportRosterPng,
      ),
      _CommandAction(
        label: 'Export Roster JPG',
        icon: Icons.image_rounded,
        keywords: const ['export', 'jpg', 'jpeg', 'image'],
        onExecute: _exportRosterJpg,
      ),
      _CommandAction(
        label: 'Export Calendar (ICS)',
        icon: Icons.calendar_month_rounded,
        keywords: const ['export', 'ics', 'calendar'],
        onExecute: _exportCalendarIcs,
      ),
      _CommandAction(
        label: 'Export to Cloud',
        icon: Icons.cloud_upload_rounded,
        keywords: const ['export', 'cloud'],
        onExecute: _exportToCloud,
        enabled: !widget.isGuestMode && !readOnly,
      ),
      _CommandAction(
        label: 'Export Data',
        icon: Icons.upload_rounded,
        keywords: const ['export', 'backup'],
        onExecute: _exportData,
      ),
      _CommandAction(
        label: 'Import Data',
        icon: Icons.download_rounded,
        keywords: const ['import', 'restore'],
        onExecute: _importData,
      ),
      _CommandAction(
        label: 'Account Settings',
        icon: Icons.manage_accounts,
        keywords: const ['account', 'profile'],
        onExecute: () => _tabController.animateTo(6),
        enabled: !widget.isGuestMode,
      ),
      _CommandAction(
        label: 'Logout',
        icon: Icons.logout_rounded,
        keywords: const ['logout', 'sign out'],
        onExecute: _logout,
        enabled: !widget.isGuestMode,
      ),
      _CommandAction(
        label: 'Refresh AI Suggestions',
        icon: Icons.refresh_rounded,
        keywords: const ['ai', 'suggestions'],
        onExecute: () async {
          await ref.read(rosterProvider).refreshAiSuggestions();
        },
      ),
    ].where((action) => action.enabled).toList();
  }

  Future<void> _showAddEventDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AddEventDialog(
        onAddEvents: (events) {
          if (events.length == 1) {
            ref.read(rosterProvider).addEvent(events.first);
          } else {
            ref.read(rosterProvider).addBulkEvents(events);
          }
        },
      ),
    );
  }

  Future<void> _openActivityLog() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ActivityLogView()),
    );
  }

  Future<void> _exportToCloud() async {
    if (widget.isGuestMode) {
      _showSignUpPrompt();
      return;
    }
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No roster selected')),
      );
      return;
    }
    try {
      final result = await AwsService.instance.exportRosterToCloud(rosterId);
      final url = result['signedUrl'] as String?;
      if (url != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cloud export ready')),
        );
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cloud Export'),
            content: SelectableText(url),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, e);
      }
    }
  }

  Future<void> _showPresenceList() async {
    final roster = ref.read(rosterProvider);
    if (roster.presenceEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active collaborators')),
      );
      return;
    }
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Live Presence'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: roster.presenceEntries.map((entry) {
              return ListTile(
                leading: const Icon(Icons.circle, color: Colors.green, size: 12),
                title: Text(entry.displayName),
                subtitle: Text('Active on ${entry.device}'),
              );
            }).toList(),
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

  Future<void> _showOfflineQueue() async {
    final roster = ref.read(rosterProvider);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Offline Queue'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: roster.pendingSync.length,
            itemBuilder: (context, index) {
              final op = roster.pendingSync[index];
              return ListTile(
                leading: const Icon(Icons.sync_problem),
                title: Text(op.type.name),
                subtitle: Text(op.timestamp.toIso8601String()),
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

  Future<String?> _showConflictResolutionDialog(
    BuildContext context,
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
    String? lastModifiedBy,
  ) async {
    final details = _buildConflictDetails(local, remote, lastModifiedBy);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Sync conflict detected'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Last modified by: ${details['lastModifiedBy']}'),
                const SizedBox(height: 12),
                _buildConflictTable(details),
                const SizedBox(height: 12),
                if ((details['staffOnlyLocal'] as List).isNotEmpty) ...[
                  const Text('Only in local:'),
                  Text((details['staffOnlyLocal'] as List).join(', ')),
                  const SizedBox(height: 8),
                ],
                if ((details['staffOnlyRemote'] as List).isNotEmpty) ...[
                  const Text('Only in cloud:'),
                  Text((details['staffOnlyRemote'] as List).join(', ')),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'remote'),
            child: const Text('Use Cloud'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'local'),
            child: const Text('Overwrite Cloud'),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _buildConflictDetails(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
    String? lastModifiedBy,
  ) {
    int countList(dynamic value) => value is List ? value.length : 0;
    int countPattern(dynamic value) => value is List ? value.length : 0;

    List<String> staffNames(dynamic value) {
      if (value is! List) return [];
      return value
          .map((item) {
            if (item is Map && item['name'] != null) {
              return item['name'].toString();
            }
            return item.toString();
          })
          .where((name) => name.trim().isNotEmpty)
          .toList();
    }

    final localStaff = staffNames(local['staffMembers']);
    final remoteStaff = staffNames(remote['staffMembers']);
    final localSet = localStaff.toSet();
    final remoteSet = remoteStaff.toSet();

    return {
      'lastModifiedBy': lastModifiedBy ?? 'unknown',
      'local': {
        'staff': countList(local['staffMembers']),
        'overrides': countList(local['overrides']),
        'events': countList(local['events']),
        'patternWeeks': countPattern(local['masterPattern']),
      },
      'remote': {
        'staff': countList(remote['staffMembers']),
        'overrides': countList(remote['overrides']),
        'events': countList(remote['events']),
        'patternWeeks': countPattern(remote['masterPattern']),
      },
      'staffOnlyLocal': localSet.difference(remoteSet).toList(),
      'staffOnlyRemote': remoteSet.difference(localSet).toList(),
    };
  }

  Widget _buildConflictTable(Map<String, dynamic> details) {
    final local = details['local'] as Map<String, dynamic>;
    final remote = details['remote'] as Map<String, dynamic>;
    Widget row(String label, dynamic localValue, dynamic remoteValue) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text(label)),
            Expanded(
              child: Text(
                localValue.toString(),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                remoteValue.toString(),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: const [
            Expanded(flex: 2, child: Text('')),
            Expanded(
              child: Text(
                'Local',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cloud',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const Divider(),
        row('Staff', local['staff'], remote['staff']),
        row('Changes', local['overrides'], remote['overrides']),
        row('Events', local['events'], remote['events']),
        row('Pattern weeks', local['patternWeeks'], remote['patternWeeks']),
      ],
    );
  }

  Future<void> _showBulkEditDialog() async {
    final roster = ref.read(rosterProvider);
    if (roster.staffMembers.isEmpty) return;

    final staff = roster.getActiveStaffNames();
    final selectedStaff = <String>{staff.first};
    final shiftOptions = <String>{
      ...roster.getShiftTypes(),
      'OFF',
      'AL',
    }.where((s) => s.trim().isNotEmpty).toList();
    shiftOptions.sort();
    String selectedShift = shiftOptions.isNotEmpty ? shiftOptions.first : 'D';
    bool useCustomShift = false;
    final customShiftController = TextEditingController();
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    final reasonController = TextEditingController();
    bool overwriteExisting = true;
    final weekdays = <int>{1, 2, 3, 4, 5, 6, 7};

    int estimateCount() {
      int days = 0;
      for (var date = startDate;
          date.isBefore(endDate) || date.isAtSameMomentAs(endDate);
          date = date.add(const Duration(days: 1))) {
        if (!weekdays.contains(date.weekday)) continue;
        days += 1;
      }
      if (days == 0) return 0;
      if (overwriteExisting) return days * selectedStaff.length;
      int count = 0;
      for (final person in selectedStaff) {
        for (var date = startDate;
            date.isBefore(endDate) || date.isAtSameMomentAs(endDate);
            date = date.add(const Duration(days: 1))) {
          if (!weekdays.contains(date.weekday)) continue;
          final existing = roster.overrides.any(
            (o) =>
                o.personName == person &&
                o.date.year == date.year &&
                o.date.month == date.month &&
                o.date.day == date.day,
          );
          if (!existing) {
            count += 1;
          }
        }
      }
      return count;
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final shiftValue =
              useCustomShift ? customShiftController.text : selectedShift;
          final totalEstimate = estimateCount();
          return AlertDialog(
            title: const Text('Bulk Edit Shifts'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Staff',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: staff.map((name) {
                      final isSelected = selectedStaff.contains(name);
                      return FilterChip(
                        label: Text(name),
                        selected: isSelected,
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              selectedStaff.add(name);
                            } else {
                              selectedStaff.remove(name);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selectedStaff.length == staff.length,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selectedStaff
                            ..clear()
                            ..addAll(staff);
                        } else {
                          selectedStaff
                            ..clear()
                            ..add(staff.first);
                        }
                      });
                    },
                    title: const Text('Select all staff'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: useCustomShift ? 'Custom' : selectedShift,
                    items: [
                      ...shiftOptions.map(
                        (shift) => DropdownMenuItem(
                          value: shift,
                          child: Text(shift),
                        ),
                      ),
                      const DropdownMenuItem(
                        value: 'Custom',
                        child: Text('Custom'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        if (value == 'Custom') {
                          useCustomShift = true;
                        } else {
                          useCustomShift = false;
                          selectedShift = value;
                        }
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Shift'),
                  ),
                  if (useCustomShift)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SafeTextField(
                        controller: customShiftController,
                        decoration: const InputDecoration(
                          labelText: 'Custom shift code',
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
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
                              if (endDate.isBefore(date)) {
                                endDate = date;
                              }
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
                              if (startDate.isAfter(date)) {
                                startDate = date;
                              }
                            }
                          },
                          child: Text('End: ${_formatDate(endDate)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Days of week',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  ToggleButtons(
                    isSelected: List.generate(
                      7,
                      (i) => weekdays.contains(i + 1),
                    ),
                    onPressed: (index) {
                      final day = index + 1;
                      setState(() {
                        if (weekdays.contains(day)) {
                          weekdays.remove(day);
                        } else {
                          weekdays.add(day);
                        }
                      });
                    },
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('Mon'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('Tue'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('Wed'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('Thu'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('Fri'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('Sat'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('Sun'),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: overwriteExisting,
                    onChanged: (value) {
                      setState(() => overwriteExisting = value);
                    },
                    title: const Text('Overwrite existing changes'),
                  ),
                  SafeTextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Applying to $totalEstimate shifts',
                    style: Theme.of(context).textTheme.labelMedium,
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
                  if (selectedStaff.isEmpty || weekdays.isEmpty) {
                    return;
                  }
                  final shift =
                      useCustomShift ? shiftValue.trim() : selectedShift;
                  if (shift.isEmpty) return;
                  roster.addBulkOverridesAdvanced(
                    people: selectedStaff.toList(),
                    startDate: startDate,
                    endDate: endDate,
                    shift: shift.toUpperCase(),
                    reason: reasonController.text.trim(),
                    weekdays: weekdays,
                    overwriteExisting: overwriteExisting,
                  );
                  Navigator.pop(context);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    customShiftController.dispose();
    reasonController.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _icsDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  Future<void> _exportData() async {
    try {
      final roster = ref.read(rosterProvider);
      final data = jsonEncode(roster.toJson());
      final fileName =
          'roster_backup_${DateTime.now().millisecondsSinceEpoch}.json';

      // Use file_picker to save file
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Roster Data',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputFile != null) {
        // Ensure .json extension
        if (!outputFile.endsWith('.json')) {
          outputFile = '$outputFile.json';
        }

        final file = File(outputFile);
        await file.writeAsString(data);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Data exported to: ${file.path}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // User canceled the picker
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export cancelled'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, e);
      }
    }
  }

  Future<void> _exportRosterCsv() async {
    try {
      final roster = ref.read(rosterProvider);
      final now = DateTime.now();
      final buffer = StringBuffer('Date,Person,Shift\n');
      for (int i = 0; i < 30; i++) {
        final date = now.add(Duration(days: i));
        final dateLabel = _formatDate(date);
        for (final staff in roster.staffMembers) {
          final shift = roster.getShiftForDate(staff.name, date);
          buffer.writeln('$dateLabel,${staff.name},$shift');
        }
      }

      final fileName =
          'roster_export_${DateTime.now().millisecondsSinceEpoch}.csv';
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Roster CSV',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (outputFile != null) {
        if (!outputFile.endsWith('.csv')) {
          outputFile = '$outputFile.csv';
        }
        final file = File(outputFile);
        await file.writeAsString(buffer.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('CSV exported to: ${file.path}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, e);
      }
    }
  }

  Future<void> _exportRosterPng() async {
    await _exportRosterImage(format: 'png');
  }

  Future<void> _exportRosterJpg() async {
    await _exportRosterImage(format: 'jpg');
  }

  Future<void> _exportRosterPdf() async {
    try {
      final bytes = await _rosterViewKey.currentState
          ?.captureRosterPng(pixelRatio: 2.0);
      if (bytes == null) {
        throw Exception('Unable to capture roster view.');
      }
      final doc = pw.Document();
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
      final fileName =
          'roster_export_${DateTime.now().millisecondsSinceEpoch}.pdf';
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Roster PDF',
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
          SnackBar(
            content: Text('PDF exported to: ${file.path}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, e);
      }
    }
  }

  Future<void> _exportRosterImage({required String format}) async {
    try {
      final pngBytes = await _rosterViewKey.currentState
          ?.captureRosterPng(pixelRatio: 2.0);
      if (pngBytes == null) {
        throw Exception('Unable to capture roster view.');
      }
      Uint8List bytesOut = pngBytes;
      if (format == 'jpg') {
        final decoded = img.decodeImage(pngBytes);
        if (decoded == null) {
          throw Exception('Failed to encode JPG.');
        }
        bytesOut = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
      }
      final fileName =
          'roster_export_${DateTime.now().millisecondsSinceEpoch}.$format';
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Roster ${format.toUpperCase()}',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [format],
      );
      if (outputFile == null) return;
      if (!outputFile.toLowerCase().endsWith('.$format')) {
        outputFile = '$outputFile.$format';
      }
      final file = File(outputFile);
      await file.writeAsBytes(bytesOut);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${format.toUpperCase()} exported to: ${file.path}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, e);
      }
    }
  }

  Future<void> _exportCalendarIcs() async {
    try {
      final roster = ref.read(rosterProvider);
      final now = DateTime.now();
      final buffer = StringBuffer();
      buffer.writeln('BEGIN:VCALENDAR');
      buffer.writeln('VERSION:2.0');
      buffer.writeln('PRODID:-//Roster Champ//EN');

      for (int i = 0; i < 30; i++) {
        final date = now.add(Duration(days: i));
        final start = _icsDate(date);
        final end = _icsDate(date.add(const Duration(days: 1)));
        for (final staff in roster.staffMembers) {
          final shift = roster.getShiftForDate(staff.name, date);
          if (shift == 'OFF' || shift == 'AL') continue;
          buffer.writeln('BEGIN:VEVENT');
          buffer.writeln(
            'UID:${date.millisecondsSinceEpoch}_${staff.id}@rosterchamp',
          );
          buffer.writeln('DTSTART;VALUE=DATE:$start');
          buffer.writeln('DTEND;VALUE=DATE:$end');
          buffer.writeln('SUMMARY:Shift $shift - ${staff.name}');
          buffer.writeln('END:VEVENT');
        }
      }

      buffer.writeln('END:VCALENDAR');

      final fileName =
          'roster_calendar_${DateTime.now().millisecondsSinceEpoch}.ics';
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Calendar (ICS)',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['ics'],
      );

      if (outputFile != null) {
        if (!outputFile.endsWith('.ics')) {
          outputFile = '$outputFile.ics';
        }
        final file = File(outputFile);
        await file.writeAsString(buffer.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Calendar exported to: ${file.path}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, e);
      }
    }
  }

  Future<void> _importData() async {
    // Show import confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Roster Data'),
        content: const Text(
          'This will replace your current roster data with the imported data. '
          'Make sure you have exported your current data if you want to keep it. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final importedData = await _importFile();

        if (importedData != null) {
          await ref.read(rosterProvider).importData(importedData);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Data imported successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No file selected or invalid data'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ErrorHandler.showErrorSnackBar(context, e);
        }
      }
    }
  }

  Future<Map<String, dynamic>?> _importFile() async {
    try {
      // Use file_picker to pick file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select Roster Backup File',
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String contents = await file.readAsString();

        // Validate JSON
        final decodedData = jsonDecode(contents);
        if (decodedData is Map<String, dynamic>) {
          return decodedData;
        } else {
          throw FormatException('Invalid JSON format');
        }
      }
      return null;
    } on FormatException catch (e) {
      throw Exception('Invalid file format: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _clearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text(
          'This will permanently delete all roster data, including staff, changes, and events. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(rosterProvider).clearAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared')),
        );
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await AwsService.instance.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Logged out successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ErrorHandler.showErrorSnackBar(context, e);
        }
      }
    }
  }

  Future<void> _showAccountActions() async {
    final isGuest = widget.isGuestMode;
    final email = AwsService.instance.userEmail;
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(isGuest
                  ? 'Guest session'
                  : (email ?? 'Signed in')),
              subtitle:
                  Text(isGuest ? 'Sign in to sync across devices' : 'Account'),
            ),
            if (!isGuest)
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('Account Settings'),
                onTap: () {
                  Navigator.pop(context);
                  _tabController.animateTo(6);
                },
              ),
            if (!isGuest)
              ListTile(
                leading: const Icon(Icons.switch_account_outlined),
                title: const Text('Switch User'),
                onTap: () async {
                  Navigator.pop(context);
                  await _logout();
                },
              ),
            if (isGuest)
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Sign In / Create Account'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showSignUpPrompt();
                },
              ),
            if (isGuest)
              ListTile(
                leading: const Icon(Icons.arrow_back),
                title: const Text('Back to Start'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onExitGuestMode?.call();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _showSignUpPrompt() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Account'),
        content: const Text(
          'Would you like to create an account to sync your data across devices '
          'and access cloud features? Your current roster data will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'later'),
            child: const Text('Maybe Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'create'),
            child: const Text('Create Account'),
          ),
        ],
      ),
    );

    if (choice == 'create') {
      widget.onExitGuestMode?.call();
      // Navigate to login screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }
}

class _CommandAction {
  final String label;
  final IconData icon;
  final List<String> keywords;
  final VoidCallback onExecute;
  final bool enabled;

  const _CommandAction({
    required this.label,
    required this.icon,
    required this.keywords,
    required this.onExecute,
    this.enabled = true,
  });
}

class _CommandCenterView extends StatefulWidget {
  final List<_CommandAction> actions;
  final VoidCallback onOpenPalette;

  const _CommandCenterView({
    required this.actions,
    required this.onOpenPalette,
  });

  @override
  State<_CommandCenterView> createState() => _CommandCenterViewState();
}

class _CommandCenterViewState extends State<_CommandCenterView> {
  final TextEditingController _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _filterController.text.trim().toLowerCase();
    final actions = widget.actions.where((action) {
      if (query.isEmpty) return true;
      return action.label.toLowerCase().contains(query) ||
          action.keywords.any((k) => k.contains(query));
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SafeTextField(
                    controller: _filterController,
                    decoration: const InputDecoration(
                      labelText: 'Search commands',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: widget.onOpenPalette,
                  icon: const Icon(Icons.keyboard_command_key_rounded),
                  label: const Text('Palette'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: actions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final action = actions[index];
                  return ListTile(
                    leading: Icon(action.icon),
                    title: Text(action.label),
                    onTap: action.onExecute,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
