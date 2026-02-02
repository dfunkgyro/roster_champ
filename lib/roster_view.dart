import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers.dart';
import 'models.dart' as models;
import 'dialogs.dart';
import 'services/holiday_service.dart';
import 'services/observance_service.dart';
import 'services/sports_service.dart';
import 'services/weather_service.dart';
import 'services/time_service.dart';
import 'aws_service.dart';
import 'screens/pattern_editor_screen.dart';
import 'screens/roster_sharing_screen.dart';
import 'roster_generator_view.dart';
import 'utils/error_handler.dart';

class _OverlayBundle {
  final Map<String, HolidayItem> holidayMap;
  final Map<String, List<HolidayItem>> observanceMap;
  final Map<String, List<SportsEventItem>> sportsMap;

  const _OverlayBundle({
    required this.holidayMap,
    required this.observanceMap,
    required this.sportsMap,
  });
}

enum _RosterViewMode { month, week }

class RosterView extends ConsumerStatefulWidget {
  const RosterView({super.key});

  @override
  ConsumerState<RosterView> createState() => _RosterViewState();
}

class _RosterViewState extends ConsumerState<RosterView> {
  DateTime _currentWeekStart = _startOfDay(DateTime.now());
  DateTime _currentMonthAnchor =
      DateTime(DateTime.now().year, DateTime.now().month);
  final ScrollController _scrollController = ScrollController();
  final ScrollController _monthScrollController = ScrollController();
  final Map<String, ScrollController> _monthHorizontalControllers = {};
  final Map<String, ScrollController> _monthVerticalControllers = {};
  late final PageController _weekPageController;
  final int _weekPageBase = 10000;
  int _currentWeekPage = 10000;
  late DateTime _weekPageAnchor;
  int _weekStartDay = 0;
  final Map<String, TextEditingController> _nameControllers = {};
  final Map<String, FocusNode> _nameFocusNodes = {};
  final Map<String, List<HolidayItem>> _holidayCache = {};
  final Map<String, List<HolidayItem>> _observanceCache = {};
  String? _selectedStaffName;
  _RosterViewMode _viewMode = _RosterViewMode.month;
  bool _focusMode = true;
  double _cellScale = 1.0;
  double _scaleStart = 1.0;
  final Map<String, GlobalKey> _monthCardKeys = {};
  bool _showTodayChip = false;
  Timer? _todayChipTimer;
  bool _ignoreScrollNotifications = false;
  DateTime? _focusedDate;
  bool _monthAutoSnapEnabled = true;
  bool _initialMonthSnapDone = false;
  static const int _monthsBack = 12;
  static const int _monthsForward = 12;
  Future<_OverlayBundle>? _monthOverlayFuture;
  String? _monthOverlayKey;
  bool get _isMonthView => _viewMode == _RosterViewMode.month;
  bool get _isWeekView => _viewMode == _RosterViewMode.week;
  bool get _isMonthLike => _isMonthView || _isWeekView;

  double get _headerHeight => 56 * _cellScale;
  double get _rowHeight => 56 * _cellScale;
  double get _staffColumnWidth =>
      (170 * _cellScale).clamp(110, 220).toDouble();
  double get _dayCellWidthWeek =>
      (80 * _cellScale).clamp(40, 110).toDouble();
  double get _dayCellHeightWeek =>
      (48 * _cellScale).clamp(28, 70).toDouble();
  double get _dayCellWidthMonth =>
      (48 * _cellScale).clamp(24, 70).toDouble();
  double get _dayCellHeightMonth =>
      (36 * _cellScale).clamp(20, 56).toDouble();

  String _formatLeaveLabel(String? leaveType) {
    if (leaveType == null || leaveType.isEmpty) return 'Leave';
    if (leaveType.startsWith('custom:')) {
      final label = leaveType.substring('custom:'.length).trim();
      return label.isEmpty ? 'Custom Leave' : label;
    }
    switch (leaveType) {
      case 'secondment':
        return 'Secondment';
      case 'sick':
        return 'Sick';
      case 'annual':
        return 'Annual Leave';
      default:
        return 'Leave';
    }
  }

