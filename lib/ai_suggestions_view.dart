import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'providers.dart';
import 'models.dart' as models;
import 'roster_generator_view.dart';
import 'services/time_service.dart';
import 'services/weather_service.dart';
import 'services/holiday_service.dart';
import 'services/observance_service.dart';
import 'services/voice_service.dart';
import 'aws_service.dart';
import 'dialogs.dart';

class AiSuggestionsView extends ConsumerStatefulWidget {
  const AiSuggestionsView({super.key});

  @override
  ConsumerState<AiSuggestionsView> createState() => _AiSuggestionsViewState();
}

class _DateRange {
  final DateTime start;
  final DateTime end;
  final int? durationDays;
  final bool explicitStart;
  final bool explicitEnd;

  const _DateRange({
    required this.start,
    required this.end,
    this.durationDays,
    required this.explicitStart,
    required this.explicitEnd,
  });
}

class _LeaveAssignment {
  final String staff;
  final _DateRange range;

  const _LeaveAssignment({required this.staff, required this.range});
}

class _AiSuggestionsViewState extends ConsumerState<AiSuggestionsView> {
  final TextEditingController _commandController = TextEditingController();
  final VoiceService _voiceService = VoiceService.instance;
  bool _didAutoRefresh = false;

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _voiceService.onCommand = (text) {
      if (!mounted) return;
      final command = text.trim();
      if (command.isEmpty) {
        _respondWithRC(context, 'I am listening. What should I do?');
        return;
      }
      _commandController.text = command;
      _handleAiCommand(context);
    };
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final settings = ref.watch(settingsProvider);
    _voiceService.configure(settings);
    final suggestions = roster.aiSuggestions;
    if (!_didAutoRefresh && suggestions.isEmpty) {
      _didAutoRefresh = true;
      Future.microtask(() {
        if (mounted) {
          ref.read(rosterProvider).refreshAiSuggestions();
        }
      });
    }

    final sortedSuggestions = List<models.AiSuggestion>.from(suggestions)
      ..sort((a, b) {
        if (a.isRead != b.isRead) return a.isRead ? 1 : -1;
        return b.priority.index.compareTo(a.priority.index);
      });

