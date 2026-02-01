import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/roster.dart';
import '../models/data_table.dart';
import '../services/storage_service.dart';
import '../services/roster_service.dart';
import 'roster_screen.dart';
import 'table_screen.dart';

class SavedDocumentsScreen extends StatefulWidget {
  const SavedDocumentsScreen({super.key});

  @override
  State<SavedDocumentsScreen> createState() => _SavedDocumentsScreenState();
}

class _SavedDocumentsScreenState extends State<SavedDocumentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Roster> _rosters = [];
  List<ExtractedDataTable> _tables = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDocuments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);

    final storage = context.read<StorageService>();
    final rosters = await storage.loadAllRosters();
    final tables = await storage.loadAllTables();

    if (mounted) {
      setState(() {
        _rosters = rosters;
        _tables = tables;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Documents'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: [
            Tab(
              icon: const Icon(Icons.calendar_month),
              text: 'Rosters (${_rosters.length})',
            ),
            Tab(
              icon: const Icon(Icons.table_chart),
              text: 'Tables (${_tables.length})',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRosterList(),
                _buildTableList(),
              ],
            ),
    );
  }

  Widget _buildRosterList() {
    if (_rosters.isEmpty) {
      return _buildEmptyState(
        icon: Icons.calendar_month,
        title: 'No Saved Rosters',
        subtitle: 'Upload an image or create a new roster to get started',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDocuments,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _rosters.length,
        itemBuilder: (context, index) {
          final roster = _rosters[index];
          return _buildRosterCard(roster);
        },
      ),
    );
  }

  Widget _buildTableList() {
    if (_tables.isEmpty) {
      return _buildEmptyState(
        icon: Icons.table_chart,
        title: 'No Saved Tables',
        subtitle: 'Upload an image containing a table to get started',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDocuments,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tables.length,
        itemBuilder: (context, index) {
          final table = _tables[index];
          return _buildTableCard(table);
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRosterCard(Roster roster) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openRoster(roster),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.calendar_month,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roster.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dateFormat.format(roster.startDate)} - ${dateFormat.format(roster.endDate)}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${roster.employees.length} employees • ${roster.numberOfDays} days',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => _handleRosterAction(value, roster),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'open',
                    child: ListTile(
                      leading: Icon(Icons.open_in_new),
                      title: Text('Open'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete, color: Colors.red),
                      title: Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableCard(ExtractedDataTable table) {
    final dateFormat = DateFormat('MMM d, yyyy HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openTable(table),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.table_chart,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      table.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${table.columnCount} columns • ${table.rowCount} rows',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Updated: ${dateFormat.format(table.updatedAt)}',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => _handleTableAction(value, table),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'open',
                    child: ListTile(
                      leading: Icon(Icons.open_in_new),
                      title: Text('Open'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete, color: Colors.red),
                      title: Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRoster(Roster roster) {
    final rosterService = context.read<RosterService>();
    rosterService.setCurrentRoster(roster);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RosterScreen(),
      ),
    );
  }

  void _openTable(ExtractedDataTable table) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TableScreen(table: table),
      ),
    );
  }

  void _handleRosterAction(String action, Roster roster) async {
    switch (action) {
      case 'open':
        _openRoster(roster);
        break;
      case 'delete':
        _confirmDeleteRoster(roster);
        break;
    }
  }

  void _handleTableAction(String action, ExtractedDataTable table) async {
    switch (action) {
      case 'open':
        _openTable(table);
        break;
      case 'delete':
        _confirmDeleteTable(table);
        break;
    }
  }

  void _confirmDeleteRoster(Roster roster) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Roster'),
        content: Text('Are you sure you want to delete "${roster.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final storage = context.read<StorageService>();
              await storage.deleteRoster(roster.id);
              _loadDocuments();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTable(ExtractedDataTable table) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Table'),
        content: Text('Are you sure you want to delete "${table.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final storage = context.read<StorageService>();
              await storage.deleteTable(table.id);
              _loadDocuments();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