  @override
  void initState() {
    super.initState();
    _weekPageAnchor =
        _startOfWeekWithStart(DateTime.now(), _weekStartDay);
    _currentWeekStart = _weekPageAnchor;
    _currentWeekPage = _weekPageBase;
    _weekPageController = PageController(initialPage: _weekPageBase);
    _focusedDate = _startOfDay(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToToday(force: true);
    });
  }

  // Color system matching pattern editor
  // Update the shift colors in the RosterView to match pattern editor
  final Map<String, Color> _shiftColors = {
    'D': Colors.blue,
    'D12': Colors.blueAccent,
    'N': Colors.purple,
    'L': Colors.orange,
    'AL': Colors.redAccent,
    'OFF': Colors.grey,
    'R': Colors.green,
    'E': Colors.lightBlue,
    'N12': Colors.deepPurple,
    'C': Colors.teal,
    'C1': Colors.teal[300]!,
    'C2': Colors.teal[400]!,
    'C3': Colors.teal[600]!,
    'C4': Colors.teal[800]!,
  };

  @override
  void dispose() {
    _scrollController.dispose();
    _monthScrollController.dispose();
    _todayChipTimer?.cancel();
    _weekPageController.dispose();
    for (final controller in _monthHorizontalControllers.values) {
      controller.dispose();
    }
    for (final controller in _monthVerticalControllers.values) {
      controller.dispose();
    }
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    for (final node in _nameFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final settings = ref.watch(settingsProvider);
    final isReadOnly = roster.readOnly;
    final isCompactLayout = MediaQuery.of(context).size.width < 720;
    _ensureWeekStartDay(roster.weekStartDay);

    if (roster.getActiveStaffNames().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Roster Data',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Initialize a roster to get started',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: isReadOnly ? null : () => _showInitializeDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Initialize Roster'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (isReadOnly)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Read-only shared roster',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => _showGuestLeaveRequestDialog(context),
                  child: const Text('Request Leave'),
                ),
              ],
            ),
          ),
        if (!isReadOnly && !_focusMode)
          _buildQuickTools(context, isCompactLayout),
        if (settings.showWeatherOverlay &&
            settings.siteLat != null &&
            settings.siteLon != null &&
            !_focusMode)
          _buildWeatherStrip(settings),
        _buildViewModeToggle(context),
        _buildDateRibbon(context),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            children: [
              _isWeekView
                  ? _buildMonthOverviewHorizontal(context, roster, settings)
                  : _buildMonthOverview(context, roster, settings),
              if (_showTodayChip && !_isMonthLike)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FilledButton.icon(
                    onPressed: _smartHome,
                    icon: const Icon(Icons.today_rounded),
                    label: const Text('Back to Today'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildViewModeToggle(BuildContext context) {
    final useCompactNames = _cellScale < 0.6;
    final nameFontSize = _cellScale < 0.55 ? 11.0 : 13.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ToggleButtons(
            isSelected: [_isWeekView, _isMonthView],
            onPressed: (index) {
              setState(() {
                _viewMode =
                    index == 0 ? _RosterViewMode.week : _RosterViewMode.month;
                _focusedDate = _focusedDate ?? _startOfDay(DateTime.now());
              });
              _scrollToToday(force: true);
            },
            borderRadius: BorderRadius.circular(8),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.calendar_view_week_rounded, size: 18),
                    SizedBox(width: 6),
                    Text('Timeline'),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.calendar_view_month_rounded, size: 18),
                    SizedBox(width: 6),
                    Text('Month'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _focusMode ? 'Exit focus mode' : 'Focus mode',
            onPressed: () {
              setState(() => _focusMode = !_focusMode);
            },
            icon: Icon(
              _focusMode ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            ),
          ),
          TextButton.icon(
            onPressed: _smartHome,
            icon: const Icon(Icons.today_rounded, size: 18),
            label: const Text('Today'),
          ),
          PopupMenuButton<double>(
            tooltip: 'Roster size',
            onSelected: (value) {
              setState(() => _cellScale = value);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 1.0, child: Text('Large')),
              PopupMenuItem(value: 0.85, child: Text('Medium')),
              PopupMenuItem(value: 0.7, child: Text('Small')),
              PopupMenuItem(value: 0.6, child: Text('X-Small')),
              PopupMenuItem(value: 0.5, child: Text('XX-Small')),
            ],
            icon: const Icon(Icons.text_fields_rounded),
          ),
          const Spacer(),
          if (_selectedStaffName != null)
            TextButton.icon(
              onPressed: () {
                setState(() => _selectedStaffName = null);
              },
              icon: const Icon(Icons.highlight_off, size: 18),
              label: Text('Clear ${_selectedStaffName!}'),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickTools(BuildContext context, bool compact) {
    final roster = ref.read(rosterProvider);
    final settings = ref.watch(settingsProvider);
    final isSignedIn = AwsService.instance.isAuthenticated;
    final accessLabel = roster.readOnly
        ? 'Shared (${roster.sharedRole ?? 'viewer'})'
        : isSignedIn
            ? 'Signed in'
            : 'Guest';
    final accessIcon = roster.readOnly
        ? Icons.visibility
        : isSignedIn
            ? Icons.verified_user_outlined
            : Icons.person_outline;
    final lastSync = roster.lastSyncedAt != null
        ? DateFormat('MMM d, HH:mm').format(roster.lastSyncedAt!)
        : 'Never';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(accessIcon, size: 16),
                label: Text(accessLabel),
              ),
              Chip(
                avatar: const Icon(Icons.sync_rounded, size: 16),
                label: Text('Last sync: $lastSync'),
              ),
              if (roster.pendingSync.isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.cloud_upload, size: 16),
                  label: Text('Pending: ${roster.pendingSync.length}'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _openPatternEditor(context),
                icon: const Icon(Icons.pattern_rounded),
                label: const Text('Edit Pattern'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(settingsProvider.notifier).updateSettings(
                        settings.copyWith(
                          showHolidayOverlay: !settings.showHolidayOverlay,
                        ),
                      );
                },
                icon: Icon(
                  Icons.celebration_rounded,
                  color: settings.showHolidayOverlay
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                label: Text(
                  settings.showHolidayOverlay
                      ? 'Hide holidays'
                      : 'Show holidays',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(settingsProvider.notifier).updateSettings(
                        settings.copyWith(
                          showWeatherOverlay: !settings.showWeatherOverlay,
                        ),
                      );
                },
                icon: Icon(
                  Icons.cloud_rounded,
                  color: settings.showWeatherOverlay
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                label: Text(
                  settings.showWeatherOverlay
                      ? 'Hide weather'
                      : 'Show weather',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openGenerator(context),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate Pattern'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showAlignmentDialog(context),
                icon: const Icon(Icons.align_horizontal_left),
                label: const Text('Align Pattern'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openShareCodes(context),
                icon: const Icon(Icons.key_rounded),
                label: const Text('Access Code'),
              ),
              OutlinedButton.icon(
                onPressed: roster.staffMembers.isEmpty
                    ? null
                    : () => _showBulkEditDialog(context),
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('Bulk Edit'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await roster.syncToAWS();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Roster synced to cloud')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ErrorHandler.showErrorSnackBar(context, e);
                    }
                  }
                },
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Save & Sync'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherStrip(models.AppSettings settings) {
    final start = DateTime(
      _currentWeekStart.year,
      _currentWeekStart.month,
      _currentWeekStart.day,
    );
    final days = List.generate(7, (i) => start.add(Duration(days: i)));
    return FutureBuilder<Map<DateTime, WeatherDay>>(
      future: WeatherService.instance.getWeekly(
        lat: settings.siteLat!,
        lon: settings.siteLon!,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: LinearProgressIndicator(),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data!;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_outlined, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: days.map((day) {
                    final key = DateTime(day.year, day.month, day.day);
                    final info = data[key];
                    if (info == null) {
                      return Chip(label: Text(DateFormat('EEE').format(day)));
                    }
                    final precip = info.precipChance.round();
                    return Tooltip(
                      message:
                          '${info.maxTemp.toStringAsFixed(0)}° / ${info.minTemp.toStringAsFixed(0)}° - $precip% rain',
                      child: Chip(
                        label: Text(
                          '${DateFormat('EEE').format(day)} '
                          '${info.maxTemp.toStringAsFixed(0)}°',
                        ),
                        avatar: Icon(
                          precip >= 60
                              ? Icons.umbrella
                              : precip >= 30
                                  ? Icons.grain
                                  : Icons.wb_sunny,
                          size: 16,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 8),
              FutureBuilder<TimeInfo>(
                future: TimeService.instance.getTime(settings.timeZone),
                builder: (context, timeSnap) {
                  if (!timeSnap.hasData) {
                    return const SizedBox.shrink();
                  }
                  final time = timeSnap.data!;
                  final clock = DateFormat('HH:mm').format(time.dateTime);
                  return Text(
                    '${time.timezone} $clock',
                    style: Theme.of(context).textTheme.labelSmall,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPatternEditor(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PatternEditorScreen()),
    );
  }

  Future<void> _openGenerator(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RosterGeneratorView()),
    );
  }

  Future<void> _openShareCodes(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RosterSharingScreen(initialTabIndex: 3),
      ),
    );
  }

  Future<void> _showBulkEditDialog(BuildContext context) async {
    final roster = ref.read(rosterProvider);
    if (roster.staffMembers.isEmpty) return;

    String selectedPerson = roster.staffMembers.first.name;
    final shiftController = TextEditingController(text: 'D');
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    final reasonController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Bulk Edit Shifts'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedPerson,
                  items: roster.staffMembers
                      .map((s) => DropdownMenuItem(
                            value: s.name,
                            child: Text(s.name),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedPerson = value);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Staff'),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(labelText: 'Shift'),
                  controller: shiftController,
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
                          }
                        },
                        child: Text('Start: ${_formatShortDate(startDate)}'),
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
                          }
                        },
                        child: Text('End: ${_formatShortDate(endDate)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  decoration:
                      const InputDecoration(labelText: 'Reason (optional)'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final shift = shiftController.text.trim();
                  if (shift.isEmpty) return;
                  roster.addBulkOverrides(
                    selectedPerson,
                    startDate,
                    endDate,
                    shift,
                    reasonController.text.trim(),
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
  }

  Future<void> _showAlignmentDialog(BuildContext context) async {
    final roster = ref.read(rosterProvider);
    if (roster.masterPattern.isEmpty) return;
    int dayOffset = 0;
    int weekOffset = 0;
    bool propagate = true;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Align Pattern'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOffsetControl(
                label: 'Day offset',
                value: dayOffset,
                onChanged: (value) => setState(() => dayOffset = value),
              ),
              const SizedBox(height: 12),
              _buildOffsetControl(
                label: 'Week offset',
                value: weekOffset,
                onChanged: (value) => setState(() => weekOffset = value),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Propagate after align'),
                value: propagate,
                onChanged: (value) => setState(() => propagate = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                roster.shiftPatternAlignment(
                  dayOffset: dayOffset,
                  weekOffset: weekOffset,
                );
                if (propagate) {
                  roster.propagatePattern();
                }
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffsetControl({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => onChanged(value - 1),
            ),
            Expanded(
              child: Center(
                child: Text(
                  value.toString(),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }

  String _formatShortDate(DateTime date) {
    return DateFormat('MMM d').format(date);
  }

  // Week navigator removed in favor of year timeline view.

  DateTime _startOfWeek(DateTime date) {
    return _startOfWeekWithStart(date, _weekStartDay);
  }

  DateTime _startOfWeekWithStart(DateTime date, int weekStartDay) {
    final normalized = DateTime(date.year, date.month, date.day);
    final startWeekday = weekStartDay == 0 ? DateTime.sunday : weekStartDay;
    final rawDelta = normalized.weekday - startWeekday;
    final delta = rawDelta < 0 ? rawDelta + 7 : rawDelta;
    return normalized.subtract(Duration(days: delta));
  }

  static DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isSameMonth(DateTime date1, DateTime date2) {
    return date1.year == date2.year && date1.month == date2.month;
  }

  void _setFocusedDate(DateTime date) {
    setState(() {
      _focusedDate = _startOfDay(date);
    });
  }

  String _initialsForName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      return parts.first.isEmpty ? '' : parts.first[0].toUpperCase();
    }
    return (parts.first.isNotEmpty ? parts.first[0] : '') +
        (parts.last.isNotEmpty ? parts.last[0] : '');
  }

  String _monthKey(DateTime monthStart) {
    return '${monthStart.year}-'
        '${monthStart.month.toString().padLeft(2, '0')}';
  }

  void _ensureWeekStartDay(int value) {
    if (_weekStartDay == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _weekStartDay = value.clamp(0, 6);
        _weekPageAnchor =
            _startOfWeekWithStart(DateTime.now(), _weekStartDay);
        _currentWeekPage = _weekPageBase;
        _currentWeekStart = _weekPageAnchor;
        _focusedDate = _currentWeekStart;
      });
      if (_weekPageController.hasClients) {
        _weekPageController.jumpToPage(_weekPageBase);
      }
    });
  }

  DateTime _weekStartForPage(int pageIndex) {
    final deltaWeeks = pageIndex - _weekPageBase;
    return _weekPageAnchor.add(Duration(days: deltaWeeks * 7));
  }

  void _onWeekPageChanged(int pageIndex) {
    final start = _weekStartForPage(pageIndex);
    setState(() {
      _currentWeekPage = pageIndex;
      _currentWeekStart = start;
      _focusedDate = start;
    });
    _markScrolledAway();
  }

  void _animateWeekDelta(int delta) {
    if (!_scrollController.hasClients) return;
    final shift = delta * 7 * _dayCellWidthWeek;
    final target = _scrollController.offset + shift;
    final maxExtent = _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      target.clamp(0.0, maxExtent),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  ScrollController _getMonthScrollController(DateTime monthStart) {
    final key = _monthKey(monthStart);
    return _monthHorizontalControllers.putIfAbsent(
      key,
      () => ScrollController(),
    );
  }

  ScrollController _getMonthVerticalController(DateTime monthStart) {
    final key = 'v-${_monthKey(monthStart)}';
    return _monthVerticalControllers.putIfAbsent(
      key,
      () => ScrollController(),
    );
  }

  GlobalKey _getMonthCardKey(DateTime monthStart) {
    final key = _monthKey(monthStart);
    return _monthCardKeys.putIfAbsent(key, () => GlobalKey());
  }

  void _jumpToToday() {
    setState(() {
      final today = _startOfDay(DateTime.now());
      _weekPageAnchor = _startOfWeekWithStart(today, _weekStartDay);
      _currentWeekStart = _weekPageAnchor;
      _currentMonthAnchor = DateTime(today.year, today.month);
      _focusedDate = today;
      _showTodayChip = false;
      _monthAutoSnapEnabled = true;
    });
    _todayChipTimer?.cancel();
    if (_weekPageController.hasClients) {
      _weekPageController.animateToPage(
        _weekPageBase,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    } else {
      _currentWeekPage = _weekPageBase;
    }
    _scrollToToday(force: true);
  }

  void _smartHome() {
    final today = _startOfDay(DateTime.now());
    setState(() {
      _currentMonthAnchor = DateTime(today.year, today.month);
      _monthAutoSnapEnabled = true;
      _initialMonthSnapDone = false;
      _focusedDate = today;
      _showTodayChip = false;
    });
    if (_isMonthLike) {
      if (_monthScrollController.hasClients) {
        _monthScrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTodayMonth(force: true);
        Future.delayed(const Duration(milliseconds: 350), () {
          if (!mounted) return;
          _scrollToTodayDayInMonth(today);
        });
      });
    }
  }

  void _snapMonthAndToday() {
    final today = _startOfDay(DateTime.now());
    setState(() {
      _currentMonthAnchor = DateTime(today.year, today.month);
      _focusedDate = today;
      _monthAutoSnapEnabled = true;
      _initialMonthSnapDone = false;
    });
    _scrollToToday(force: true);
  }

  void _scrollToToday({bool force = false}) {
    final today = _startOfDay(DateTime.now());
    final rangeStart =
        DateTime(_currentMonthAnchor.year, _currentMonthAnchor.month - _monthsBack, 1);
    final rangeEnd = DateTime(
      _currentMonthAnchor.year,
      _currentMonthAnchor.month + _monthsForward + 1,
      0,
    );
    if (today.isBefore(rangeStart) || today.isAfter(rangeEnd)) {
      setState(() {
        _currentMonthAnchor = DateTime(today.year, today.month);
        _monthAutoSnapEnabled = true;
        _initialMonthSnapDone = false;
        _focusedDate = today;
      });
    }
    _ignoreScrollNotifications = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isMonthLike) {
        if (force || (!_initialMonthSnapDone && _monthAutoSnapEnabled)) {
          _scrollToTodayMonth(force: force);
          _initialMonthSnapDone = true;
        }
      }
      Future.delayed(const Duration(milliseconds: 350), () {
        _ignoreScrollNotifications = false;
      });
    });
  }

  void _scrollToTodayMonth({bool force = false}) {
    final today = _startOfDay(DateTime.now());
    _scrollToMonth(today, alignment: 0.1);
    _scrollToTodayDayInMonth(today);
  }

  void _scrollToMonth(DateTime target, {double alignment = 0.1}) {
    final monthStart = DateTime(target.year, target.month, 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _getMonthCardKey(monthStart).currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: alignment,
          duration: const Duration(milliseconds: 300),
        );
        return;
      }
      if (_monthScrollController.hasClients) {
        _monthScrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final retryContext = _getMonthCardKey(monthStart).currentContext;
        if (retryContext != null) {
          Scrollable.ensureVisible(
            retryContext,
            alignment: alignment,
            duration: const Duration(milliseconds: 300),
          );
        }
      });
    });
  }

  void _scrollToTodayDayInMonth(DateTime today) {
    final key = _monthKey(DateTime(today.year, today.month, 1));
    final controller = _monthHorizontalControllers[key];
    if (controller == null || !controller.hasClients) return;
    final settings = ref.read(settingsProvider);
    final offset = settings.monthSnapOffsetPx;
    final target = (today.day - 1) * _dayCellWidthMonth + offset;
    final maxExtent = controller.position.maxScrollExtent;
    controller.animateTo(
      target.clamp(0.0, maxExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _markScrolledAway() {
    if (_ignoreScrollNotifications) return;
    if (_isMonthLike) {
      _monthAutoSnapEnabled = false;
      return;
    }
    if (_showTodayChip) return;
    setState(() => _showTodayChip = true);
    _todayChipTimer?.cancel();
    _todayChipTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() => _showTodayChip = false);
    });
  }

  List<DateTime> _buildMonthList(DateTime anchor) {
    final total = _monthsBack + _monthsForward + 1;
    return List.generate(
      total,
      (i) => DateTime(anchor.year, anchor.month + i - _monthsBack, 1),
    );
  }

  void _toggleSelectedStaff(String name) {
    setState(() {
      if (_selectedStaffName == name) {
        _selectedStaffName = null;
      } else {
        _selectedStaffName = name;
      }
    });
  }

  String _holidayCacheKey(String countryCode, int year) {
    return '$countryCode-$year';
  }

  String _observanceCacheKey(String countryCode, int year, List<String> types) {
    return '$countryCode-$year-${types.join(',')}';
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, HolidayItem>> _loadHolidayMapForRange(
    models.AppSettings settings,
    DateTime start,
    DateTime end,
  ) async {
    try {
      final years = <int>{start.year, end.year};
      final all = <HolidayItem>[];
      final countries = <String>{
        settings.holidayCountryCode,
        ...settings.additionalHolidayCountries,
      };
      for (final country in countries) {
        if (country.trim().isEmpty) continue;
        for (final year in years) {
          final key = _holidayCacheKey(country, year);
          if (!_holidayCache.containsKey(key)) {
            final fetched = await HolidayService.instance.getHolidays(
              countryCode: country,
              year: year,
            );
            _holidayCache[key] = fetched;
          }
          all.addAll(_holidayCache[key]!);
        }
      }
      final map = <String, HolidayItem>{};
      for (final item in all) {
        if (item.date.isBefore(start) || item.date.isAfter(end)) {
          continue;
        }
        if (settings.holidayTypes.isNotEmpty &&
            item.types.isNotEmpty &&
            !item.types.any(settings.holidayTypes.contains)) {
          continue;
        }
        map[_dateKey(item.date)] = item;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Map<String, List<models.Event>> _buildEventMap(
    RosterNotifier roster,
    DateTime start,
    DateTime end,
  ) {
    final map = <String, List<models.Event>>{};
    for (final event in roster.events) {
      if (event.date.isBefore(start) || event.date.isAfter(end)) {
        continue;
      }
      map.putIfAbsent(_dateKey(event.date), () => []).add(event);
    }
    return map;
  }

  Future<_OverlayBundle> _loadOverlayBundleForRange(
    models.AppSettings settings,
    DateTime start,
    DateTime end,
  ) async {
    final holidayMap = settings.showHolidayOverlay
        ? await _loadHolidayMapForRange(settings, start, end)
        : <String, HolidayItem>{};
    final observanceMap = settings.showObservanceOverlay
        ? (settings.calendarificApiKey.trim().isEmpty
            ? _deriveObservancesFromHolidays(holidayMap)
            : await _loadObservanceMapForRange(settings, start, end))
        : <String, List<HolidayItem>>{};
    final sportsMap = settings.showSportsOverlay
        ? await _loadSportsMapForRange(settings, start, end)
        : <String, List<SportsEventItem>>{};
    final hidden = settings.hiddenOverlayDates.toSet();
    if (hidden.isNotEmpty) {
      holidayMap.removeWhere((key, _) => hidden.contains(key));
      observanceMap.removeWhere((key, _) => hidden.contains(key));
      sportsMap.removeWhere((key, _) => hidden.contains(key));
    }
    return _OverlayBundle(
      holidayMap: holidayMap,
      observanceMap: observanceMap,
      sportsMap: sportsMap,
    );
  }

  Future<Map<String, List<HolidayItem>>> _loadObservanceMapForRange(
    models.AppSettings settings,
    DateTime start,
    DateTime end,
  ) async {
    if (settings.calendarificApiKey.trim().isEmpty) return {};
    if (settings.observanceTypes.isEmpty) return {};
    try {
      final years = <int>{start.year, end.year};
      final all = <HolidayItem>[];
      for (final year in years) {
        final key = _observanceCacheKey(
          settings.holidayCountryCode,
          year,
          settings.observanceTypes,
        );
        if (!_observanceCache.containsKey(key)) {
          final fetched = await ObservanceService.instance.getObservances(
            apiKey: settings.calendarificApiKey,
            countryCode: settings.holidayCountryCode,
            year: year,
            types: settings.observanceTypes,
          );
          _observanceCache[key] = fetched;
        }
        all.addAll(_observanceCache[key]!);
      }
      final map = <String, List<HolidayItem>>{};
      for (final item in all) {
        map.putIfAbsent(_dateKey(item.date), () => []).add(item);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, List<SportsEventItem>>> _loadSportsMapForRange(
    models.AppSettings settings,
    DateTime start,
    DateTime end,
  ) async {
    final apiKey =
        settings.sportsApiKey.trim().isEmpty ? '1' : settings.sportsApiKey;
    if (settings.sportsLeagueIds.isEmpty) return {};
    try {
      final events = await SportsService.instance.getLeagueEvents(
        leagueIds: settings.sportsLeagueIds,
        apiKey: apiKey,
      );
      final map = <String, List<SportsEventItem>>{};
      for (final event in events) {
        if (event.date.isBefore(start) || event.date.isAfter(end)) continue;
        map.putIfAbsent(_dateKey(event.date), () => []).add(event);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  models.EventType _inferObservanceType(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('ramadan') ||
        lower.contains('easter') ||
        lower.contains('diwali') ||
        lower.contains('hanukkah') ||
        lower.contains('eid') ||
        lower.contains('christmas')) {
      return models.EventType.religious;
    }
    if (lower.contains('carnival') ||
        lower.contains('festival') ||
        lower.contains('lunar new year') ||
        lower.contains('chinese new year') ||
        lower.contains('mardi gras') ||
        lower.contains('valentine')) {
      return models.EventType.cultural;
    }
    return models.EventType.cultural;
  }

  Color _eventLineColor(BuildContext context, models.EventType type) {
    switch (type) {
      case models.EventType.payday:
        return Colors.amber.shade700;
      case models.EventType.religious:
        return Colors.deepPurple.shade400;
      case models.EventType.cultural:
        return Colors.purple.shade300;
      case models.EventType.sports:
        return Colors.green.shade600;
      case models.EventType.training:
      case models.EventType.meeting:
      case models.EventType.general:
      case models.EventType.custom:
        return Colors.blue.shade600;
      case models.EventType.deadline:
        return Colors.red.shade400;
      case models.EventType.birthday:
        return Colors.pink.shade400;
      case models.EventType.anniversary:
        return Colors.teal.shade400;
      case models.EventType.holiday:
        return Colors.red.shade600;
    }
  }

  String _eventTypeLabel(models.EventType type) {
    switch (type) {
      case models.EventType.payday:
        return 'Payday';
      case models.EventType.religious:
        return 'Religious';
      case models.EventType.cultural:
        return 'Cultural';
      case models.EventType.sports:
        return 'Sports';
      case models.EventType.training:
        return 'Training';
      case models.EventType.meeting:
        return 'Meeting';
      case models.EventType.deadline:
        return 'Deadline';
      case models.EventType.birthday:
        return 'Birthday';
      case models.EventType.anniversary:
        return 'Anniversary';
      case models.EventType.holiday:
        return 'Holiday';
      case models.EventType.custom:
        return 'Custom';
      case models.EventType.general:
        return 'Event';
    }
  }

  Map<String, List<HolidayItem>> _deriveObservancesFromHolidays(
    Map<String, HolidayItem> holidayMap,
  ) {
    final derived = <String, List<HolidayItem>>{};
    for (final entry in holidayMap.entries) {
      final type = _inferObservanceType(entry.value.localName);
      if (type == models.EventType.cultural ||
          type == models.EventType.religious) {
        derived.putIfAbsent(entry.key, () => []).add(entry.value);
      }
    }
    return derived;
  }

  List<Color> _eventLineColors({
    required BuildContext context,
    HolidayItem? holiday,
    List<models.Event> events = const [],
    List<HolidayItem> observances = const [],
    List<SportsEventItem> sportsEvents = const [],
  }) {
    final colors = <Color>{};
    if (holiday != null) {
      colors.add(_eventLineColor(context, models.EventType.holiday));
    }
    for (final event in events) {
      colors.add(_eventLineColor(context, event.eventType));
    }
    for (final obs in observances) {
      colors.add(_eventLineColor(
          context, _inferObservanceType(obs.localName)));
    }
    if (sportsEvents.isNotEmpty) {
      colors.add(_eventLineColor(context, models.EventType.sports));
    }
    return colors.toList();
  }

  Widget _buildEventLine(
    BuildContext context, {
    HolidayItem? holiday,
    List<models.Event> events = const [],
    List<HolidayItem> observances = const [],
    List<SportsEventItem> sportsEvents = const [],
  }) {
    final colors = _eventLineColors(
      context: context,
      holiday: holiday,
      events: events,
      observances: observances,
      sportsEvents: sportsEvents,
    );
    if (colors.isEmpty) {
      return const SizedBox(height: 4);
    }
    final limited = colors.length > 5 ? colors.take(4).toList() : colors;
    return SizedBox(
      height: 4,
      child: Row(
        children: [
          for (var i = 0; i < limited.length; i++) ...[
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: limited[i],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            if (i != limited.length - 1) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthOverview(
    BuildContext context,
    RosterNotifier roster,
    models.AppSettings settings,
  ) {
    final months = _buildMonthList(_currentMonthAnchor);
    final start = months.first;
    final end = DateTime(months.last.year, months.last.month + 1, 0);
    final staffMembers = roster.getStaffForRange(start, end);
    final staff = staffMembers.map((s) => s.name).toList();
    final monthKey =
        '${_monthKey(start)}-${_monthKey(end)}-${settings.showHolidayOverlay}-${settings.showObservanceOverlay}-${settings.showSportsOverlay}-${settings.holidayCountryCode}-${settings.holidayTypes.join(',')}-${settings.observanceTypes.join(',')}-${settings.sportsLeagueIds.join(',')}-${settings.calendarificApiKey.isNotEmpty}-${settings.sportsApiKey.isNotEmpty}';
    if (_monthOverlayKey != monthKey) {
      _monthOverlayKey = monthKey;
      _monthOverlayFuture = _loadOverlayBundleForRange(settings, start, end);
    }
    return FutureBuilder<_OverlayBundle>(
      future: _monthOverlayFuture,
      builder: (context, snapshot) {
        final bundle = snapshot.data ??
            const _OverlayBundle(
              holidayMap: {},
              observanceMap: {},
              sportsMap: {},
            );
        final holidayMap = bundle.holidayMap;
        final observanceMap = bundle.observanceMap;
        final sportsMap = bundle.sportsMap;
        final eventMap = _buildEventMap(roster, start, end);
        // Keep showing previous content while loading to preserve scroll position
        return GestureDetector(
          onScaleStart: (details) {
            _scaleStart = _cellScale;
          },
          onScaleUpdate: (details) {
            if (details.scale == 1.0) return;
            setState(() {
              _cellScale =
                  (_scaleStart * details.scale).clamp(0.45, 1.3).toDouble();
            });
          },
          child: Scrollbar(
            controller: _monthScrollController,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification) {
                  _markScrolledAway();
                  if (_isMonthView) {
                    _monthAutoSnapEnabled = false;
                  }
                }
                return false;
              },
              child: ListView.builder(
                key: const ValueKey('month_view_list'),
                controller: _monthScrollController,
                padding: const EdgeInsets.all(12),
                cacheExtent: 50000,
                itemCount: months.length,
                itemBuilder: (context, index) {
                  final monthStart = months[index];
                  final daysInMonth =
                      DateTime(monthStart.year, monthStart.month + 1, 0).day;
                  final days = List.generate(
                    daysInMonth,
                    (i) => DateTime(monthStart.year, monthStart.month, i + 1),
                  );
                  return Card(
                    key: _getMonthCardKey(monthStart),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('MMMM yyyy').format(monthStart),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStaffColumn(
                                context,
                                roster,
                                staff,
                                roster.readOnly,
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  key: PageStorageKey(
                                    'month-scroll-${_monthKey(monthStart)}',
                                  ),
                                  controller: _getMonthScrollController(monthStart),
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    showCheckboxColumn: false,
                                    headingRowHeight: _headerHeight,
                                    dataRowMinHeight: _rowHeight,
                                    dataRowMaxHeight: _rowHeight,
                                    headingRowColor: WidgetStateProperty.resolveWith(
                                      (states) => Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withOpacity(0.3),
                                    ),
                                    border: TableBorder.all(
                                      color: Theme.of(context).dividerColor,
                                      width: 1,
                                    ),
                                    columns: [
                                      ...days.map((day) {
                                        final isToday = _isSameDay(day, DateTime.now());
                                        final holiday = holidayMap[_dateKey(day)];
                                        final dayEvents = eventMap[_dateKey(day)] ?? [];
                                        final observances = observanceMap[_dateKey(day)] ?? [];
                                        final sportsEvents = sportsMap[_dateKey(day)] ?? [];
                                        final hasOverlay = holiday != null ||
                                            dayEvents.isNotEmpty ||
                                            observances.isNotEmpty ||
                                            sportsEvents.isNotEmpty;
                                        return DataColumn(
                                          label: InkWell(
                                            onTap: hasOverlay
                                                ? () => _showOverlaySummary(
                                                      day,
                                                      holiday: holiday,
                                                      observances: observances,
                                                      sportsEvents: sportsEvents,
                                                    )
                                                : null,
                                            child: SizedBox(
                                              width: _dayCellWidthMonth,
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    DateFormat('E').format(day),
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: isToday
                                                          ? Theme.of(context).colorScheme.primary
                                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  Text(
                                                    DateFormat('d').format(day),
                                                    style: GoogleFonts.inter(
                                                      fontSize: 11,
                                                      color: isToday
                                                          ? Theme.of(context).colorScheme.primary
                                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  if (hasOverlay) ...[
                                                    const SizedBox(height: 2),
                                                    _buildEventLine(
                                                      context,
                                                      holiday: holiday,
                                                      events: dayEvents,
                                                      observances: observances,
                                                      sportsEvents: sportsEvents,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                    rows: staffMembers.map((staffMember) {
                                      final personName = staffMember.name;
                                      final isSelected = _selectedStaffName == personName;
                                      return DataRow(
                                        color: WidgetStateProperty.resolveWith(
                                          (states) => isSelected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                                  .withOpacity(0.35)
                                              : null,
                                        ),
                                        cells: [
                                          ...days.map((day) {
                                            final isToday =
                                                _isSameDay(day, DateTime.now());
                                            final unavailable = roster
                                                .isStaffUnavailableOnDate(staffMember, day);
                                            final vacant = roster
                                                    .isStaffVacantOnDate(staffMember, day) &&
                                                staffMember.employmentType == 'permanent';
                                            final preStart = staffMember.startDate != null &&
                                                day.isBefore(DateTime(
                                                    staffMember.startDate!.year,
                                                    staffMember.startDate!.month,
                                                    staffMember.startDate!.day));
                                            final shift = (vacant || preStart)
                                                ? roster.getPatternShiftForDate(
                                                    personName, day)
                                                : roster.getShiftForDate(personName, day);
                                            final shiftColor =
                                                _shiftColors[shift.toUpperCase()] ??
                                                    Colors.grey;
                                            final holiday = holidayMap[_dateKey(day)];
                                            final events = eventMap[_dateKey(day)] ?? [];
                                            final observances =
                                                observanceMap[_dateKey(day)] ?? [];
                                            final sportsEvents =
                                                sportsMap[_dateKey(day)] ?? [];
                                            final hasOverlayCell = holiday != null ||
                                                events.isNotEmpty ||
                                                observances.isNotEmpty ||
                                                sportsEvents.isNotEmpty;
                                            return DataCell(
                                              InkWell(
                                                onTap: () {
                                                  _setFocusedDate(day);
                                                  if (roster.readOnly) {
                                                    _showDayDetails(
                                                      personName,
                                                      day,
                                                      readOnly: true,
                                                    );
                                                  } else {
                                                    _showShiftOptions(context, personName, day);
                                                  }
                                                },
                                                child: Container(
                                                  width: _dayCellWidthMonth,
                                                  height: _dayCellHeightMonth,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: shiftColor.withOpacity(
                                                        (vacant || unavailable || preStart)
                                                            ? 0.08
                                                            : 0.15),
                                                    border: Border.all(
                                                      color: shiftColor,
                                                      width: 1.5,
                                                    ),
                                                    borderRadius: BorderRadius.circular(6),
                                                    boxShadow: isToday
                                                        ? [
                                                            BoxShadow(
                                                              color: Theme.of(context)
                                                                  .colorScheme
                                                                  .primary
                                                                  .withOpacity(0.35),
                                                              blurRadius: 6,
                                                              spreadRadius: 1,
                                                            ),
                                                          ]
                                                        : null,
                                                  ),
                                                  child: Stack(
                                                    children: [
                                                      Center(
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment.center,
                                                          children: [
                                                            Text(
                                                              shift,
                                                              style: TextStyle(
                                                                fontWeight: FontWeight.bold,
                                                                color: (vacant ||
                                                                        unavailable ||
                                                                        preStart)
                                                                    ? Colors.grey
                                                                    : shiftColor,
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                            if (vacant)
                                                              Text(
                                                                'Vacant',
                                                                style: TextStyle(
                                                                  fontSize: 9,
                                                                  color: Colors.grey[600],
                                                                ),
                                                              )
                                                            else if (unavailable)
                                                              Text(
                                                            _formatLeaveLabel(
                                                                staffMember
                                                                    .leaveType),
                                                                style: TextStyle(
                                                                  fontSize: 9,
                                                                  color: Colors.grey[600],
                                                                ),
                                                              )
                                                            else if (preStart)
                                                              Text(
                                                                'Not started',
                                                                style: TextStyle(
                                                                  fontSize: 9,
                                                                  color: Colors.grey[600],
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                      // Event lines appear only in the date header.
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
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMonthOverviewHorizontal(
    BuildContext context,
    RosterNotifier roster,
    models.AppSettings settings,
  ) {
    final months = _buildMonthList(_currentMonthAnchor);
    final start = months.first;
    final end = DateTime(months.last.year, months.last.month + 1, 0);
    final staffMembers = roster.getStaffForRange(start, end);
    final staff = staffMembers.map((s) => s.name).toList();
    final monthKey =
        '${_monthKey(start)}-${_monthKey(end)}-${settings.showHolidayOverlay}-${settings.showObservanceOverlay}-${settings.showSportsOverlay}-${settings.holidayCountryCode}-${settings.additionalHolidayCountries.join(',')}-${settings.holidayTypes.join(',')}-${settings.observanceTypes.join(',')}-${settings.sportsLeagueIds.join(',')}-${settings.calendarificApiKey.isNotEmpty}-${settings.sportsApiKey.isNotEmpty}';
    if (_monthOverlayKey != monthKey) {
      _monthOverlayKey = monthKey;
      _monthOverlayFuture = _loadOverlayBundleForRange(settings, start, end);
    }
    return FutureBuilder<_OverlayBundle>(
      future: _monthOverlayFuture,
      builder: (context, snapshot) {
        final bundle = snapshot.data ??
            const _OverlayBundle(
              holidayMap: {},
              observanceMap: {},
              sportsMap: {},
            );
        final holidayMap = bundle.holidayMap;
        final observanceMap = bundle.observanceMap;
        final sportsMap = bundle.sportsMap;
        final eventMap = _buildEventMap(roster, start, end);
        // Keep showing previous content while loading to preserve scroll position
        return GestureDetector(
          onScaleStart: (details) {
            _scaleStart = _cellScale;
          },
          onScaleUpdate: (details) {
            if (details.scale == 1.0) return;
            setState(() {
              _cellScale =
                  (_scaleStart * details.scale).clamp(0.45, 1.3).toDouble();
            });
          },
          child: Scrollbar(
            controller: _monthScrollController,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification) {
                  _markScrolledAway();
                  if (_isMonthLike) {
                    _monthAutoSnapEnabled = false;
                  }
                }
                return false;
              },
              child: ListView.builder(
                key: const ValueKey('timeline_view_list'),
                controller: _monthScrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                cacheExtent: 50000,
                itemCount: months.length,
                itemBuilder: (context, index) {
                  final monthStart = months[index];
                  final daysInMonth =
                      DateTime(monthStart.year, monthStart.month + 1, 0).day;
                  final days = List.generate(
                    daysInMonth,
                    (i) => DateTime(monthStart.year, monthStart.month, i + 1),
                  );
                  return SizedBox(
                    width: MediaQuery.of(context).size.width * 0.92,
                    child: Card(
                      key: _getMonthCardKey(monthStart),
                      margin: const EdgeInsets.only(right: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('MMMM yyyy').format(monthStart),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height:
                                  MediaQuery.of(context).size.height * 0.68,
                              child: Scrollbar(
                                controller:
                                    _getMonthVerticalController(monthStart),
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller:
                                      _getMonthVerticalController(monthStart),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                _buildStaffColumn(
                                  context,
                                  roster,
                                  staff,
                                  roster.readOnly,
                                ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    key: PageStorageKey(
                                      'month-scroll-${_monthKey(monthStart)}',
                                    ),
                                    controller:
                                        _getMonthScrollController(monthStart),
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      showCheckboxColumn: false,
                                      headingRowHeight: _headerHeight,
                                      dataRowMinHeight: _rowHeight,
                                      dataRowMaxHeight: _rowHeight,
                                      headingRowColor:
                                          WidgetStateProperty.resolveWith(
                                        (states) => Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withOpacity(0.3),
                                      ),
                                      border: TableBorder.all(
                                        color: Theme.of(context).dividerColor,
                                        width: 1,
                                      ),
                                      columns: [
                                        ...days.map((day) {
                                          final isToday =
                                              _isSameDay(day, DateTime.now());
                                          final holiday =
                                              holidayMap[_dateKey(day)];
                                          final dayEvents =
                                              eventMap[_dateKey(day)] ?? [];
                                          final obs =
                                              observanceMap[_dateKey(day)] ?? [];
                                          final sports =
                                              sportsMap[_dateKey(day)] ?? [];
                                          final hasOverlay = holiday != null ||
                                              dayEvents.isNotEmpty ||
                                              obs.isNotEmpty ||
                                              sports.isNotEmpty;
                                          return DataColumn(
                                            label: InkWell(
                                              onTap: hasOverlay
                                                  ? () => _showOverlaySummary(
                                                        day,
                                                        holiday: holiday,
                                                        observances: obs,
                                                        sportsEvents: sports,
                                                      )
                                                  : null,
                                              child: SizedBox(
                                                width: _dayCellWidthMonth,
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      DateFormat('E').format(day),
                                                      style: GoogleFonts.inter(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: isToday
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .primary
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      ),
                                                    ),
                                                    Text(
                                                      DateFormat('d').format(day),
                                                      style: GoogleFonts.inter(
                                                        fontSize: 11,
                                                        color: isToday
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .primary
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      ),
                                                    ),
                                                    if (hasOverlay) ...[
                                                      const SizedBox(height: 2),
                                                      _buildEventLine(
                                                        context,
                                                        holiday: holiday,
                                                        events: dayEvents,
                                                        observances: obs,
                                                        sportsEvents: sports,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                      rows: staffMembers.map((staffMember) {
                                        final personName = staffMember.name;
                                        final isSelected =
                                            _selectedStaffName == personName;
                                        return DataRow(
                                          color: WidgetStateProperty.resolveWith(
                                            (states) => isSelected
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                                    .withOpacity(0.35)
                                                : null,
                                          ),
                                          cells: [
                                            ...days.map((day) {
                                              final isToday =
                                                  _isSameDay(day, DateTime.now());
                                              final unavailable = roster
                                                  .isStaffUnavailableOnDate(
                                                      staffMember, day);
                                              final vacant = roster
                                                      .isStaffVacantOnDate(
                                                          staffMember, day) &&
                                                  staffMember.employmentType ==
                                                      'permanent';
                                              final preStart =
                                                  staffMember.startDate != null &&
                                                      day.isBefore(DateTime(
                                                          staffMember
                                                              .startDate!.year,
                                                          staffMember
                                                              .startDate!.month,
                                                          staffMember
                                                              .startDate!.day));
                                              final shift = (vacant || preStart)
                                                  ? roster.getPatternShiftForDate(
                                                      personName, day)
                                                  : roster.getShiftForDate(
                                                      personName, day);
                                              final shiftColor =
                                                  _shiftColors[shift.toUpperCase()] ??
                                                      Colors.grey;
                                              return DataCell(
                                                InkWell(
                                                  onTap: () {
                                                    _setFocusedDate(day);
                                                    if (roster.readOnly) {
                                                      _showDayDetails(
                                                        personName,
                                                        day,
                                                        readOnly: true,
                                                      );
                                                    } else {
                                                      _showShiftOptions(
                                                          context, personName, day);
                                                    }
                                                  },
                                                  child: Container(
                                                    width: _dayCellWidthMonth,
                                                    height: _dayCellHeightMonth,
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      color: shiftColor
                                                          .withOpacity(
                                                              (vacant ||
                                                                      unavailable ||
                                                                      preStart)
                                                                  ? 0.08
                                                                  : 0.15),
                                                      border: Border.all(
                                                        color: shiftColor,
                                                        width: 1.5,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(6),
                                                      boxShadow: isToday
                                                          ? [
                                                              BoxShadow(
                                                                color: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .primary
                                                                    .withOpacity(
                                                                        0.35),
                                                                blurRadius: 6,
                                                                spreadRadius: 1,
                                                              ),
                                                            ]
                                                          : null,
                                                    ),
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.center,
                                                      children: [
                                                        Text(
                                                          shift,
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: (vacant ||
                                                                    unavailable ||
                                                                    preStart)
                                                                ? Colors.grey
                                                                : shiftColor,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                        if (vacant)
                                                          Text(
                                                            'Vacant',
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              color:
                                                                  Colors.grey[600],
                                                            ),
                                                          )
                                                        else if (unavailable)
                                                          Text(
                                                            _formatLeaveLabel(
                                                                staffMember
                                                                    .leaveType),
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              color:
                                                                  Colors.grey[600],
                                                            ),
                                                          )
                                                        else if (preStart)
                                                          Text(
                                                            'Not started',
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              color:
                                                                  Colors.grey[600],
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
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStaffColumn(
    BuildContext context,
    RosterNotifier roster,
    List<String> staff,
    bool isReadOnly,
  ) {
    final useCompactNames = _cellScale < 0.6;
    final nameFontSize = _cellScale < 0.55 ? 11.0 : 13.0;
    return Container(
      width: _staffColumnWidth,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: _headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withOpacity(0.3),
            child: Row(
              children: [
                  Text(
                    'Staff',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
          ...staff.map((personName) {
            final isSelected = _selectedStaffName == personName;
            final staffMember = roster.staffMembers.firstWhere(
              (s) => s.name == personName,
              orElse: () => models.StaffMember(
                  id: '',
                  name: personName,
                  isActive: true,
                  leaveBalance: 31.0,
              ),
            );
            _nameControllers[personName] ??=
                  TextEditingController(text: personName);
            return Tooltip(
              message: personName,
              child: Container(
                height: _rowHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withOpacity(0.35)
                      : null,
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      staffMember.isActive
                          ? Icons.person_rounded
                          : Icons.person_off_rounded,
                      size: 16,
                      color: staffMember.isActive ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    if (staffMember.employmentType == 'temporary') ...[
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Temp',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[800],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (useCompactNames)
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          _initialsForName(personName),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    if (useCompactNames) const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _nameControllers[personName]!,
                        onTap: () => _toggleSelectedStaff(personName),
                        focusNode: _nameFocusNodes.putIfAbsent(
                          personName,
                          () {
                            final node = FocusNode();
                            node.addListener(() {
                              if (!node.hasFocus) {
                                final current =
                                    _nameControllers[personName]!.text.trim();
                                if (current.isEmpty || current == personName) {
                                  _nameControllers[personName]!.text =
                                      personName;
                                  return;
                                }
                                final index = roster.staffMembers
                                    .indexWhere((s) => s.name == personName);
                                if (index != -1) {
                                  ref
                                      .read(rosterProvider)
                                      .renameStaff(index, current);
                                }
                              }
                            });
                            return node;
                          },
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        style: GoogleFonts.inter(fontSize: nameFontSize),
                        readOnly: isReadOnly,
                        onSubmitted: isReadOnly
                            ? null
                            : (newName) {
                                if (newName.trim().isNotEmpty &&
                                    newName != personName) {
                                  final index = roster.staffMembers
                                      .indexWhere((s) => s.name == personName);
                                  if (index != -1) {
                                    ref.read(rosterProvider).renameStaff(
                                          index,
                                          newName.trim(),
                                        );
                                  }
                                } else {
                                  _nameControllers[personName]!.text =
                                      personName;
                                }
                              },
                      ),
                    ),
                    if (!isReadOnly)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, size: 16),
                        onSelected: (value) {
                          switch (value) {
                            case 'leave':
                              _showLeaveDialog(personName);
                              break;
                            case 'overrides':
                              _showStaffOverrides(personName);
                              break;
                            case 'toggle':
                              final index = roster.staffMembers
                                  .indexWhere((s) => s.name == personName);
                              if (index != -1) {
                                ref
                                    .read(rosterProvider)
                                    .toggleStaffStatus(index);
                              }
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'leave',
                            child: ListTile(
                              leading: Icon(Icons.beach_access_rounded),
                              title: Text('Manage Leave'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'overrides',
                            child: ListTile(
                              leading: Icon(Icons.edit_calendar_rounded),
                              title: Text('View Overrides'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: ListTile(
                              leading: Icon(staffMember.isActive
                                  ? Icons.person_off_rounded
                                  : Icons.person_rounded),
                              title: Text(staffMember.isActive
                                  ? 'Deactivate'
                                  : 'Activate'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRibbonCell(
    BuildContext context,
    RosterNotifier roster,
    String personName,
    DateTime date,
  ) {
    final isReadOnly = roster.readOnly;
    final shift = roster.getShiftForDate(personName, date);
    final shiftColor = _shiftColors[shift.toUpperCase()] ?? Colors.grey;
    return InkWell(
      onTap: () {
        _setFocusedDate(date);
        if (isReadOnly) {
          _showDayDetails(personName, date, readOnly: true);
        } else {
          _showShiftOptions(context, personName, date);
        }
      },
      child: Container(
        width: _dayCellWidthWeek,
        height: _rowHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: shiftColor.withOpacity(0.15),
          border: Border(
            left: BorderSide(
              color: _isSameDay(date, DateTime.now())
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: _isSameDay(date, DateTime.now()) ? 2 : 0,
            ),
            right: BorderSide(color: Theme.of(context).dividerColor),
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              shift,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: shiftColor,
                fontSize: 14,
              ),
            ),
            if (shift == 'AL')
              Icon(
                Icons.beach_access_rounded,
                size: 12,
                color: shiftColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRibbon(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final today = _startOfDay(DateTime.now());
    final focus = _focusedDate ?? today;
    final isToday = _isSameDay(focus, today);
    final subtitle = DateFormat('EEEE, MMM d, yyyy').format(focus);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday ? 'Today' : 'Focused date',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Text(
                  DateFormat('MMM d, yyyy').format(focus),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Jump to year',
            onPressed: () => _showYearPicker(context),
            icon: const Icon(Icons.event),
          ),
          FilledButton.tonalIcon(
            onPressed: _smartHome,
            icon: const Icon(Icons.home_rounded, size: 16),
            label: const Text('Today'),
          ),
        ],
      ),
    );
  }

  Widget _buildRosterCards(
    BuildContext context,
    RosterNotifier roster,
    models.AppSettings settings,
    Map<String, HolidayItem> holidayMap,
    Map<String, List<HolidayItem>> observanceMap,
    Map<String, List<SportsEventItem>> sportsMap,
    Map<String, List<models.Event>> eventMap,
    DateTime weekStart,
  ) {
    final staff = roster.getActiveStaffNames();
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 300) return;
        _animateWeekDelta(velocity > 0 ? -1 : 1);
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: staff.length,
        itemBuilder: (context, index) {
          final personName = staff[index];
          final isSelected = _selectedStaffName == personName;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: isSelected
                ? Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withOpacity(0.25)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => _toggleSelectedStaff(personName),
                    child: Text(
                      personName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: _dayCellHeightWeek,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: days.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, dayIndex) {
                      final day = days[dayIndex];
                      final shift = roster.getShiftForDate(personName, day);
                      final shiftColor =
                          _shiftColors[shift.toUpperCase()] ?? Colors.grey;
                        final holiday = holidayMap[_dateKey(day)];
                        final events = eventMap[_dateKey(day)] ?? [];
                        final observances =
                            observanceMap[_dateKey(day)] ?? [];
                        final sportsEvents =
                            sportsMap[_dateKey(day)] ?? [];
                        return GestureDetector(
                          onTap: () {
                            _setFocusedDate(day);
                            if (roster.readOnly) {
                              _showDayDetails(
                                personName,
                                day,
                                readOnly: true,
                              );
                            } else {
                              _showShiftOptions(context, personName, day);
                            }
                          },
                          onHorizontalDragEnd: roster.readOnly
                              ? null
                              : (details) {
                                  final delta = details.primaryVelocity ?? 0;
                                  if (delta == 0) return;
                                  _applySwipeShift(
                                    roster,
                                    personName,
                                    day,
                                    delta,
                                  );
                                },
                          child: Container(
                            width: _dayCellWidthWeek,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: shiftColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: shiftColor, width: 2),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  DateFormat('EEE').format(day),
                                  style:
                                      Theme.of(context).textTheme.labelSmall,
                                ),
                                Text(
                                  shift,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: shiftColor,
                                  ),
                                ),
                                if (holiday != null ||
                                    events.isNotEmpty ||
                                    observances.isNotEmpty ||
                                    sportsEvents.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  _buildEventLine(
                                    context,
                                    holiday: holiday,
                                    events: events,
                                    observances: observances,
                                    sportsEvents: sportsEvents,
                                  ),
                                ],
                            ],
                          ),
                        ),
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

  void _applySwipeShift(
    RosterNotifier roster,
    String personName,
    DateTime date,
    double velocity,
  ) {
    final shiftTypes = [
      ...roster.getShiftTypes(),
      'OFF',
      'AL',
    ].toSet().toList();
    if (shiftTypes.isEmpty) return;
    final currentShift = roster.getShiftForDate(personName, date);
    final currentIndex =
        shiftTypes.indexWhere((shift) => shift == currentShift);
    final direction = velocity < 0 ? 1 : -1;
    final nextIndex =
        (currentIndex + direction + shiftTypes.length) % shiftTypes.length;
    final nextShift = shiftTypes[nextIndex];
    roster.setOverride(personName, date, nextShift, 'Swipe edit');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Set $personName to $nextShift')),
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  void _showShiftOptions(
      BuildContext context, String personName, DateTime date) {
    final settings = ref.read(settingsProvider);
    final dateKey = _dateKey(date);
    final isHidden = settings.hiddenOverlayDates.contains(dateKey);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                    '${DateFormat('EEE, MMM d').format(date)} - $personName',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Add Override'),
              subtitle: const Text('Set custom shift for this day'),
              onTap: () {
                    Navigator.pop(context);
                    _showAddOverrideDialog(personName, date);
              },
            ),
            ListTile(
              leading: const Icon(Icons.date_range_rounded),
              title: const Text('Bulk Override'),
              subtitle: const Text('Set overrides for multiple days'),
              onTap: () {
                    Navigator.pop(context);
                    _showBulkOverrideDialog(personName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_rounded),
              title: const Text('Add Event'),
              subtitle: const Text('Create an event for this date'),
              onTap: () {
                    Navigator.pop(context);
                    _showAddEventForDate(date);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Quick Swap'),
              subtitle: const Text('Swap this shift with another staff member'),
              onTap: () {
                Navigator.pop(context);
                _showQuickSwapDialog(context, personName, date);
              },
            ),
              ListTile(
                leading: const Icon(Icons.event_available_rounded),
                title: const Text('View Events on this date'),
                subtitle: const Text('Edit or delete events for this date'),
                onTap: () {
                      Navigator.pop(context);
                      _showEventsForDate(date);
                },
              ),
              ListTile(
                leading: Icon(
                  isHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                ),
                title: Text(
                  isHidden
                      ? 'Show overlays for this date'
                      : 'Hide overlays for this date',
                ),
                subtitle: const Text('Hide holiday, observance, and sports badges'),
                onTap: () {
                  final updated =
                      List<String>.from(settings.hiddenOverlayDates);
                  if (isHidden) {
                    updated.remove(dateKey);
                  } else {
                    updated.add(dateKey);
                  }
                  ref.read(settingsProvider.notifier).updateSettings(
                        settings.copyWith(hiddenOverlayDates: updated),
                      );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('View Details'),
                subtitle: const Text('See shift information and history'),
                onTap: () {
                    Navigator.pop(context);
                    _showDayDetails(personName, date);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQuickSwapDialog(
    BuildContext context,
    String fromPerson,
    DateTime date,
  ) async {
    final roster = ref.read(rosterProvider);
    if (roster.readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read-only roster cannot be edited.')),
      );
      return;
    }
    final staff = roster.staffMembers
        .map((s) => s.name)
        .where((name) => name != fromPerson)
        .toList();
    if (staff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other staff available to swap.')),
      );
      return;
    }
    final preferred = <String>[];
    final others = <String>[];
    for (final name in staff) {
      final shift = roster.getShiftForDate(name, date);
      if (shift == 'OFF' || shift == 'R') {
        preferred.add(name);
      } else {
        others.add(name);
      }
    }
    final options = [...preferred, ...others];
    String toPerson = options.first;
    bool recordDebt = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quick Swap'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${DateFormat('EEE, MMM d').format(date)} · $fromPerson',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: toPerson,
              items: options
                  .map(
                    (name) => DropdownMenuItem(
                      value: name,
                      child: Text(
                        '$name (${roster.getShiftForDate(name, date)})',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  toPerson = value;
                }
              },
              decoration: const InputDecoration(
                labelText: 'Swap with',
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: recordDebt,
              onChanged: (value) {
                recordDebt = value ?? true;
              },
              title: const Text('Record swap debt'),
              subtitle: const Text('Track owed shift if needed'),
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
            child: const Text('Apply Swap'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final applied = roster.applySwapForDate(
      fromPerson: fromPerson,
      toPerson: toPerson,
      date: date,
      reason: 'Quick swap',
    );
    if (applied == true && recordDebt) {
      roster.addSwapDebt(
        fromPerson: fromPerson,
        toPerson: toPerson,
        daysOwed: 1,
        reason: 'Quick swap',
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            applied == true
                ? 'Swap applied for $fromPerson and $toPerson'
                : 'Swap failed. Check shifts for both staff.',
          ),
        ),
      );
    }
  }

  Future<void> _showAddOverrideDialog(String personName, DateTime date) async {
    await showDialog(
      context: context,
      builder: (context) => AddOverrideDialog(
        person: personName,
        date: date,
        onAdd: (shift, reason) {
          ref.read(rosterProvider).setOverride(personName, date, shift, reason);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Override added successfully')),
          );
        },
      ),
    );
  }

  Future<void> _showAddEventForDate(DateTime date) async {
    await showDialog(
      context: context,
      builder: (context) => AddEventDialog(
        initialDate: date,
        onAddEvents: (events) {
          final roster = ref.read(rosterProvider);
          if (events.length == 1) {
            roster.addEvent(events.first);
          } else {
            roster.addBulkEvents(events);
          }
        },
      ),
    );
  }

  Future<void> _showEventsForDate(DateTime date) async {
    final roster = ref.read(rosterProvider);
    final dayEvents = roster.events.where((event) {
      return event.date.year == date.year &&
          event.date.month == date.month &&
          event.date.day == date.day;
    }).toList();

    if (dayEvents.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No events on this date.')),
        );
      }
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Events on ${DateFormat('MMM d, yyyy').format(date)}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: dayEvents.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final event = dayEvents[index];
              return ListTile(
                title: Text(event.title),
                subtitle: event.description != null
                    ? Text(event.description!)
                    : null,
                leading: const Icon(Icons.event),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _showEditEventDialog(event);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        final confirmed = await _confirmDeleteEvent(
                          context,
                          event.title,
                        );
                        if (confirmed && mounted) {
                          ref.read(rosterProvider).deleteEvent(event.id);
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
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

  Future<void> _showEditEventDialog(models.Event event) async {
    await showDialog(
      context: context,
      builder: (context) => AddEventDialog(
        initialDate: event.date,
        initialTitle: event.title,
        onAddEvents: (events) {
          if (events.isEmpty) return;
          final roster = ref.read(rosterProvider);
          roster.deleteEvent(event.id);
          if (events.length == 1) {
            roster.addEvent(events.first);
          } else {
            roster.addBulkEvents(events);
          }
        },
      ),
    );
  }

  Future<bool> _confirmDeleteEvent(BuildContext context, String title) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event?'),
        content: Text('Delete "$title"?'),
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
    );
    return result ?? false;
  }

  Future<void> _showBulkOverrideDialog(String personName) async {
    await showDialog(
      context: context,
      builder: (context) => BulkOverrideDialog(
        person: personName,
        onAdd: (startDate, endDate, shift, reason) {
          ref.read(rosterProvider).addBulkOverrides(
                    personName,
                    startDate,
                    endDate,
                    shift,
                    reason,
              );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                    'Bulk override added for ${endDate.difference(startDate).inDays + 1} days',
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDayDetails(String personName, DateTime date,
      {bool readOnly = false}) {
    final roster = ref.read(rosterProvider);
    final shift = roster.getShiftForDate(personName, date);
    final override = roster.overrides.firstWhere(
      (o) =>
          o.personName == personName &&
          o.date.year == date.year &&
          o.date.month == date.month &&
          o.date.day == date.day,
      orElse: () => models.Override(
        id: '',
        personName: '',
        date: DateTime.now(),
        shift: '',
        createdAt: DateTime.now(),
      ),
    );

    final shiftColor = _shiftColors[shift.toUpperCase()] ?? Colors.grey;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            '$personName - ${DateFormat('EEE, MMM d, yyyy').format(date)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: shiftColor.withOpacity(0.2),
                      border: Border.all(color: shiftColor, width: 2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        shift,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: shiftColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
              ),
              title: const Text('Scheduled Shift'),
              subtitle: Text(
                    shift,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: shiftColor,
                    ),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            if (override.id.isNotEmpty) ...[
              const Divider(),
              ListTile(
                    leading: const Icon(Icons.edit_calendar_rounded),
                    title: const Text('Override Applied'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shift: ${override.shift}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _shiftColors[override.shift.toUpperCase()] ??
                                Colors.grey,
                          ),
                        ),
                        if (override.reason != null)
                          Text('Reason: ${override.reason}'),
                        Text(
                          'Added: ${DateFormat('MMM d, yyyy').format(override.createdAt)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    contentPadding: EdgeInsets.zero,
              ),
              TextButton.icon(
                    onPressed: readOnly
                        ? null
                        : () {
                            roster.overrides
                                .removeWhere((o) => o.id == override.id);
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Override removed')),
                            );
                            roster.notifyListeners();
                          },
                    icon: const Icon(Icons.delete_rounded, color: Colors.red),
                    label: const Text('Remove Override',
                        style: TextStyle(color: Colors.red)),
              ),
            ] else ...[
              const Divider(),
              Text(
                    'No overrides applied',
                    style: GoogleFonts.inter(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
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

  void _showLeaveDialog(String personName) {
    final roster = ref.read(rosterProvider);
    final staffMember = roster.staffMembers.firstWhere(
      (s) => s.name == personName,
      orElse: () => models.StaffMember(
        id: '',
        name: personName,
        isActive: true,
        leaveBalance: 31.0, // Updated to 31.0 days
      ),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Manage Leave - $personName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Current Leave Balance: ${staffMember.leaveBalance.toStringAsFixed(1)} days',
              style: GoogleFonts.inter(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          roster.adjustLeaveBalance(personName, 1.0);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Leave day added')),
                          );
                        },
                        child: const Text('+1 Day'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          roster.adjustLeaveBalance(personName, -1.0);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Leave day deducted')),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                        child: const Text('-1 Day'),
                      ),
                    ),
              ],
            ),
          ],
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

  void _showStaffOverrides(String personName) {
    final roster = ref.read(rosterProvider);
    final overrides = roster.getOverridesForPerson(personName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Overrides - $personName'),
        content: SizedBox(
          width: double.maxFinite,
          child: overrides.isEmpty
              ? const Text('No overrides found')
              : ListView.builder(
                      shrinkWrap: true,
                      itemCount: overrides.length,
                      itemBuilder: (context, index) {
                        final override = overrides[index];
                        final shiftColor =
                            _shiftColors[override.shift.toUpperCase()] ??
                                Colors.grey;

                        return ListTile(
                          leading: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: shiftColor.withOpacity(0.2),
                              border: Border.all(color: shiftColor, width: 2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                override.shift,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: shiftColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          title:
                              Text(DateFormat('MMM d, yyyy').format(override.date)),
                          subtitle: override.reason != null
                              ? Text(override.reason!)
                              : null,
                          trailing: IconButton(
                            icon:
                                const Icon(Icons.delete_rounded, color: Colors.red),
                            onPressed: () {
                              roster.overrides
                                  .removeWhere((o) => o.id == override.id);
                              Navigator.pop(context);
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Override Removed'),
                                  content: const Text(
                                      'The override has been removed successfully.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              );
                              roster.notifyListeners();
                            },
                          ),
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

  Future<void> _showGuestLeaveRequestDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final notesController = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final startLabel = startDate == null
              ? 'Select start date'
              : DateFormat('MMM d, yyyy').format(startDate!);
          final endLabel = endDate == null
              ? 'Select end date'
              : DateFormat('MMM d, yyyy').format(endDate!);

          return AlertDialog(
            title: const Text('Leave Request'),
            content: SingleChildScrollView(
              child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime.now()
                                      .subtract(const Duration(days: 1)),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                );
                                if (picked != null) {
                                  setState(() {
                                    startDate = picked;
                                    if (endDate != null &&
                                        endDate!.isBefore(picked)) {
                                      endDate = picked;
                                    }
                                  });
                                }
                              },
                              child: Text(startLabel),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: startDate ?? DateTime.now(),
                                  firstDate:
                                      startDate ?? DateTime.now(),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                );
                                if (picked != null) {
                                  setState(() {
                                    endDate = picked;
                                  });
                                }
                              },
                              child: Text(endLabel),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder(),
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
                onPressed: () async {
                  if (nameController.text.trim().isEmpty || startDate == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Name and start date are required'),
                      ),
                    );
                    return;
                  }
                  try {
                    await ref.read(rosterProvider).submitSharedLeaveRequest(
                          guestName: nameController.text.trim(),
                          startDate: startDate!,
                          endDate: endDate,
                          notes: notesController.text.trim(),
                        );
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Leave request submitted'),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showYearPicker(BuildContext context) async {
    final now = DateTime.now();
    int selectedYear = (_focusedDate ?? now).year;
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jump to year'),
        content: SizedBox(
          width: 300,
          height: 320,
          child: YearPicker(
            firstDate: DateTime(now.year - 20),
            lastDate: DateTime(now.year + 20),
            selectedDate: DateTime(selectedYear),
            onChanged: (date) {
              Navigator.pop(context, date.year);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final target = DateTime(result, (_focusedDate ?? now).month, 1);
    setState(() {
      _currentMonthAnchor = DateTime(target.year, target.month);
      _focusedDate = target;
      _monthAutoSnapEnabled = false;
      _initialMonthSnapDone = true;
    });
    await Future.delayed(const Duration(milliseconds: 100));
    if (_monthScrollController.hasClients) {
      _monthScrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToMonth(target, alignment: 0.1);
      _scrollToTodayDayInMonth(target);
    });
  }

  Widget _buildRosterTable(
    BuildContext context,
    RosterNotifier roster,
    models.AppSettings settings,
    Map<String, HolidayItem> holidayMap,
    Map<String, List<HolidayItem>> observanceMap,
    Map<String, List<SportsEventItem>> sportsMap,
    Map<String, List<models.Event>> eventMap,
    DateTime weekStart,
    bool timelineMode,
  ) {
    final isReadOnly = roster.readOnly;
    final staffMembers = roster.getStaffForRange(
      weekStart,
      weekStart.add(const Duration(days: 6)),
    );
    final staff = staffMembers.map((s) => s.name).toList();
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStaffColumn(context, roster, staff, isReadOnly),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              headingRowHeight: _headerHeight,
              dataRowMinHeight: _rowHeight,
              dataRowMaxHeight: _rowHeight,
              headingRowColor: WidgetStateProperty.resolveWith(
                (states) => Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withOpacity(0.3),
              ),
              border: TableBorder.all(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
              columns: [
                ...days.map((day) {
                  final isToday = _isSameDay(day, DateTime.now());
                  final holiday = holidayMap[_dateKey(day)];
                  final events = eventMap[_dateKey(day)] ?? [];
                  final observances = observanceMap[_dateKey(day)] ?? [];
                  final sportsEvents = sportsMap[_dateKey(day)] ?? [];
                  final hasOverlay = holiday != null ||
                      events.isNotEmpty ||
                      observances.isNotEmpty ||
                      sportsEvents.isNotEmpty;
                  return DataColumn(
                    label: InkWell(
                      onTap: hasOverlay
                          ? () => _showOverlaySummary(
                                day,
                                holiday: holiday,
                                observances: observances,
                                sportsEvents: sportsEvents,
                              )
                          : null,
                      child: SizedBox(
                        width: _dayCellWidthWeek,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat('EEE').format(day),
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                color: isToday
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                              ),
                            ),
                            Text(
                              DateFormat('MMM d').format(day),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: isToday
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                              ),
                            ),
                            if (hasOverlay) ...[
                              const SizedBox(height: 2),
                              _buildEventLine(
                                context,
                                holiday: holiday,
                                events: events,
                                observances: observances,
                                sportsEvents: sportsEvents,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
              rows: staffMembers.map((staffMember) {
                final personName = staffMember.name;
                final isSelected = _selectedStaffName == personName;
                return DataRow(
                  color: WidgetStateProperty.resolveWith(
                    (states) => isSelected
                        ? Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withOpacity(0.35)
                        : null,
                  ),
                  cells: [
                    ...days.map((day) {
                      final employed =
                          roster.isStaffEmployedOnDate(staffMember, day);
                      final unavailable =
                          roster.isStaffUnavailableOnDate(staffMember, day);
                      final vacant = roster.isStaffVacantOnDate(staffMember, day) &&
                          staffMember.employmentType == 'permanent';
                      final preStart = staffMember.startDate != null &&
                          day.isBefore(DateTime(
                              staffMember.startDate!.year,
                              staffMember.startDate!.month,
                              staffMember.startDate!.day));
                      final shift = (vacant || preStart)
                          ? roster.getPatternShiftForDate(personName, day)
                          : roster.getShiftForDate(personName, day);
                      final shiftColor =
                          _shiftColors[shift.toUpperCase()] ?? Colors.grey;
                      final holiday = holidayMap[_dateKey(day)];
                      final events = eventMap[_dateKey(day)] ?? [];
                      final observances = observanceMap[_dateKey(day)] ?? [];
                      final sportsEvents = sportsMap[_dateKey(day)] ?? [];
                      final hasOverlayCell = holiday != null ||
                          events.isNotEmpty ||
                          observances.isNotEmpty ||
                          sportsEvents.isNotEmpty;
                      return DataCell(
                        InkWell(
                          onTap: () {
                            _setFocusedDate(day);
                            if (isReadOnly) {
                              _showDayDetails(
                                personName,
                                day,
                                readOnly: true,
                              );
                            } else {
                              _showShiftOptions(context, personName, day);
                            }
                          },
                          child: Container(
                            width: _dayCellWidthWeek,
                            height: _dayCellHeightWeek,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: shiftColor.withOpacity(
                                  (vacant || unavailable || preStart)
                                      ? 0.08
                                      : 0.15),
                              border: Border.all(
                                color: shiftColor,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        shift,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: (vacant || unavailable || preStart)
                                              ? Colors.grey
                                              : shiftColor,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (vacant)
                                        Text(
                                          'Vacant',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey[600],
                                          ),
                                        )
                                      else if (unavailable)
                                        Text(
                                          _formatLeaveLabel(
                                              staffMember.leaveType),
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey[600],
                                          ),
                                        )
                                      else if (preStart)
                                        Text(
                                          'Not started',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      if (shift == 'AL')
                                        Icon(
                                          Icons.beach_access_rounded,
                                          size: 12,
                                          color: shiftColor,
                                        ),
                                    ],
                                  ),
                                ),
                                // Event lines appear only in the date header.
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
      ],
    );
  }

  Future<void> _showOverlaySummary(
    DateTime date, {
    HolidayItem? holiday,
    List<HolidayItem> observances = const [],
    List<SportsEventItem> sportsEvents = const [],
  }) async {
    final roster = ref.read(rosterProvider);
    final dayEvents = roster.events.where((event) {
      return event.date.year == date.year &&
          event.date.month == date.month &&
          event.date.day == date.day;
    }).toList();

    final items = <Map<String, dynamic>>[];
    if (holiday != null) {
      items.add({
        'title': holiday.localName.isNotEmpty ? holiday.localName : holiday.name,
        'subtitle': 'Holiday',
        'color': _eventLineColor(context, models.EventType.holiday),
      });
    }
    for (final obs in observances) {
      final type = _inferObservanceType(obs.localName);
      items.add({
        'title': obs.localName,
        'subtitle': _eventTypeLabel(type),
        'color': _eventLineColor(context, type),
      });
    }
    for (final sport in sportsEvents) {
      items.add({
        'title': sport.name,
        'subtitle': sport.league,
        'color': _eventLineColor(context, models.EventType.sports),
      });
    }
    for (final event in dayEvents) {
      items.add({
        'title': event.title,
        'subtitle': event.description?.isNotEmpty == true
            ? '${_eventTypeLabel(event.eventType)} - ${event.description}'
            : _eventTypeLabel(event.eventType),
        'color': _eventLineColor(context, event.eventType),
      });
    }

    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No events on this date.')),
        );
      }
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Events on ${DateFormat('MMM d, yyyy').format(date)}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                title: Text(item['title'] as String),
                subtitle: Text(item['subtitle'] as String),
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: item['color'] as Color,
                    shape: BoxShape.circle,
                  ),
                ),
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
}

