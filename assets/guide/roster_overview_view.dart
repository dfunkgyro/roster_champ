import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'dart:io';

import 'providers.dart';
import 'models.dart';
import 'utils.dart';

class RosterOverviewView extends ConsumerStatefulWidget {
  const RosterOverviewView({super.key});

  @override
  ConsumerState<RosterOverviewView> createState() =>
      _RosterOverviewViewState();
}

class _RosterOverviewViewState extends ConsumerState<RosterOverviewView> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  int _rangeMonths = 12;
  final GlobalKey _monthKey = GlobalKey();
  _OverviewRange _range = _OverviewRange.year;

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final settings = ref.watch(settingsProvider);
    final staff = roster.getActiveStaffNames();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Roster Overview',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            DropdownButton<_OverviewRange>(
              value: _range,
              items: const [
                DropdownMenuItem(
                  value: _OverviewRange.month,
                  child: Text('Month'),
                ),
                DropdownMenuItem(
                  value: _OverviewRange.year,
                  child: Text('Year'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _range = value ?? _OverviewRange.month),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildControls(context),
        const SizedBox(height: 12),
          _buildExportControls(context, roster, settings),
          const SizedBox(height: 12),
        Text(
          'Now: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        if (_range == _OverviewRange.month)
          RepaintBoundary(
            key: _monthKey,
            child: _buildMonthTable(roster, staff, _year, _month),
          )
        else
          _buildYearView(roster, staff, _year),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            value: _month,
            decoration: const InputDecoration(
              labelText: 'Month',
              border: OutlineInputBorder(),
            ),
            items: List.generate(
              12,
              (index) => DropdownMenuItem(
                value: index + 1,
                child: Text(DateFormat.MMMM().format(DateTime(2024, index + 1))),
              ),
            ),
            onChanged: (value) => setState(() => _month = value ?? _month),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<int>(
            value: _year,
            decoration: const InputDecoration(
              labelText: 'Year',
              border: OutlineInputBorder(),
            ),
            items: List.generate(
              7,
              (index) {
                final year = DateTime.now().year - 3 + index;
                return DropdownMenuItem(
                  value: year,
                  child: Text(year.toString()),
                );
              },
            ),
            onChanged: (value) => setState(() => _year = value ?? _year),
          ),
        ),
      ],
    );
  }

  Widget _buildExportControls(
    BuildContext context,
    RosterNotifier roster,
    AppSettings settings,
  ) {
    final exportLabel = (settings.exportDirectory == null ||
            settings.exportDirectory!.isEmpty)
        ? 'Downloads folder (default)'
        : settings.exportDirectory!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Export',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Export location: $exportLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickExportDirectory(context),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose folder'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => _setExportDirectory(null),
                  child: const Text('Use Downloads'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _exportMonthImage(context),
                    icon: const Icon(Icons.image),
                    label: const Text('Export Month Image'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _exportMonthXml(context, roster),
                    icon: const Icon(Icons.code),
                    label: const Text('Export Month XML'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _rangeMonths,
                    decoration: const InputDecoration(
                      labelText: 'Months to export (XML)',
                      border: OutlineInputBorder(),
                    ),
                    items: [1, 2, 3, 6, 12]
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.toString()),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _rangeMonths = value ?? _rangeMonths),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _exportRangeXml(context, roster),
                  icon: const Icon(Icons.download),
                  label: const Text('Export Range XML'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _exportRangeImages(context),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Export Range PNG'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthTable(
    RosterNotifier roster,
    List<String> staff,
    int year,
    int month,
  ) {
    final today = DateTime.now();
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final dates = List.generate(
      daysInMonth,
      (index) => DateTime(year, month, index + 1),
    );
    final paydayMap = {
      for (final date in dates) _formatDateKey(date): roster.isPayday(date)
    };
    final holidayMap = {
      for (final date in dates) _formatDateKey(date): roster.isBankHoliday(date)
    };
    final holidayNameMap = {
      for (final date in dates)
        _formatDateKey(date): roster.getBankHolidayName(date) ?? ''
    };
    final majorEventsMap = {
      for (final date in dates)
        _formatDateKey(date): roster.getMajorEventNames(date)
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat.yMMMM().format(DateTime(year, month)),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DataTable(
              headingRowHeight: 40,
              dataRowHeight: 40,
              horizontalMargin: 0,
              columnSpacing: 0,
              columns: const [
                DataColumn(label: Text('Staff')),
              ],
              rows: staff
                  .map((name) => DataRow(cells: [
                        DataCell(
                          SizedBox(
                            width: 140,
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ]))
                  .toList(),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 40,
                  dataRowHeight: 40,
                  horizontalMargin: 0,
                  columnSpacing: 0,
                  columns: [
                    ...dates.map(
                      (date) => DataColumn(
                        label: Column(
                          children: [
                            Text(DateFormat.E().format(date)),
                            Text(date.day.toString()),
                          ],
                        ),
                      ),
                    ),
                  ],
                  rows: staff.map((name) {
                    return DataRow(
                      cells: [
                        ...dates.map((date) {
                          final key = _formatDateKey(date);
                          final shift = roster.getShift(name, date);
                          final isPayday = paydayMap[key] ?? false;
                          final isHoliday = holidayMap[key] ?? false;
                          final holidayName = holidayNameMap[key] ?? '';
                          final majorEvents =
                              majorEventsMap[key] ?? const <String>[];
                          final hasMajorEvents = majorEvents.isNotEmpty;
                          final isToday = date.year == today.year &&
                              date.month == today.month &&
                              date.day == today.day;
                          final color =
                              AppColors.getShiftColor(shift).withOpacity(0.2);
                          final borderColor = isPayday
                              ? Colors.green.shade400
                              : isHoliday
                                  ? Colors.orange.shade400
                                  : hasMajorEvents
                                      ? Colors.indigo.shade400
                                      : Colors.transparent;
                          final cell = Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: isToday
                                  ? Colors.yellow.withOpacity(0.2)
                                  : color,
                              border: Border.all(
                                color: isToday
                                    ? Colors.yellow.shade700
                                    : borderColor,
                              ),
                            ),
                            child: Center(child: Text(shift)),
                          );
                          if (holidayName.isNotEmpty || hasMajorEvents) {
                            final parts = <String>[];
                            if (holidayName.isNotEmpty) {
                              parts.add(holidayName);
                            }
                            if (hasMajorEvents) {
                              parts.add('Major events: ${majorEvents.join(', ')}');
                            }
                            return DataCell(
                              Tooltip(message: parts.join('\n'), child: cell),
                            );
                          }
                          return DataCell(cell);
                        }),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildYearView(
    RosterNotifier roster,
    List<String> staff,
    int year,
  ) {
    return Column(
      children: List.generate(12, (index) {
        final month = index + 1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildMonthTable(roster, staff, year, month),
        );
      }),
    );
  }

  Future<void> _exportMonthImage(BuildContext context) async {
    try {
      final boundary =
          _monthKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final directory = await _resolveExportDirectory();
      final file = File(
          '${directory.path}/roster_${_year}_${_month.toString().padLeft(2, '0')}.png');
      await file.writeAsBytes(bytes);
      _showSnack(context, 'Saved image to ${file.path}');
    } catch (e) {
      _showSnack(context, 'Failed to export image.');
    }
  }

  Future<void> _exportRangeImages(BuildContext context) async {
    try {
      final roster = ref.read(rosterProvider);
      final staff = roster.getActiveStaffNames();
      final key = GlobalKey();
      final overlay = OverlayEntry(
        builder: (ctx) => Material(
          type: MaterialType.transparency,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(_rangeMonths, (index) {
                    final target = DateTime(_year, _month + index, 1);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child:
                          _buildMonthTable(roster, staff, target.year, target.month),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      );

      Overlay.of(context).insert(overlay);
      await WidgetsBinding.instance.endOfFrame;

      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        overlay.remove();
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      overlay.remove();
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final directory = await _resolveExportDirectory();
      final file = File(
          '${directory.path}/roster_${_year}_${_month}_x$_rangeMonths.png');
      await file.writeAsBytes(bytes);
      _showSnack(context, 'Saved image to ${file.path}');
    } catch (e) {
      _showSnack(context, 'Failed to export image.');
    }
  }

  Future<void> _exportMonthXml(
    BuildContext context,
    RosterNotifier roster,
  ) async {
    final xml = _buildXmlForRange(roster, _year, _month, 1);
    await _saveXml(context, xml, 'roster_${_year}_${_month.toString().padLeft(2, '0')}.xml');
  }

  Future<void> _exportRangeXml(
    BuildContext context,
    RosterNotifier roster,
  ) async {
    final xml = _buildXmlForRange(roster, _year, _month, _rangeMonths);
    await _saveXml(context, xml, 'roster_${_year}_${_month}_x$_rangeMonths.xml');
  }

  String _buildXmlForRange(
    RosterNotifier roster,
    int year,
    int startMonth,
    int months,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<RosterRange>');
    final staff = roster.getActiveStaffNames();

    for (int offset = 0; offset < months; offset++) {
      final monthDate = DateTime(year, startMonth + offset, 1);
      final month = monthDate.month;
      final monthYear = monthDate.year;
      final daysInMonth = DateTime(monthYear, month + 1, 0).day;
      buffer.writeln('  <Month year="$monthYear" month="$month">');
      for (final name in staff) {
        buffer.writeln('    <Staff name="${_escapeXml(name)}">');
        for (int day = 1; day <= daysInMonth; day++) {
          final date = DateTime(monthYear, month, day);
          final shift = roster.getShift(name, date);
          buffer.writeln('      <Day date="${_formatDateKey(date)}">$shift</Day>');
        }
        buffer.writeln('    </Staff>');
      }
      buffer.writeln('  </Month>');
    }

    buffer.writeln('</RosterRange>');
    return buffer.toString();
  }

  Future<void> _saveXml(
    BuildContext context,
    String xml,
    String filename,
  ) async {
    try {
      final directory = await _resolveExportDirectory();
      final file = File('${directory.path}/$filename');
      await file.writeAsString(xml);
      _showSnack(context, 'Saved XML to ${file.path}');
    } catch (e) {
      _showSnack(context, 'Failed to export XML.');
    }
  }

  Future<void> _pickExportDirectory(BuildContext context) async {
    final directoryPath = await getDirectoryPath();
    if (directoryPath == null || directoryPath.isEmpty) return;
    _setExportDirectory(directoryPath);
    if (mounted) {
      _showSnack(context, 'Export location updated.');
    }
  }

  void _setExportDirectory(String? path) {
    final settingsController = ref.read(settingsProvider.notifier);
    final updated = settingsController.state.copyWith(exportDirectory: path);
    settingsController.state = updated;
    saveSettings(updated);
  }

  Future<Directory> _resolveExportDirectory() async {
    final settings = ref.read(settingsProvider);
    final configured = settings.exportDirectory;
    if (configured != null && configured.isNotEmpty) {
      return Directory(configured);
    }

    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return downloads;
    }
    return getApplicationDocumentsDirectory();
  }

  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  String _formatDateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

enum _OverviewRange { month, year }
