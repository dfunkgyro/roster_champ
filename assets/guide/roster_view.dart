import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'providers.dart';
import 'dialogs.dart';
import 'utils.dart';
import 'models.dart' as models;

class RosterView extends ConsumerStatefulWidget {
  const RosterView({super.key});

  @override
  ConsumerState<RosterView> createState() => _RosterViewState();
}

class _RosterViewState extends ConsumerState<RosterView> {
  DateTime _anchorDate = DateTime.now();
  static const int _dateWindow = 21;
  static const double _cellWidth = 80;
  bool _isAdjustingScroll = false;
  String _filterText = '';
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rosterProvider.notifier).initializeData();
      _jumpToCenter();
    });
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rosterNotifier = ref.watch(rosterProvider);
    final dates = _buildDateWindow();
    final dateKeys = {
      for (final date in dates)
        _dateKey(date): DateTime(date.year, date.month, date.day)
    };
    final paydayMap = {
      for (final date in dates) _dateKey(date): rosterNotifier.isPayday(date)
    };
    final holidayMap = {
      for (final date in dates) _dateKey(date): rosterNotifier.isBankHoliday(date)
    };
    final holidayNameMap = {
      for (final date in dates)
        _dateKey(date): rosterNotifier.getBankHolidayName(date) ?? ''
    };
    final majorEventsMap = {
      for (final date in dates)
        _dateKey(date): rosterNotifier.getMajorEventNames(date)
    };
    final overridesByKey = <String, models.Override>{};
    for (final override in rosterNotifier.overrides) {
      final key = '${override.person}|${_dateKey(override.date)}';
      overridesByKey[key] = override;
    }
    final canEdit = rosterNotifier.activeRoster?.role != 'staff';

    final changeColors = {
      'sickness': Colors.red.withOpacity(0.3),
      'long_term_sick': Colors.deepOrange.withOpacity(0.3),
      'annual_leave': Colors.blue.withOpacity(0.3),
      'sabbatical': Colors.indigo.withOpacity(0.3),
      'training': Colors.green.withOpacity(0.3),
      'secondment': Colors.teal.withOpacity(0.3),
      'cover': Colors.cyan.withOpacity(0.3),
      'overtime': Colors.orange.withOpacity(0.3),
      'external': Colors.brown.withOpacity(0.3),
      'unfilled': Colors.black.withOpacity(0.3),
      'swap': Colors.yellow.withOpacity(0.3),
      'other': Colors.purple.withOpacity(0.3),
    };

    List<String> activeStaff = rosterNotifier.getActiveStaffNames();

    if (_filterText.isNotEmpty) {
      activeStaff = activeStaff
          .where(
              (name) => name.toLowerCase().contains(_filterText.toLowerCase()))
          .toList();
    }

    return Column(
      children: [
        _buildDateNavigator(dates.first, dates.last),
        _buildSearchBar(),
        if (activeStaff.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                _filterText.isEmpty
                    ? "No active staff found. Add people in Staff Management."
                    : "No staff found matching '$_filterText'",
              ),
            ),
          )
        else
          Expanded(
            child: Scrollbar(
              controller: _verticalController,
              child: SingleChildScrollView(
                controller: _verticalController,
                scrollDirection: Axis.vertical,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DataTable(
                      headingRowColor: MaterialStateColor.resolveWith(
                        (states) =>
                            Theme.of(context).primaryColor.withOpacity(0.2),
                      ),
                      headingRowHeight: 56,
                      dataRowHeight: 64,
                      horizontalMargin: 0,
                      columnSpacing: 0,
                      columns: const [
                        DataColumn(
                          label: Text(
                            'Name',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      rows: activeStaff.map((name) {
                        return DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 140,
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _handleHorizontalScroll,
                        child: SingleChildScrollView(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                        headingRowColor: MaterialStateColor.resolveWith(
                          (states) =>
                              Theme.of(context).primaryColor.withOpacity(0.2),
                        ),
                        headingRowHeight: 56,
                        dataRowHeight: 64,
                        horizontalMargin: 0,
                        columnSpacing: 0,
                        columns: [
                          ...dates.map(
                            (date) => DataColumn(
                              label: SizedBox(
                                width: _cellWidth,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      DateFormat.E().format(date),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Builder(
                                      builder: (context) {
                                        final dateKey = _dateKey(date);
                                        final isPayday =
                                            paydayMap[dateKey] ?? false;
                                        final isHoliday =
                                            holidayMap[dateKey] ?? false;
                                        final holidayName =
                                            holidayNameMap[dateKey] ?? '';
                                        final majorEvents =
                                            majorEventsMap[dateKey] ??
                                                const <String>[];
                                        final hasMajorEvents =
                                            majorEvents.isNotEmpty;
                                        Color? badgeColor;
                                        if (isPayday && isHoliday) {
                                          badgeColor = Colors.purple.shade400;
                                        } else if (isPayday) {
                                          badgeColor = Colors.green.shade400;
                                        } else if (isHoliday) {
                                          badgeColor = Colors.orange.shade400;
                                        } else if (hasMajorEvents) {
                                          badgeColor = Colors.indigo.shade400;
                                        }
                                        final tooltipParts = <String>[];
                                        if (holidayName.isNotEmpty) {
                                          tooltipParts
                                              .add('Bank holiday: $holidayName');
                                        }
                                        if (hasMajorEvents) {
                                          tooltipParts.add(
                                              'Major events: ${majorEvents.join(', ')}');
                                        }
                                        final label = Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: badgeColor?.withOpacity(0.2),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                DateFormat('dd/MM').format(date),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              if (badgeColor != null) ...[
                                                const SizedBox(width: 4),
                                                Container(
                                                  width: 6,
                                                  height: 6,
                                                  decoration: BoxDecoration(
                                                    color: badgeColor,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                        if (tooltipParts.isNotEmpty) {
                                          return Tooltip(
                                            message: tooltipParts.join('\n'),
                                            child: label,
                                          );
                                        }
                                        return label;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        rows: activeStaff.map((name) {
                          return DataRow(
                            cells: [
                              ...dates.map((date) {
                                final dateKey = _dateKey(date);
                                final shift =
                                    rosterNotifier.getShift(name, date);
                                final override =
                                    overridesByKey['$name|$dateKey'];
                                final baseColor =
                                    AppColors.getShiftColor(shift)
                                        .withOpacity(0.25);
                                final overrideColor =
                                    changeColors[override?.changeType] ??
                                        Colors.grey.withOpacity(0.6);
                                final isPayday = paydayMap[dateKey] ?? false;
                                final isHoliday = holidayMap[dateKey] ?? false;
                                final holidayName =
                                    holidayNameMap[dateKey] ?? '';
                                final majorEvents =
                                    majorEventsMap[dateKey] ??
                                        const <String>[];
                                final hasMajorEvents =
                                    majorEvents.isNotEmpty;
                                final highlightColor = isPayday && isHoliday
                                    ? Colors.purple.shade400
                                    : isPayday
                                        ? Colors.green.shade400
                                        : isHoliday
                                            ? Colors.orange.shade400
                                            : hasMajorEvents
                                                ? Colors.indigo.shade400
                                                : null;

                                final isSwap = override?.swapId != null;

                                return DataCell(
                                  InkWell(
                                    onTap: canEdit
                                        ? () {
                                            HapticFeedback.lightImpact();
                                            showCellOptionsDialog(
                                              context,
                                              ref,
                                              name,
                                              date,
                                            );
                                          }
                                        : null,
                                    onLongPress: canEdit
                                        ? () {
                                            HapticFeedback.heavyImpact();
                                            showQuickEditMenu(
                                                context, ref, name, date);
                                          }
                                        : null,
                                    child: Container(
                                      width: _cellWidth,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: baseColor,
                                        border: Border.all(
                                          color: isSwap
                                              ? Colors.blue
                                              : highlightColor ?? overrideColor,
                                          width: override != null ||
                                                  isSwap ||
                                                  highlightColor != null
                                              ? 2
                                              : 1,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.all(4),
                                      child: Stack(
                                        children: [
                                          Center(
                                            child: Tooltip(
                                              message: () {
                                                if (override != null) {
                                                  return '${override.changeType}${override.notes != null ? '\nNotes: ${override.notes}' : ''}';
                                                }
                                                final parts = <String>[];
                                                if (holidayName.isNotEmpty) {
                                                  parts.add(
                                                      'Bank holiday: $holidayName');
                                                }
                                                if (hasMajorEvents) {
                                                  parts.add(
                                                      'Major events: ${majorEvents.join(', ')}');
                                                }
                                                if (parts.isEmpty) {
                                                  parts.add('Default shift');
                                                }
                                                return parts.join('\n');
                                              }(),
                                              child: Text(
                                                shift,
                                                style: TextStyle(
                                                  fontWeight: override != null
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (isSwap)
                                            const Positioned(
                                              top: 2,
                                              right: 2,
                                              child: Icon(
                                                Icons.swap_horiz,
                                                size: 12,
                                                color: Colors.blue,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          );
                        }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDateNavigator(DateTime start, DateTime end) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(
              () => _anchorDate = _anchorDate.subtract(
                const Duration(days: 7),
              ),
            ),
          ),
          Text(
            '${DateFormat.yMMMd().format(start)} - ${DateFormat.yMMMd().format(end)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Jump to today',
            onPressed: () {
              setState(() => _anchorDate = DateTime.now());
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _jumpToCenter());
            },
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _pickAnchorDate,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(
              () => _anchorDate = _anchorDate.add(
                const Duration(days: 7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: TextField(
        decoration: const InputDecoration(
          labelText: 'Search staff',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState(() => _filterText = value),
      ),
    );
  }

  String _dateKey(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.toIso8601String();
  }

  List<DateTime> _buildDateWindow() {
    final start =
        _anchorDate.subtract(const Duration(days: _dateWindow ~/ 2));
    return List.generate(
      _dateWindow,
      (i) => start.add(Duration(days: i)),
    );
  }

  bool _handleHorizontalScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification ||
        _isAdjustingScroll ||
        !_horizontalController.hasClients) {
      return false;
    }

    final metrics = notification.metrics;
    const thresholdCells = 2;
    final threshold = _cellWidth * thresholdCells;
    final shiftDays = _dateWindow ~/ 2;
    if (metrics.pixels <= threshold) {
      _shiftWindow(-shiftDays, threshold);
    } else if (metrics.pixels >= metrics.maxScrollExtent - threshold) {
      _shiftWindow(shiftDays, -threshold);
    }
    return false;
  }

  void _shiftWindow(int days, double offsetAdjust) {
    _isAdjustingScroll = true;
    setState(() {
      _anchorDate = _anchorDate.add(Duration(days: days));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_horizontalController.hasClients) {
        final target =
            _horizontalController.offset + (days * _cellWidth) - offsetAdjust;
        _horizontalController.jumpTo(target.clamp(
          0.0,
          _horizontalController.position.maxScrollExtent,
        ));
      }
      _isAdjustingScroll = false;
    });
  }

  void _jumpToCenter() {
    if (!_horizontalController.hasClients) return;
    final centerOffset = (_dateWindow ~/ 2) * _cellWidth;
    _horizontalController.jumpTo(centerOffset);
  }

  Future<void> _pickAnchorDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchorDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _anchorDate = picked);
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToCenter());
    }
  }

}
