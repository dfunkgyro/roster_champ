import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/roster.dart';
import '../services/roster_service.dart';
import '../services/storage_service.dart';
import '../utils/app_theme.dart';
import '../widgets/shift_cell.dart';
import '../widgets/shift_picker_dialog.dart';

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RosterService>(
      builder: (context, rosterService, child) {
        final roster = rosterService.currentRoster;

        if (roster == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Roster')),
            body: const Center(
              child: Text('No roster loaded'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(roster.title),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_add),
                tooltip: 'Add Employee',
                onPressed: () => _showAddEmployeeDialog(context, rosterService),
              ),
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'Save Roster',
                onPressed: () => _saveRoster(context, roster),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => _handleMenuAction(value, roster),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'export_json',
                    child: ListTile(
                      leading: Icon(Icons.code),
                      title: Text('Export JSON'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'export_csv',
                    child: ListTile(
                      leading: Icon(Icons.table_chart),
                      title: Text('Export CSV'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'statistics',
                    child: ListTile(
                      leading: Icon(Icons.analytics),
                      title: Text('View Statistics'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit_title',
                    child: ListTile(
                      leading: Icon(Icons.edit),
                      title: Text('Edit Title'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              // Legend bar
              _buildLegendBar(roster),

              // Roster grid
              Expanded(
                child: _buildRosterGrid(roster, rosterService),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddEmployeeDialog(context, rosterService),
            child: const Icon(Icons.person_add),
          ),
        );
      },
    );
  }

  Widget _buildLegendBar(Roster roster) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: roster.shiftCodes.entries.map((entry) {
          final color = _parseColor(entry.value.color);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Chip(
              avatar: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey[400]!),
                ),
                child: Center(
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white,
                    ),
                  ),
                ),
              ),
              label: Text(
                entry.value.name,
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: Colors.white,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRosterGrid(Roster roster, RosterService rosterService) {
    final dates = roster.dateRange;
    final employees = roster.employees;

    if (employees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No employees in roster'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _showAddEmployeeDialog(context, rosterService),
              icon: const Icon(Icons.person_add),
              label: const Text('Add Employee'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      controller: _verticalScrollController,
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header rows
            _buildHeaderRows(dates),

            // Employee rows
            ...employees.map((employee) => _buildEmployeeRow(
                  employee,
                  dates,
                  roster,
                  rosterService,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRows(List<DateTime> dates) {
    // Group dates by month
    final monthGroups = <String, List<DateTime>>{};
    for (final date in dates) {
      final monthKey = DateFormat('MMMM yyyy').format(date);
      monthGroups.putIfAbsent(monthKey, () => []).add(date);
    }

    return Column(
      children: [
        // Month row
        Row(
          children: [
            _buildHeaderCell('', width: 120, isFirstColumn: true),
            _buildHeaderCell('', width: 40), // Delete column
            ...monthGroups.entries.map((entry) => Container(
                  width: entry.value.length * 40.0,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFF001a33),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Center(
                    child: Text(
                      entry.key.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                )),
          ],
        ),

        // Day name row
        Row(
          children: [
            _buildHeaderCell('', width: 120, isFirstColumn: true),
            _buildHeaderCell('', width: 40),
            ...dates.map((date) {
              final dayName = DateFormat('EEE').format(date).toUpperCase();
              final isWeekend = date.weekday == 6 || date.weekday == 7;
              return _buildHeaderCell(
                dayName,
                isWeekend: isWeekend,
                backgroundColor: const Color(0xFF004488),
              );
            }),
          ],
        ),

        // Date number row
        Row(
          children: [
            _buildHeaderCell('Employee', width: 120, isFirstColumn: true),
            _buildHeaderCell('', width: 40),
            ...dates.map((date) {
              final isWeekend = date.weekday == 6 || date.weekday == 7;
              return _buildHeaderCell(
                date.day.toString().padLeft(2, '0'),
                isWeekend: isWeekend,
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderCell(
    String text, {
    double width = 40,
    bool isFirstColumn = false,
    bool isWeekend = false,
    Color? backgroundColor,
  }) {
    return Container(
      width: width,
      height: 30,
      decoration: BoxDecoration(
        color: backgroundColor ??
            (isWeekend
                ? const Color(0xFF002255)
                : const Color(0xFF003366)),
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isFirstColumn ? FontWeight.bold : FontWeight.w500,
            fontSize: isFirstColumn ? 12 : 10,
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeRow(
    Employee employee,
    List<DateTime> dates,
    Roster roster,
    RosterService rosterService,
  ) {
    return Row(
      children: [
        // Employee name
        Container(
          width: 120,
          height: 35,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border.all(color: Colors.grey[300]!, width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              employee.name,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),

        // Delete button
        Container(
          width: 40,
          height: 35,
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border.all(color: Colors.grey[300]!, width: 0.5),
          ),
          child: IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.red),
            padding: EdgeInsets.zero,
            onPressed: () => _confirmDeleteEmployee(
              context,
              employee,
              rosterService,
            ),
          ),
        ),

        // Shift cells
        ...dates.map((date) {
          final shift = employee.getShift(date);
          final isWeekend = date.weekday == 6 || date.weekday == 7;

          return ShiftCell(
            shiftCode: shift,
            isWeekend: isWeekend,
            shiftCodes: roster.shiftCodes,
            onTap: () => _showShiftPicker(
              context,
              employee,
              date,
              shift,
              roster,
              rosterService,
            ),
          );
        }),
      ],
    );
  }

  void _showShiftPicker(
    BuildContext context,
    Employee employee,
    DateTime date,
    String currentShift,
    Roster roster,
    RosterService rosterService,
  ) {
    showDialog(
      context: context,
      builder: (context) => ShiftPickerDialog(
        employeeName: employee.name,
        date: date,
        currentShift: currentShift,
        shiftCodes: roster.shiftCodes,
        onShiftSelected: (newShift) {
          rosterService.updateShift(employee.id, date, newShift);
        },
      ),
    );
  }

  void _showAddEmployeeDialog(
    BuildContext context,
    RosterService rosterService,
  ) {
    final controller = TextEditingController();
    String defaultShift = 'R';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Employee'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Employee Name',
                hintText: 'Enter name',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: defaultShift,
              decoration: const InputDecoration(
                labelText: 'Default Shift',
              ),
              items: rosterService.currentRoster?.shiftCodes.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text('${e.key} - ${e.value.name}'),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  defaultShift = value;
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                rosterService.addEmployee(name, defaultShift: defaultShift);
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteEmployee(
    BuildContext context,
    Employee employee,
    RosterService rosterService,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Employee'),
        content: Text('Are you sure you want to remove ${employee.name} from the roster?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              rosterService.removeEmployee(employee.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRoster(BuildContext context, Roster roster) async {
    final storage = context.read<StorageService>();
    final success = await storage.saveRoster(roster);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Roster saved successfully' : 'Failed to save roster'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _handleMenuAction(String action, Roster roster) async {
    switch (action) {
      case 'export_json':
        await _exportJson(roster);
        break;
      case 'export_csv':
        await _exportCsv(roster);
        break;
      case 'statistics':
        _showStatistics();
        break;
      case 'edit_title':
        _showEditTitleDialog();
        break;
    }
  }

  Future<void> _exportJson(Roster roster) async {
    final storage = context.read<StorageService>();
    final file = await storage.exportRosterToJson(roster);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            file != null
                ? 'Exported to: ${file.path}'
                : 'Failed to export',
          ),
        ),
      );
    }
  }

  Future<void> _exportCsv(Roster roster) async {
    final storage = context.read<StorageService>();
    final file = await storage.exportRosterToCsv(roster);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            file != null
                ? 'Exported to: ${file.path}'
                : 'Failed to export',
          ),
        ),
      );
    }
  }

  void _showStatistics() {
    final rosterService = context.read<RosterService>();
    final stats = rosterService.getRosterStatistics();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Roster Statistics'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatRow('Employees', '${stats['employeeCount']}'),
              _buildStatRow('Days', '${stats['dayCount']}'),
              const Divider(),
              const Text(
                'Shift Breakdown:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...(stats['shiftBreakdown'] as Map<String, int>?)
                      ?.entries
                      .map((e) => _buildStatRow(e.key, '${e.value}'))
                      .toList() ??
                  [],
            ],
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

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showEditTitleDialog() {
    final rosterService = context.read<RosterService>();
    final controller = TextEditingController(
      text: rosterService.currentRoster?.title ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Title'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Roster Title',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final title = controller.text.trim();
              if (title.isNotEmpty) {
                rosterService.updateTitle(title);
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String colorString) {
    try {
      final hex = colorString.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }
}
