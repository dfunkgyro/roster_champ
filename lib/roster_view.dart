import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers.dart';
import 'models.dart' as models;
import 'dialogs.dart';
import 'services/holiday_service.dart';
import 'services/weather_service.dart';
import 'services/time_service.dart';
import 'aws_service.dart';
import 'screens/pattern_editor_screen.dart';
import 'screens/roster_sharing_screen.dart';
import 'roster_generator_view.dart';
import 'utils/error_handler.dart';

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
  final Map<String, TextEditingController> _nameControllers = {};
  final Map<String, FocusNode> _nameFocusNodes = {};
  final Map<String, List<HolidayItem>> _holidayCache = {};
  String? _selectedStaffName;
  bool _showMonthOverview = false;
  bool _focusMode = false;
  double _cellScale = 1.0;
  double _scaleStart = 1.0;
  final GlobalKey _todayMonthKey = GlobalKey();
  bool _showTodayChip = false;
  Timer? _todayChipTimer;
  bool _ignoreScrollNotifications = false;

  double get _headerHeight => 56 * _cellScale;
  double get _rowHeight => 56 * _cellScale;
  double get _staffColumnWidth =>
      (170 * _cellScale).clamp(130, 220).toDouble();
  double get _dayCellWidthWeek =>
      (80 * _cellScale).clamp(56, 110).toDouble();
  double get _dayCellHeightWeek =>
      (48 * _cellScale).clamp(36, 70).toDouble();
  double get _dayCellWidthMonth =>
      (48 * _cellScale).clamp(36, 70).toDouble();
  double get _dayCellHeightMonth =>
      (36 * _cellScale).clamp(28, 56).toDouble();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToToday();
    });
  }

  // Color system matching pattern editor
  // Update the shift colors in the RosterView to match pattern editor
  final Map<String, Color> _shiftColors = {
    'D': Colors.blue,
    'D12': Colors.blueAccent,
    'N': Colors.purple,
    'L': Colors.orange,
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
            !_showMonthOverview &&
            !_focusMode)
          _buildWeatherStrip(settings),
        _buildViewModeToggle(context),
        _showMonthOverview
            ? _buildMonthNavigator(context)
            : _buildWeekNavigator(context),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            children: [
              _showMonthOverview
                  ? _buildMonthOverview(context, roster, settings)
                  : settings.showHolidayOverlay
                      ? FutureBuilder<Map<String, HolidayItem>>(
                          future: _loadHolidayMapForRange(
                            settings,
                            _currentWeekStart,
                            _currentWeekStart.add(const Duration(days: 6)),
                          ),
                          builder: (context, snapshot) {
                            final holidayMap = snapshot.data ?? {};
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            return isCompactLayout
                                ? _buildRosterCards(
                                    context,
                                    roster,
                                    settings,
                                    holidayMap,
                                  )
                                : GestureDetector(
                                    onScaleStart: (details) {
                                      _scaleStart = _cellScale;
                                    },
                                    onScaleUpdate: (details) {
                                      if (details.scale == 1.0) return;
                                      setState(() {
                                        _cellScale =
                                            (_scaleStart * details.scale)
                                                .clamp(0.7, 1.2)
                                                .toDouble();
                                      });
                                    },
                                    child: SingleChildScrollView(
                                      child: _buildRosterTable(
                                        context,
                                        roster,
                                        settings,
                                        holidayMap,
                                      ),
                                    ),
                                  );
                          },
                        )
                      : isCompactLayout
                          ? _buildRosterCards(
                              context,
                              roster,
                              settings,
                              const {},
                            )
                          : GestureDetector(
                              onScaleStart: (details) {
                                _scaleStart = _cellScale;
                              },
                              onScaleUpdate: (details) {
                                if (details.scale == 1.0) return;
                                setState(() {
                                  _cellScale = (_scaleStart * details.scale)
                                      .clamp(0.7, 1.2)
                                      .toDouble();
                                });
                              },
                              child: SingleChildScrollView(
                                child: _buildRosterTable(
                                  context,
                                  roster,
                                  settings,
                                  const {},
                                ),
                              ),
                            ),
              if (_showTodayChip)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FilledButton.icon(
                    onPressed: _jumpToToday,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ToggleButtons(
            isSelected: [_showMonthOverview == false, _showMonthOverview == true],
            onPressed: (index) {
              setState(() {
                _showMonthOverview = index == 1;
              });
              _scrollToToday();
            },
            borderRadius: BorderRadius.circular(8),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.calendar_view_week_rounded, size: 18),
                    SizedBox(width: 6),
                    Text('Week'),
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
            onPressed: () {
              _jumpToToday();
            },
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
              PopupMenuItem(value: 0.9, child: Text('Medium')),
              PopupMenuItem(value: 0.8, child: Text('Small')),
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
                          '${info.maxTemp.toStringAsFixed(0)}° / ${info.minTemp.toStringAsFixed(0)}° • $precip% rain',
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

  Widget _buildWeekNavigator(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () {
              setState(() {
                _currentWeekStart =
                    _currentWeekStart.subtract(const Duration(days: 7));
              });
              _markScrolledAway();
            },
          ),
          Column(
            children: [
              Text(
                'Starting ${DateFormat('MMM d, yyyy').format(_currentWeekStart)}',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _getWeekRange(),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.today_rounded),
            onPressed: () {
              _jumpToToday();
            },
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () {
              setState(() {
                _currentWeekStart =
                    _currentWeekStart.add(const Duration(days: 7));
              });
              _markScrolledAway();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthNavigator(BuildContext context) {
    final months = _buildMonthList(_currentMonthAnchor);
    final startLabel = DateFormat('MMM yyyy').format(months.first);
    final endLabel = DateFormat('MMM yyyy').format(months.last);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
            tooltip: 'Previous year',
            onPressed: () {
              setState(() {
                _currentMonthAnchor = DateTime(
                  _currentMonthAnchor.year - 1,
                  _currentMonthAnchor.month,
                );
              });
              _markScrolledAway();
            },
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous month',
            onPressed: () {
              setState(() {
                _currentMonthAnchor = DateTime(
                  _currentMonthAnchor.year,
                  _currentMonthAnchor.month - 1,
                );
              });
              _markScrolledAway();
            },
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '$startLabel - $endLabel',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Scroll to browse months',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.today_rounded),
            tooltip: 'Go to current month',
            onPressed: () {
              _jumpToToday();
            },
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next month',
            onPressed: () {
              setState(() {
                _currentMonthAnchor = DateTime(
                  _currentMonthAnchor.year,
                  _currentMonthAnchor.month + 1,
                );
              });
              _markScrolledAway();
            },
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
            tooltip: 'Next year',
            onPressed: () {
              setState(() {
                _currentMonthAnchor = DateTime(
                  _currentMonthAnchor.year + 1,
                  _currentMonthAnchor.month,
                );
              });
              _markScrolledAway();
            },
          ),
        ],
      ),
    );
  }

  String _getWeekRange() {
    final weekEnd = _currentWeekStart.add(const Duration(days: 6));
    return '${DateFormat('MMM d').format(_currentWeekStart)} - ${DateFormat('MMM d').format(weekEnd)}';
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final delta = normalized.weekday - DateTime.monday;
    return normalized.subtract(Duration(days: delta));
  }

  static DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isSameMonth(DateTime date1, DateTime date2) {
    return date1.year == date2.year && date1.month == date2.month;
  }

  void _jumpToToday() {
    setState(() {
      final today = _startOfDay(DateTime.now());
      _currentWeekStart = today;
      _currentMonthAnchor = DateTime(today.year, today.month);
      _showTodayChip = false;
    });
    _todayChipTimer?.cancel();
    _scrollToToday();
  }

  void _scrollToToday() {
    _ignoreScrollNotifications = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_showMonthOverview) {
        _scrollToTodayMonth();
      } else {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
      Future.delayed(const Duration(milliseconds: 350), () {
        _ignoreScrollNotifications = false;
      });
    });
  }

  void _scrollToTodayMonth() {
    final context = _todayMonthKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.1,
      duration: const Duration(milliseconds: 300),
    );
  }

  void _markScrolledAway() {
    if (_ignoreScrollNotifications) return;
    if (_showTodayChip) return;
    setState(() => _showTodayChip = true);
    _todayChipTimer?.cancel();
    _todayChipTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() => _showTodayChip = false);
    });
  }

  List<DateTime> _buildMonthList(DateTime anchor) {
    return List.generate(
      12,
      (i) => DateTime(anchor.year, anchor.month + i, 1),
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
    if (!settings.showHolidayOverlay) return {};
    if (settings.holidayTypes.isEmpty) return {};
    final years = <int>{start.year, end.year};
    final all = <HolidayItem>[];

    for (final year in years) {
      final key = _holidayCacheKey(settings.holidayCountryCode, year);
      if (!_holidayCache.containsKey(key)) {
        final fetched = await HolidayService.instance.getHolidays(
          countryCode: settings.holidayCountryCode,
          year: year,
        );
        _holidayCache[key] = fetched;
      }
      all.addAll(_holidayCache[key]!);
    }

    final filtered = all.where((holiday) {
      return holiday.types.any(settings.holidayTypes.contains);
    });

    final map = <String, HolidayItem>{};
    for (final holiday in filtered) {
      map[_dateKey(holiday.date)] = holiday;
    }
    return map;
  }

  Widget _buildMonthOverview(
    BuildContext context,
    RosterNotifier roster,
    models.AppSettings settings,
  ) {
    final months = _buildMonthList(_currentMonthAnchor);
    final start = months.first;
    final end = DateTime(months.last.year, months.last.month + 1, 0);
    final staff = roster.getActiveStaffNames();
    return FutureBuilder<Map<String, HolidayItem>>(
      future: settings.showHolidayOverlay
          ? _loadHolidayMapForRange(settings, start, end)
          : Future.value(const {}),
      builder: (context, snapshot) {
        final holidayMap = snapshot.data ?? {};
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return GestureDetector(
          onScaleStart: (details) {
            _scaleStart = _cellScale;
          },
          onScaleUpdate: (details) {
            if (details.scale == 1.0) return;
            setState(() {
              _cellScale =
                  (_scaleStart * details.scale).clamp(0.7, 1.2).toDouble();
            });
          },
          child: Scrollbar(
            controller: _monthScrollController,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification) {
                  _markScrolledAway();
                }
                return false;
              },
              child: ListView.builder(
                controller: _monthScrollController,
                padding: const EdgeInsets.all(12),
                itemCount: months.length,
                itemBuilder: (context, index) {
                  final monthStart = months[index];
                  final daysInMonth =
                      DateTime(monthStart.year, monthStart.month + 1, 0).day;
                  final days = List.generate(
                    daysInMonth,
                    (i) => DateTime(monthStart.year, monthStart.month, i + 1),
                  );
                  final isTodayMonth =
                      _isSameMonth(monthStart, DateTime.now());
                  return Card(
                    key: isTodayMonth ? _todayMonthKey : null,
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
                                        return DataColumn(
                                          label: SizedBox(
                                            width: _dayCellWidthMonth,
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  DateFormat('E').format(day),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
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
                                                if (holiday != null)
                                                  Icon(
                                                    Icons.event_available,
                                                    size: 10,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                    rows: staff.map((personName) {
                                      final isSelected =
                                          _selectedStaffName == personName;
                                      return DataRow(
                                        color:
                                            WidgetStateProperty.resolveWith(
                                          (states) => isSelected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                                  .withOpacity(0.35)
                                              : null,
                                        ),
                                        cells: [
                                          ...days.map((day) {
                                            final shift =
                                                roster.getShiftForDate(
                                              personName,
                                              day,
                                            );
                                            final shiftColor = _shiftColors[
                                                    shift.toUpperCase()] ??
                                                Colors.grey;
                                            return DataCell(
                                              InkWell(
                                                onTap: () {
                                                  if (roster.readOnly) {
                                                    _showDayDetails(
                                                      personName,
                                                      day,
                                                      readOnly: true,
                                                    );
                                                  } else {
                                                    _showShiftOptions(
                                                      context,
                                                      personName,
                                                      day,
                                                    );
                                                  }
                                                },
                                                child: Container(
                                                  width: _dayCellWidthMonth,
                                                  height: _dayCellHeightMonth,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: shiftColor
                                                        .withOpacity(0.15),
                                                    border: Border.all(
                                                      color: shiftColor,
                                                      width: 1.5,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                    boxShadow: _isSameDay(
                                                            day,
                                                            DateTime.now())
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
                                                  child: Text(
                                                    shift,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: shiftColor,
                                                      fontSize: 11,
                                                    ),
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

  Widget _buildRosterTable(
    BuildContext context,
    RosterNotifier roster,
    models.AppSettings settings,
    Map<String, HolidayItem> holidayMap,
  ) {
    final isReadOnly = roster.readOnly;
    final staff = roster.getActiveStaffNames();
    final days =
        List.generate(7, (i) => _currentWeekStart.add(Duration(days: i)));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStaffColumn(context, roster, staff, isReadOnly),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                  if (notification is ScrollUpdateNotification) {
                    _markScrolledAway();
                  }
                  return false;
              },
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
                      return DataColumn(
                        label: SizedBox(
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
                              if (holiday != null)
                                Tooltip(
                                  message: holiday.localName,
                                  child: Icon(
                                    Icons.event_available,
                                    size: 12,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              if (isToday)
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                  rows: staff.map((personName) {
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
                          final shift = roster.getShiftForDate(personName, day);
                          final isToday = _isSameDay(day, DateTime.now());
                          final shiftColor =
                              _shiftColors[shift.toUpperCase()] ?? Colors.grey;

                          final holiday = holidayMap[_dateKey(day)];
                          return DataCell(
                            InkWell(
                              onTap: () {
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
                                  color: shiftColor.withOpacity(0.15),
                                  border: Border.all(
                                    color: shiftColor,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: isToday
                                      ? [
                                          BoxShadow(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withOpacity(0.3),
                                            blurRadius: 4,
                                            spreadRadius: 1,
                                          )
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
                                              color: shiftColor,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (shift == 'L')
                                            Icon(
                                              Icons.beach_access_rounded,
                                              size: 12,
                                              color: shiftColor,
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (holiday != null)
                                      Positioned(
                                        right: 4,
                                        top: 4,
                                        child: Tooltip(
                                          message: holiday.localName,
                                          child: Icon(
                                            Icons.event_available,
                                            size: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
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
    );
  }

  Widget _buildStaffColumn(
    BuildContext context,
    RosterNotifier roster,
    List<String> staff,
    bool isReadOnly,
  ) {
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
            return Container(
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
                                _nameControllers[personName]!.text = personName;
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
                        style: GoogleFonts.inter(fontSize: 14),
                        readOnly: isReadOnly,
                        onSubmitted: isReadOnly
                            ? null
                            : (newName) {
                                if (newName.trim().isNotEmpty &&
                                    newName != personName) {
                                  final index = roster.staffMembers
                                      .indexWhere((s) => s.name == personName);
                                  if (index != -1) {
                                    ref
                                        .read(rosterProvider)
                                        .renameStaff(index, newName.trim());
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
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRosterCards(
    BuildContext context,
    RosterNotifier roster,
    models.AppSettings settings,
    Map<String, HolidayItem> holidayMap,
  ) {
    final staff = roster.getActiveStaffNames();
    final days =
        List.generate(7, (i) => _currentWeekStart.add(Duration(days: i)));

    return ListView.builder(
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
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
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
                      return GestureDetector(
                        onTap: () {
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
                              if (holiday != null)
                                const Icon(
                                  Icons.event_available,
                                  size: 12,
                                ),
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
      'L',
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
                      if (nameController.text.trim().isEmpty ||
                          startDate == null) {
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
                            const SnackBar(content: Text('Leave request submitted')),
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
}

