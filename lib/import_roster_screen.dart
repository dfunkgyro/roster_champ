import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'providers.dart';
import 'aws_service.dart';
import 'services/roster_import_service.dart';
import 'services/roster_import_prefs.dart';
import 'services/adaptive_learning_service.dart';
import 'package:roster_champ/safe_text_field.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ImportRosterScreen extends ConsumerStatefulWidget {
  const ImportRosterScreen({super.key});

  @override
  ConsumerState<ImportRosterScreen> createState() =>
      _ImportRosterScreenState();
}

class _ImportRosterScreenState extends ConsumerState<ImportRosterScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _templateCodeController =
      TextEditingController();
  final TextEditingController _templatePasswordController =
      TextEditingController();
  bool _loading = false;
  String? _error;
  ImportedRoster? _imported;
  File? _selectedFile;
  String? _sourceLabel;
  bool _cancelRequested = false;
  int _taskId = 0;
  Map<String, String> _corrections = {};
  List<RosterImportTemplate> _templates = [];
  List<RosterImportHistoryEntry> _history = [];
  final List<String> _auditLog = [];
  String? _activeSignature;
  RosterImportTemplate? _matchedTemplate;
  String? _pendingTemplateCode;
  String? _pendingTemplatePassword;
  bool _templateIncludeStaff = true;
  bool _templateIncludeOverrides = false;

  @override
  void dispose() {
    _nameController.dispose();
    _templateCodeController.dispose();
    _templatePasswordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadImportPrefs();
  }

  Future<void> _loadImportPrefs() async {
    final corrections = await RosterImportPrefs.loadCorrections();
    final templates = await RosterImportPrefs.loadTemplates();
    final history = await RosterImportPrefs.loadHistory();
    if (!mounted) return;
    setState(() {
      _corrections = corrections;
      _templates = templates;
      _history = history;
    });
  }

  Future<void> _pickFromFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.single.path == null) return;
    await _processFile(File(result.files.single.path!), source: 'CSV');
  }

  Future<void> _processFile(File file, {required String source}) async {
    final taskId = ++_taskId;
    setState(() {
      _loading = true;
      _error = null;
      _imported = null;
      _selectedFile = file;
      _sourceLabel = source;
      _auditLog.clear();
      _matchedTemplate = null;
      _cancelRequested = false;
    });
    try {
      ImportedRoster imported;
      if (_cancelRequested || taskId != _taskId) return;
      final text = await file.readAsString();
      if (_cancelRequested || taskId != _taskId) return;
      imported = await RosterImportService.instance.importFromCsv(
        text,
        title: 'Imported CSV Roster',
      );
      if (_cancelRequested || taskId != _taskId) return;
      setState(() {
        _imported = imported;
        _nameController.text =
            _nameController.text.isEmpty ? imported.title : _nameController.text;
      });
      _logAction('Imported roster from $source');
      if (_cancelRequested || taskId != _taskId) return;
      await _applyStoredCorrections();
      if (_cancelRequested || taskId != _taskId) return;
      await _autoMatchTemplate(imported);
      if (_cancelRequested || taskId != _taskId) return;
      await _storeHistory(imported);
    } catch (e) {
      if (_cancelRequested || taskId != _taskId) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _createRoster() async {
    final imported = _imported;
    if (imported == null &&
        (_pendingTemplateCode == null ||
            _pendingTemplateCode!.trim().isEmpty)) {
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      if (_pendingTemplateCode != null &&
          _pendingTemplateCode!.trim().isNotEmpty) {
        _nameController.text =
            'Template Roster ${DateTime.now().toString().split(' ').first}';
      } else {
        return;
      }
    }
    if (imported == null) {
      setState(() => _loading = true);
      try {
        final rosterId = await AwsService.instance.createRoster(
          _nameController.text.trim(),
          null,
        );
        await AwsService.instance.setLastRosterId(rosterId);
        await ref.read(rosterProvider).loadFromAWS();
        final applied = ref.read(rosterProvider).applyTemplateCode(
              _pendingTemplateCode!.trim(),
              includeStaffNames: _templateIncludeStaff,
              includeOverrides: _templateIncludeOverrides,
              password: _pendingTemplatePassword,
            );
        if (applied) {
          await ref.read(rosterProvider).saveToAWS();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Roster created from template')),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creating roster: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _loading = false);
        }
      }
      return;
    }

    final canProceed = await _validateBeforeCreate(imported);
    if (!canProceed) return;
    final name = _nameController.text.trim().isEmpty
        ? imported.title
        : _nameController.text.trim();
    setState(() => _loading = true);
    try {
      if (AwsService.instance.isAuthenticated) {
        final rosterId = await AwsService.instance.createRoster(name, null);
        await AwsService.instance.setLastRosterId(rosterId);
      }
      final data = RosterImportService.instance.toRosterJson(imported);
      await ref.read(rosterProvider).importData(data);
      if (AwsService.instance.isAuthenticated) {
        await ref.read(rosterProvider).syncToAWS();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Roster imported successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showTemplateImportDialog() async {
    _templateCodeController.text = _pendingTemplateCode ?? '';
    bool includeStaff = _templateIncludeStaff;
    bool includeOverrides = _templateIncludeOverrides;
    String password = _templatePasswordController.text.trim();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final parse = ref
                .read(rosterProvider)
                .parseTemplateCode(
                  _templateCodeController.text.trim(),
                  password: password.isEmpty ? null : password,
                );
            final payload = parse.payload;
            final summary = payload == null
                ? null
                : 'Cycle ${payload['cycleLength'] ?? 'N/A'} | '
                    'Week start ${payload['weekStartDay'] ?? 'N/A'} | '
                    'Staff ${(payload['staffNames'] as List?)?.length ?? 0}';
            return AlertDialog(
              title: const Text('Use Template Code'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SafeTextField(
                    controller: _templateCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Template Code',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    onChanged: (_) => setStateDialog(() {}),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final scanned = await _scanTemplateQr();
                      if (scanned != null && scanned.isNotEmpty) {
                        _templateCodeController.text = scanned;
                        setStateDialog(() {});
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR'),
                  ),
                  const SizedBox(height: 8),
                  SafeTextField(
                    controller: _templatePasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Password (if required)',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    onChanged: (value) {
                      password = value.trim();
                      setStateDialog(() {});
                    },
                  ),
                  CheckboxListTile(
                    value: includeStaff,
                    onChanged: (value) {
                      setStateDialog(() => includeStaff = value ?? true);
                    },
                    title: const Text('Include staff names'),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: includeOverrides,
                    onChanged: (value) {
                      setStateDialog(() => includeOverrides = value ?? false);
                    },
                    title: const Text('Include overrides'),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 8),
                  if (parse.isValid)
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(child: Text(summary ?? 'Template ready')),
                      ],
                    )
                  else if (parse.error != null)
                    Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text(parse.error!)),
                      ],
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _pendingTemplateCode =
                          _templateCodeController.text.trim();
                      _templateIncludeStaff = includeStaff;
                      _templateIncludeOverrides = includeOverrides;
                      _pendingTemplatePassword =
                          _templatePasswordController.text.trim().isEmpty
                              ? null
                              : _templatePasswordController.text.trim();
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _scanTemplateQr() async {
    String? result;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: SizedBox(
            width: 320,
            height: 420,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Scan Template QR'),
                ),
                Expanded(
                  child: MobileScanner(
                    onDetect: (capture) {
                      final barcode = capture.barcodes.isNotEmpty
                          ? capture.barcodes.first
                          : null;
                      final value = barcode?.rawValue;
                      if (value != null && value.startsWith('RC')) {
                        result = value;
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final imported = _imported;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Roster'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Import from CSV',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _buildImportWizard(),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _showTemplateImportDialog,
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Use template code'),
                  ),

                  FilledButton.icon(
                    onPressed: _loading ? null : _pickFromFiles,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Choose CSV'),
                  ),
                ],
              ),
              if (_pendingTemplateCode != null &&
                  _pendingTemplateCode!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: const [
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Template code ready. Create roster to apply.',
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              if (_selectedFile != null)
                Text(
                  'Selected: ${_selectedFile!.path.split(Platform.pathSeparator).last} (${_sourceLabel ?? ''})',
                ),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      const Expanded(child: LinearProgressIndicator()),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _cancelRequested = true;
                            _loading = false;
                            _error = null;
                          });
                        },
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (imported == null &&
                  _pendingTemplateCode != null &&
                  _pendingTemplateCode!.trim().isNotEmpty) ...[
                const Divider(height: 32),
                SafeTextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Roster name',
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Template code will be applied after creation.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _createRoster,
                  icon: const Icon(Icons.check),
                  label: const Text('Create roster'),
                ),
              ],
              if (imported != null) ...[
                const Divider(height: 32),
                SafeTextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Roster name',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Staff: ${imported.staff.length} | Dates: ${imported.dates.length}',
                ),
                if (imported.dates.isNotEmpty)
                  Text(
                    'Range: ${DateFormat('MMM d, yyyy').format(imported.dates.first)} '
                    '-> ${DateFormat('MMM d, yyyy').format(imported.dates.last)}',
                  ),
                const SizedBox(height: 8),
                Text(
                  _buildImportSummary(imported),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Detected: ${_documentTypeLabel(imported.documentType)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${(imported.documentConfidence * 100).round()}%)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Import: ${imported.ImportSource.toUpperCase()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (imported.staff.isEmpty || imported.dates.isEmpty)
                  Text(
                    'Import produced no rows. Check your CSV header and date columns.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.redAccent),
                  ),
                if (imported.documentType != ImportDocumentType.roster)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'This looks like a ${_documentTypeLabel(imported.documentType).toLowerCase()} file. '
                      'Review shifts before creating the roster.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.orange),
                    ),
                  ),
                if (imported.rawLines.isNotEmpty)
                  TextButton.icon(
                    onPressed: _loading ? null : () => _showRawText(imported),
                    icon: const Icon(Icons.text_snippet),
                    label: const Text('View raw text'),
                  ),
                if (_matchedTemplate != null)
                  Text(
                    'Template applied: ${_matchedTemplate!.name}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.green),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _addStaffRow,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add staff'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _addBlankColumn,
                      icon: const Icon(Icons.calendar_today),
                      label: const Text('Add date column'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _rebuildDates,
                      icon: const Icon(Icons.date_range),
                      label: const Text('Rebuild dates'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _autoCleanShifts,
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Auto-clean shifts'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _reviewLowConfidence,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Review low-confidence'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _showInsights,
                      icon: const Icon(Icons.insights_outlined),
                      label: const Text('Insights'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _smartFillGaps,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Smart fill gaps'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _bulkReplaceRule,
                      icon: const Icon(Icons.find_replace),
                      label: const Text('Bulk replace'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _showTemplates,
                      icon: const Icon(Icons.bookmark_border),
                      label: const Text('Templates'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _showHistory,
                      icon: const Icon(Icons.history),
                      label: const Text('Import history'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _showAuditLog,
                      icon: const Icon(Icons.article_outlined),
                      label: const Text('Audit log'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _shareReview,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share review'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _loading ? null : () => _mapUnknownShifts(imported),
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Map unknown shifts'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : () => _showFullPreview(imported),
                      icon: const Icon(Icons.table_rows),
                      label: const Text('Full preview'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _buildPreview(imported),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _createRoster,
                  icon: const Icon(Icons.check),
                  label: const Text('Create roster'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(ImportedRoster imported) {
    final staff = imported.staff.take(5).toList();
    final dates = imported.dates.take(7).toList();
    return SingleChildScrollView(
      child: DataTable(
        columns: [
          const DataColumn(label: Text('Staff')),
          ...dates.map(
            (d) => DataColumn(label: Text(DateFormat('d MMM').format(d))),
          ),
        ],
        rows: [
          for (final name in staff)
            DataRow(
              cells: [
                DataCell(
                  Row(
                    children: [
                      Expanded(child: Text(name)),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 16),
                        onPressed: _loading ? null : () => _editStaffName(name),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16),
                        onPressed:
                            _loading ? null : () => _removeStaff(name),
                      ),
                    ],
                  ),
                ),
                ...dates.map((d) {
                  final shift =
                      imported.assignments[name]?[d] ?? '';
                  final confidence =
                      imported.confidence[name]?[d] ?? 1.0;
                  return DataCell(
                    Container(
                      color: _confidenceColor(confidence),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        children: [
                          Expanded(child: Text(shift)),
                          if (confidence > 0 && confidence < 0.6)
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 14,
                              color: Colors.orange,
                            ),
                        ],
                      ),
                    ),
                    onTap: _loading
                        ? null
                        : () => _editShift(name, d, shift),
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildImportWizard() {
    final step = _imported == null ? 1 : 2;
    final completed = _imported != null ? 2 : 0;
    return Row(
      children: [
        _wizardChip('1', 'Choose file', step >= 1),
        const SizedBox(width: 8),
        _wizardChip('2', 'Review & fix', step >= 2),
        const SizedBox(width: 8),
        _wizardChip('3', 'Create roster', _imported != null),
        if (completed > 0) ...[
          const Spacer(),
          Icon(
            Icons.check_circle,
            color: Theme.of(context).colorScheme.primary,
            size: 18,
          ),
        ],
      ],
    );
  }

  Widget _wizardChip(String step, String label, bool active) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? scheme.primaryContainer : scheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: active ? scheme.primary : scheme.outlineVariant,
            child: Text(
              step,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  void _updateImportedRoster(ImportedRoster roster) {
    setState(() {
      _imported = roster;
    });
  }

  void _logAction(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    _auditLog.add('[$timestamp] $message');
  }

  void _addStaffRow() async {
    final roster = _imported;
    if (roster == null) return;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add staff'),
        content: SafeTextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Staff name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    if (roster.staff.contains(result)) {
      setState(() => _error = 'Staff name already exists.');
      return;
    }
    final updatedStaff = [...roster.staff, result];
    final updatedAssignments =
        Map<String, Map<DateTime, String>>.from(roster.assignments);
    final updatedConfidence =
        Map<String, Map<DateTime, double>>.from(roster.confidence);
    updatedAssignments[result] = {};
    updatedConfidence[result] = {};
    _updateImportedRoster(
      ImportedRoster(
        title: roster.title,
        staff: updatedStaff,
        dates: roster.dates,
        assignments: updatedAssignments,
        confidence: updatedConfidence,
        documentType: roster.documentType,
        documentConfidence: roster.documentConfidence,
        rawLines: roster.rawLines,
        ImportSource: roster.ImportSource,
        ocrSource: roster.ocrSource,
        mlKitLineCount: roster.mlKitLineCount,
        textractLineCount: roster.textractLineCount,
      ),
    );
    _logAction('Added staff "$result"');
  }

  void _addBlankColumn() async {
    final roster = _imported;
    if (roster == null) return;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add date column'),
        content: SafeTextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Date (e.g. 2026-02-01)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    DateTime? parsed;
    try {
      parsed = DateTime.parse(result);
    } catch (_) {
      setState(() => _error = 'Invalid date format.');
      return;
    }
    if (roster.dates.any((d) =>
        d.year == parsed!.year && d.month == parsed.month && d.day == parsed.day)) {
      setState(() => _error = 'Date already exists.');
      return;
    }
    final updatedDates = [...roster.dates, parsed]..sort();
    _updateImportedRoster(
      ImportedRoster(
        title: roster.title,
        staff: roster.staff,
        dates: updatedDates,
        assignments: roster.assignments,
        confidence: roster.confidence,
        documentType: roster.documentType,
        documentConfidence: roster.documentConfidence,
        rawLines: roster.rawLines,
        ImportSource: roster.ImportSource,
        ocrSource: roster.ocrSource,
        mlKitLineCount: roster.mlKitLineCount,
        textractLineCount: roster.textractLineCount,
      ),
    );
    _logAction(
      'Added date column ${DateFormat('yyyy-MM-dd').format(parsed)}',
    );
  }

  void _editStaffName(String oldName) async {
    final roster = _imported;
    if (roster == null) return;
    final controller = TextEditingController(text: oldName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit staff name'),
        content: SafeTextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Staff name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || result == oldName) return;
    if (roster.staff.contains(result)) {
      setState(() => _error = 'Staff name already exists.');
      return;
    }
    final updatedStaff =
        roster.staff.map((name) => name == oldName ? result : name).toList();
    final updatedAssignments =
        Map<String, Map<DateTime, String>>.from(roster.assignments);
    final updatedConfidence =
        Map<String, Map<DateTime, double>>.from(roster.confidence);
    final existing = updatedAssignments.remove(oldName);
    updatedAssignments[result] = existing ?? {};
    updatedConfidence[result] = updatedConfidence.remove(oldName) ?? {};
    _updateImportedRoster(
      ImportedRoster(
        title: roster.title,
        staff: updatedStaff,
        dates: roster.dates,
        assignments: updatedAssignments,
        confidence: updatedConfidence,
        documentType: roster.documentType,
        documentConfidence: roster.documentConfidence,
        rawLines: roster.rawLines,
        ImportSource: roster.ImportSource,
        ocrSource: roster.ocrSource,
        mlKitLineCount: roster.mlKitLineCount,
        textractLineCount: roster.textractLineCount,
      ),
    );
    _logAction('Renamed staff "$oldName" to "$result"');
  }

  void _removeStaff(String name) {
    final roster = _imported;
    if (roster == null) return;
    final updatedStaff = roster.staff.where((s) => s != name).toList();
    final updatedAssignments =
        Map<String, Map<DateTime, String>>.from(roster.assignments);
    updatedAssignments.remove(name);
    final updatedConfidence =
        Map<String, Map<DateTime, double>>.from(roster.confidence);
    updatedConfidence.remove(name);
    _updateImportedRoster(
      ImportedRoster(
        title: roster.title,
        staff: updatedStaff,
        dates: roster.dates,
        assignments: updatedAssignments,
        confidence: updatedConfidence,
        documentType: roster.documentType,
        documentConfidence: roster.documentConfidence,
        rawLines: roster.rawLines,
        ImportSource: roster.ImportSource,
        ocrSource: roster.ocrSource,
        mlKitLineCount: roster.mlKitLineCount,
        textractLineCount: roster.textractLineCount,
      ),
    );
    _logAction('Removed staff "$name"');
  }

  void _editShift(String name, DateTime date, String current) async {
    final roster = _imported;
    if (roster == null) return;
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit shift - ${DateFormat('MMM d').format(date)}'),
        content: SafeTextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Shift code'),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final updatedAssignments =
        Map<String, Map<DateTime, String>>.from(roster.assignments);
    final staffMap = Map<DateTime, String>.from(updatedAssignments[name] ?? {});
    final updatedConfidence =
        Map<String, Map<DateTime, double>>.from(roster.confidence);
    final staffConfidence =
        Map<DateTime, double>.from(updatedConfidence[name] ?? {});
    if (result.isEmpty) {
      staffMap.remove(date);
      staffConfidence.remove(date);
    } else {
      staffMap[date] = result.toUpperCase();
      staffConfidence[date] = _shiftConfidence(result.toUpperCase());
    }
    updatedAssignments[name] = staffMap;
    updatedConfidence[name] = staffConfidence;
    _updateImportedRoster(
      ImportedRoster(
        title: roster.title,
        staff: roster.staff,
        dates: roster.dates,
        assignments: updatedAssignments,
        confidence: updatedConfidence,
        documentType: roster.documentType,
        documentConfidence: roster.documentConfidence,
        rawLines: roster.rawLines,
        ImportSource: roster.ImportSource,
        ocrSource: roster.ocrSource,
        mlKitLineCount: roster.mlKitLineCount,
        textractLineCount: roster.textractLineCount,
      ),
    );
    _logAction(
      'Edited shift $name ${DateFormat('yyyy-MM-dd').format(date)} to "${result.toUpperCase()}"',
    );
  }

  void _rebuildDates() async {
    final roster = _imported;
    if (roster == null) return;
    final startController = TextEditingController(
      text: roster.dates.isNotEmpty
          ? DateFormat('yyyy-MM-dd').format(roster.dates.first)
          : DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    final stepController = TextEditingController(text: '1');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rebuild dates'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SafeTextField(
              controller: startController,
              decoration: const InputDecoration(
                labelText: 'Start date (YYYY-MM-DD)',
              ),
            ),
            const SizedBox(height: 12),
            SafeTextField(
              controller: stepController,
              decoration: const InputDecoration(
                labelText: 'Step in days',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (result != true) return;
    DateTime? startDate;
    int step = 1;
    try {
      startDate = DateTime.parse(startController.text.trim());
    } catch (_) {}
    step = int.tryParse(stepController.text.trim()) ?? 1;
    if (startDate == null || step <= 0) {
      setState(() => _error = 'Invalid start date or step.');
      return;
    }
    final updatedDates = <DateTime>[];
    for (int i = 0; i < roster.dates.length; i++) {
      updatedDates.add(
        DateTime(
          startDate.year,
          startDate.month,
          startDate.day + (i * step),
        ),
      );
    }
    _updateImportedRoster(
      ImportedRoster(
        title: roster.title,
        staff: roster.staff,
        dates: updatedDates,
        assignments: roster.assignments,
        confidence: roster.confidence,
        documentType: roster.documentType,
        documentConfidence: roster.documentConfidence,
        rawLines: roster.rawLines,
        ImportSource: roster.ImportSource,
        ocrSource: roster.ocrSource,
        mlKitLineCount: roster.mlKitLineCount,
        textractLineCount: roster.textractLineCount,
      ),
    );
    _logAction(
      'Rebuilt dates from ${DateFormat('yyyy-MM-dd').format(startDate)} step $step',
    );
  }

  void _smartFillGaps() {
    final roster = _imported;
    if (roster == null) return;
    final updatedAssignments =
        Map<String, Map<DateTime, String>>.from(roster.assignments);
    final updatedConfidence =
        Map<String, Map<DateTime, double>>.from(roster.confidence);
    for (final entry in updatedAssignments.entries) {
      final name = entry.key;
      final staffMap = Map<DateTime, String>.from(entry.value);
      final staffConfidence =
          Map<DateTime, double>.from(updatedConfidence[name] ?? {});
      final weekdayMostCommon = _buildWeekdayShiftHints(staffMap);
      for (final date in roster.dates) {
        if ((staffMap[date] ?? '').isNotEmpty) continue;
        final hint = weekdayMostCommon[date.weekday];
        if (hint != null && hint.isNotEmpty) {
          staffMap[date] = hint;
          staffConfidence[date] = 0.55;
        }
      }
      updatedAssignments[name] = staffMap;
      updatedConfidence[name] = staffConfidence;
    }
    _updateImportedRoster(
      ImportedRoster(
        title: roster.title,
        staff: roster.staff,
        dates: roster.dates,
        assignments: updatedAssignments,
        confidence: updatedConfidence,
        documentType: roster.documentType,
        documentConfidence: roster.documentConfidence,
        rawLines: roster.rawLines,
        ImportSource: roster.ImportSource,
        ocrSource: roster.ocrSource,
        mlKitLineCount: roster.mlKitLineCount,
        textractLineCount: roster.textractLineCount,
      ),
    );
    _logAction('Smart-filled gaps using weekday hints');
    AdaptiveLearningService.instance
        .recordSmartFillUsage(ref.read(settingsProvider));
  }

  Map<int, String> _buildWeekdayShiftHints(Map<DateTime, String> staffMap) {
    final buckets = <int, Map<String, int>>{};
    for (final entry in staffMap.entries) {
      final shift = entry.value.trim().toUpperCase();
      if (shift.isEmpty) continue;
      final bucket = buckets.putIfAbsent(entry.key.weekday, () => {});
      bucket[shift] = (bucket[shift] ?? 0) + 1;
    }
    final result = <int, String>{};
    for (final entry in buckets.entries) {
      final top = entry.value.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (top.isNotEmpty) {
        result[entry.key] = top.first.key;
      }
    }
    return result;
  }

  void _bulkReplaceRule() async {
    final roster = _imported;
    if (roster == null) return;
    final findController = TextEditingController();
    final replaceController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bulk replace'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SafeTextField(
              controller: findController,
              decoration: const InputDecoration(labelText: 'Find shift code'),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            SafeTextField(
              controller: replaceController,
              decoration: const InputDecoration(labelText: 'Replace with'),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final find = findController.text.trim().toUpperCase();
    final replace = replaceController.text.trim().toUpperCase();
    if (find.isEmpty || replace.isEmpty) {
      setState(() => _error = 'Find and replace values are required.');
      return;
    }
    final updatedAssignments =
        Map<String, Map<DateTime, String>>.from(roster.assignments);
    final updatedConfidence =
        Map<String, Map<DateTime, double>>.from(roster.confidence);
    for (final entry in updatedAssignments.entries) {
      final staff = entry.key;
      final staffMap = Map<DateTime, String>.from(entry.value);
      final staffConfidence =
          Map<DateTime, double>.from(updatedConfidence[staff] ?? {});
      for (final dateEntry in staffMap.entries.toList()) {
        if (dateEntry.value.trim().toUpperCase() == find) {
          staffMap[dateEntry.key] = replace;
          staffConfidence[dateEntry.key] =
              RosterImportService.instance.isKnownShift(replace) ? 0.95 : 0.6;
        }
      }
      updatedAssignments[staff] = staffMap;
      updatedConfidence[staff] = staffConfidence;
    }
    _updateImportedRoster(
      ImportedRoster(
        title: roster.title,
        staff: roster.staff,
        dates: roster.dates,
        assignments: updatedAssignments,
        confidence: updatedConfidence,
        documentType: roster.documentType,
        documentConfidence: roster.documentConfidence,
        rawLines: roster.rawLines,
        ImportSource: roster.ImportSource,
        ocrSource: roster.ocrSource,
        mlKitLineCount: roster.mlKitLineCount,
        textractLineCount: roster.textractLineCount,
      ),
    );
    _logAction('Bulk replaced "$find" with "$replace"');
    AdaptiveLearningService.instance
        .recordBulkReplace(find, replace, ref.read(settingsProvider));
  }

  void _showTemplates() {
    if (_templates.isEmpty) {
      setState(() => _error = 'No templates saved yet.');
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import templates'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final template in _templates)
                ListTile(
                  title: Text(template.name),
                  subtitle: Text(
                    'Start ${DateFormat('yyyy-MM-dd').format(template.startDate)} '
                    '| step ${template.stepDays} day(s)',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await RosterImportPrefs.deleteTemplate(template.id);
                      await _loadImportPrefs();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _applyTemplate(template);
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _saveTemplate();
            },
            child: const Text('Save current as template'),
          ),
        ],
      ),
    );
  }

  void _applyTemplate(RosterImportTemplate template) {
    final roster = _imported;
    if (roster == null) return;
    final updatedDates = <DateTime>[];
    for (int i = 0; i < roster.dates.length; i++) {
      updatedDates.add(
        DateTime(
          template.startDate.year,
          template.startDate.month,
          template.startDate.day + (i * template.stepDays),
        ),
      );
    }
    _updateImportedRoster(
      ImportedRoster(
        title: roster.title,
        staff: roster.staff,
        dates: updatedDates,
        assignments: roster.assignments,
        confidence: roster.confidence,
        documentType: roster.documentType,
        documentConfidence: roster.documentConfidence,
        rawLines: roster.rawLines,
        ImportSource: roster.ImportSource,
        ocrSource: roster.ocrSource,
        mlKitLineCount: roster.mlKitLineCount,
        textractLineCount: roster.textractLineCount,
      ),
    );
    _logAction('Applied template "${template.name}"');
  }

  void _saveTemplate() async {
    final roster = _imported;
    if (roster == null || roster.dates.isEmpty) {
      setState(() => _error = 'Import dates before saving a template.');
      return;
    }
    final controller = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save template'),
        content: SafeTextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Template name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Template name is required.');
      return;
    }
    final template = RosterImportTemplate(
      id: const Uuid().v4(),
      name: name,
      startDate: roster.dates.first,
      stepDays: roster.dates.length >= 2
          ? roster.dates[1].difference(roster.dates[0]).inDays.abs().clamp(1, 31)
          : 1,
      signature: _activeSignature,
    );
    await RosterImportPrefs.saveTemplate(template);
    await _loadImportPrefs();
    _logAction('Saved template "$name"');
  }

  void _showHistory() async {
    if (_history.isEmpty) {
      setState(() => _error = 'No import history yet.');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import history'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in _history)
                ListTile(
                  title: Text(entry.title),
                  subtitle: Text(
                    '${_documentTypeLabel(entry.documentType)} '
                    '(${(entry.documentConfidence * 100).round()}%) '
                    '- ${DateFormat('MMM d, yyyy').format(entry.createdAt)}',
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _loadFromHistory(entry);
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (_imported != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _showAutoRepairSuggestions(_imported!);
              },
              child: const Text('Auto-repair'),
            ),
        ],
      ),
    );
  }

  Future<void> _loadFromHistory(RosterImportHistoryEntry entry) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final imported = await RosterImportService.instance.importFromTable(
        entry.table,
        title: entry.title,
        documentType: entry.documentType,
        documentConfidence: entry.documentConfidence,
        rawLines: entry.rawLines,
      );
      setState(() {
        _imported = imported;
        _nameController.text = imported.title;
        _activeSignature = entry.signature;
      });
      _auditLog
        ..clear()
        ..addAll(entry.auditLog);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showInsights() {
    final roster = _imported;
    if (roster == null) return;
    final anomalies = _detectAnomalies(roster);
    final coverage = _buildCoverageSummary(roster);
    final patterns = _detectPatterns(roster);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import insights'),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('Patterns'),
              const SizedBox(height: 6),
              if (patterns.isEmpty)
                const Text('No repeating patterns detected.'),
              for (final pattern in patterns.take(6))
                Text('- $pattern'),
              const SizedBox(height: 12),
              const Text('Anomalies'),
              const SizedBox(height: 6),
              if (anomalies.isEmpty)
                const Text('No anomalies detected.'),
              for (final anomaly in anomalies.take(6))
                Text('- $anomaly'),
              const SizedBox(height: 12),
              const Text('Coverage summary'),
              const SizedBox(height: 6),
              for (final line in coverage)
                Text(line),
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

  List<String> _detectPatterns(ImportedRoster roster) {
    final patterns = <String>[];
    for (final name in roster.staff) {
      final shifts = roster.dates
          .map((d) => roster.assignments[name]?[d] ?? '')
          .toList();
      if (shifts.length < 14) continue;
      final pattern7 = shifts.take(7).join(',');
      final repeats = shifts
          .skip(7)
          .take(7)
          .join(',');
      if (pattern7 == repeats) {
        patterns.add('$name repeats weekly pattern');
        continue;
      }
      if (shifts.length >= 28) {
        final pattern14 = shifts.take(14).join(',');
        final repeat14 = shifts.skip(14).take(14).join(',');
        if (pattern14 == repeat14) {
          patterns.add('$name repeats 2-week pattern');
        }
      }
    }
    return patterns;
  }

  List<String> _detectAnomalies(ImportedRoster roster) {
    final anomalies = <String>[];
    for (final name in roster.staff) {
      final staffMap = roster.assignments[name] ?? {};
      for (int i = 1; i < roster.dates.length; i++) {
        final prevDate = roster.dates[i - 1];
        final date = roster.dates[i];
        final prev = (staffMap[prevDate] ?? '').toUpperCase();
        final current = (staffMap[date] ?? '').toUpperCase();
        if (_isNightShift(prev) && _isEarlyShift(current)) {
          anomalies.add(
            '$name night -> early on ${DateFormat('MMM d').format(date)}',
          );
        }
      }
    }
    return anomalies;
  }

  bool _isNightShift(String code) => code == 'N' || code == 'N12';
  bool _isEarlyShift(String code) =>
      code == 'E' || code == 'D' || code == 'D12';

  List<String> _buildCoverageSummary(ImportedRoster roster) {
    if (roster.dates.isEmpty) return ['No dates available'];
    final counts = <String, List<int>>{
      'E': [],
      'D': [],
      'L': [],
      'N': [],
      'D12': [],
      'N12': [],
    };
    for (final date in roster.dates) {
      final dailyCounts = <String, int>{};
      for (final name in roster.staff) {
        final shift = roster.assignments[name]?[date] ?? '';
        if (shift.isEmpty) continue;
        dailyCounts[shift] = (dailyCounts[shift] ?? 0) + 1;
      }
      for (final key in counts.keys) {
        counts[key]!.add(dailyCounts[key] ?? 0);
      }
    }
    return counts.entries
        .map(
          (entry) {
            final values = entry.value;
            final min = values.reduce((a, b) => a < b ? a : b);
            final max = values.reduce((a, b) => a > b ? a : b);
            return '${entry.key} coverage: min $min / max $max';
          },
        )
        .toList();
  }

  void _showAutoRepairSuggestions(ImportedRoster roster) {
    final suggestions = _buildAutoRepairSuggestions(roster);
    if (suggestions.isEmpty) {
      setState(() => _error = 'No auto-repair suggestions at this time.');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auto-repair suggestions'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final suggestion in suggestions)
                ListTile(
                  title: Text(suggestion.label),
                  subtitle: suggestion.details == null
                      ? null
                      : Text(suggestion.details!),
                  trailing: suggestion.action == null
                      ? null
                      : FilledButton(
                          onPressed: () {
                            Navigator.pop(context);
                            suggestion.action!.call();
                          },
                          child: const Text('Apply'),
                        ),
                ),
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

  List<_AutoRepairSuggestion> _buildAutoRepairSuggestions(
    ImportedRoster roster,
  ) {
    final suggestions = <_AutoRepairSuggestion>[];
    if (_collectUnknownShifts(roster).isNotEmpty) {
      suggestions.add(
        _AutoRepairSuggestion(
          label: 'Map unknown shifts',
          details: 'Use the mapping tool to normalize Import codes.',
          action: () => _mapUnknownShifts(roster),
        ),
      );
    }
    if (_collectLowConfidence(roster).isNotEmpty) {
      suggestions.add(
        _AutoRepairSuggestion(
          label: 'Review low-confidence cells',
          details: 'Inspect Import cells that need confirmation.',
          action: _reviewLowConfidence,
        ),
      );
    }
    suggestions.add(
      _AutoRepairSuggestion(
        label: 'Auto-clean shifts',
        details: 'Normalize shift codes and remove blanks.',
        action: _autoCleanShifts,
      ),
    );
    suggestions.add(
      _AutoRepairSuggestion(
        label: 'Smart fill gaps',
        details: 'Fill missing shifts using weekday hints.',
        action: _smartFillGaps,
      ),
    );
    return suggestions;
  }

  void _showAuditLog() {
    if (_auditLog.isEmpty) {
      setState(() => _error = 'No audit log entries yet.');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import audit log'),
        content: SizedBox(
          width: 420,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _auditLog.length,
            itemBuilder: (context, index) {
              return Text(_auditLog[index]);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _auditLog.join('\n')));
              Navigator.pop(context);
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _shareReview() {
    final roster = _imported;
    if (roster == null) return;
    final buffer = StringBuffer()
      ..writeln('Roster import review')
      ..writeln('Title: ${roster.title}')
      ..writeln(
          'Detected: ${_documentTypeLabel(roster.documentType)} (${(roster.documentConfidence * 100).round()}%)')
      ..writeln(
          'Staff: ${roster.staff.length}, Dates: ${roster.dates.length}')
      ..writeln('Audit log:')
      ..writeln(_auditLog.join('\n'));
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Review copied to clipboard')),
    );
  }

  Future<void> _autoMatchTemplate(ImportedRoster roster) async {
    final signature = _buildSignature(roster);
    _activeSignature = signature;
    if (signature != null) {
      AdaptiveLearningService.instance
          .recordLayoutSignature(signature, ref.read(settingsProvider));
    }
    if (_templates.isEmpty || signature == null) return;
    for (final template in _templates) {
      if (template.signature != null && template.signature == signature) {
        _matchedTemplate = template;
        _applyTemplate(template);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Applied template: ${template.name}')),
          );
        }
        return;
      }
    }
  }

  String? _buildSignature(ImportedRoster roster) {
    if (roster.staff.isEmpty || roster.dates.isEmpty) return null;
    final header = roster.dates
        .take(7)
        .map((d) => DateFormat('MM-dd').format(d))
        .join('|');
    final columns = roster.dates.length;
    final rows = roster.staff.length;
    return 'c$columns-r$rows-$header';
  }

  double _shiftConfidence(String value) {
    const known = {
      'D',
      'D12',
      'E',
      'L',
      'N',
      'N12',
      'AL',
      'R',
      'OFF',
      'C',
      'C1',
      'C2',
      'C3',
      'C4',
    };
    if (known.contains(value)) return 0.9;
    if (value.isEmpty) return 0.0;
    if (value.length <= 2) return 0.5;
    return 0.4;
  }

  Color? _confidenceColor(double confidence) {
    if (confidence <= 0 || confidence >= 0.6) return null;
    if (confidence < 0.4) {
      return Colors.red.withOpacity(0.15);
    }
    return Colors.orange.withOpacity(0.15);
  }

  String _documentTypeLabel(ImportDocumentType type) {
    switch (type) {
      case ImportDocumentType.roster:
        return 'Roster';
      case ImportDocumentType.table:
        return 'Table';
      case ImportDocumentType.unknown:
        return 'Unknown';
    }
  }

  void _showRawText(ImportedRoster roster) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raw extracted text'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Text(
              roster.rawLines.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
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

  void _showFullPreview(ImportedRoster roster) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Full preview'),
        content: SizedBox(
          width: 720,
          height: 420,
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('Staff')),
                    ...roster.dates.map(
                      (d) =>
                          DataColumn(label: Text(DateFormat('d MMM').format(d))),
                    ),
                  ],
                  rows: [
                    for (final name in roster.staff)
                      DataRow(
                        cells: [
                          DataCell(Text(name)),
                          ...roster.dates.map((d) {
                            final shift =
                                roster.assignments[name]?[d] ?? '';
                            return DataCell(Text(shift));
                          }),
                        ],
                      ),
                  ],
                ),
              ),
            ),
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

  String _buildImportSummary(ImportedRoster roster) {
    int lowConfidence = 0;
    final unknown = <String>{};
    for (final entry in roster.assignments.entries) {
      final name = entry.key;
      for (final dateEntry in entry.value.entries) {
        final shift = dateEntry.value.trim().toUpperCase();
        if (shift.isNotEmpty &&
            !RosterImportService.instance.isKnownShift(shift)) {
          unknown.add(shift);
        }
        final confidence = roster.confidence[name]?[dateEntry.key] ?? 1.0;
        if (confidence > 0 && confidence < 0.6) {
          lowConfidence++;
        }
      }
    }
    final unknownText =
        unknown.isEmpty ? 'None' : unknown.take(8).join(', ');
    return 'Low-confidence cells: $lowConfidence | Unknown shifts: ${unknown.length} ($unknownText)';
  }

  List<_LowConfidenceEntry> _collectLowConfidence(ImportedRoster roster) {
    final entries = <_LowConfidenceEntry>[];
    for (final entry in roster.assignments.entries) {
      final name = entry.key;
      for (final dateEntry in entry.value.entries) {
        final confidence = roster.confidence[name]?[dateEntry.key] ?? 1.0;
        if (confidence > 0 && confidence < 0.6) {
          entries.add(
            _LowConfidenceEntry(
              staff: name,
              date: dateEntry.key,
              shift: dateEntry.value,
              confidence: confidence,
            ),
          );
        }
      }
    }
    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  void _reviewLowConfidence() {
    final roster = _imported;
    if (roster == null) return;
    final entries = _collectLowConfidence(roster);
    if (entries.isEmpty) {
      setState(() => _error = 'No low-confidence cells detected.');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Low-confidence shifts'),
        content: SizedBox(
          width: 420,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                dense: true,
                title: Text(
                  '${entry.staff} - ${DateFormat('MMM d').format(entry.date)}',
                ),
                subtitle: Text(_buildLowConfidenceSubtitle(roster, entry)),
                trailing: _buildSuggestionButton(roster, entry),
                onTap: () {
                  Navigator.pop(context);
                  _editShift(entry.staff, entry.date, entry.shift);
                },
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

  String _buildLowConfidenceSubtitle(
    ImportedRoster roster,
    _LowConfidenceEntry entry,
  ) {
    final suggestion = _suggestShiftForEntry(roster, entry);
    final base =
        '${entry.shift.isEmpty ? '(blank)' : entry.shift} (confidence ${(entry.confidence * 100).round()}%)';
    if (suggestion == null) return base;
    return '$base | suggested: $suggestion';
  }

  Widget? _buildSuggestionButton(
    ImportedRoster roster,
    _LowConfidenceEntry entry,
  ) {
    final suggestion = _suggestShiftForEntry(roster, entry);
    if (suggestion == null) return null;
    return IconButton(
      icon: const Icon(Icons.check_circle_outline),
      tooltip: 'Apply suggestion',
      onPressed: () {
        Navigator.pop(context);
        _applySuggestedShift(entry.staff, entry.date, suggestion);
      },
    );
  }

  String? _suggestShiftForEntry(
    ImportedRoster roster,
    _LowConfidenceEntry entry,
  ) {
    final staffMap = roster.assignments[entry.staff] ?? {};
    final hints = _buildWeekdayShiftHints(staffMap);
    final suggestion = hints[entry.date.weekday];
    if (suggestion == null || suggestion.isEmpty) return null;
    return suggestion;
  }

  void _applySuggestedShift(String staff, DateTime date, String suggestion) {
    final roster = _imported;
    if (roster == null) return;
    final updatedAssignments =
        Map<String, Map<DateTime, String>>.from(roster.assignments);
    final updatedConfidence =
        Map<String, Map<DateTime, double>>.from(roster.confidence);
    final staffMap = Map<DateTime, String>.from(updatedAssignments[staff] ?? {});
    final staffConfidence =
        Map<DateTime, double>.from(updatedConfidence[staff] ?? {});
    staffMap[date] = suggestion;
    staffConfidence[date] = 0.85;
    updatedAssignments[staff] = staffMap;
    updatedConfidence[staff] = staffConfidence;
    _updateImportedRoster(
      ImportedRoster(
        title: roster.title,
        staff: roster.staff,
        dates: roster.dates,
        assignments: updatedAssignments,
        confidence: updatedConfidence,
        documentType: roster.documentType,
        documentConfidence: roster.documentConfidence,
        rawLines: roster.rawLines,
        ImportSource: roster.ImportSource,
        ocrSource: roster.ocrSource,
        mlKitLineCount: roster.mlKitLineCount,
        textractLineCount: roster.textractLineCount,
      ),
    );
    _logAction(
      'Applied suggestion $staff ${DateFormat('yyyy-MM-dd').format(date)} -> $suggestion',
    );
  }

  void _autoCleanShifts() {
    final roster = _imported;
    if (roster == null) return;
    final updatedAssignments =
        Map<String, Map<DateTime, String>>.from(roster.assignments);
    final updatedConfidence =
        Map<String, Map<DateTime, double>>.from(roster.confidence);
    for (final entry in updatedAssignments.entries) {
      final staff = entry.key;
      final staffMap = Map<DateTime, String>.from(entry.value);
      final staffConfidence =
          Map<DateTime, double>.from(updatedConfidence[staff] ?? {});
      for (final dateEntry in staffMap.entries.toList()) {
        final raw = dateEntry.value;
        final normalized =
            RosterImportService.instance.normalizeShiftCode(raw);
        if (normalized.isEmpty) {
          staffMap.remove(dateEntry.key);
          staffConfidence.remove(dateEntry.key);
        } else {
          staffMap[dateEntry.key] = normalized;
          staffConfidence[dateEntry.key] =
              RosterImportService.instance
                  .confidenceForShift(normalized, raw);
        }
      }
      updatedAssignments[staff] = staffMap;
      updatedConfidence[staff] = staffConfidence;
    }
    _updateImportedRoster(
      ImportedRoster(
        title: roster.title,
        staff: roster.staff,
        dates: roster.dates,
        assignments: updatedAssignments,
        confidence: updatedConfidence,
        documentType: roster.documentType,
        documentConfidence: roster.documentConfidence,
        rawLines: roster.rawLines,
        ImportSource: roster.ImportSource,
        ocrSource: roster.ocrSource,
        mlKitLineCount: roster.mlKitLineCount,
        textractLineCount: roster.textractLineCount,
      ),
    );
  }

  Future<void> _storeHistory(ImportedRoster roster) async {
    final entry = RosterImportHistoryEntry(
      id: const Uuid().v4(),
      title: roster.title,
      createdAt: DateTime.now(),
      documentType: roster.documentType,
      documentConfidence: roster.documentConfidence,
      table: _buildTableFromRoster(roster),
      rawLines: roster.rawLines,
      signature: _activeSignature,
      auditLog: List<String>.from(_auditLog),
    );
    await RosterImportPrefs.addHistory(entry);
    if (mounted) {
      final history = await RosterImportPrefs.loadHistory();
      setState(() => _history = history);
    }
  }

  Future<void> _applyStoredCorrections() async {
    if (_corrections.isEmpty) return;
    final roster = _imported;
    if (roster == null) return;
    final unknown = _collectUnknownShifts(roster).toSet();
    final adaptiveMapping =
        await AdaptiveLearningService.instance.buildMappingForUnknown(
      unknown,
      ref.read(settingsProvider),
    );
    final combined = <String, String>{}
      ..addAll(_corrections)
      ..addAll(adaptiveMapping);
    if (combined.isNotEmpty) {
      _applyShiftMapping(combined);
    }
  }

  List<List<String>> _buildTableFromRoster(ImportedRoster roster) {
    final header = <String>['Staff', ...roster.dates.map((d) => DateFormat('yyyy-MM-dd').format(d))];
    final rows = <List<String>>[header];
    for (final name in roster.staff) {
      final row = <String>[name];
      for (final date in roster.dates) {
        row.add(roster.assignments[name]?[date] ?? '');
      }
      rows.add(row);
    }
    return rows;
  }

  Future<bool> _validateBeforeCreate(ImportedRoster roster) async {
    final issues = <String>[];
    if (roster.staff.isEmpty) {
      issues.add('No staff rows detected.');
    }
    if (roster.dates.isEmpty) {
      issues.add('No dates detected.');
    }
    final duplicates = _findDuplicateNames(roster.staff);
    if (duplicates.isNotEmpty) {
      issues.add('Duplicate staff names: ${duplicates.join(', ')}.');
    }
    final unknown = _collectUnknownShifts(roster).toList();
    if (unknown.isNotEmpty) {
      issues.add('Unknown shift codes: ${unknown.join(', ')}.');
    }
    if (issues.isEmpty) return true;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review before creating'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('We found a few issues:'),
            const SizedBox(height: 8),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('- $issue'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create anyway'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  List<String> _findDuplicateNames(List<String> names) {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final name in names) {
      final key = name.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (!seen.add(key)) {
        duplicates.add(name);
      }
    }
    return duplicates.toList();
  }

  void _mapUnknownShifts(ImportedRoster roster) {
    final unknown = _collectUnknownShifts(roster).toList()..sort();
    if (unknown.isEmpty) {
      setState(() => _error = 'No unknown shift codes detected.');
      return;
    }
    final selections = <String, String>{};
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Map unknown shifts'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'Map Import codes to known shifts. Leave blank to keep as-is.',
              ),
              const SizedBox(height: 12),
              for (final code in unknown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    value: selections[code],
                    decoration: InputDecoration(
                      labelText: 'Map "$code" to',
                      border: const OutlineInputBorder(),
                    ),
                    items: _knownShiftOptions
                        .map(
                          (option) => DropdownMenuItem(
                            value: option,
                            child: Text(option),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        selections.remove(code);
                      } else {
                        selections[code] = value;
                      }
                    },
                  ),
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
              Navigator.pop(context);
              _applyShiftMapping(selections);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Iterable<String> _collectUnknownShifts(ImportedRoster roster) sync* {
    final seen = <String>{};
    for (final entry in roster.assignments.entries) {
      for (final shift in entry.value.values) {
        final normalized = shift.trim().toUpperCase();
        if (normalized.isEmpty) continue;
        if (!RosterImportService.instance.isKnownShift(normalized)) {
          if (seen.add(normalized)) {
            yield normalized;
          }
        }
      }
    }
  }

  void _applyShiftMapping(Map<String, String> mapping) {
    if (mapping.isEmpty) return;
    final roster = _imported;
    if (roster == null) return;
    final updatedAssignments =
        Map<String, Map<DateTime, String>>.from(roster.assignments);
    final updatedConfidence =
        Map<String, Map<DateTime, double>>.from(roster.confidence);
    for (final entry in updatedAssignments.entries) {
      final staff = entry.key;
      final staffMap = Map<DateTime, String>.from(entry.value);
      final staffConfidence =
          Map<DateTime, double>.from(updatedConfidence[staff] ?? {});
      for (final dateEntry in staffMap.entries.toList()) {
        final shift = dateEntry.value.trim().toUpperCase();
        final mapped = mapping[shift];
        if (mapped != null && mapped.isNotEmpty) {
          staffMap[dateEntry.key] = mapped;
          staffConfidence[dateEntry.key] = 0.95;
        }
      }
      updatedAssignments[staff] = staffMap;
      updatedConfidence[staff] = staffConfidence;
    }
    _updateImportedRoster(
      ImportedRoster(
        title: roster.title,
        staff: roster.staff,
        dates: roster.dates,
        assignments: updatedAssignments,
        confidence: updatedConfidence,
        documentType: roster.documentType,
        documentConfidence: roster.documentConfidence,
        rawLines: roster.rawLines,
        ImportSource: roster.ImportSource,
        ocrSource: roster.ocrSource,
        mlKitLineCount: roster.mlKitLineCount,
        textractLineCount: roster.textractLineCount,
      ),
    );
    RosterImportPrefs.mergeCorrections(mapping);
    _logAction('Mapped unknown shifts: ${mapping.keys.join(', ')}');
    AdaptiveLearningService.instance
        .recordShiftCorrections(mapping, ref.read(settingsProvider));
  }
}

class _LowConfidenceEntry {
  final String staff;
  final DateTime date;
  final String shift;
  final double confidence;

  _LowConfidenceEntry({
    required this.staff,
    required this.date,
    required this.shift,
    required this.confidence,
  });
}

const List<String> _knownShiftOptions = [
  'D',
  'D12',
  'E',
  'L',
  'N',
  'N12',
  'AL',
  'R',
  'OFF',
  'C',
  'C1',
  'C2',
  'C3',
  'C4',
];

class _AutoRepairSuggestion {
  final String label;
  final String? details;
  final VoidCallback? action;

  _AutoRepairSuggestion({
    required this.label,
    this.details,
    this.action,
  });
}