    if (sortedSuggestions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAiCommandPanel(context),
          const SizedBox(height: 12),
          _buildEmptyState(context),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedSuggestions.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildAiCommandPanel(context);
        }
        if (index == 1) {
          return _ScenarioImpactCard(
            suggestions: sortedSuggestions,
          );
        }
        final suggestion = sortedSuggestions[index - 2];
        return _SuggestionCard(suggestion: suggestion);
      },
    );
  }

  Widget _buildAiCommandPanel(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final settings = ref.watch(settingsProvider);
    final rosterLabel =
        roster.sharedRosterName ?? AwsService.instance.currentRosterId ?? 'Current';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RC Assistant',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Roster: $rosterLabel | Staff: ${roster.staffMembers.length} | Week start: ${roster.weekStartDay}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commandController,
              decoration: InputDecoration(
                hintText: 'e.g. Add payday every 2 weeks for 8 future + 4 past',
                border: OutlineInputBorder(),
                suffixIcon: ValueListenableBuilder<bool>(
                  valueListenable: _voiceService.isListening,
                  builder: (context, listening, _) {
                    final enabled = settings.voiceEnabled;
                    return IconButton(
                      tooltip: listening ? 'Stop listening' : 'Push to talk',
                      onPressed: enabled
                          ? () {
                              if (listening) {
                                _voiceService.stopListening();
                              } else {
                                _voiceService.startListening(pushToTalk: true);
                              }
                            }
                          : null,
                      icon: Icon(
                        listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: listening
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ),
              onSubmitted: (_) => _handleAiCommand(context),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CommandChip(
                  label: 'Add payday every 2 weeks',
                  onTap: () => _runCommand(
                    context,
                    'add event payday every 2 weeks future 8 past 4',
                  ),
                ),
                _CommandChip(
                  label: 'How do I add events?',
                  onTap: () => _runCommand(context, 'how do i add events'),
                ),
                _CommandChip(
                  label: 'Add meeting tomorrow',
                  onTap: () => _runCommand(context, 'add event meeting tomorrow'),
                ),
                _CommandChip(
                  label: 'Set Jack to Night shift today',
                  onTap: () => _runCommand(context, 'set jack night shift today'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => _handleAiCommand(context),
                child: const Icon(Icons.arrow_upward_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No AI Suggestions',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap refresh to generate suggestions',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ],
      ),
    );
  }

  void _runCommand(BuildContext context, String text) {
    _commandController.text = text;
    _handleAiCommand(context);
  }

  void _handleAiCommand(BuildContext context) {
    final raw = _commandController.text.trim();
    if (raw.isEmpty) return;
    final text = _normalizeCommand(raw);
    final tokens = text.split(' ');
    final roster = ref.read(rosterProvider);
    final staffMatch = _matchStaffName(text, roster);
    final shiftMatch = _extractShiftCode(text);
    final shiftQueryIntent = _isShiftQueryIntent(text, tokens);

    if (_containsAny(tokens, ['hello', 'hi', 'hey']) ||
        text.contains('how are you')) {
      _respondWithRC(
        context,
        'Hello! I can help with rosters, events, time, and weather. '
            'Ask me anything and I will tie it back to your schedule.',
      );
      return;
    }

    if (text.contains('how do i') ||
        text.contains('how to') ||
        _containsAny(tokens, ['help'])) {
      _showAiHelp(context);
      return;
    }

    if (_handleShiftMeaningQuery(context, text)) {
      return;
    }

    if (text.contains('create roster') ||
        text.contains('generate roster') ||
        text.contains('build roster')) {
      _handleRosterCommand(context, raw);
      return;
    }

    if (text.startsWith('when is') ||
        text.contains('when is ') ||
        (text.contains('when') && text.contains('payday')) ||
        (text.contains('next') && text.contains('payday')) ||
        (text.contains('when') &&
            _containsAny(tokens, ['event', 'holiday', 'festival', 'payday']))) {
      _handleWhenIsCommand(context, raw);
      return;
    }

    if (text.contains('cancel swap') ||
        text.contains('remove swap') ||
        text.contains('cancel shiftswap')) {
      _handleCancelSwapCommand(context, raw);
      return;
    }

    if (_isSwapIntent(text, tokens, roster)) {
      _handleSwapCommand(context, raw);
      return;
    }

    if (text.contains('owed') ||
        text.contains('owe') ||
        text.contains('debt') ||
        text.contains('swap debt')) {
      _handleSwapDebtQuery(context, raw);
      return;
    }

    if (text.contains('compassionate') ||
        text.contains('bereavement') ||
        text.contains('study') ||
        text.contains('parental') ||
        text.contains('maternity') ||
        text.contains('paternity') ||
        text.contains('jury') ||
        text.contains('unpaid') ||
        text.contains('special leave') ||
        text.contains('custom leave')) {
      _handleStaffLeaveCommand(context, raw, 'custom');
      return;
    }

    if (text.contains('annual leave') ||
        _containsAny(tokens, ['annual']) ||
        text.contains(' al ')) {
      _handleStaffLeaveCommand(context, raw, 'annual');
      return;
    }

    if (text.contains('secondment')) {
      _handleStaffLeaveCommand(context, raw, 'secondment');
      return;
    }

    if (text.contains('sick') ||
        text.contains('illness') ||
        text.contains(' ill ')) {
      _handleStaffLeaveCommand(context, raw, 'sick');
      return;
    }

    if (_containsAny(tokens, ['event', 'events', 'holiday', 'festival', 'payday']) &&
        !_containsAny(tokens, ['set', 'create', 'add', 'delete', 'remove'])) {
      _handleEventCommand(context, raw);
      return;
    }

    if (shiftQueryIntent) {
      _handleShiftQuery(context, raw);
      return;
    }

    if (staffMatch != null && shiftMatch == null) {
      _respondWithRC(context, 'Which shift should I set for $staffMatch?');
      _showSetShiftWizard(context, initialStaff: staffMatch);
      return;
    }

    if (staffMatch == null && shiftMatch != null) {
      _respondWithRC(context, 'Which staff member should I update?');
      _showSetShiftWizard(context, initialShift: shiftMatch);
      return;
    }

    if (staffMatch != null && shiftMatch != null) {
      _handleNaturalLanguageOverride(
        context,
        raw,
        staffMatch,
        shiftMatch,
      );
      return;
    }

    if (_containsAny(tokens, ['time', 'date', 'today'])) {
      _handleTimeCommand(context);
      return;
    }

    if (_containsAny(tokens, ['weather', 'forecast', 'temperature'])) {
      _handleWeatherCommand(context);
      return;
    }

    if (text.contains('delete event') || text.contains('remove event')) {
      _handleDeleteEventCommand(context, raw);
      return;
    }

    if (text.contains('event') || text.contains('payday') || text.contains('holiday')) {
      _handleEventCommand(context, raw);
      return;
    }

    if (text.contains('set ') || text.contains('override')) {
      _handleSetShiftCommand(context, raw);
      return;
    }

    if (_handleClarification(context, raw, text, tokens, roster)) {
      return;
    }

    _respondWithRC(
      context,
      "I did not catch that. Tell me the staff, date, and action (set shift, swap, leave, or event).",
    );
  }

  bool _isShiftQueryIntent(String text, List<String> tokens) {
    if (text.contains('?')) return true;
    if (text.contains('what shift')) return true;
    if (text.contains('who is') || text.contains("who's")) return true;
    if (text.startsWith('who ')) return true;
    if (text.contains('how many')) return true;
    if (text.contains('count')) return true;
    if (text.contains('on today') || text.contains('on tomorrow')) return true;
    if (text.contains('on shift')) return true;
    if (text.contains('working') && _containsAny(tokens, ['today', 'tomorrow', 'tonight', 'yesterday'])) {
      return true;
    }
    if (text.contains('shift') && !_containsAny(tokens, ['set', 'assign', 'change', 'override'])) {
      return true;
    }
    return false;
  }

  void _handleRosterCommand(BuildContext context, String raw) {
    final text = raw.toLowerCase();
    final staffMatch =
        RegExp(r'(\\d{1,3})\\s*(staff|people|person)')
            .firstMatch(text);
    final cycleMatch =
        RegExp(r'(\\d{1,2})\\s*(week|weeks)')
            .firstMatch(text);
    final weekStartMatch = RegExp(r'week\\s*start\\s*(\\w+)')
        .firstMatch(text);

    int? staffCount;
    int? cycleLength;
    int? weekStartDay;

    if (staffMatch != null) {
      staffCount = int.tryParse(staffMatch.group(1)!);
    }
    if (cycleMatch != null) {
      cycleLength = int.tryParse(cycleMatch.group(1)!);
    }
    if (weekStartMatch != null) {
      final label = weekStartMatch.group(1)!;
      const days = {
        'sun': 0,
        'sunday': 0,
        'mon': 1,
        'monday': 1,
        'tue': 2,
        'tues': 2,
        'tuesday': 2,
        'wed': 3,
        'wednesday': 3,
        'thu': 4,
        'thur': 4,
        'thursday': 4,
        'fri': 5,
        'friday': 5,
        'sat': 6,
        'saturday': 6,
      };
      weekStartDay = days[label];
    }

    _showRosterWizard(
      context,
      staffCount: staffCount,
      cycleLength: cycleLength,
      weekStartDay: weekStartDay,
    );
  }

  Future<void> _handleTimeCommand(BuildContext context) async {
    final settings = ref.read(settingsProvider);
    try {
      final info = await TimeService.instance.getTime(settings.timeZone);
      _respondWithRC(
        context,
        'Time in ${info.timezone}: ${DateFormat('MMM d, HH:mm').format(info.dateTime)}. '
            'Want it shown on the roster?',
      );
    } catch (_) {
      final now = DateTime.now();
      _respondWithRC(
        context,
        'Local time: ${DateFormat('MMM d, HH:mm').format(now)}. '
            'Want it shown on the roster?',
      );
    }
  }

  Future<void> _handleWeatherCommand(BuildContext context) async {
    final settings = ref.read(settingsProvider);
    if (settings.siteLat == null || settings.siteLon == null) {
      _respondWithRC(
        context,
        'Set a site location in Settings to show weather.',
      );
      return;
    }
    try {
      final map = await WeatherService.instance.getWeekly(
        lat: settings.siteLat!,
        lon: settings.siteLon!,
      );
      final today = DateTime.now();
      final key = DateTime(today.year, today.month, today.day);
      final day = map[key];
      if (day == null) {
        throw Exception('Weather unavailable.');
      }
      _respondWithRC(
        context,
        'Weather today: ${day.minTemp.toStringAsFixed(0)} deg - '
            '${day.maxTemp.toStringAsFixed(0)} deg, rain '
            '${day.precipChance.toStringAsFixed(0)}%. '
            'I can overlay weather on the roster.',
      );
    } catch (e) {
      _respondWithRC(context, 'Weather unavailable: $e');
    }
  }

  void _handleShiftQuery(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    final text = raw.toLowerCase();
    DateTime? explicitDate = _parseDateFromText(raw);
    final dateSet = <DateTime>{};
    if (explicitDate != null) {
      dateSet.add(DateTime(
        explicitDate.year,
        explicitDate.month,
        explicitDate.day,
      ));
    } else {
      dateSet.addAll(
        _extractDatesForOverride(raw, roster.weekStartDay),
      );
    }
    if (dateSet.isEmpty) {
      dateSet.add(DateTime.now());
    }
    final dates = dateSet.toList()..sort();
    final staff = roster.staffMembers.map((s) => s.name).toList();

    final shiftHint = _extractShiftCode(text);
    final wantsLeave = text.contains('leave') ||
        text.contains('sick') ||
        text.contains('secondment');
    final wantsCount = text.contains('how many') ||
        text.contains('count') ||
        text.contains('number of');
    final isWhoQuery = text.contains('who') || text.startsWith('who');
    if (wantsCount && !isWhoQuery) {
      if (dates.length > 7) {
        _respondWithRC(
          context,
          'That spans ${dates.length} days. Ask about fewer dates.',
        );
        return;
      }
      final responses = <String>[];
      for (final date in dates) {
        int count = 0;
        for (final name in staff) {
          final staffMember = roster.staffMembers
              .where((s) => s.name == name)
              .firstOrNull;
          if (staffMember == null) continue;
          if (wantsLeave) {
            final unavailable =
                roster.isStaffUnavailableOnDate(staffMember, date);
            if (!unavailable) continue;
            if (text.contains('secondment') &&
                staffMember.leaveType != 'secondment') continue;
            if (text.contains('sick') && staffMember.leaveType != 'sick') {
              continue;
            }
            count++;
            continue;
          }
          final shift = roster.getShiftForDate(name, date);
          if (shiftHint != null) {
            if (shift == shiftHint) count++;
          } else {
            if (shift != 'OFF' && shift != 'AL') count++;
          }
        }
        final label = wantsLeave
            ? (text.contains('secondment')
                ? 'on secondment'
                : text.contains('sick')
                    ? 'sick'
                    : 'on leave')
            : shiftHint != null
                ? _shiftLabel(shiftHint)
                : 'working';
        responses.add(
          '$count staff are $label on ${DateFormat('MMM d').format(date)}.',
        );
      }
      _respondWithRC(context, responses.join(' '));
      return;
    }
    if (isWhoQuery) {
      if (dates.length > 3) {
        _respondWithRC(
          context,
          'That spans ${dates.length} days. Ask about fewer dates.',
        );
        return;
      }
      final results = <String>[];
      final responses = <String>[];
      for (final date in dates) {
        results.clear();
        for (final name in staff) {
          final staffMember = roster.staffMembers
              .where((s) => s.name == name)
              .firstOrNull;
          if (staffMember == null) continue;
          if (wantsLeave) {
            final unavailable =
                roster.isStaffUnavailableOnDate(staffMember, date);
            if (!unavailable) continue;
            if (text.contains('secondment') &&
                staffMember.leaveType != 'secondment') continue;
            if (text.contains('sick') &&
                staffMember.leaveType != 'sick') continue;
            results.add(name);
            continue;
          }
          final shift = roster.getShiftForDate(name, date);
          if (shiftHint != null) {
            if (shift == shiftHint) {
              results.add(name);
            }
          } else {
            if (shift != 'OFF' && shift != 'AL') {
              results.add(name);
            }
          }
        }
        final label = wantsLeave
            ? (text.contains('secondment')
                ? 'on secondment'
                : text.contains('sick')
                    ? 'sick'
                    : 'on leave')
            : shiftHint != null
                ? _shiftLabel(shiftHint)
                : 'working';
        responses.add(
          results.isEmpty
              ? 'No staff $label on ${DateFormat('MMM d').format(date)}.'
              : '${results.join(', ')} are $label on ${DateFormat('MMM d').format(date)}.',
        );
      }
      _respondWithRC(context, responses.join(' '));
      return;
    }

    String? matched;
    for (final name in staff) {
      if (text.contains(name.toLowerCase())) {
        matched = name;
        break;
      }
    }
    if (matched == null) {
      _respondWithRC(context, 'Tell me which staff member to check.');
      return;
    }
    final staffMember =
        roster.staffMembers.where((s) => s.name == matched).firstOrNull;
    final responses = <String>[];
    for (final date in dates) {
    if (staffMember != null &&
        roster.isStaffUnavailableOnDate(staffMember, date)) {
        final label = _formatLeaveLabel(staffMember.leaveType);
        responses.add(
          '$matched is on $label for ${DateFormat('MMM d, yyyy').format(date)}.',
        );
        continue;
      }
      final shift = roster.getShiftForDate(matched, date);
      responses.add(
        '$matched is on ${_shiftLabel(shift)} for ${DateFormat('MMM d, yyyy').format(date)}.',
      );
    }
    _respondWithRC(context, responses.join(' '));
  }

  void _handleStaffLeaveCommand(
    BuildContext context,
    String raw,
    String leaveType,
  ) {
    final roster = ref.read(rosterProvider);
    if (roster.readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read-only roster cannot be edited.')),
      );
      return;
    }
    final text = raw.toLowerCase();
    final isExtend = text.contains('extend') || text.contains('extension');
    String effectiveLeaveType = leaveType;
    if (leaveType == 'custom') {
      final label = _extractCustomLeaveLabelFromText(text);
      if (label == null || label.isEmpty) {
        _respondWithRC(context, 'What is the custom leave label?');
        _showLeaveWizard(context, leaveType: 'custom');
        return;
      }
      effectiveLeaveType = 'custom:$label';
    }
    final staffNames = _matchAllStaffNames(text, roster);
    if (staffNames.isEmpty) {
      _respondWithRC(context, 'Which staff member is this for?');
      _showLeaveWizard(context, leaveType: leaveType);
      return;
    }

    final ranges = _extractMultipleDateRanges(text, roster.weekStartDay);

    if (isExtend && staffNames.length == 1) {
      final staffMember = roster.staffMembers.firstWhere(
        (s) => s.name == staffNames.first,
        orElse: () => models.StaffMember(id: '', name: staffNames.first),
      );
      if (staffMember.id.isEmpty) {
        _respondWithRC(context, 'Staff member not found.');
        return;
      }
      if (staffMember.leaveEnd == null) {
        _respondWithRC(
          context,
          'No active leave found for ${staffMember.name}. Tell me the start and end dates.',
        );
        _showLeaveWizard(
          context,
          initialStaff: staffMember.name,
          leaveType: leaveType,
        );
        return;
      }
      DateTime newEnd = staffMember.leaveEnd!;
      if (ranges.isNotEmpty) {
        final range = ranges.first;
        if (range.explicitEnd) {
          newEnd = range.end;
        } else if (range.durationDays != null) {
          newEnd = staffMember.leaveEnd!.add(
            Duration(days: range.durationDays!),
          );
        } else {
          newEnd = range.end;
        }
      } else {
        _respondWithRC(context, 'How long should I extend it for?');
        _showLeaveWizard(
          context,
          initialStaff: staffMember.name,
          leaveType: leaveType,
        );
        return;
      }
      final start = staffMember.leaveStart ??
          DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      roster.setStaffLeaveStatus(
        staffId: staffMember.id,
        leaveType: staffMember.leaveType ?? effectiveLeaveType,
        startDate: start,
        endDate: newEnd,
      );
      _respondWithRC(
        context,
        'Extended ${staffMember.name} ${_formatLeaveLabel(staffMember.leaveType ?? effectiveLeaveType)} to '
            '${DateFormat('MMM d, yyyy').format(newEnd)}.',
      );
      return;
    }

    if (ranges.isEmpty) {
      _respondWithRC(
        context,
        staffNames.length == 1
            ? 'Which dates should I set for ${staffNames.first}?'
            : 'Which dates should I set for each staff member?',
      );
      _showLeaveWizard(
        context,
        initialStaff: staffNames.first,
        leaveType: leaveType,
      );
      return;
    }

    final assignments = _pairStaffToRanges(staffNames, ranges);
    if (assignments == null) {
      _respondWithRC(
        context,
        'I need a clear date range for each staff member.',
      );
      _showLeaveWizard(
        context,
        initialStaff: staffNames.first,
        leaveType: leaveType,
      );
      return;
    }

    final summary = assignments
        .map(
          (entry) =>
              '${entry.staff} (${DateFormat('MMM d').format(entry.range.start)} to ${DateFormat('MMM d').format(entry.range.end)})',
        )
        .join(', ');
    _confirmAction(
      context,
      title: 'Set ${_formatLeaveLabel(effectiveLeaveType)}',
      message: 'Apply ${_formatLeaveLabel(effectiveLeaveType)} for: $summary?',
      onConfirm: () {
        for (final entry in assignments) {
          final staffMember = roster.staffMembers.firstWhere(
            (s) => s.name == entry.staff,
            orElse: () => models.StaffMember(id: '', name: entry.staff),
          );
          if (staffMember.id.isEmpty) continue;
          roster.setStaffLeaveStatus(
            staffId: staffMember.id,
            leaveType: effectiveLeaveType,
            startDate: entry.range.start,
            endDate: entry.range.end,
          );
        }
        _respondWithRC(
          context,
          'Applied ${_formatLeaveLabel(effectiveLeaveType)} for ${assignments.length} staff.',
        );
      },
    );
  }

  Future<void> _showLeaveWizard(
    BuildContext context, {
    String? initialStaff,
    String leaveType = 'leave',
  }) async {
    final roster = ref.read(rosterProvider);
    final staff = roster.staffMembers.map((s) => s.name).toList();
    if (staff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add staff before setting leave.')),
      );
      return;
    }
    String staffName = initialStaff ?? staff.first;
    DateTime start = DateTime.now();
    DateTime end = DateTime.now();
    String type = leaveType;
    String customLabel = '';
    if (type.startsWith('custom:')) {
      customLabel = type.substring('custom:'.length).trim();
      type = 'custom';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set leave/secondment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: staffName,
              items: staff
                  .map(
                    (name) => DropdownMenuItem(
                      value: name,
                      child: Text(name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  staffName = value;
                }
              },
              decoration: const InputDecoration(labelText: 'Staff member'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: type,
              items: const [
                DropdownMenuItem(value: 'leave', child: Text('Leave')),
                DropdownMenuItem(value: 'annual', child: Text('Annual Leave')),
                DropdownMenuItem(value: 'sick', child: Text('Sick')),
                DropdownMenuItem(value: 'secondment', child: Text('Secondment')),
                DropdownMenuItem(value: 'custom', child: Text('Custom')),
              ],
              onChanged: (value) {
                if (value != null) {
                  type = value;
                }
              },
              decoration: const InputDecoration(labelText: 'Type'),
            ),
            if (type == 'custom') ...[
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Custom leave label',
                  hintText: 'e.g. Compassionate Leave',
                ),
                onChanged: (value) => customLabel = value,
                controller: TextEditingController(text: customLabel),
              ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Start'),
              subtitle: Text(DateFormat('MMM d, yyyy').format(start)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: start,
                  firstDate: DateTime.now().subtract(const Duration(days: 730)),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (picked != null) {
                  start = picked;
                  if (end.isBefore(start)) {
                    end = start;
                  }
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available),
              title: const Text('End'),
              subtitle: Text(DateFormat('MMM d, yyyy').format(end)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: end,
                  firstDate: DateTime.now().subtract(const Duration(days: 730)),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (picked != null) {
                  end = picked;
                  if (end.isBefore(start)) {
                    start = end;
                  }
                }
              },
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

    if (confirmed == true) {
      final staffMember = roster.staffMembers.firstWhere(
        (s) => s.name == staffName,
        orElse: () => models.StaffMember(id: '', name: staffName),
      );
      if (staffMember.id.isEmpty) return;
      final effectiveType =
          type == 'custom' ? 'custom:${customLabel.trim()}' : type;
      roster.setStaffLeaveStatus(
        staffId: staffMember.id,
        leaveType: effectiveType,
        startDate: start,
        endDate: end,
      );
    }
  }

  String? _matchStaffName(String text, RosterNotifier roster) {
    final staff = roster.staffMembers.map((s) => s.name).toList();
    for (final name in staff) {
      if (text.contains(name.toLowerCase())) {
        return name;
      }
    }
    return null;
  }

  String _normalizeCommand(String raw) {
    final lower = raw.toLowerCase();
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ');
    return cleaned.replaceAll(RegExp(r'\\s+'), ' ').trim();
  }

  bool _containsAny(List<String> tokens, List<String> keywords) {
    for (final keyword in keywords) {
      if (tokens.contains(keyword)) return true;
    }
    return false;
  }

  bool _isSwapIntent(String text, List<String> tokens, RosterNotifier roster) {
    if (text.contains('swap') ||
        text.contains('shift swap') ||
        text.contains('shift-swap') ||
        text.contains('swap shifts') ||
        text.contains('swapshift') ||
        _containsAny(tokens, ['swap', 'switch', 'trade', 'cover'])) {
      return true;
    }
    final staffMatches = _matchAllStaffNames(text, roster);
    final dateRange = _extractDateRangeFromText(text, roster.weekStartDay);
    if (staffMatches.length >= 2 && dateRange != null) {
      return true;
    }
    return false;
  }

  bool _handleClarification(
    BuildContext context,
    String raw,
    String text,
    List<String> tokens,
    RosterNotifier roster,
  ) {
    final staffNames = _matchAllStaffNames(text, roster);
    final dates = _extractAllDatesFromText(text);
    final shift = _extractShiftCode(text);
    final hasSwap = _isSwapIntent(text, tokens, roster);
    final mentionsEvent =
        text.contains('event') || text.contains('holiday') || text.contains('payday');

    if (hasSwap) {
      if (staffNames.length < 2) {
        _respondWithRC(
          context,
          'Who is swapping? Tell me two staff names and a date.',
        );
        return true;
      }
      if (dates.isEmpty) {
        _respondWithRC(context, 'Which date is the swap for?');
        return true;
      }
    }

    if (staffNames.isNotEmpty && dates.isNotEmpty && shift == null) {
      final dateLabel = DateFormat('MMM d').format(dates.first);
      _respondWithRC(
        context,
        'What should I do for ${staffNames.first} on $dateLabel? '
        'Say: set shift, add leave, or swap.',
      );
      return true;
    }

    if (staffNames.isNotEmpty && dates.isEmpty && shift == null) {
      _respondWithRC(
        context,
        'Which date should I use for ${staffNames.first}?',
      );
      return true;
    }

    if (staffNames.isEmpty && dates.isNotEmpty && shift == null) {
      _respondWithRC(
        context,
        'Who is this for on ${DateFormat('MMM d').format(dates.first)}?',
      );
      return true;
    }

    if (shift != null && staffNames.isEmpty) {
      _respondWithRC(
        context,
        'Which staff member should I set to ${_shiftLabelWithCode(shift)}?',
      );
      return true;
    }

    if (mentionsEvent && dates.isEmpty) {
      _respondWithRC(
        context,
        'Which date should I add the event to?',
      );
      return true;
    }

    return false;
  }

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

  bool _handleShiftMeaningQuery(BuildContext context, String text) {
    final match = RegExp(
      r'\b(?:what does|what is|meaning of|define)\s+(d12|n12|d|n|l|e|r|al|off|c1|c2|c3|c4|c)\b',
    ).firstMatch(text);
    if (match == null) return false;
    final code = match.group(1)!.toUpperCase();
    _respondWithRC(context, '$code means ${_shiftLabel(code)}.');
    return true;
  }

  String _shiftLabelWithCode(String code) {
    final label = _shiftLabel(code);
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return label;
    return '$label ($normalized)';
  }

  String _shiftLabel(String code) {
    final normalized = code.trim().toUpperCase();
    switch (normalized) {
      case 'D':
        return 'Day shift';
      case 'D12':
        return '12-hour day shift';
      case 'E':
        return 'Early shift';
      case 'L':
        return 'Late shift';
      case 'N':
        return 'Night shift';
      case 'N12':
        return '12-hour night shift';
      case 'AL':
        return 'Annual leave';
      case 'R':
        return 'Rest day';
      case 'OFF':
        return 'Off';
      case 'C':
        return 'Cover';
      case 'C1':
        return 'Cover 1';
      case 'C2':
        return 'Cover 2';
      case 'C3':
        return 'Cover 3';
      case 'C4':
        return 'Cover 4';
      default:
        return normalized.isEmpty ? 'Unassigned' : normalized;
    }
  }

  void _handleSwapCommand(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    if (roster.readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read-only roster cannot be edited.')),
      );
      return;
    }
    final text = raw.toLowerCase();
    final staffNames = _matchAllStaffNames(text, roster);
    final range = _extractDateRangeFromText(text, roster.weekStartDay);
    final weekIndex = _extractPatternWeekIndex(text);
    final endDate = _extractSwapEndDate(text);
    _DateRange? effectiveRange = range;
    if (effectiveRange == null && weekIndex != null) {
      final start = _nextPatternWeekStart(
        roster,
        weekIndex,
      );
      if (start != null) {
        final end = endDate ?? DateTime(start.year + 1, 1, 0);
        effectiveRange = _DateRange(
          start: start,
          end: end,
          explicitStart: true,
          explicitEnd: endDate != null,
        );
      }
    }
    if (effectiveRange == null) {
      _respondWithRC(context, 'Which date should the swap happen?');
      return;
    }

    if (staffNames.isEmpty) {
      final guess = _guessStaffName(text, roster);
      if (guess != null) {
        staffNames.add(guess);
      }
    }

    if (staffNames.isEmpty) {
      _respondWithRC(context, 'Which staff member needs the swap?');
      return;
    }

    final fromPerson = staffNames.first;
    final toPerson = staffNames.length > 1 ? staffNames[1] : null;
    if (toPerson == null) {
      final suggestions = _suggestSwapCandidates(
        roster,
        fromPerson,
        effectiveRange.start,
      );
      if (suggestions.isEmpty) {
        _respondWithRC(
          context,
          'No obvious swap candidates found. Who is volunteering?',
        );
      } else {
        _respondWithRC(
          context,
          'Possible swap candidates on ${DateFormat('MMM d').format(effectiveRange.start)}: '
              '${suggestions.join(', ')}. Who is volunteering?',
        );
      }
      return;
    }

    final isRecurring = text.contains('pattern') ||
        text.contains('every') ||
        text.contains('each') ||
        text.contains('rest of year') ||
        text.contains('months') ||
        weekIndex != null;
    if (isRecurring) {
      final fromShift = roster.getShiftForDate(fromPerson, effectiveRange.start);
      final toShift = roster.getShiftForDate(toPerson, effectiveRange.start);
      if (fromShift.isEmpty || toShift.isEmpty) {
        _respondWithRC(
          context,
          'Swap not applied. Check that both staff are scheduled that week.',
        );
        return;
      }
      roster.addRegularSwap(
        models.RegularShiftSwap(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          fromPerson: fromPerson,
          toPerson: toPerson,
          fromShift: fromShift,
          toShift: toShift,
          startDate: effectiveRange.start,
          endDate: endDate,
          isActive: true,
          weekIndex: weekIndex != null ? weekIndex - 1 : null,
        ),
      );
      _respondWithRC(
        context,
        'Recurring swap set for $fromPerson and $toPerson starting ${DateFormat('MMM d, yyyy').format(effectiveRange.start)}.',
      );
      return;
    }

    final applied = effectiveRange.start == effectiveRange.end
        ? (roster.applySwapForDate(
                fromPerson: fromPerson,
                toPerson: toPerson,
                date: effectiveRange.start,
                reason: 'AI swap request') ==
            true)
            ? 1
            : 0
        : roster.applySwapRange(
            fromPerson: fromPerson,
            toPerson: toPerson,
            startDate: effectiveRange.start,
            endDate: effectiveRange.end,
            reason: 'AI swap request',
          );

    if (applied == 0) {
      _respondWithRC(
        context,
        'Swap not applied. Check that both staff are scheduled on those dates.',
      );
      return;
    }
    if (!text.contains('no debt') &&
        !text.contains('even') &&
        !text.contains('swap back')) {
      roster.addSwapDebt(
        fromPerson: fromPerson,
        toPerson: toPerson,
        daysOwed: applied,
        reason: 'AI swap request',
      );
    }
    _respondWithRC(
      context,
      'Swap applied for $fromPerson and $toPerson (${applied} day(s)).',
    );
  }

  void _handleCancelSwapCommand(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    final text = raw.toLowerCase();
    final staffNames = _matchAllStaffNames(text, roster);
    if (staffNames.length < 2) {
      _respondWithRC(context, 'Tell me the two staff names to cancel the swap.');
      return;
    }
    final fromPerson = staffNames[0];
    final toPerson = staffNames[1];
    final match = roster.regularSwaps.firstWhere(
      (swap) =>
          (swap.fromPerson == fromPerson && swap.toPerson == toPerson) ||
          (swap.fromPerson == toPerson && swap.toPerson == fromPerson),
      orElse: () => models.RegularShiftSwap(
        id: '',
        fromPerson: '',
        toPerson: '',
        fromShift: '',
        toShift: '',
        startDate: DateTime.now(),
      ),
    );
    if (match.id.isEmpty) {
      _respondWithRC(context, 'No matching recurring swap found.');
      return;
    }
    _confirmAction(
      context,
      title: 'Cancel swap',
      message: 'Cancel recurring swap between $fromPerson and $toPerson?',
      onConfirm: () => roster.removeRegularSwap(match.id),
    );
  }

  void _handleSwapDebtQuery(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    if (roster.swapDebts.isEmpty) {
      _respondWithRC(context, 'No swap debts recorded.');
      return;
    }
    final text = raw.toLowerCase();
    final staffNames = _matchAllStaffNames(text, roster);
    final wantsIgnore = text.contains('ignore');
    final wantsDates = text.contains('date') || text.contains('when');
    final filtered = roster.swapDebts.where((debt) {
      if (staffNames.isEmpty) return true;
      return staffNames.contains(debt.fromPerson) ||
          staffNames.contains(debt.toPerson);
    }).toList();

    if (filtered.isEmpty) {
      _respondWithRC(context, 'No matching swap debts found.');
      return;
    }

    if (wantsIgnore && staffNames.length >= 2) {
      final from = staffNames[0];
      final to = staffNames[1];
      final match = filtered.firstWhere(
        (d) => d.fromPerson == from && d.toPerson == to,
        orElse: () => filtered.first,
      );
      _confirmAction(
        context,
        title: 'Ignore swap debt',
        message: 'Ignore debt from $from to $to?',
        onConfirm: () => roster.ignoreSwapDebt(match.id),
      );
      return;
    }

    final lines = filtered.map((debt) {
      final remaining = debt.daysOwed - debt.daysSettled;
      final status = debt.isIgnored
          ? 'ignored'
          : debt.isResolved
              ? 'settled'
              : 'remaining $remaining';
      final dateInfo = wantsDates && debt.settledDates.isNotEmpty
          ? ' Settled on ${debt.settledDates.map((d) => DateFormat('MMM d').format(DateTime.parse(d))).join(', ')}.'
          : '';
      return '${debt.fromPerson} owes ${debt.toPerson} ($status).$dateInfo';
    }).join(' ');
    _respondWithRC(context, lines);
  }

  String? _extractCustomLeaveLabelFromText(String text) {
    final lowered = text.toLowerCase();
    final match = RegExp(r'(custom leave|special leave|leave type)\\s+([a-z\\s\\-]+)')
        .firstMatch(lowered);
    if (match != null) {
      return _titleCase(match.group(2)!.trim());
    }
    final keywords = {
      'compassionate': 'Compassionate Leave',
      'bereavement': 'Bereavement Leave',
      'study': 'Study Leave',
      'parental': 'Parental Leave',
      'maternity': 'Maternity Leave',
      'paternity': 'Paternity Leave',
      'jury': 'Jury Duty',
      'unpaid': 'Unpaid Leave',
    };
    for (final entry in keywords.entries) {
      if (lowered.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  String _titleCase(String input) {
    return input
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  List<String> _matchAllStaffNames(String text, RosterNotifier roster) {
    final lowered = text.toLowerCase();
    final matches = <MapEntry<String, int>>[];
    for (final staff in roster.staffMembers) {
      final nameLower = staff.name.toLowerCase();
      final index = lowered.indexOf(nameLower);
      if (index != -1) {
        matches.add(MapEntry(staff.name, index));
      }
    }
    matches.sort((a, b) => a.value.compareTo(b.value));
    return matches.map((e) => e.key).toList();
  }

  String? _guessStaffName(String text, RosterNotifier roster) {
    final lowered = text.toLowerCase();
    String? best;
    int bestScore = 9999;
    for (final staff in roster.staffMembers) {
      final name = staff.name.toLowerCase();
      final score = _levenshtein(lowered, name);
      if (score < bestScore) {
        bestScore = score;
        best = staff.name;
      }
    }
    return bestScore <= 5 ? best : null;
  }

  int _levenshtein(String s, String t) {
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    final v0 = List<int>.generate(t.length + 1, (i) => i);
    final v1 = List<int>.filled(t.length + 1, 0);
    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = s[i] == t[j] ? 0 : 1;
        v1[j + 1] = [
          v1[j] + 1,
          v0[j + 1] + 1,
          v0[j] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }

  List<String> _suggestSwapCandidates(
    RosterNotifier roster,
    String requester,
    DateTime date,
  ) {
    final candidates = <String>[];
    for (final staff in roster.staffMembers) {
      if (staff.name == requester || !staff.isActive) continue;
      final shift = roster.getShiftForDate(staff.name, date);
      if (shift == 'OFF' || shift == 'AL') {
        candidates.add(staff.name);
      }
    }
    return candidates;
  }

  int? _extractPatternWeekIndex(String text) {
    final match = RegExp(r'week\\s*(\\d{1,2})').firstMatch(text);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!);
    if (value == null || value < 1) return null;
    return value;
  }

  DateTime? _extractSwapEndDate(String text) {
    final lowered = text.toLowerCase();
    final now = DateTime.now();
    if (lowered.contains('rest of year') || lowered.contains('end of year')) {
      return DateTime(now.year, 12, 31);
    }
    final monthMatch = RegExp(r'for\\s+(\\d+)\\s*months?').firstMatch(lowered);
    if (monthMatch != null) {
      final months = int.tryParse(monthMatch.group(1)!) ?? 0;
      if (months > 0) {
        return _addMonths(now, months);
      }
    }
    return null;
  }

  DateTime _addMonths(DateTime date, int months) {
    final year = date.year + ((date.month - 1 + months) ~/ 12);
    final month = ((date.month - 1 + months) % 12) + 1;
    final day = date.day;
    final lastDay = DateTime(year, month + 1, 0).day;
    final safeDay = day > lastDay ? lastDay : day;
    return DateTime(year, month, safeDay);
  }

  DateTime? _nextPatternWeekStart(
    RosterNotifier roster,
    int weekIndex,
  ) {
    final targetWeek = weekIndex - 1;
    if (targetWeek < 0 || targetWeek >= roster.cycleLength) return null;
    final now = DateTime.now();
    final referenceDate = DateTime(2024, 1, 1);
    for (int i = 0; i < 400; i++) {
      final date = now.add(Duration(days: i));
      final daysSinceReference = date.difference(referenceDate).inDays;
      final cycleDay = daysSinceReference % (roster.cycleLength * 7);
      final week = cycleDay ~/ 7;
      final day = cycleDay % 7;
      if (week == targetWeek && day == roster.weekStartDay) {
        return DateTime(date.year, date.month, date.day);
      }
    }
    return null;
  }

  String? _extractShiftCode(String text) {
    final lowered = text.toLowerCase();
    if (lowered.contains('payday') || lowered.contains('holiday')) {
      return null;
    }
    final explicit =
        RegExp(r'\\b(d12|n12|d|n|l|off|r|e|c1|c2|c3|c4|c)\\b')
            .firstMatch(lowered);
    if (explicit != null) {
      return explicit.group(1)!.toUpperCase();
    }
    if (lowered.contains('late')) return 'L';
    if (lowered.contains('leave') ||
        lowered.contains('vacation') ||
        lowered.contains('annual leave')) {
      return 'AL';
    }
    if (lowered.contains('night')) {
      return lowered.contains('12') ? 'N12' : 'N';
    }
    if (lowered.contains('day') && !lowered.contains('payday')) {
      return lowered.contains('12') ? 'D12' : 'D';
    }
    if (lowered.contains('early')) return 'E';
    if (lowered.contains('off') || lowered.contains('rest')) return 'OFF';
    return null;
  }

  void _handleNaturalLanguageOverride(
    BuildContext context,
    String raw,
    String staffName,
    String shift,
  ) {
    final roster = ref.read(rosterProvider);
    if (roster.readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read-only roster cannot be edited.')),
      );
      return;
    }

    final dates = _extractDatesForOverride(
      raw,
      roster.weekStartDay,
    );

    if (dates.isEmpty) {
      _respondWithRC(
        context,
        'Which date(s) should I apply $shift for $staffName?',
      );
      _showSetShiftWizard(
        context,
        initialStaff: staffName,
        initialShift: shift,
      );
      return;
    }

    if (dates.length == 1) {
      _confirmAction(
        context,
        title: 'Set shift',
        message:
            'Set $staffName to ${_shiftLabelWithCode(shift)} on ${DateFormat('MMM d, yyyy').format(dates.first)}?',
        onConfirm: () {
          final warning = _coverageWarningForChange(
            roster,
            staffName,
            dates.first,
            shift,
          );
          roster.setOverride(staffName, dates.first, shift, 'AI command');
          if (warning != null) {
            _respondWithRC(context, warning);
          }
        },
      );
      return;
    }

    final sorted = dates.toList()..sort();
    final preview = sorted
        .take(5)
        .map((d) => DateFormat('EEE d MMM').format(d))
        .join(', ');
    final suffix = sorted.length > 5 ? '...' : '';
    _confirmAction(
      context,
      title: 'Set multiple shifts',
      message:
          'Set $staffName to ${_shiftLabelWithCode(shift)} on ${sorted.length} dates ($preview$suffix)?',
      onConfirm: () {
        for (final date in sorted) {
          final warning = _coverageWarningForChange(
            roster,
            staffName,
            date,
            shift,
          );
          roster.setOverride(staffName, date, shift, 'AI command');
          if (warning != null) {
            _respondWithRC(context, warning);
          }
        }
      },
    );
  }

  String? _coverageWarningForChange(
    RosterNotifier roster,
    String staffName,
    DateTime date,
    String newShift,
  ) {
    final constraints = roster.constraints;
    final dayKey = date.weekday.toString();
    final targets = constraints.shiftCoverageTargetsByDay[dayKey] ??
        constraints.shiftCoverageTargets;
    if (targets.isEmpty) return null;

    final originalShift = roster.getShiftForDate(staffName, date);
    if (originalShift == newShift) return null;

    final target = targets[originalShift];
    if (target == null) return null;

    int staffed = 0;
    for (final staff in roster.staffMembers) {
      if (!staff.isActive) continue;
      final shift = staff.name == staffName
          ? newShift
          : roster.getShiftForDate(staff.name, date);
      if (shift == originalShift) {
        staffed++;
      }
    }

    if (staffed >= target) return null;

    final candidate = _findCoverageCandidateForShift(
      roster,
      originalShift,
      date,
    );
    if (candidate != null) {
      return 'Coverage alert: $originalShift drops below target on '
          '${DateFormat('MMM d').format(date)}. '
          'Suggested cover: ${candidate['personName']} -> $originalShift.';
    }
    return 'Coverage alert: $originalShift drops below target on '
        '${DateFormat('MMM d').format(date)}. '
        'No obvious cover found.';
  }

  Map<String, dynamic>? _findCoverageCandidateForShift(
    RosterNotifier roster,
    String shiftType,
    DateTime date,
  ) {
    for (final staff in roster.staffMembers) {
      if (!staff.isActive) continue;
      final shift = roster.getShiftForDate(staff.name, date);
      if (shift == 'OFF') {
        final preferences = staff.preferences;
        if (preferences != null &&
            preferences.preferredDaysOff.contains(date.weekday)) {
          continue;
        }
        return {
          'personName': staff.name,
          'date': date.toIso8601String(),
          'shift': shiftType,
        };
      }
    }
    return null;
  }

  models.EventType _inferEventType(String text, String title) {
    final lowered = text.toLowerCase();
    if (lowered.contains('payday')) return models.EventType.payday;
    if (lowered.contains('ramadan') || lowered.contains('easter') || lowered.contains('diwali') || lowered.contains('hanukkah') || lowered.contains('eid')) {
      return models.EventType.religious;
    }
    if (lowered.contains('carnival') || lowered.contains('festival') || lowered.contains('lunar new year') || lowered.contains('chinese new year') || lowered.contains('mardi gras')) {
      return models.EventType.cultural;
    }
    if (lowered.contains('world cup') || lowered.contains('super bowl') || lowered.contains('olympic') || lowered.contains('final') || lowered.contains('grand prix')) {
      return models.EventType.sports;
    }
    if (lowered.contains('meeting')) return models.EventType.meeting;
    if (lowered.contains('training')) return models.EventType.training;
    if (lowered.contains('deadline') || lowered.contains('due')) return models.EventType.deadline;
    if (lowered.contains('birthday')) return models.EventType.birthday;
    if (lowered.contains('anniversary')) return models.EventType.anniversary;
    if (lowered.contains('holiday')) return models.EventType.holiday;
    return models.EventType.general;
  }

  void _handleEventCommand(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    final text = raw.toLowerCase();
    final now = DateTime.now();

    String? title;
    if (text.contains('payday')) {
      title = 'Payday';
    } else if (text.contains('meeting')) {
      title = 'Meeting';
    } else if (text.contains('training')) {
      title = 'Training';
    } else if (text.contains('holiday')) {
      title = 'Holiday';
    }

    DateTime date = DateTime(now.year, now.month, now.day);
    if (text.contains('tomorrow')) {
      date = date.add(const Duration(days: 1));
    } else {
      final parsed = _parseDateFromText(text);
      if (parsed != null) {
        date = parsed;
      }
    }

    if (title == null ||
        text.contains('add event') ||
        text.contains('create event') ||
        text == 'event') {
      showDialog(
        context: context,
        builder: (context) => AddEventDialog(
          initialDate: date,
          initialTitle: title,
          onAddEvents: (events) {
            if (events.length == 1) {
              roster.addEvent(events.first);
            } else {
              roster.addBulkEvents(events);
            }
          },
        ),
      );
      return;
    }

    final effectiveTitle = title ?? 'Event';

    final intervalMatch = RegExp(r'every\\s+(\\d+)\\s*(day|days|week|weeks)')
        .firstMatch(text);
    int interval = 1;
    bool weekly = true;
    if (intervalMatch != null) {
      interval = int.tryParse(intervalMatch.group(1)!) ?? 1;
      weekly = intervalMatch.group(2)!.startsWith('week');
    }
    final futureMatch = RegExp(r'future\\s+(\\d+)').firstMatch(text);
    final pastMatch = RegExp(r'past\\s+(\\d+)').firstMatch(text);
    final wantsInfinity = text.contains('infinite') || text.contains('forever');
    final futureCount = futureMatch != null
        ? int.parse(futureMatch.group(1)!)
        : wantsInfinity
            ? (weekly ? 520 : 3650)
            : 8;
    final pastCount = pastMatch != null
        ? int.parse(pastMatch.group(1)!)
        : wantsInfinity
            ? (weekly ? 520 : 3650)
            : 0;

    final stepDays = (weekly ? 7 : 1) * interval;
    final events = <models.Event>[];
    final recurringId = DateTime.now().millisecondsSinceEpoch.toString();

    void addEvent(DateTime d) {
      events.add(
        models.Event(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: effectiveTitle,
          date: d,
          eventType: _inferEventType(text, effectiveTitle),
          recurringId: intervalMatch != null ? recurringId : null,
        ),
      );
    }

    addEvent(date);
    if (intervalMatch != null) {
      for (var i = 1; i <= futureCount; i++) {
        addEvent(date.add(Duration(days: stepDays * i)));
      }
      for (var i = 1; i <= pastCount; i++) {
        addEvent(date.subtract(Duration(days: stepDays * i)));
      }
    }

    if (events.length == 1) {
      _confirmAction(
        context,
        title: 'Add event',
        message:
            'Add "${events.first.title}" on ${DateFormat('MMM d, yyyy').format(events.first.date)}?',
        onConfirm: () => roster.addEvent(events.first),
      );
    } else {
      _confirmAction(
        context,
        title: 'Add recurring events',
        message:
            'Add ${events.length} events for "$effectiveTitle" from '
            '${DateFormat('MMM d, yyyy').format(events.first.date)}?',
        onConfirm: () => roster.addBulkEvents(events),
      );
    }

    if (wantsInfinity) {
      _respondWithRC(
        context,
        'Added a large recurring range. Use future/past counts to adjust.',
      );
    }
    _respondWithRC(
      context,
      'Queued ${events.length} event(s): $effectiveTitle.',
    );
  }

  _DateRange? _extractDateRangeFromText(String text, int weekStartDay) {
    final lowered = text.toLowerCase();
    final dates = _extractAllDatesFromText(lowered);
    final durationDays = _extractDurationDays(lowered);
    final hasFromTo = lowered.contains('from') && lowered.contains('to');
    final hasUntil = lowered.contains('until') ||
        lowered.contains('till') ||
        lowered.contains('through') ||
        lowered.contains('thru');

    if (hasFromTo && dates.length >= 2) {
      final start = dates.first;
      final end = dates[1];
      return _DateRange(
        start: _startOfDay(start),
        end: _startOfDay(end),
        explicitStart: true,
        explicitEnd: true,
      );
    }

    if (hasUntil && dates.isNotEmpty) {
      final today = DateTime.now();
      return _DateRange(
        start: _startOfDay(today),
        end: _startOfDay(dates.first),
        explicitStart: false,
        explicitEnd: true,
      );
    }

    if (durationDays != null) {
      final base = dates.isNotEmpty ? dates.first : DateTime.now();
      final start = _startOfDay(base);
      final end = start.add(Duration(days: durationDays - 1));
      return _DateRange(
        start: start,
        end: end,
        durationDays: durationDays,
        explicitStart: dates.isNotEmpty,
        explicitEnd: false,
      );
    }

    final weekOffset = _extractWeekOffset(lowered);
    final weekdays = _extractWeekdays(lowered);
    if (weekOffset != null && weekdays.isEmpty) {
      final base = DateTime.now().add(Duration(days: weekOffset * 7));
      final start = _startOfWeekWithStart(base, weekStartDay);
      final end = start.add(const Duration(days: 6));
      return _DateRange(
        start: _startOfDay(start),
        end: _startOfDay(end),
        explicitStart: false,
        explicitEnd: false,
      );
    }

    if (weekdays.isNotEmpty) {
      final dayDates = _extractDatesForOverride(lowered, weekStartDay);
      if (dayDates.isNotEmpty) {
        final sorted = dayDates.toList()..sort();
        return _DateRange(
          start: _startOfDay(sorted.first),
          end: _startOfDay(sorted.last),
          explicitStart: false,
          explicitEnd: false,
        );
      }
    }

    if (dates.isNotEmpty) {
      final date = _startOfDay(dates.first);
      return _DateRange(
        start: date,
        end: date,
        explicitStart: true,
        explicitEnd: true,
      );
    }

    return null;
  }

  List<DateTime> _extractAllDatesFromText(String text) {
    final lowered = text.toLowerCase();
    final dates = <DateTime>[];
    final today = DateTime.now();

    if (lowered.contains('today')) {
      dates.add(DateTime(today.year, today.month, today.day));
    }
    if (lowered.contains('tomorrow')) {
      final t = today.add(const Duration(days: 1));
      dates.add(DateTime(t.year, t.month, t.day));
    }
    if (lowered.contains('yesterday')) {
      final y = today.subtract(const Duration(days: 1));
      dates.add(DateTime(y.year, y.month, y.day));
    }

    final isoMatches =
        RegExp(r'(\\d{4})-(\\d{2})-(\\d{2})').allMatches(lowered);
    for (final match in isoMatches) {
      dates.add(DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      ));
    }

    final slashMatches =
        RegExp(r'(\\d{1,2})[/-](\\d{1,2})[/-](\\d{4})').allMatches(lowered);
    for (final match in slashMatches) {
      dates.add(DateTime(
        int.parse(match.group(3)!),
        int.parse(match.group(2)!),
        int.parse(match.group(1)!),
      ));
    }

    final monthNames = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final dayMonthMatches = RegExp(
      r'(\\d{1,2})(?:st|nd|rd|th)?\\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)(?:\\s*(\\d{4}))?',
    ).allMatches(lowered);
    for (final match in dayMonthMatches) {
      final day = int.parse(match.group(1)!);
      final month = monthNames[match.group(2)!]!;
      final year =
          match.group(3) != null ? int.parse(match.group(3)!) : today.year;
      dates.add(DateTime(year, month, day));
    }

    final monthDayMatches = RegExp(
      r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\\s*(\\d{1,2})(?:st|nd|rd|th)?(?:\\s*(\\d{4}))?',
    ).allMatches(lowered);
    for (final match in monthDayMatches) {
      final day = int.parse(match.group(2)!);
      final month = monthNames[match.group(1)!]!;
      final year =
          match.group(3) != null ? int.parse(match.group(3)!) : today.year;
      dates.add(DateTime(year, month, day));
    }

    return dates;
  }

  List<_DateRange> _extractMultipleDateRanges(
    String text,
    int weekStartDay,
  ) {
    final lowered = text.toLowerCase();
    final ranges = <_DateRange>[];
    final explicitRanges =
        RegExp(r'from\\s+([^,]+?)\\s+to\\s+([^,]+?)(?:,|$)')
            .allMatches(lowered);
    for (final match in explicitRanges) {
      final startText = match.group(1) ?? '';
      final endText = match.group(2) ?? '';
      final start = _parseDateFromText(startText);
      final end = _parseDateFromText(endText);
      if (start != null && end != null) {
        ranges.add(
          _DateRange(
            start: _startOfDay(start),
            end: _startOfDay(end),
            explicitStart: true,
            explicitEnd: true,
          ),
        );
      }
    }

    if (ranges.isNotEmpty) {
      return ranges;
    }

    final single = _extractDateRangeFromText(lowered, weekStartDay);
    if (single != null) {
      ranges.add(single);
    }
    return ranges;
  }

  List<_LeaveAssignment>? _pairStaffToRanges(
    List<String> staffNames,
    List<_DateRange> ranges,
  ) {
    if (ranges.length == 1) {
      return staffNames
          .map((name) => _LeaveAssignment(staff: name, range: ranges.first))
          .toList();
    }
    if (ranges.length == staffNames.length) {
      final assignments = <_LeaveAssignment>[];
      for (int i = 0; i < staffNames.length; i++) {
        assignments.add(
          _LeaveAssignment(staff: staffNames[i], range: ranges[i]),
        );
      }
      return assignments;
    }
    return null;
  }

  int? _extractDurationDays(String text) {
    final match = RegExp(r'for\\s+(\\d+)\\s*(day|days|week|weeks)')
        .firstMatch(text);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!) ?? 0;
    if (value <= 0) return null;
    final unit = match.group(2) ?? 'day';
    return unit.startsWith('week') ? value * 7 : value;
  }

  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime? _parseDateFromText(String text) {
    final lowered = text.toLowerCase();
    final today = DateTime.now();
    if (lowered.contains('today')) {
      return DateTime(today.year, today.month, today.day);
    }
    if (lowered.contains('tomorrow')) {
      final tomorrow = today.add(const Duration(days: 1));
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    }
    if (lowered.contains('yesterday')) {
      final yesterday = today.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day);
    }
    final isoMatch = RegExp(r'(\\d{4})-(\\d{2})-(\\d{2})').firstMatch(lowered);
    if (isoMatch != null) {
      return DateTime(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
      );
    }
    final slashMatch =
        RegExp(r'(\\d{1,2})[/-](\\d{1,2})[/-](\\d{4})').firstMatch(lowered);
    if (slashMatch != null) {
      return DateTime(
        int.parse(slashMatch.group(3)!),
        int.parse(slashMatch.group(2)!),
        int.parse(slashMatch.group(1)!),
      );
    }
    final monthNames = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final match = RegExp(
      r'(\\d{1,2})(?:st|nd|rd|th)?\\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)(?:\\s*(\\d{4}))?',
    )
        .firstMatch(lowered);
    if (match != null) {
      final day = int.parse(match.group(1)!);
      final month = monthNames[match.group(2)!]!;
      final year = match.group(3) != null
          ? int.parse(match.group(3)!)
          : DateTime.now().year;
      return DateTime(year, month, day);
    }
    final reverseMatch = RegExp(
      r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\\s*(\\d{1,2})(?:st|nd|rd|th)?(?:\\s*(\\d{4}))?',
    ).firstMatch(lowered);
    if (reverseMatch != null) {
      final day = int.parse(reverseMatch.group(2)!);
      final month = monthNames[reverseMatch.group(1)!]!;
      final year = reverseMatch.group(3) != null
          ? int.parse(reverseMatch.group(3)!)
          : DateTime.now().year;
      return DateTime(year, month, day);
    }
    return null;
  }

  List<DateTime> _extractDatesForOverride(String text, int weekStartDay) {
    final lowered = text.toLowerCase();
    final dates = <DateTime>{};

    final explicit = _parseDateFromText(lowered);
    if (explicit != null) {
      dates.add(DateTime(explicit.year, explicit.month, explicit.day));
    }

    final weekOffset = _extractWeekOffset(lowered);
    final weekdays = _extractWeekdays(lowered);
    if (weekOffset != null && weekdays.isNotEmpty) {
      final base = DateTime.now().add(Duration(days: weekOffset * 7));
      final start = _startOfWeekWithStart(base, weekStartDay);
      for (final weekday in weekdays) {
        final date = start.add(Duration(
          days: _weekdayOffsetFromStart(weekday, weekStartDay),
        ));
        dates.add(DateTime(date.year, date.month, date.day));
      }
    } else if (weekdays.isNotEmpty) {
      final start = _startOfWeekWithStart(DateTime.now(), weekStartDay);
      for (final weekday in weekdays) {
        final date = start.add(Duration(
          days: _weekdayOffsetFromStart(weekday, weekStartDay),
        ));
        dates.add(DateTime(date.year, date.month, date.day));
      }
    }
    return dates.toList();
  }

  int? _extractWeekOffset(String text) {
    if (text.contains('next week')) return 1;
    if (text.contains('this week')) return 0;
    if (text.contains('last week') || text.contains('previous week')) return -1;
    if (text.contains('next mon') ||
        text.contains('next tue') ||
        text.contains('next wed') ||
        text.contains('next thu') ||
        text.contains('next fri') ||
        text.contains('next sat') ||
        text.contains('next sun') ||
        text.contains('next monday') ||
        text.contains('next tuesday') ||
        text.contains('next wednesday') ||
        text.contains('next thursday') ||
        text.contains('next friday') ||
        text.contains('next saturday') ||
        text.contains('next sunday')) {
      return 1;
    }
    if (text.contains('this mon') ||
        text.contains('this tue') ||
        text.contains('this wed') ||
        text.contains('this thu') ||
        text.contains('this fri') ||
        text.contains('this sat') ||
        text.contains('this sun') ||
        text.contains('this monday') ||
        text.contains('this tuesday') ||
        text.contains('this wednesday') ||
        text.contains('this thursday') ||
        text.contains('this friday') ||
        text.contains('this saturday') ||
        text.contains('this sunday')) {
      return 0;
    }
    final match = RegExp(r'in\\s+(\\d+)\\s+weeks?').firstMatch(text);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return null;
  }

  List<int> _extractWeekdays(String text) {
    final days = <int>{};
    final map = <String, int>{
      'sun': 0,
      'sunday': 0,
      'mon': 1,
      'monday': 1,
      'tue': 2,
      'tues': 2,
      'tuesday': 2,
      'wed': 3,
      'wednesday': 3,
      'thu': 4,
      'thur': 4,
      'thursday': 4,
      'fri': 5,
      'friday': 5,
      'sat': 6,
      'saturday': 6,
    };
    for (final entry in map.entries) {
      if (text.contains(entry.key)) {
        days.add(entry.value);
      }
    }
    if (text.contains('weekday')) {
      days.addAll([1, 2, 3, 4, 5]);
    }
    if (text.contains('weekend')) {
      days.addAll([0, 6]);
    }
    return days.toList();
  }

  DateTime _startOfWeekWithStart(DateTime date, int weekStartDay) {
    final weekdayIndex = date.weekday % 7;
    int delta = weekdayIndex - weekStartDay;
    if (delta < 0) delta += 7;
    final start = date.subtract(Duration(days: delta));
    return DateTime(start.year, start.month, start.day);
  }

  int _weekdayOffsetFromStart(int weekday, int weekStartDay) {
    int delta = weekday - weekStartDay;
    if (delta < 0) delta += 7;
    return delta;
  }

  void _showAiHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI Help'),
        content: const Text(
          'Try commands like:\\n'
          '- "Add payday every 2 weeks future 8 past 4"\\n'
          '- "Add meeting tomorrow"\\n'
          '- "Delete event payday"\\n'
          '- "Set Jack N today"\\n'
          '- "Jack late next week wed thu fri"\\n'
          '- "Create roster 16 staff 8 weeks start monday"\\n'
          '- "How do I add events?"\\n\\n'
          'You can also add events from the Events tab or by tapping a date in the roster.',
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

  void _handleDeleteEventCommand(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    final text = raw.toLowerCase();
    final matches = roster.events.where((event) {
      return text.contains(event.title.toLowerCase());
    }).toList();

    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matching event found.')),
      );
      return;
    }
    _confirmAction(
      context,
      title: 'Delete events',
      message: 'Delete ${matches.length} event(s)?',
      onConfirm: () {
        for (final event in matches) {
          roster.deleteEvent(event.id);
        }
      },
    );
  }

  Future<void> _handleWhenIsCommand(BuildContext context, String raw) async {
    final query = raw.toLowerCase().replaceFirst('when is', '').trim();
    if (query.isEmpty) {
      _respondWithRC(context, 'Tell me the event name.');
      return;
    }

    final today = DateTime.now();
    final fixedDates = <String, DateTime Function(int)>{
      'valentines day': (y) => DateTime(y, 2, 14),
      'valentine': (y) => DateTime(y, 2, 14),
      'christmas': (y) => DateTime(y, 12, 25),
      'new year': (y) => DateTime(y, 1, 1),
      'halloween': (y) => DateTime(y, 10, 31),
    };

    for (final entry in fixedDates.entries) {
      if (query.contains(entry.key)) {
        var date = entry.value(today.year);
        if (date.isBefore(today)) {
          date = entry.value(today.year + 1);
        }
        _respondWithRC(
          context,
          '${entry.key[0].toUpperCase()}${entry.key.substring(1)} is on '
              '${DateFormat('MMM d, yyyy').format(date)}. '
              'I can add it to your roster.',
        );
        return;
      }
    }

    if (query.contains('chinese new year') ||
        query.contains('lunar new year')) {
      final settings = ref.read(settingsProvider);
      final holidaysThis = await HolidayService.instance.getHolidays(
        countryCode: settings.holidayCountryCode,
        year: today.year,
      );
      final holidaysNext = await HolidayService.instance.getHolidays(
        countryCode: settings.holidayCountryCode,
        year: today.year + 1,
      );
      final all = [...holidaysThis, ...holidaysNext];
      final match = all.firstWhere(
        (h) =>
            h.name.toLowerCase().contains('chinese new year') ||
            h.localName.toLowerCase().contains('chinese new year') ||
            h.name.toLowerCase().contains('lunar new year') ||
            h.localName.toLowerCase().contains('lunar new year'),
        orElse: () => HolidayItem(
          date: DateTime(1900),
          name: '',
          localName: '',
          types: const [],
        ),
      );
      if (match.name.isNotEmpty) {
        _respondWithRC(
          context,
          '${match.localName} is on '
              '${DateFormat('MMM d, yyyy').format(match.date)}.',
        );
        return;
      }
    }

    final roster = ref.read(rosterProvider);
    final eventMatch = roster.events.firstWhere(
      (e) => e.title.toLowerCase().contains(query),
      orElse: () => models.Event(
        id: '',
        title: '',
        date: DateTime(1900),
      ),
    );
    if (eventMatch.id.isNotEmpty) {
      _respondWithRC(
        context,
        '${eventMatch.title} is on ${DateFormat('MMM d, yyyy').format(eventMatch.date)}.',
      );
      return;
    }

    final settings = ref.read(settingsProvider);
    final holidayCountries = <String>{
      settings.holidayCountryCode,
      ...settings.additionalHolidayCountries,
    };
    final holidays = <HolidayItem>[];
    for (final country in holidayCountries) {
      if (country.trim().isEmpty) continue;
      final holidaysThis = await HolidayService.instance.getHolidays(
        countryCode: country,
        year: today.year,
      );
      final holidaysNext = await HolidayService.instance.getHolidays(
        countryCode: country,
        year: today.year + 1,
      );
      holidays.addAll(holidaysThis);
      holidays.addAll(holidaysNext);
    }
    if (query.contains('holiday') || query.contains('bank')) {
      final upcoming = holidays
          .where((h) => !h.date.isBefore(today))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      if (upcoming.isNotEmpty) {
        final nextHoliday = upcoming.first;
        _respondWithRC(
          context,
          'Next holiday is ${nextHoliday.localName} on '
              '${DateFormat('MMM d, yyyy').format(nextHoliday.date)}.',
        );
        return;
      }
    }
    final holidayMatch = holidays.firstWhere(
      (h) =>
          h.name.toLowerCase().contains(query) ||
          h.localName.toLowerCase().contains(query),
      orElse: () => HolidayItem(
        date: DateTime(1900),
        name: '',
        localName: '',
        types: const [],
      ),
    );
    if (holidayMatch.name.isNotEmpty) {
      _respondWithRC(
        context,
        '${holidayMatch.localName} is on '
            '${DateFormat('MMM d, yyyy').format(holidayMatch.date)}. '
            'I can add it to your roster.',
      );
      return;
    }

    if (settings.calendarificApiKey.trim().isNotEmpty) {
      final observances = await ObservanceService.instance.getObservances(
        apiKey: settings.calendarificApiKey,
        countryCode: settings.holidayCountryCode,
        year: today.year,
        types: settings.observanceTypes,
      );
      final observancesNext = await ObservanceService.instance.getObservances(
        apiKey: settings.calendarificApiKey,
        countryCode: settings.holidayCountryCode,
        year: today.year + 1,
        types: settings.observanceTypes,
      );
      final allObservances = [...observances, ...observancesNext];
      final obsMatch = allObservances.firstWhere(
        (o) => o.localName.toLowerCase().contains(query),
        orElse: () => HolidayItem(
          date: DateTime(1900),
          name: '',
          localName: '',
          types: const [],
        ),
      );
      if (obsMatch.name.isNotEmpty) {
        _respondWithRC(
          context,
          '${obsMatch.localName} is on '
              '${DateFormat('MMM d, yyyy').format(obsMatch.date)}. '
              'I can add it to your roster.',
        );
        return;
      }
      if (query.contains('observance') || query.contains('religious')) {
        final upcoming = allObservances
            .where((o) => !o.date.isBefore(today))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        if (upcoming.isNotEmpty) {
          final nextObs = upcoming.first;
          _respondWithRC(
            context,
            'Next observance is ${nextObs.localName} on '
                '${DateFormat('MMM d, yyyy').format(nextObs.date)}.',
          );
          return;
        }
      }
    }

    _respondWithRC(
      context,
      "I could not find '$query' in your roster or holiday sources. "
          'You can add it as an event.',
    );
  }

  void _respondWithRC(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('RC: $message'),
      ),
    );
    final settings = ref.read(settingsProvider);
    _voiceService.speak(message, settings);
  }

  Future<void> _showRosterWizard(
    BuildContext context, {
    int? staffCount,
    int? cycleLength,
    int? weekStartDay,
  }) async {
    final roster = ref.read(rosterProvider);
    final staffController = TextEditingController(
      text: staffCount?.toString() ?? roster.numPeople.toString(),
    );
    final cycleController = TextEditingController(
      text: cycleLength?.toString() ?? roster.cycleLength.toString(),
    );
    int startDay = weekStartDay ?? roster.weekStartDay;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Roster Wizard'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: staffController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of staff',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cycleController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cycle length (weeks)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: startDay,
              decoration: const InputDecoration(labelText: 'Week start'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Sunday')),
                DropdownMenuItem(value: 1, child: Text('Monday')),
                DropdownMenuItem(value: 2, child: Text('Tuesday')),
                DropdownMenuItem(value: 3, child: Text('Wednesday')),
                DropdownMenuItem(value: 4, child: Text('Thursday')),
                DropdownMenuItem(value: 5, child: Text('Friday')),
                DropdownMenuItem(value: 6, child: Text('Saturday')),
              ],
              onChanged: (value) {
                if (value != null) {
                  startDay = value;
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
          FilledButton(
            onPressed: () {
              final staff = int.tryParse(staffController.text.trim()) ?? 0;
              final cycle = int.tryParse(cycleController.text.trim()) ?? 0;
              if (staff < 1 || cycle < 1) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter valid values.')),
                );
                return;
              }
              roster.setWeekStartDay(startDay);
              roster.initializeRoster(cycle, staff, keepExistingData: false);
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RosterGeneratorView(),
                ),
              );
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _handleSetShiftCommand(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    if (roster.readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read-only roster cannot be edited.')),
      );
      return;
    }
    final text = raw.toLowerCase();
    final staff = roster.staffMembers.map((s) => s.name).toList();
    String? matched;
    for (final name in staff) {
      if (text.contains(name.toLowerCase())) {
        matched = name;
        break;
      }
    }
    if (matched == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff name not recognized.')),
      );
      return;
    }

    final date = _parseDateFromText(text) ?? DateTime.now();
    final shiftMatch =
        RegExp(r'\\b(d12|n12|d|n|l|off|r|e|c1|c2|c3|c4|c)\\b')
            .firstMatch(text);
    if (shiftMatch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift code not recognized.')),
      );
      return;
    }
    final shift = shiftMatch.group(1)!.toUpperCase();
    _confirmAction(
      context,
      title: 'Set shift',
      message:
          'Set $matched to ${_shiftLabelWithCode(shift)} on ${DateFormat('MMM d, yyyy').format(date)}?',
      onConfirm: () =>
          roster.setOverride(matched!, date, shift, 'AI command'),
    );
  }

  Future<void> _showSetShiftWizard(
    BuildContext context, {
    String? initialStaff,
    DateTime? initialDate,
    String? initialShift,
  }) async {
    final roster = ref.read(rosterProvider);
    final staff = roster.staffMembers.map((s) => s.name).toList();
    if (staff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add staff before setting shifts.')),
      );
      return;
    }
    String staffName = initialStaff ?? staff.first;
    DateTime date = initialDate ?? DateTime.now();
    final shiftController =
        TextEditingController(text: initialShift ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: staffName,
              items: staff
                  .map(
                    (name) => DropdownMenuItem(
                      value: name,
                      child: Text(name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  staffName = value;
                }
              },
              decoration: const InputDecoration(labelText: 'Staff member'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Date'),
              subtitle: Text(DateFormat('MMM d, yyyy').format(date)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime.now().subtract(const Duration(days: 730)),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (picked != null) {
                  date = picked;
                }
              },
            ),
            TextField(
              controller: shiftController,
              decoration: const InputDecoration(
                labelText: 'Shift code',
                hintText: 'e.g. D, N, D12, N12, OFF',
              ),
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

    if (confirmed == true) {
      final shift = shiftController.text.trim().toUpperCase();
      if (shift.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a shift code.')),
        );
        return;
      }
      roster.setOverride(staffName, date, shift, 'AI command');
    }
  }

  Future<void> _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
    if (confirmed == true) {
      onConfirm();
    }
  }
}

