import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'roster_view.dart';
import 'stats_view.dart';
import 'events_view.dart';
import 'ai_suggestions_view.dart';
import 'settings_view.dart';
import 'screens/staff_management_screen.dart';
import 'screens/pattern_editor_screen.dart';
import 'providers.dart';
import 'models.dart' as models;
import 'dialogs.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentIndex = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final supabaseStatus = ref.watch(supabaseStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Text(
              'Roster Champ Pro',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Center(
              child: _ConnectionStatusIndicator(status: supabaseStatus),
            ),
          ),
          // AI suggestions badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.psychology_outlined),
                onPressed: () {
                  _tabController.animateTo(3);
                },
                tooltip: 'AI Suggestions',
              ),
              if (roster.aiSuggestions.where((s) => !s.isRead).isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${roster.aiSuggestions.where((s) => !s.isRead).length}',
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
          // Sync button
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
                case 'staff':
                  await _navigateToStaffManagement();
                  break;
                case 'pattern':
                  await _navigateToPatternEditor();
                  break;
                case 'initialize':
                  await _showInitializeDialog();
                  break;
                case 'export':
                  await _exportData();
                  break;
                case 'import':
                  await _importData();
                  break;
                case 'clear':
                  await _clearData();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'staff',
                child: ListTile(
                  leading: Icon(Icons.people_alt_rounded),
                  title: Text('Manage Staff'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'pattern',
                child: ListTile(
                  leading: Icon(Icons.pattern_rounded),
                  title: Text('Edit Pattern'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
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
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.download_rounded),
                  title: Text('Import Data'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
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
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Stats'),
            Tab(icon: Icon(Icons.event_rounded), text: 'Events'),
            Tab(icon: Icon(Icons.psychology_rounded), text: 'AI Insights'),
            Tab(icon: Icon(Icons.settings_rounded), text: 'Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          RosterView(),
          StatsView(),
          EventsView(),
          AiSuggestionsView(),
          SettingsView(),
        ],
      ),
      floatingActionButton: _buildFAB(context),
    );
  }

  Widget? _buildFAB(BuildContext context) {
    switch (_currentIndex) {
      case 0: // Roster
        return FloatingActionButton.extended(
          onPressed: () => _navigateToStaffManagement(),
          icon: const Icon(Icons.people_alt_rounded),
          label: const Text('Manage Staff'),
        );
      case 2: // Events
        return FloatingActionButton.extended(
          onPressed: () => _showAddEventDialog(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Event'),
        );
      case 3: // AI
        return FloatingActionButton.extended(
          onPressed: () {
            ref.read(rosterProvider).refreshAiSuggestions();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('AI suggestions refreshed')),
            );
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        );
      default:
        return null;
    }
  }

  Future<void> _syncData() async {
    try {
      await ref.read(rosterProvider).syncToSupabase();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  Future<void> _showAddEventDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AddEventDialog(
        onAdd: (event) {
          ref.read(rosterProvider).addEvent(event);
        },
      ),
    );
  }

  Future<void> _exportData() async {
    try {
      await ref.read(rosterProvider).exportData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data exported successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
        // Simulate file picker and import process
        // In a real implementation, you would use file_picker package
        final importedData = await _simulateFileImport();

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
                content: Text('No valid data found to import'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Import failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Simulate file import - in real app, use file_picker package
  Future<Map<String, dynamic>?> _simulateFileImport() async {
    try {
      // In a real implementation, you would use:
      // FilePickerResult? result = await FilePicker.platform.pickFiles();
      // if (result != null) {
      //   File file = File(result.files.single.path!);
      //   String contents = await file.readAsString();
      //   return jsonDecode(contents);
      // }

      // For now, simulate by loading from shared preferences (existing exported data)
      final roster = ref.read(rosterProvider);
      final data = roster.toJson();

      // Return a copy of current data to simulate import
      return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('Import simulation error: $e');
      return null;
    }
  }

  Future<void> _clearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text(
          'This will permanently delete all roster data, including staff, overrides, and events. This action cannot be undone.',
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
}

class _ConnectionStatusIndicator extends StatelessWidget {
  final models.ServiceStatus status;

  const _ConnectionStatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    final icon = _getStatusIcon();

    return Tooltip(
      message: status.message ?? 'Unknown status',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              _getStatusText(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (status.status) {
      case models.ConnectionStatus.connected:
        return Colors.green;
      case models.ConnectionStatus.connecting:
        return Colors.orange;
      case models.ConnectionStatus.disconnected:
        return Colors.grey;
      case models.ConnectionStatus.error:
        return Colors.red;
    }
  }

  IconData _getStatusIcon() {
    switch (status.status) {
      case models.ConnectionStatus.connected:
        return Icons.cloud_done_rounded;
      case models.ConnectionStatus.connecting:
        return Icons.cloud_sync_rounded;
      case models.ConnectionStatus.disconnected:
        return Icons.cloud_off_rounded;
      case models.ConnectionStatus.error:
        return Icons.error_rounded;
    }
  }

  String _getStatusText() {
    switch (status.status) {
      case models.ConnectionStatus.connected:
        return 'Online';
      case models.ConnectionStatus.connecting:
        return 'Connecting';
      case models.ConnectionStatus.disconnected:
        return 'Offline';
      case models.ConnectionStatus.error:
        return 'Error';
    }
  }
}
