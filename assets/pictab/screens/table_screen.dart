import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/data_table.dart';
import '../services/storage_service.dart';

class TableScreen extends StatefulWidget {
  final ExtractedDataTable table;

  const TableScreen({super.key, required this.table});

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  late ExtractedDataTable _table;
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _table = widget.table;
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_table.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Row',
            onPressed: _addRow,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save Table',
            onPressed: _saveTable,
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export_csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart),
                  title: Text('Export CSV'),
                ),
              ),
              const PopupMenuItem(
                value: 'export_json',
                child: ListTile(
                  leading: Icon(Icons.code),
                  title: Text('Export JSON'),
                ),
              ),
              const PopupMenuItem(
                value: 'add_column',
                child: ListTile(
                  leading: Icon(Icons.view_column),
                  title: Text('Add Column'),
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
          // Info bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoChip(Icons.view_column, '${_table.columnCount} columns'),
                _buildInfoChip(Icons.table_rows, '${_table.rowCount} rows'),
              ],
            ),
          ),

          // Table content
          Expanded(
            child: _table.rowCount == 0
                ? _buildEmptyState()
                : _buildTableContent(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRow,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      backgroundColor: Colors.white,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.table_chart, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('No data in table'),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add),
            label: const Text('Add Row'),
          ),
        ],
      ),
    );
  }

  Widget _buildTableContent() {
    return SingleChildScrollView(
      controller: _verticalScrollController,
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.primary.withOpacity(0.1),
          ),
          columns: [
            const DataColumn(label: Text('#')),
            ..._table.headers.asMap().entries.map((entry) => DataColumn(
                  label: InkWell(
                    onTap: () => _editHeader(entry.key, entry.value),
                    child: Row(
                      children: [
                        Text(
                          entry.value,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit, size: 14),
                      ],
                    ),
                  ),
                )),
            const DataColumn(label: Text('')), // Actions column
          ],
          rows: _table.rows.asMap().entries.map((rowEntry) {
            final rowIndex = rowEntry.key;
            final row = rowEntry.value;

            return DataRow(
              cells: [
                DataCell(Text('${rowIndex + 1}')),
                ...row.cells.asMap().entries.map((cellEntry) {
                  final colIndex = cellEntry.key;
                  final cell = cellEntry.value;

                  return DataCell(
                    Text(cell.value),
                    onTap: () => _editCell(rowIndex, colIndex, cell.value),
                  );
                }),
                DataCell(
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: () => _deleteRow(rowIndex),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  void _editCell(int rowIndex, int colIndex, String currentValue) {
    final controller = TextEditingController(text: currentValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Cell (${_table.headers[colIndex]})'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Value',
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
              setState(() {
                _table.updateCell(rowIndex, colIndex, controller.text);
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _editHeader(int index, String currentValue) {
    final controller = TextEditingController(text: currentValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Column Header'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Column Name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _confirmDeleteColumn(index);
              Navigator.pop(context);
            },
            child: const Text('Delete Column', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _table.headers[index] = controller.text;
                _table.updatedAt = DateTime.now();
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _addRow() {
    if (_table.columnCount == 0) {
      _addColumn();
      return;
    }

    setState(() {
      _table.addRow(List.filled(_table.columnCount, ''));
    });
  }

  void _deleteRow(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Row'),
        content: Text('Are you sure you want to delete row ${index + 1}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _table.removeRow(index);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _addColumn() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Column'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Column Name',
            hintText: 'Enter column header',
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
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  _table.addColumn(name);
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteColumn(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Column'),
        content: Text('Are you sure you want to delete column "${_table.headers[index]}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _table.removeColumn(index);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTable() async {
    final storage = context.read<StorageService>();
    final success = await storage.saveTable(_table);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Table saved successfully' : 'Failed to save table'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _handleMenuAction(String action) async {
    switch (action) {
      case 'export_csv':
        await _exportCsv();
        break;
      case 'export_json':
        await _exportJson();
        break;
      case 'add_column':
        _addColumn();
        break;
      case 'edit_title':
        _editTitle();
        break;
    }
  }

  Future<void> _exportCsv() async {
    final storage = context.read<StorageService>();
    final file = await storage.exportTableToCsv(_table);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            file != null ? 'Exported to: ${file.path}' : 'Failed to export',
          ),
        ),
      );
    }
  }

  Future<void> _exportJson() async {
    // For now, just show the JSON
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('JSON Export'),
        content: SingleChildScrollView(
          child: SelectableText(
            _table.toJsonString(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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

  void _editTitle() {
    final controller = TextEditingController(text: _table.title);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Title'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Table Title',
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
                setState(() {
                  _table.title = title;
                  _table.updatedAt = DateTime.now();
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