class _CommandChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CommandChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _ScenarioImpactCard extends ConsumerWidget {
  final List<models.AiSuggestion> suggestions;

  const _ScenarioImpactCard({required this.suggestions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.auto_graph_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Scenario Planning',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () {
                final delta = ref
                    .read(rosterProvider)
                    .simulateScenarioImpact(suggestions);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Scenario Impact'),
                    content: _ImpactSummary(delta: delta),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Simulate'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImpactSummary extends StatelessWidget {
  final models.RosterHealthScore delta;

  const _ImpactSummary({required this.delta});

  @override
  Widget build(BuildContext context) {
    String format(double value) =>
        value >= 0 ? '+${value.toStringAsFixed(2)}' : value.toStringAsFixed(2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Overall: ${format(delta.overall)}'),
        Text('Coverage: ${format(delta.coverage)}'),
        Text('Workload: ${format(delta.workload)}'),
        Text('Fairness: ${format(delta.fairness)}'),
        Text('Leave: ${format(delta.leave)}'),
        Text('Pattern: ${format(delta.pattern)}'),
      ],
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  final models.AiSuggestion suggestion;

  const _SuggestionCard({required this.suggestion});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priorityColor = _getPriorityColor(suggestion.priority);
    final isReadOnly = ref.watch(rosterProvider).readOnly;
    final hasAction = suggestion.actionType != null &&
        suggestion.actionType != models.SuggestionActionType.none &&
        suggestion.actionPayload != null &&
        !isReadOnly;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: suggestion.isRead ? 1 : 3,
      child: InkWell(
        onTap: () {
          if (!suggestion.isRead) {
            ref.read(rosterProvider).markSuggestionAsRead(suggestion.id);
          }
          _showSuggestionDetails(context, ref);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: priorityColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: priorityColor),
                    ),
                    child: Text(
                      suggestion.priority.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: priorityColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!suggestion.isRead)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    DateFormat('MMM d').format(suggestion.createdDate),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                suggestion.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                suggestion.description,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                ),
              ),
              if (suggestion.affectedStaff != null &&
                  suggestion.affectedStaff!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: suggestion.affectedStaff!.map((staff) {
                    return Chip(
                      label: Text(staff),
                      labelStyle: const TextStyle(fontSize: 12),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      ref.read(rosterProvider).dismissSuggestion(suggestion.id);
                    },
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Dismiss'),
                  ),
                  if (hasAction) const SizedBox(width: 8),
                  if (hasAction)
                    FilledButton.icon(
                      onPressed: () => _applySuggestion(context, ref),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Apply'),
                    ),
                ],
              ),
              if (suggestion.impactScore != null ||
                  suggestion.confidence != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (suggestion.impactScore != null)
                      _buildMetaChip(
                        context,
                        'Impact ${(suggestion.impactScore! * 100).toStringAsFixed(0)}%',
                        Icons.trending_up,
                      ),
                    const SizedBox(width: 8),
                    if (suggestion.confidence != null)
                      _buildMetaChip(
                        context,
                        'Confidence ${(suggestion.confidence! * 100).toStringAsFixed(0)}%',
                        Icons.verified,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getPriorityColor(models.SuggestionPriority priority) {
    switch (priority) {
      case models.SuggestionPriority.low:
        return Colors.blue;
      case models.SuggestionPriority.medium:
        return Colors.orange;
      case models.SuggestionPriority.high:
        return Colors.red;
      case models.SuggestionPriority.critical:
        return Colors.purple;
    }
  }

  void _showSuggestionDetails(BuildContext context, WidgetRef ref) {
    final impactDelta = ref
        .read(rosterProvider)
        .previewSuggestionImpact(suggestion);
    final isReadOnly = ref.read(rosterProvider).readOnly;
    final hasAction = suggestion.actionType != null &&
        suggestion.actionType != models.SuggestionActionType.none &&
        suggestion.actionPayload != null &&
        !isReadOnly;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(suggestion.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(suggestion.description),
              if (suggestion.reason != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Why this helps',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(suggestion.reason!),
              ],
              const SizedBox(height: 12),
              _buildImpactDelta(impactDelta),
              const SizedBox(height: 16),
              if (suggestion.affectedStaff != null &&
                  suggestion.affectedStaff!.isNotEmpty) ...[
                const Text(
                  'Affected Staff:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...suggestion.affectedStaff!.map((staff) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.person, size: 16),
                          const SizedBox(width: 8),
                          Text(staff),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Priority: ${suggestion.priority.name}',
                    style: TextStyle(
                      color: _getPriorityColor(suggestion.priority),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    DateFormat('MMM d, yyyy').format(suggestion.createdDate),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(rosterProvider).dismissSuggestion(suggestion.id);
            },
            child: const Text('Dismiss'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(rosterProvider)
                  .setSuggestionFeedback(
                    suggestion.id,
                    models.SuggestionFeedback.notHelpful,
                  );
              Navigator.pop(context);
            },
            child: const Text('Not Helpful'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(rosterProvider)
                  .setSuggestionFeedback(
                    suggestion.id,
                    models.SuggestionFeedback.helpful,
                  );
              Navigator.pop(context);
            },
            child: const Text('Helpful'),
          ),
          if (hasAction)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _applySuggestion(context, ref);
              },
              child: const Text('Apply'),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
        ],
      ),
    );
  }

  Future<void> _applySuggestion(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply Suggestion?'),
        content: Text(
          'This will apply: ${suggestion.title}\n\n'
          'You can undo the change after applying.',
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

    if (confirmed == true && context.mounted) {
      final roster = ref.read(rosterProvider);
      final backup = roster.createBackup();
      final applied = roster.applySuggestionAction(suggestion);
      if (applied) {
        roster.dismissSuggestion(suggestion.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Suggestion applied'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => roster.restoreBackup(backup),
              ),
            ),
          );
        }
      }
    }
  }

  Widget _buildMetaChip(
    BuildContext context,
    String label,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildImpactDelta(models.RosterHealthScore delta) {
    String format(double value) =>
        value >= 0 ? '+${value.toStringAsFixed(2)}' : value.toStringAsFixed(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'KPI Impact',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text('Overall: ${format(delta.overall)}'),
        Text('Coverage: ${format(delta.coverage)}'),
        Text('Workload: ${format(delta.workload)}'),
        Text('Fairness: ${format(delta.fairness)}'),
        Text('Leave: ${format(delta.leave)}'),
        Text('Pattern: ${format(delta.pattern)}'),
      ],
    );
  }
}

