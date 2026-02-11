import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'services/activity_log_service.dart';
import 'aws_service.dart';
import 'dialogs.dart';
import 'package:roster_champ/safe_text_field.dart';

class AiSuggestionsView extends ConsumerStatefulWidget {
  final String? initialCommand;

  const AiSuggestionsView({super.key, this.initialCommand});

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

class _ResolvedDates {
  final List<DateTime> dates;
  final double confidence;

  const _ResolvedDates(this.dates, this.confidence);
}

class _ParsedDate {
  final DateTime date;
  final double confidence;

  const _ParsedDate(this.date, this.confidence);
}

_ParsedDate? _parseDateLoose(
  String raw, {
  bool monthFirst = false,
}) {
  final cleaned = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ')
      .replaceAll(RegExp(r'\\s+'), ' ')
      .trim();
  final patterns = <String>[
    'd MMMM yyyy',
    'd MMM yyyy',
    'd MMMM',
    'd MMM',
    'MMMM d yyyy',
    'MMM d yyyy',
    'MMMM d',
    'MMM d',
  ];
  for (final pattern in patterns) {
    try {
      final fmt = DateFormat(pattern);
      final parsed = fmt.parseStrict(cleaned);
      var date = DateTime(parsed.year, parsed.month, parsed.day);
      if (!pattern.contains('yyyy')) {
        final now = DateTime.now();
        date = DateTime(now.year, parsed.month, parsed.day);
      }
      return _ParsedDate(date, 0.8);
    } catch (_) {}
  }
  final numeric = RegExp(r'(\\d{1,2})\\s+(\\d{1,2})\\s+(\\d{2,4})')
      .firstMatch(cleaned);
  if (numeric != null) {
    final a = int.parse(numeric.group(1)!);
    final b = int.parse(numeric.group(2)!);
    final rawYear = int.parse(numeric.group(3)!);
    final year = rawYear < 100 ? 2000 + rawYear : rawYear;
    final month = monthFirst ? a : b;
    final day = monthFirst ? b : a;
    return _ParsedDate(DateTime(year, month, day), 0.7);
  }
  return null;
}


class _AiContextState {
  String? lastStaff;
  DateTime? lastDate;
  String? lastShift;
  String? lastAction;
  String? lastPendingRaw;
  List<String>? lastStaffList;
  String? pendingStaff;
  String? pendingShift;
  List<DateTime>? pendingDates;
  DateTime? pendingCreatedAt;

  void remember({
    String? staff,
    DateTime? date,
    String? shift,
    String? action,
    String? pendingRaw,
    List<String>? staffList,
    String? pendingStaff,
    String? pendingShift,
    List<DateTime>? pendingDates,
    DateTime? pendingCreatedAt,
  }) {
    if (staff != null && staff.isNotEmpty) lastStaff = staff;
    if (date != null) lastDate = date;
    if (shift != null && shift.isNotEmpty) lastShift = shift;
    if (action != null && action.isNotEmpty) lastAction = action;
    if (pendingRaw != null && pendingRaw.isNotEmpty) {
      lastPendingRaw = pendingRaw;
    }
    if (staffList != null && staffList.isNotEmpty) {
      lastStaffList = staffList;
    }
    if (pendingStaff != null && pendingStaff.isNotEmpty) {
      this.pendingStaff = pendingStaff;
    }
    if (pendingShift != null && pendingShift.isNotEmpty) {
      this.pendingShift = pendingShift;
    }
    if (pendingDates != null && pendingDates.isNotEmpty) {
      this.pendingDates = pendingDates;
    }
    if (pendingCreatedAt != null) {
      this.pendingCreatedAt = pendingCreatedAt;
    }
  }
}

class _AiSuggestionsViewState extends ConsumerState<AiSuggestionsView> {
  final TextEditingController _commandController = TextEditingController();
  final VoiceService _voiceService = VoiceService.instance;
  bool _didAutoRefresh = false;
  final _AiContextState _contextState = _AiContextState();
  bool _canSend = false;
  bool _lastCommandFromVoice = false;
  String? _lastVoiceTranscript;

  @override
  void dispose() {
    _commandController.removeListener(_updateSendState);
    _commandController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _commandController.addListener(_updateSendState);
    _voiceService.onCommand = (text) {
      if (!mounted) return;
      final command = text.trim();
      if (command.isEmpty) {
        _respondWithRC(context, 'I am listening. What should I do?');
        return;
      }
      _lastCommandFromVoice = true;
      _lastVoiceTranscript = command;
      _commandController.text = command;
      _handleAiCommand(context);
    };
    if (widget.initialCommand != null &&
        widget.initialCommand!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _commandController.text = widget.initialCommand!.trim();
        _handleAiCommand(context);
      });
    }
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
    final style = settings.layoutStyle;
    final panelColor = _aiPanelColor(context, style);
    final panelBorder = _aiPanelBorder(context, style);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: panelColor ?? Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: panelBorder,
        boxShadow: panelColor == null
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
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
            if (_contextState.lastAction != null &&
                _contextState.lastAction!.isNotEmpty &&
                _contextState.lastAction!.startsWith('await_')) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pending_actions, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _pendingSummary(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Clear pending',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() {
                          _contextState.remember(action: '');
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            SafeTextField(
              controller: _commandController,
              decoration: InputDecoration(
                hintText: 'e.g. Add payday every 2 weeks for 8 future + 4 past',
                border: const OutlineInputBorder(),
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
                onPressed: _canSend ? () => _handleAiCommand(context) : null,
                child: const Icon(Icons.arrow_upward_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color? _aiPanelColor(BuildContext context, models.AppLayoutStyle style) {
    switch (style) {
      case models.AppLayoutStyle.sophisticated:
        return const Color(0xFF0D1A22);
      case models.AppLayoutStyle.ambience:
        return const Color(0xFF0E1F27);
      case models.AppLayoutStyle.professional:
        return Theme.of(context).colorScheme.surface;
      case models.AppLayoutStyle.intuitive:
        return Theme.of(context).colorScheme.surface;
      case models.AppLayoutStyle.standard:
      default:
        return null;
    }
  }

  Border? _aiPanelBorder(BuildContext context, models.AppLayoutStyle style) {
    switch (style) {
      case models.AppLayoutStyle.sophisticated:
        return Border.all(color: const Color(0xFF1EC7D6), width: 1);
      case models.AppLayoutStyle.ambience:
        return Border.all(color: const Color(0xFF2EA6B6), width: 1);
      default:
        return Border.all(
          color: Theme.of(context).dividerColor,
          width: 1,
        );
    }
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
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type a command to send.')),
      );
      return;
    }
    ActivityLogService.instance.addInfo(
      'RC command received',
      details: raw,
    );
    final fromVoice = _lastCommandFromVoice;
    final voiceTranscript = _lastVoiceTranscript;
    _lastCommandFromVoice = false;
    _lastVoiceTranscript = null;
    try {
      _clearExpiredPendingContext();
      final clauses = _splitIntoClauses(raw);
      int answerIndex = 0;
      for (final clause in clauses) {
        if (clause.trim().isEmpty) continue;
        answerIndex++;
        bool handled = false;
        try {
          handled = _handleAiCommandClause(
            context,
            clause,
            isBatch: clauses.length > 1,
          );
        } catch (e) {
          ActivityLogService.instance.addError(
            'RC command failed',
            const ['Try rephrasing the request', 'Check roster data'],
            details: e.toString(),
          );
          _respondWithRC(
            context,
            'I had trouble processing that. Please try again or rephrase.',
          );
          handled = true;
        }
        if (!handled) {
          if (fromVoice && (voiceTranscript?.isNotEmpty ?? false)) {
            _respondWithRC(
              context,
              'I heard: "$voiceTranscript". Tell me the staff, date, and action (set shift, swap, leave, or event).',
            );
          } else {
            _respondWithRC(
              context,
              "I did not catch that. Tell me the staff, date, and action (set shift, swap, leave, or event).",
            );
          }
        }
      }
    } catch (e) {
      ActivityLogService.instance.addError(
        'RC command failed',
        const ['Try rephrasing the request', 'Check roster data'],
        details: e.toString(),
      );
      _respondWithRC(
        context,
        'I had trouble processing that. Please try again.',
      );
    }
  }

  void _updateSendState() {
    final hasText = _commandController.text.trim().isNotEmpty;
    if (hasText != _canSend) {
      setState(() => _canSend = hasText);
    }
  }

  bool _handleAiCommandClause(
    BuildContext context,
    String raw, {
    required bool isBatch,
  }) {
    _clearExpiredPendingContext();
    final text = _normalizeCommand(raw);
    final tokens = text.split(' ');
    final roster = ref.read(rosterProvider);

    if (_isTemplateGenerateIntent(text)) {
      _handleTemplateGenerateCommand(context, raw);
      return true;
    }

    if (_isTemplateApplyIntent(text)) {
      final codeMatch = RegExp(r'(RC[12]-[A-Za-z0-9_-]+)')
          .firstMatch(raw);
      if (codeMatch == null) {
        _respondWithRC(
          context,
          'Paste the template code (starts with RC2-).',
        );
        return true;
      }
      final applied = roster.applyTemplateCode(codeMatch.group(1)!);
      if (applied) {
        _respondWithRC(
          context,
          'Template code applied. The roster is now updated.',
        );
      } else {
        _respondWithRC(
          context,
          'I could not apply that template code. Check the code and try again.',
        );
      }
      return true;
    }
    final staffMatch = _matchStaffName(text, roster);
    final staffMatches = _matchAllStaffNames(text, roster);
    final shiftMatch = _extractShiftCode(text);
    final dateRange = _extractDateRangeFromText(text, roster.weekStartDay);
    final resolvedStaff = staffMatch ??
        (_contextState.lastStaff != null &&
                _shouldUseContextStaff(text, tokens)
            ? _contextState.lastStaff
            : null);
    final resolvedShift = shiftMatch ??
        (_contextState.lastShift != null &&
                _shouldUseContextShift(text, tokens)
            ? _contextState.lastShift
            : null);
    final resolvedDate = dateRange?.start ??
        (_contextState.lastDate != null && _shouldUseContextDate(text, tokens)
            ? _contextState.lastDate
            : null);

    if (staffMatch != null || shiftMatch != null || dateRange != null) {
      _contextState.remember(
        staff: staffMatch,
        shift: shiftMatch,
        date: dateRange?.start,
      );
    }
    final shiftQueryIntent = _isShiftQueryIntent(text, tokens);
    final isQuestion = _isQuestionLike(text, tokens);
    final actionVerbPresent = _containsAnyFuzzy(tokens, [
      'set',
      'assign',
      'change',
      'override',
      'swap',
      'add',
      'remove',
      'delete',
      'cancel',
      'create',
      'generate',
      'build',
      'make',
    ]);
    final implicitAction =
        staffMatch != null && shiftMatch != null && dateRange != null;
    final actionIntent = actionVerbPresent || implicitAction;
    final cancelLeaveIntent = _isCancelLeaveIntent(text, tokens);
    final setLeaveIntent = _isSetLeaveIntent(text, tokens);
    if (_handleRosterMathQuery(context, raw, text, roster)) {
      return true;
    }
    if (_handleMathQuery(context, raw)) {
      return true;
    }
    if (_handleNameQuery(context, text)) {
      return true;
    }
    if (_handleNextRestDayQuery(context, text, roster)) {
      return true;
    }
    if (_contextState.lastAction == 'await_date_for_query') {
      final monthFirst = _isMonthFirst(ref.read(settingsProvider));
      final dates = _collectDates(
        text: text,
        raw: raw,
        weekStartDay: roster.weekStartDay,
        monthFirst: monthFirst,
      );
      final pendingStaff = _contextState.pendingStaff;
      if (dates.isNotEmpty && pendingStaff != null) {
        _handleShiftQuery(
          context,
          raw,
          fallbackStaff: pendingStaff,
          fallbackDate: dates.first,
        );
        _contextState.remember(action: '');
        return true;
      }
      _respondWithRC(context, 'Which date should I check?');
      return true;
    }
    if (_contextState.lastAction == 'await_date_for_swap') {
      final monthFirst = _isMonthFirst(ref.read(settingsProvider));
      final dates = _collectDates(
        text: text,
        raw: raw,
        weekStartDay: roster.weekStartDay,
        monthFirst: monthFirst,
      );
      if (dates.isNotEmpty) {
        final base = _contextState.lastPendingRaw ?? '';
        final merged = base.isEmpty ? raw : '$base $raw';
        _handleSwapCommand(context, merged);
        _contextState.remember(action: '');
        return true;
      }
      _respondWithRC(context, 'Which date should the swap happen?');
      return true;
    }
    if (_contextState.lastAction == 'await_staff_for_query') {
      final staff = _matchStaffName(text, roster);
      final pendingDates = _contextState.pendingDates;
      if (staff != null && pendingDates != null && pendingDates.isNotEmpty) {
        _handleShiftQuery(
          context,
          raw,
          fallbackStaff: staff,
          fallbackDate: pendingDates.first,
        );
        _contextState.remember(action: '');
        return true;
      }
      _respondWithRC(context, 'Which staff member should I check?');
      return true;
    }
    if (_contextState.lastAction == 'await_staff_for_change') {
      final staff = _matchStaffName(text, roster);
      final staffList = _matchAllStaffNames(text, roster);
      final pendingShift = _contextState.pendingShift;
      final pendingDates = _contextState.pendingDates;
      if (pendingShift != null && pendingDates != null) {
        if (staffList.isNotEmpty) {
          _confirmAndApplyBulkChange(
            context,
            staffList,
            pendingShift,
            pendingDates,
          );
          _contextState.remember(action: '');
          return true;
        }
        if (staff != null) {
          _confirmAndApplyChange(context, staff, pendingShift, pendingDates);
          _contextState.remember(action: '');
          return true;
        }
      }
    }
    if (_contextState.lastAction == 'await_shift_for_change') {
      final shift = _extractShiftCode(text);
      final staff = _contextState.pendingStaff ?? resolvedStaff;
      final staffList = _contextState.lastStaffList;
      final pendingDates = _contextState.pendingDates;
      if (shift != null && pendingDates != null) {
        if (staffList != null && staffList.isNotEmpty) {
          _confirmAndApplyBulkChange(
            context,
            staffList,
            shift,
            pendingDates,
          );
          _contextState.remember(action: '');
          return true;
        }
        if (staff != null) {
          _confirmAndApplyChange(context, staff, shift, pendingDates);
          _contextState.remember(action: '');
          return true;
        }
      }
    }
    if (_contextState.lastAction == 'clarify_leave_action') {
      if (_isCancelLeaveIntent(text, tokens)) {
        _contextState.remember(action: 'cancel_leave');
        _handleRemoveLeaveCommand(
          context,
          '${_contextState.lastPendingRaw ?? ''} $raw'.trim(),
          fallbackStaff: resolvedStaff ?? _contextState.lastStaff,
        );
        return true;
      }
      if (_isSetLeaveIntent(text, tokens)) {
        _contextState.remember(action: 'set_leave');
        _handleStaffLeaveCommand(
          context,
          '${_contextState.lastPendingRaw ?? ''} $raw'.trim(),
          _inferLeaveTypeForSet(
            '${_contextState.lastPendingRaw ?? ''} $raw'.trim(),
          ),
        );
        return true;
      }
    }
    if (_contextState.lastAction == 'clarify_change_remove') {
      if (_isCancelLeaveIntent(text, tokens)) {
        _handleRemoveLeaveCommand(
          context,
          raw,
          fallbackStaff: resolvedStaff ?? _contextState.lastStaff,
        );
        _contextState.remember(action: '');
        return true;
      }
      if (text.contains('change') ||
          text.contains('amend') ||
          text.contains('update') ||
          text.contains('remove')) {
        _handleRemoveOverrideCommand(
          context,
          raw,
          fallbackStaff: resolvedStaff ?? _contextState.lastStaff,
        );
        _contextState.remember(action: '');
        return true;
      }
    }
    if (_contextState.lastAction == 'cancel_leave') {
      final followupDates = _extractDatesForOverride(raw, roster.weekStartDay);
      final followupRange =
          _extractDateRangeFromText(text, roster.weekStartDay);
      if (followupDates.isNotEmpty || followupRange != null) {
        _handleRemoveLeaveCommand(
          context,
          raw,
          fallbackStaff: resolvedStaff ?? _contextState.lastStaff,
        );
        return true;
      }
      if (resolvedStaff != null) {
        _handleRemoveLeaveCommand(
          context,
          raw,
          fallbackStaff: resolvedStaff,
        );
        return true;
      }
    }

    if (_containsAny(tokens, ['hello', 'hi', 'hey']) ||
        text.contains('how are you')) {
      _respondWithRC(
        context,
        'Hello! I can help with rosters, events, time, and weather. '
            'Ask me anything and I will tie it back to your schedule.',
      );
      return true;
    }

    if (text.contains('how do i') ||
        text.contains('how to') ||
        _containsAny(tokens, ['help'])) {
      _showAiHelp(context);
      return true;
    }

    if (_handleShiftMeaningQuery(context, text)) {
      return true;
    }

    if (cancelLeaveIntent && setLeaveIntent) {
      _respondWithRC(
        context,
        'Do you want to cancel existing leave or set new leave?',
      );
      _contextState.remember(
        action: 'clarify_leave_action',
        pendingRaw: raw,
      );
      return true;
    }

    if (_isRosterStatsIntent(text, tokens)) {
      _handleRosterStatsQuery(
        context,
        raw,
        fallbackStaff: resolvedStaff,
      );
      return true;
    }

    if (_isLeaveBalanceQuery(text, tokens)) {
      _handleLeaveBalanceQuery(
        context,
        raw,
        fallbackStaff: resolvedStaff,
      );
      return true;
    }

    if (_isSickStatsQuery(text, tokens)) {
      _handleSickStatsQuery(
        context,
        raw,
        fallbackStaff: resolvedStaff,
      );
      return true;
    }

    if (_isSecondmentQuery(text, tokens)) {
      _handleSecondmentQuery(
        context,
        raw,
        fallbackStaff: resolvedStaff,
      );
      return true;
    }

    if (_isRosterCreateIntent(text, tokens)) {
      _handleRosterCommand(context, raw);
      return true;
    }

    if (_isDuplicatePatternIntent(text, tokens)) {
      _handleDuplicatePatternCommand(context, raw);
      return true;
    }

    if (_isAccessCodeIntent(text, tokens)) {
      _handleCreateAccessCodeCommand(context, raw);
      return true;
    }

    if (_isPanToDateIntent(text, tokens)) {
      _handlePanToDateCommand(context, raw);
      return true;
    }

    if (text.startsWith('when is') ||
        text.contains('when is ') ||
        (text.contains('when') && text.contains('payday')) ||
        (text.contains('next') && text.contains('payday')) ||
        (text.contains('when') &&
            _containsAny(tokens, ['event', 'holiday', 'festival', 'payday']))) {
      _handleWhenIsCommand(context, raw);
      return true;
    }

    if (text.contains('cancel swap') ||
        text.contains('remove swap') ||
        text.contains('cancel shiftswap')) {
      _handleCancelSwapCommand(context, raw);
      return true;
    }

    if (_isSwapIntent(text, tokens, roster)) {
      _handleSwapCommand(context, raw);
      return true;
    }

    if (text.contains('owed') ||
        text.contains('owe') ||
        text.contains('debt') ||
        text.contains('swap debt')) {
      _handleSwapDebtQuery(context, raw);
      return true;
    }

    if (!cancelLeaveIntent &&
        (text.contains('compassionate') ||
            text.contains('bereavement') ||
            text.contains('study') ||
            text.contains('parental') ||
            text.contains('maternity') ||
            text.contains('paternity') ||
            text.contains('jury') ||
            text.contains('unpaid') ||
            text.contains('special leave') ||
            text.contains('custom leave'))) {
      _handleStaffLeaveCommand(context, raw, 'custom');
      return true;
    }

    if (!cancelLeaveIntent && setLeaveIntent) {
      _handleStaffLeaveCommand(context, raw, _inferLeaveTypeForSet(raw));
      return true;
    }

    if (!cancelLeaveIntent && text.contains('secondment')) {
      _handleStaffLeaveCommand(context, raw, 'secondment');
      return true;
    }

    if (!cancelLeaveIntent &&
        (text.contains('sick') ||
            text.contains('illness') ||
            text.contains(' ill '))) {
      _handleStaffLeaveCommand(context, raw, 'sick');
      return true;
    }

    if (_containsAny(tokens, ['event', 'events', 'holiday', 'festival', 'payday']) &&
        !_containsAny(tokens, ['set', 'create', 'add', 'delete', 'remove'])) {
      _handleWhenIsCommand(context, raw);
      return true;
    }

    if (shiftQueryIntent) {
      _handleShiftQuery(
        context,
        raw,
        fallbackStaff: resolvedStaff,
        fallbackDate: resolvedDate,
      );
      _contextState.remember(staff: resolvedStaff, date: resolvedDate);
      return true;
    }

    if (isQuestion && resolvedStaff != null && !actionIntent) {
      _handleShiftQuery(
        context,
        raw,
        fallbackStaff: resolvedStaff,
        fallbackDate: resolvedDate,
      );
      _contextState.remember(staff: resolvedStaff, date: resolvedDate);
      return true;
    }

    if (cancelLeaveIntent) {
      _contextState.remember(action: 'cancel_leave');
      _handleRemoveLeaveCommand(
        context,
        raw,
        fallbackStaff: resolvedStaff,
      );
      return true;
    }

    if (resolvedStaff != null && resolvedShift == null && actionIntent) {
      _respondWithRC(context, 'Which shift should I set for $resolvedStaff?');
      _showSetShiftWizard(context, initialStaff: resolvedStaff);
      final pendingDates = <DateTime>[];
      if (dateRange != null) {
        pendingDates.add(DateTime(
          dateRange.start.year,
          dateRange.start.month,
          dateRange.start.day,
        ));
      } else if (resolvedDate != null) {
        pendingDates.add(DateTime(
          resolvedDate.year,
          resolvedDate.month,
          resolvedDate.day,
        ));
      }
      _contextState.remember(
        action: 'await_shift_for_change',
        pendingStaff: resolvedStaff,
        pendingDates: pendingDates.isEmpty ? null : pendingDates,
        pendingCreatedAt: DateTime.now(),
      );
      _contextState.remember(staff: resolvedStaff, date: resolvedDate);
      return true;
    }

    if (resolvedStaff == null && resolvedShift != null && actionIntent) {
      _respondWithRC(context, 'Which staff member should I update?');
      _showSetShiftWizard(context, initialShift: resolvedShift);
      final pendingDates = <DateTime>[];
      if (dateRange != null) {
        pendingDates.add(DateTime(
          dateRange.start.year,
          dateRange.start.month,
          dateRange.start.day,
        ));
      } else if (resolvedDate != null) {
        pendingDates.add(DateTime(
          resolvedDate.year,
          resolvedDate.month,
          resolvedDate.day,
        ));
      }
      _contextState.remember(
        action: 'await_staff_for_change',
        pendingShift: resolvedShift,
        pendingDates: pendingDates.isEmpty ? null : pendingDates,
        pendingCreatedAt: DateTime.now(),
      );
      return true;
    }

    if (actionIntent &&
        resolvedShift != null &&
        staffMatches.length >= 2) {
      _handleBulkOverrideCommand(
        context,
        raw,
        staffMatches,
        resolvedShift,
      );
      _contextState.remember(
        staff: staffMatches.first,
        date: resolvedDate,
        shift: resolvedShift,
      );
      return true;
    }

    if (resolvedStaff != null && resolvedShift != null && actionIntent) {
      _handleNaturalLanguageOverride(
        context,
        raw,
        resolvedStaff,
        resolvedShift,
      );
      _contextState.remember(
        staff: resolvedStaff,
        date: resolvedDate,
        shift: resolvedShift,
      );
      return true;
    }

    if (_containsAny(tokens, ['time', 'date', 'today'])) {
      _handleTimeCommand(context);
      return true;
    }

    if (_containsAny(tokens, ['weather', 'forecast', 'temperature'])) {
      _handleWeatherCommand(context);
      return true;
    }

    if (text.contains('delete event') || text.contains('remove event')) {
      _handleDeleteEventCommand(context, raw);
      return true;
    }

    if (text.contains('remove override') ||
        text.contains('remove overrides') ||
        text.contains('remove change') ||
        text.contains('remove changes') ||
        text.contains('clear override') ||
        text.contains('clear overrides') ||
        text.contains('clear change') ||
        text.contains('clear changes') ||
        text.contains('cancel override') ||
        text.contains('cancel change') ||
        text.contains('undo override') ||
        text.contains('undo change') ||
        text.contains('reset override') ||
        text.contains('reset change') ||
        text.contains('amendment') ||
        text.contains('amended')) {
      _handleRemoveOverrideCommand(
        context,
        raw,
        fallbackStaff: resolvedStaff,
      );
      return true;
    }

    if (text.contains('event') || text.contains('payday') || text.contains('holiday')) {
      _handleEventCommand(context, raw);
      return true;
    }

    if (text.contains('set ') ||
        text.contains('override') ||
        text.contains('change ') ||
        text.contains('amend') ||
        text.contains('update ')) {
      _handleSetShiftCommand(context, raw);
      return true;
    }

    if (_handleClarification(context, raw, text, tokens, roster)) {
      return true;
    }

    if (_tryBuildClarifyingQuestion(context, raw, roster)) {
      return true;
    }
    return false;
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
    if (_containsAnyFuzzy(tokens, ['who', 'what', 'when', 'which']) &&
        _containsAnyFuzzy(tokens, ['shift', 'work', 'working', 'on'])) {
      return true;
    }
    return false;
  }

  bool _hasDateHint(String text) {
    if (RegExp(r'\\b\\d{1,2}(st|nd|rd|th)?\\b').hasMatch(text)) return true;
    if (RegExp(r'\\b\\d{4}-\\d{2}-\\d{2}\\b').hasMatch(text)) return true;
    if (RegExp(r'\\b\\d{1,2}[/-]\\d{1,2}[/-]\\d{4}\\b').hasMatch(text)) {
      return true;
    }
    const monthHints = [
      'jan',
      'january',
      'feb',
      'february',
      'mar',
      'march',
      'apr',
      'april',
      'may',
      'jun',
      'june',
      'jul',
      'july',
      'aug',
      'august',
      'sep',
      'sept',
      'september',
      'oct',
      'october',
      'nov',
      'november',
      'dec',
      'december',
    ];
    for (final month in monthHints) {
      if (text.contains(month)) return true;
    }
    if (text.contains('today') ||
        text.contains('tomorrow') ||
        text.contains('yesterday')) {
      return true;
    }
    if (text.contains('next week') ||
        text.contains('this week') ||
        text.contains('last week') ||
        text.contains('previous week')) {
      return true;
    }
    return false;
  }

  _ResolvedDates? _resolveDatesForQuery(
    String normalized,
    String raw,
    int weekStartDay,
    DateTime? fallbackDate,
    RosterNotifier roster,
  ) {
    final dateSet = <DateTime>{};
    double confidence = 1.0;
    final range = _extractDateRangeFromText(normalized, weekStartDay);
    if (range != null) {
      var cursor = DateTime(range.start.year, range.start.month, range.start.day);
      final end = DateTime(range.end.year, range.end.month, range.end.day);
      while (!cursor.isAfter(end)) {
        dateSet.add(cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    final monthFirst = _isMonthFirst(ref.read(settingsProvider));
    final explicit = _parseDateFromText(normalized, monthFirst: monthFirst);
    if (explicit != null) {
      dateSet.add(DateTime(
        explicit.date.year,
        explicit.date.month,
        explicit.date.day,
      ));
      confidence = explicit.confidence;
    }
    if (dateSet.isEmpty) {
      dateSet.addAll(
        _extractDatesForOverride(raw, weekStartDay),
      );
    }
    if (dateSet.isEmpty) {
      dateSet.addAll(_extractAllDatesFromText(
        normalized,
        monthFirst: monthFirst,
      ));
    }
    if (dateSet.isEmpty) {
      final loose = _parseDateLoose(raw, monthFirst: monthFirst);
      if (loose != null) {
        dateSet.add(loose.date);
        confidence = loose.confidence;
      }
    }
    if (dateSet.isEmpty && fallbackDate != null) {
      dateSet.add(DateTime(
        fallbackDate.year,
        fallbackDate.month,
        fallbackDate.day,
      ));
      confidence = 0.4;
    }
    if (dateSet.isEmpty) {
      final relative = _resolveRelativeDate(normalized, fallbackDate, roster);
      if (relative != null) {
        dateSet.add(relative);
        confidence = 0.5;
      }
    }
    return dateSet.isEmpty
        ? null
        : _ResolvedDates(dateSet.toList()..sort(), confidence);
  }

  List<DateTime> _collectDates({
    required String text,
    required String raw,
    required int weekStartDay,
    required bool monthFirst,
  }) {
    final dates = <DateTime>{};
    final range = _extractDateRangeFromText(text, weekStartDay);
    if (range != null) {
      var cursor = DateTime(range.start.year, range.start.month, range.start.day);
      final end = DateTime(range.end.year, range.end.month, range.end.day);
      while (!cursor.isAfter(end)) {
        dates.add(cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    final parsed = _parseDateFromText(text, monthFirst: monthFirst);
    if (parsed != null) {
      dates.add(parsed.date);
    }
    dates.addAll(_extractAllDatesFromText(text, monthFirst: monthFirst));
    dates.addAll(_extractDatesForOverride(raw, weekStartDay));
    final simple = _simpleDateFromText(raw) ??
        _simpleDateFromText(text) ??
        _parseDateLoose(raw, monthFirst: monthFirst)?.date;
    if (simple != null) {
      dates.add(simple);
    }
    return dates.toList();
  }

  DateTime? _resolveRelativeDate(
    String normalized,
    DateTime? baseDate,
    RosterNotifier roster,
  ) {
    if (normalized.contains('same day next month') ||
        normalized.contains('next month same day')) {
      final base = baseDate ?? DateTime.now();
      final next = DateTime(base.year, base.month + 1, base.day);
      return DateTime(next.year, next.month, next.day);
    }
    if (normalized.contains('same day last month') ||
        normalized.contains('last month same day') ||
        normalized.contains('previous month same day')) {
      final base = baseDate ?? DateTime.now();
      final prev = DateTime(base.year, base.month - 1, base.day);
      return DateTime(prev.year, prev.month, prev.day);
    }
    if (normalized.contains('end of month') ||
        normalized.contains('last day of month')) {
      final base = baseDate ?? DateTime.now();
      final end = DateTime(base.year, base.month + 1, 0);
      return DateTime(end.year, end.month, end.day);
    }
    if (normalized.contains('start of month') ||
        normalized.contains('first day of month')) {
      final base = baseDate ?? DateTime.now();
      final start = DateTime(base.year, base.month, 1);
      return DateTime(start.year, start.month, start.day);
    }
    final businessMatch =
        RegExp(r'in\\s+(\\d+)\\s+business\\s+days').firstMatch(normalized);
    if (businessMatch != null) {
      final count = int.tryParse(businessMatch.group(1)!) ?? 0;
      var date = DateTime.now();
      var added = 0;
      while (added < count) {
        date = date.add(const Duration(days: 1));
        if (date.weekday >= DateTime.monday &&
            date.weekday <= DateTime.friday) {
          added++;
        }
      }
      return DateTime(date.year, date.month, date.day);
    }
    final weekOfMatch =
        RegExp(r'(first|second|third|fourth|last)\\s+week\\s+of\\s+(\\w+)')
            .firstMatch(normalized);
    if (weekOfMatch != null) {
      final monthToken = weekOfMatch.group(2) ?? '';
      final month = _simpleDateFromText('1 $monthToken')?.month;
      if (month != null) {
        final year = DateTime.now().year;
        final weekIndex = {
          'first': 0,
          'second': 1,
          'third': 2,
          'fourth': 3,
        }[weekOfMatch.group(1)];
        if (weekIndex != null) {
          final start = DateTime(year, month, 1).add(Duration(days: weekIndex * 7));
          return DateTime(start.year, start.month, start.day);
        }
        if (weekOfMatch.group(1) == 'last') {
          final lastDay = DateTime(year, month + 1, 0);
          final start = lastDay.subtract(const Duration(days: 6));
          return DateTime(start.year, start.month, start.day);
        }
      }
    }
    final lastWeekdayMatch = RegExp(
      r'last\\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\s+of\\s+(\\w+)',
    ).firstMatch(normalized);
    if (lastWeekdayMatch != null) {
      final month = _simpleDateFromText('1 ${lastWeekdayMatch.group(2)}')?.month;
      if (month != null) {
        final year = DateTime.now().year;
        final lastDay = DateTime(year, month + 1, 0);
        final target = _weekdayFromName(lastWeekdayMatch.group(1)!);
        var date = lastDay;
        while (date.weekday != target) {
          date = date.subtract(const Duration(days: 1));
        }
        return DateTime(date.year, date.month, date.day);
      }
    }
    final weekDayPattern = RegExp(r'week\\s*(\\d+)\\s*day\\s*(\\d+)');
    final match = weekDayPattern.firstMatch(normalized);
    if (match != null) {
      final weekIndex = int.tryParse(match.group(1) ?? '') ?? 0;
      final dayIndex = int.tryParse(match.group(2) ?? '') ?? 0;
      if (weekIndex > 0 && dayIndex > 0) {
        final reference = DateTime(2024, 1, 1);
        final cycleDays = roster.cycleLength * 7;
        final daysSince = DateTime.now().difference(reference).inDays;
        final cycleStart =
            reference.add(Duration(days: (daysSince ~/ cycleDays) * cycleDays));
        final offset = (weekIndex - 1) * 7 + (dayIndex - 1);
        final date = cycleStart.add(Duration(days: offset));
        return DateTime(date.year, date.month, date.day);
      }
    }
    return null;
  }

  int _weekdayFromName(String name) {
    switch (name) {
      case 'monday':
        return DateTime.monday;
      case 'tuesday':
        return DateTime.tuesday;
      case 'wednesday':
        return DateTime.wednesday;
      case 'thursday':
        return DateTime.thursday;
      case 'friday':
        return DateTime.friday;
      case 'saturday':
        return DateTime.saturday;
      case 'sunday':
        return DateTime.sunday;
      default:
        return DateTime.monday;
    }
  }

  DateTime? _simpleDateFromText(String text) {
    final cleaned = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ')
        .replaceAll(RegExp(r'\\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return null;
    final monthNames = {
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    final dayMonth = RegExp(
      r'(\\d{1,2})(?:st|nd|rd|th)?\\s*(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)',
    ).firstMatch(cleaned);
    if (dayMonth != null) {
      final day = int.parse(dayMonth.group(1)!);
      final monthKey = dayMonth.group(2)!;
      final month = monthNames[monthKey]!;
      final now = DateTime.now();
      return DateTime(now.year, month, day);
    }
    final monthDay = RegExp(
      r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\\s*(\\d{1,2})(?:st|nd|rd|th)?',
    ).firstMatch(cleaned);
    if (monthDay != null) {
      final day = int.parse(monthDay.group(2)!);
      final monthKey = monthDay.group(1)!;
      final month = monthNames[monthKey]!;
      final now = DateTime.now();
      return DateTime(now.year, month, day);
    }
    // Fallback: scan tokens for a month word + a day number.
    final tokens = cleaned.split(' ');
    String? monthToken;
    int? dayValue;
    for (final token in tokens) {
      final normalizedToken = token.replaceAll(
        RegExp(r'(st|nd|rd|th)$'),
        '',
      );
      final monthMatch = _matchMonthToken(normalizedToken, monthNames.keys);
      if (monthMatch != null) {
        monthToken ??= monthMatch;
      } else {
        final number = int.tryParse(normalizedToken);
        if (number != null && number >= 1 && number <= 31) {
          dayValue ??= number;
        }
      }
    }
    if (monthToken != null && dayValue != null) {
      final now = DateTime.now();
      return DateTime(now.year, monthNames[monthToken]!, dayValue);
    }
    return null;
  }

  String? _matchMonthToken(String token, Iterable<String> months) {
    if (months.contains(token)) return token;
    String? best;
    int bestDist = 2;
    for (final month in months) {
      final dist = _editDistance(token, month);
      if (dist < bestDist) {
        bestDist = dist;
        best = month;
        if (bestDist == 1) break;
      }
    }
    return best;
  }

  int _editDistance(String a, String b) {
    if (a == b) return 0;
    final dp = List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((v, e) => v < e ? v : e);
      }
    }
    return dp[a.length][b.length];
  }

  bool _isMonthFirst(models.AppSettings settings) {
    final format = settings.dateFormat.toLowerCase();
    return format.startsWith('mm');
  }


  List<String>? _resolveStaffForQuery(
    BuildContext context,
    RosterNotifier roster,
    String normalized,
    String? fallbackStaff,
    List<DateTime> dates,
  ) {
    final matches = _matchAllStaffNames(normalized, roster);
    if (matches.isEmpty && fallbackStaff != null) {
      matches.add(fallbackStaff);
    }
    if (matches.isEmpty) {
      _contextState.remember(
        action: 'await_staff_for_query',
        pendingDates: dates,
        pendingCreatedAt: DateTime.now(),
      );
      _respondWithRC(context, 'Which staff member should I check?');
      return null;
    }
    return matches;
  }

  bool _isRosterStatsIntent(String text, List<String> tokens) {
    if (_containsAnyFuzzy(tokens, [
      'stats',
      'statistics',
      'analytics',
      'summary',
      'overview',
      'health',
      'kpi',
    ])) {
      return true;
    }
    if (_containsAnyFuzzy(tokens, [
      'utilization',
      'overtime',
      'compliance',
      'coverage',
      'burndown',
      'risk',
    ])) {
      return true;
    }
    return false;
  }

  bool _isLeaveBalanceQuery(String text, List<String> tokens) {
    if (text.contains('leave balance') || text.contains('al balance')) {
      return true;
    }
    if (_containsAnyFuzzy(tokens, ['leave', 'annual', 'al']) &&
        _containsAnyFuzzy(tokens, ['remaining', 'left', 'balance'])) {
      return true;
    }
    if (text.contains('annual leave left') || text.contains('al remaining')) {
      return true;
    }
    return false;
  }

  bool _isSickStatsQuery(String text, List<String> tokens) {
    if (!_containsAnyFuzzy(tokens, ['sick', 'illness', 'ill'])) return false;
    if (_containsAnyFuzzy(tokens, ['days', 'count', 'taken', 'how', 'many'])) {
      return true;
    }
    if (text.contains('sick leave')) return true;
    return false;
  }

  bool _isSecondmentQuery(String text, List<String> tokens) {
    if (text.contains('secondment')) return true;
    if (text.contains('return') && _containsAnyFuzzy(tokens, ['back', 'work'])) {
      return true;
    }
    if (_containsAnyFuzzy(tokens, ['back', 'return']) &&
        _containsAnyFuzzy(tokens, ['date', 'day'])) {
      return true;
    }
    return false;
  }

  bool _isRosterCreateIntent(String text, List<String> tokens) {
    if (!text.contains('roster') &&
        !_containsAnyFuzzy(tokens, ['roster', 'rosters', 'schedule'])) {
      return false;
    }
    if (_containsAnyFuzzy(tokens, [
      'create',
      'generate',
      'build',
      'make',
      'start',
      'new',
      'initialize',
      'need',
    ])) {
      return true;
    }
    if (text.contains('new roster') ||
        text.contains('need a roster') ||
        text.contains('need roster')) {
      return true;
    }
    return false;
  }

  bool _isTemplateGenerateIntent(String text) {
    if (text.contains('template code') &&
        (text.contains('generate') ||
            text.contains('create') ||
            text.contains('share') ||
            text.contains('export'))) {
      return true;
    }
    return text.contains('export template');
  }

  bool _isTemplateApplyIntent(String text) {
    if (text.contains('use template') ||
        text.contains('apply template') ||
        text.contains('import template') ||
        text.contains('template code')) {
      return true;
    }
    return false;
  }

  String? _extractRosterName(String raw) {
    final quoted = RegExp("[\"']([^\"']{3,})[\"']").firstMatch(raw);
    if (quoted != null) {
      return quoted.group(1);
    }
    final match = RegExp(r'(?:for|of|named|called)\s+(.+)$',
            caseSensitive: false)
        .firstMatch(raw);
    if (match != null) {
      return match.group(1)?.trim();
    }
    return null;
  }

  void _handleTemplateGenerateCommand(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    final rosterName = _extractRosterName(raw);
    if (rosterName == null || rosterName.trim().isEmpty) {
      final code = roster.generateTemplateCode(
        includeStaffNames: true,
        includeOverrides: false,
        compress: true,
      );
      Clipboard.setData(ClipboardData(text: code));
      _respondWithRC(
        context,
        'Template code generated for the current roster and copied:\\n$code',
      );
      return;
    }

    Future(() async {
      try {
        final list = await AwsService.instance.getUserRosters();
        final matches = <Map<String, dynamic>>[];
        for (final entry in list) {
          final rosterMap = entry['rosters'] as Map<String, dynamic>;
          final name = (rosterMap['name'] as String?) ?? '';
          if (name.toLowerCase().contains(rosterName.toLowerCase())) {
            matches.add(rosterMap);
          }
        }

        if (matches.isEmpty) {
          _respondWithRC(
            context,
            'I could not find a roster named "$rosterName". Open it first or check the name.',
          );
          return;
        }
        if (matches.length > 1) {
          final names = matches.take(5).map((r) => r['name']).join(', ');
          _respondWithRC(
            context,
            'I found multiple rosters: $names. Tell me the exact roster name.',
          );
          return;
        }

        final rosterId = matches.first['id'] as String?;
        if (rosterId == null) {
          _respondWithRC(context, 'Roster ID missing for "$rosterName".');
          return;
        }
        final remote = await AwsService.instance.loadRosterData(rosterId);
        final data = remote?['data'] as Map<String, dynamic>?;
        if (data == null) {
          _respondWithRC(context, 'Unable to load roster "$rosterName".');
          return;
        }
        final code = roster.generateTemplateCodeFromData(
          data,
          includeStaffNames: true,
          includeOverrides: false,
          compress: true,
        );
        Clipboard.setData(ClipboardData(text: code));
        _respondWithRC(
          context,
          'Template code generated for "$rosterName" and copied:\\n$code',
        );
      } catch (e) {
        _respondWithRC(
          context,
          'I could not fetch that roster. Please open it first and try again.',
        );
      }
    });
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

  void _handleShiftQuery(
    BuildContext context,
    String raw, {
    String? fallbackStaff,
    DateTime? fallbackDate,
  }) {
    final roster = ref.read(rosterProvider);
    final normalized = _normalizeCommand(raw);
    final text = normalized;
    final hadExplicitDateHint =
        _hasDateHint(normalized) ||
        _extractDateRangeFromText(normalized, roster.weekStartDay) != null;
    final hadStaffHint = _matchAllStaffNames(normalized, roster).isNotEmpty;
    final resolvedDates = _resolveDatesForQuery(
      normalized,
      raw,
      roster.weekStartDay,
      fallbackDate,
      roster,
    );
    if (resolvedDates == null || resolvedDates.dates.isEmpty) {
      final fallbackParsed =
          _simpleDateFromText(raw) ?? _simpleDateFromText(normalized);
      if (fallbackParsed != null) {
        final dates = [fallbackParsed];
        final staffList = _resolveStaffForQuery(
          context,
          roster,
          normalized,
          fallbackStaff,
          dates,
        );
        if (staffList == null) return;
        _respondWithRC(
          context,
          '${staffList.first} is on ${_shiftLabel(roster.getShiftForDate(staffList.first, fallbackParsed))} '
          'for ${DateFormat('MMM d, yyyy').format(fallbackParsed)}.',
        );
        return;
      }
      if (_hasDateHint(normalized)) {
        final pending = fallbackStaff ?? _contextState.lastStaff;
        if (pending != null) {
          _contextState.remember(
            action: 'await_date_for_query',
            pendingStaff: pending,
            pendingCreatedAt: DateTime.now(),
          );
        }
        _respondWithRC(context, 'Which date should I check?');
      } else {
      _respondWithRC(context, 'Which date should I check?');
      }
      return;
    }
    final dates = resolvedDates.dates;
    final confidence = resolvedDates.confidence;
    final usedFallbackDate = !hadExplicitDateHint && fallbackDate != null;
    final staffList = _resolveStaffForQuery(
      context,
      roster,
      normalized,
      fallbackStaff,
      dates,
    );
    if (staffList == null) {
      return;
    }
    final usedFallbackStaff = !hadStaffHint && fallbackStaff != null;
    final staff = staffList;

    final shiftHint = _extractShiftCode(text);
    final wantsLeave = text.contains('leave') ||
        text.contains('sick') ||
        text.contains('secondment');
    final wantsCoverage =
        text.contains('coverage') || text.contains('gap') || text.contains('missing');
    final wantsCount = text.contains('how many') ||
        text.contains('count') ||
        text.contains('number of');
    final isWhoQuery = text.contains('who') || text.startsWith('who');
    if ((wantsCount || wantsCoverage) && !isWhoQuery) {
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
        int missing = 0;
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
          final normalizedShift = _normalizeShiftForCoverage(shift);
          final normalizedHint = _normalizeShiftForCoverage(shiftHint);
          if (shiftHint != null) {
            if (normalizedShift == normalizedHint) count++;
          } else {
            if (shift != 'OFF' && shift != 'AL') count++;
          }
        }
        if (wantsCoverage) {
          final required = _estimateCoverageNeed(roster, date, shiftHint);
          missing = (required - count).clamp(0, required);
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
        if (wantsCoverage) {
          responses.add(
            missing == 0
                ? 'Coverage looks ok for $label on ${DateFormat('MMM d').format(date)}.'
                : 'Coverage gap: $missing for $label on ${DateFormat('MMM d').format(date)}.',
          );
        } else {
          responses.add(
            '$count staff are $label on ${DateFormat('MMM d').format(date)}.',
          );
        }
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
          final normalizedShift = _normalizeShiftForCoverage(shift);
          final normalizedHint = _normalizeShiftForCoverage(shiftHint);
          if (shiftHint != null) {
            if (normalizedShift == normalizedHint) {
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

    final matchedNames = _matchAllStaffNames(text, roster);
    if (matchedNames.isEmpty) {
      return;
    }
    final matched = matchedNames.first;
    _contextState.remember(staff: matched);
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
      final base = roster.getBaseShiftForDate(matched, date);
      final overrideApplied =
          shift.isNotEmpty && base.isNotEmpty && shift != base;
      final overrideLabel = overrideApplied ? ' (override)' : '';
      final contextNote = usedFallbackDate || usedFallbackStaff
          ? ' (from previous context)'
          : confidence < 0.6
              ? ' (date inferred)'
              : '';
      responses.add(
        '$matched is on ${_shiftLabel(shift)}$overrideLabel for ${DateFormat('MMM d, yyyy').format(date)}$contextNote.',
      );
    }
    _respondWithRC(context, responses.join(' '));
  }

  void _handleRosterStatsQuery(
    BuildContext context,
    String raw, {
    String? fallbackStaff,
  }) {
    final roster = ref.read(rosterProvider);
    final text = raw.toLowerCase();
    final staffMatch = _matchStaffName(text, roster) ?? fallbackStaff;
    if (staffMatch != null) {
      final response = _buildStaffStatsResponse(staffMatch, roster);
      _respondWithRC(context, response);
      return;
    }

    final stats = roster.getStatistics();
    final health = stats['healthScore'] as Map<String, dynamic>? ?? {};
    final utilization = (stats['utilizationRate'] as num?)?.toDouble() ?? 0;
    final avgShifts = (stats['avgShiftsPerStaff'] as num?)?.toDouble() ?? 0;
    final overtime = roster.buildOvertimeRisk();
    final compliance = roster.buildComplianceSummary();

    final highRisk = (overtime['highRiskStaff'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final coverageViolations = compliance['coverageViolations'] ?? 0;
    final shiftCoverageViolations = compliance['shiftCoverageViolations'] ?? 0;

    final response =
        'Roster summary: ${stats['activeStaff']} active staff, '
        '${stats['totalOverrides']} changes, ${stats['totalEvents']} events. '
        'Health score ${(health['overall'] ?? 0).toStringAsFixed(2)} '
        '(coverage ${(health['coverage'] ?? 0).toStringAsFixed(2)}, '
        'workload ${(health['workload'] ?? 0).toStringAsFixed(2)}). '
        'Utilization ${(utilization * 100).toStringAsFixed(0)}%, '
        'avg shifts ${(avgShifts).toStringAsFixed(1)} per staff. '
        'Coverage violations $coverageViolations, '
        'shift coverage violations $shiftCoverageViolations. '
        '${highRisk.isEmpty ? 'No high overtime risk.' : 'Overtime risk: ${highRisk.join(', ')}.'}';

    _respondWithRC(context, response);
  }

  void _handleLeaveBalanceQuery(
    BuildContext context,
    String raw, {
    String? fallbackStaff,
  }) {
    final roster = ref.read(rosterProvider);
    final text = raw.toLowerCase();
    final staffName = _matchStaffName(text, roster) ?? fallbackStaff;
    if (staffName == null) {
      _respondWithRC(context, 'Which staff member should I check leave for?');
      return;
    }
    final staff =
        roster.staffMembers.where((s) => s.name == staffName).firstOrNull;
    if (staff == null) {
      _respondWithRC(context, 'Staff member not found.');
      return;
    }
    final now = DateTime.now();
    final alOverrides = roster.overrides
        .where((o) => o.personName == staffName)
        .where((o) => o.shift.toUpperCase() == 'AL')
        .toList();
    final past = alOverrides.where((o) => o.date.isBefore(now)).length;
    final future = alOverrides.where((o) => !o.date.isBefore(now)).length;
    _respondWithRC(
      context,
      '$staffName has ${staff.leaveBalance.toStringAsFixed(1)} days remaining. '
          'AL used: $past, upcoming AL: $future.',
    );
  }

  void _handleSickStatsQuery(
    BuildContext context,
    String raw, {
    String? fallbackStaff,
  }) {
    final roster = ref.read(rosterProvider);
    final text = raw.toLowerCase();
    final staffName = _matchStaffName(text, roster) ?? fallbackStaff;
    if (staffName == null) {
      _respondWithRC(context, 'Which staff member should I check sick days for?');
      return;
    }
    final now = DateTime.now();
    final sickOverrides = roster.overrides
        .where((o) => o.personName == staffName)
        .where((o) {
          final shift = o.shift.toUpperCase();
          return shift == 'SICK' || shift == 'ILL';
        })
        .toList();
    final past = sickOverrides.where((o) => o.date.isBefore(now)).length;
    final upcoming = sickOverrides.where((o) => !o.date.isBefore(now)).length;
    _respondWithRC(
      context,
      '$staffName has $past sick day(s) recorded and $upcoming scheduled.',
    );
  }

  void _handleSecondmentQuery(
    BuildContext context,
    String raw, {
    String? fallbackStaff,
  }) {
    final roster = ref.read(rosterProvider);
    final text = raw.toLowerCase();
    final staffName = _matchStaffName(text, roster) ?? fallbackStaff;
    if (staffName == null) {
      _respondWithRC(context, 'Which staff member is on secondment?');
      return;
    }
    final staff =
        roster.staffMembers.where((s) => s.name == staffName).firstOrNull;
    if (staff == null) {
      _respondWithRC(context, 'Staff member not found.');
      return;
    }
    if (staff.leaveType == null) {
      _respondWithRC(
        context,
        '$staffName is not marked as on leave or secondment.',
      );
      return;
    }
    final start = staff.leaveStart;
    final end = staff.leaveEnd;
    final startLabel =
        start == null ? 'unknown' : DateFormat('MMM d, yyyy').format(start);
    final endLabel =
        end == null ? 'unknown' : DateFormat('MMM d, yyyy').format(end);
    _respondWithRC(
      context,
      '$staffName is on ${_formatLeaveLabel(staff.leaveType)} '
          'from $startLabel to $endLabel.',
    );
  }

  String _buildStaffStatsResponse(String staffName, RosterNotifier roster) {
    final staff =
        roster.staffMembers.where((s) => s.name == staffName).firstOrNull;
    if (staff == null) {
      return 'Staff member not found.';
    }
    final now = DateTime.now();
    int next7 = 0;
    int next30 = 0;
    for (int i = 0; i < 30; i++) {
      final date = now.add(Duration(days: i));
      final shift = roster.getShiftForDate(staffName, date);
      if (shift != 'OFF' && shift != 'AL') {
        next30++;
        if (i < 7) next7++;
      }
    }
    final alOverrides = roster.overrides
        .where((o) => o.personName == staffName)
        .where((o) => o.shift.toUpperCase() == 'AL')
        .toList();
    final alPast = alOverrides.where((o) => o.date.isBefore(now)).length;
    final alFuture = alOverrides.where((o) => !o.date.isBefore(now)).length;
    final sickOverrides = roster.overrides
        .where((o) => o.personName == staffName)
        .where((o) {
          final shift = o.shift.toUpperCase();
          return shift == 'SICK' || shift == 'ILL';
        })
        .toList();
    final sickPast = sickOverrides.where((o) => o.date.isBefore(now)).length;
    final status = staff.leaveType == null
        ? 'active'
        : staff.leaveType == 'secondment'
            ? 'on secondment'
            : staff.leaveType == 'sick'
                ? 'sick'
                : staff.leaveType!;
    final leaveStartLabel = staff.leaveStart == null
        ? ''
        : ' from ${DateFormat('MMM d, yyyy').format(staff.leaveStart!)}';
    final leaveEndLabel = staff.leaveEnd == null
        ? ''
        : ' until ${DateFormat('MMM d, yyyy').format(staff.leaveEnd!)}';

    return '$staffName summary: '
        'status $status$leaveStartLabel$leaveEndLabel. '
        'Leave remaining ${staff.leaveBalance.toStringAsFixed(1)} days '
        '(AL used $alPast, upcoming $alFuture). '
        'Sick days recorded $sickPast. '
        'Shifts scheduled: $next7 in next 7 days, $next30 in next 30 days.';
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

    if (effectiveLeaveType == 'annual') {
      if (ranges.isEmpty) {
        _respondWithRC(
          context,
          staffNames.length == 1
              ? 'Which dates should I set annual leave for ${staffNames.first}?'
              : 'Which dates should I set annual leave for each staff member?',
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
        title: 'Set Annual Leave',
        message: 'Apply annual leave for: $summary?',
        onConfirm: () {
          int dayCount = 0;
          for (final entry in assignments) {
            var date = entry.range.start;
            while (!date.isAfter(entry.range.end)) {
              roster.setOverride(entry.staff, date, 'AL', 'Annual leave');
              dayCount++;
              date = date.add(const Duration(days: 1));
            }
          }
          _respondWithRC(
            context,
            'Applied Annual Leave for ${assignments.length} staff '
                '($dayCount day(s)).',
          );
        },
      );
      return;
    }

    if (isExtend && staffNames.length == 1) {
      final staffMember = roster.staffMembers.firstWhere(
        (s) => s.name == staffNames.first,
        orElse: () => models.StaffMember(id: '', name: staffNames.first),
      );
      if (staffMember.id.isEmpty) {
        _respondWithRC(context, 'Staff member not found.');
        return;
      }
      final code = _leaveTypeToShiftCode(effectiveLeaveType);
      DateTime? currentEnd;
      final overrides = roster.overrides
          .where((o) =>
              o.personName == staffMember.name &&
              o.shift.toUpperCase() == code.toUpperCase())
          .toList();
      if (overrides.isNotEmpty) {
        overrides.sort((a, b) => a.date.compareTo(b.date));
        currentEnd = overrides.last.date;
      }
      if (currentEnd == null) {
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
      DateTime newEnd = currentEnd;
      if (ranges.isNotEmpty) {
        final range = ranges.first;
        if (range.explicitEnd) {
          newEnd = range.end;
        } else if (range.durationDays != null) {
          newEnd = currentEnd.add(
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
      var date = currentEnd.add(const Duration(days: 1));
      while (!date.isAfter(newEnd)) {
        roster.setOverride(staffMember.name, date, code, effectiveLeaveType);
        date = date.add(const Duration(days: 1));
      }
      _respondWithRC(
        context,
        'Extended ${staffMember.name} ${_formatLeaveLabel(effectiveLeaveType)} to '
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
          final code = _leaveTypeToShiftCode(effectiveLeaveType);
          var date = entry.range.start;
          while (!date.isAfter(entry.range.end)) {
            roster.setOverride(entry.staff, date, code, effectiveLeaveType);
            date = date.add(const Duration(days: 1));
          }
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
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
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
                    setState(() => staffName = value);
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
                  DropdownMenuItem(
                      value: 'secondment', child: Text('Secondment')),
                  DropdownMenuItem(value: 'custom', child: Text('Custom')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => type = value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              if (type == 'custom') ...[
                const SizedBox(height: 12),
                SafeTextField(
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
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 730)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked != null) {
                    setState(() {
                      start = picked;
                      if (end.isBefore(start)) {
                        end = start;
                      }
                    });
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
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 730)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked != null) {
                    setState(() {
                      end = picked;
                      if (end.isBefore(start)) {
                        start = end;
                      }
                    });
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
      final code = _leaveTypeToShiftCode(effectiveType);
      var date = start;
      while (!date.isAfter(end)) {
        roster.setOverride(staffMember.name, date, code, effectiveType);
        date = date.add(const Duration(days: 1));
      }
    }
  }

  String? _matchStaffName(String text, RosterNotifier roster) {
    final lowered = text.toLowerCase();
    final tokens = lowered.split(' ').where((t) => t.isNotEmpty).toList();
    final staff = roster.staffMembers.map((s) => s.name).toList();
    for (final name in staff) {
      final nameLower = name.toLowerCase();
      if (lowered.contains(nameLower)) {
        return name;
      }
      final parts = nameLower.split(' ').where((t) => t.isNotEmpty).toList();
      for (final part in parts) {
        if (part.length < 2) continue;
        final maxDistance = _maxDistanceForToken(part);
        for (final token in tokens) {
          if (token.length < 2) continue;
          if (_levenshtein(token, part) <= maxDistance) {
            return name;
          }
        }
      }
    }
    return null;
  }

  String _leaveTypeToShiftCode(String leaveType) {
    final normalized = leaveType.toLowerCase();
    if (normalized == 'annual') return 'AL';
    if (normalized == 'sick') return 'SICK';
    if (normalized == 'secondment') return 'SECONDMENT';
    if (normalized.startsWith('custom:')) {
      final label = leaveType.substring('custom:'.length).trim();
      if (label.isEmpty) return 'LEAVE';
      final parts = label.split(RegExp(r'\\s+'));
      final compact = parts.map((p) => p.substring(0, 1)).join();
      final code = compact.isEmpty ? label : compact;
      return code.toUpperCase().substring(0, code.length.clamp(1, 4));
    }
    return 'LEAVE';
  }

  void _handlePanToDateCommand(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    final text = _normalizeCommand(raw);
    final dates = _extractAllDatesFromText(text);
    DateTime? target;
    if (dates.isNotEmpty) {
      target = dates.first;
    } else {
      target = _extractMonthTarget(text);
    }
    if (target == null) {
      _respondWithRC(context, 'Which date or month should I open?');
      return;
    }
    roster.requestFocusDate(target);
    _respondWithRC(
      context,
      'Moving the roster view to ${DateFormat('MMM d, yyyy').format(target)}.',
    );
  }

  Future<void> _handleCreateAccessCodeCommand(
    BuildContext context,
    String raw,
  ) async {
    final rosterId = AwsService.instance.currentRosterId;
    if (rosterId == null || rosterId.isEmpty) {
      _respondWithRC(
        context,
        'No roster selected. Open a roster first, then ask me again.',
      );
      return;
    }
    if (!AwsService.instance.isAuthenticated) {
      _respondWithRC(
        context,
        'Sign in first to create an access code.',
      );
      return;
    }
    final text = _normalizeCommand(raw);
    String role = 'viewer';
    if (text.contains('editor') || text.contains('edit')) {
      role = 'editor';
    }
    int? expiresInHours;
    final hoursMatch =
        RegExp(r'(\\d{1,3})\\s*(hour|hours|hr|hrs)').firstMatch(text);
    if (hoursMatch != null) {
      final value = int.tryParse(hoursMatch.group(1)!);
      if (value != null && value > 0) {
        expiresInHours = value;
      }
    }
    final daysMatch =
        RegExp(r'(\\d{1,3})\\s*(day|days)').firstMatch(text);
    if (daysMatch != null) {
      final value = int.tryParse(daysMatch.group(1)!);
      if (value != null && value > 0) {
        expiresInHours = value * 24;
      }
    }
    int? maxUses;
    final maxMatch =
        RegExp(r'(\\d{1,3})\\s*(use|uses|max)').firstMatch(text);
    if (maxMatch != null) {
      final value = int.tryParse(maxMatch.group(1)!);
      if (value != null && value > 0) {
        maxUses = value;
      }
    }
    final customCode = _extractCustomCodeFromText(text);

    try {
      if (customCode != null) {
        try {
          final validation =
              await AwsService.instance.validateShareCode(customCode);
          if (validation['ok'] == true) {
            _respondWithRC(context, 'That code is already in use.');
            return;
          }
        } catch (e) {
          final msg = e.toString().toLowerCase();
          if (!msg.contains('not found') && !msg.contains('404')) {
            _respondWithRC(context, 'Failed to validate code: $e');
            return;
          }
        }
      }
      final response = await AwsService.instance.createShareCode(
        rosterId: rosterId,
        role: role,
        expiresInHours: expiresInHours,
        maxUses: maxUses,
        customCode: customCode,
      );
      final code = response['code']?.toString() ?? '';
      if (code.isEmpty) {
        _respondWithRC(context, 'Access code created, but no code returned.');
        return;
      }
      await Clipboard.setData(ClipboardData(text: code));
      _respondWithRC(
        context,
        'Access code created: $code (${role == 'viewer' ? 'read-only' : role}). '
        'Copied to clipboard.',
      );
    } catch (e) {
      if (customCode != null) {
        final suggestions = _extractSuggestionsFromError(e);
        if (suggestions.isNotEmpty) {
          _respondWithRC(
            context,
            'That code is taken. Try: ${suggestions.join(', ')}',
          );
          return;
        }
        try {
          final fallback = await AwsService.instance.createShareCode(
            rosterId: rosterId,
            role: role,
            expiresInHours: expiresInHours,
            maxUses: maxUses,
          );
          final code = fallback['code']?.toString() ?? '';
          if (code.isNotEmpty) {
            await Clipboard.setData(ClipboardData(text: code));
            _respondWithRC(
              context,
              'Custom code was taken. Generated unique code: $code. '
              'Copied to clipboard.',
            );
            return;
          }
        } catch (_) {}
      }
      _respondWithRC(context, 'Failed to create access code: $e');
    }
  }

  Future<void> _handleDuplicatePatternCommand(
    BuildContext context,
    String raw,
  ) async {
    final roster = ref.read(rosterProvider);
    final text = _normalizeCommand(raw);
    final includeStaff = text.contains('with staff') ||
        text.contains('include staff') ||
        text.contains('keep staff');
    final includeOverrides = text.contains('with overrides') ||
        text.contains('include overrides') ||
        text.contains('keep overrides');
    final name = _extractDuplicateName(text);

    if (name == null || name.isEmpty) {
      _respondWithRC(context, 'What name should I use for the duplicate?');
      _showDuplicatePatternWizard(context);
      return;
    }

    roster.saveRosterSnapshot(
      name: name,
      includeStaffNames: includeStaff,
      includeOverrides: includeOverrides,
    );
    _respondWithRC(
      context,
      'Saved duplicate "$name". Staff: ${includeStaff ? 'kept' : 'not included'}, '
      'Changes: ${includeOverrides ? 'kept' : 'not included'}.',
    );
  }

  void _showDuplicatePatternWizard(BuildContext context) {
    final nameController = TextEditingController();
    bool includeStaff = true;
    bool includeOverrides = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Duplicate Pattern'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SafeTextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Duplicate name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Include staff names'),
                  value: includeStaff,
                  onChanged: (value) => setState(() => includeStaff = value),
                ),
                SwitchListTile(
                  title: const Text('Include changes'),
                  value: includeOverrides,
                  onChanged: (value) => setState(() => includeOverrides = value),
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
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  ref.read(rosterProvider).saveRosterSnapshot(
                        name: name,
                        includeStaffNames: includeStaff,
                        includeOverrides: includeOverrides,
                      );
                  Navigator.pop(context);
                  _respondWithRC(context, 'Duplicate saved as "$name".');
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _normalizeCommand(String raw) {
    var lower = raw.toLowerCase();
    lower = _normalizeOrdinalText(lower);
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ');
    return cleaned.replaceAll(RegExp(r'\\s+'), ' ').trim();
  }

  String _normalizeOrdinalText(String text) {
    var cleaned = text.replaceAll('-', ' ');
    // Normalize numeric ordinals with space: "21 st" -> "21st"
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\\b(\\d{1,2})\\s+(st|nd|rd|th)\\b'),
      (m) => '${m[1]}${m[2]}',
    );

    final unitOrdinals = <String, int>{
      'first': 1,
      'second': 2,
      'third': 3,
      'fourth': 4,
      'fifth': 5,
      'sixth': 6,
      'seventh': 7,
      'eighth': 8,
      'ninth': 9,
    };
    final teenOrdinals = <String, int>{
      'tenth': 10,
      'eleventh': 11,
      'twelfth': 12,
      'thirteenth': 13,
      'fourteenth': 14,
      'fifteenth': 15,
      'sixteenth': 16,
      'seventeenth': 17,
      'eighteenth': 18,
      'nineteenth': 19,
    };
    final tensOrdinals = <String, int>{
      'twentieth': 20,
      'thirtieth': 30,
      'fortieth': 40,
      'fiftieth': 50,
      'sixtieth': 60,
      'seventieth': 70,
      'eightieth': 80,
      'ninetieth': 90,
    };
    final tens = <String, int>{
      'twenty': 20,
      'thirty': 30,
      'forty': 40,
      'fifty': 50,
      'sixty': 60,
      'seventy': 70,
      'eighty': 80,
      'ninety': 90,
    };

    // Replace compound ordinals like "twenty first" -> "21st"
    cleaned = cleaned.replaceAllMapped(
      RegExp(
        r'\\b(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)\\s+'
        r'(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth)\\b',
      ),
      (m) {
        final value = (tens[m[1]] ?? 0) + (unitOrdinals[m[2]] ?? 0);
        return _toOrdinal(value);
      },
    );

    // Replace single-word ordinals
    for (final entry in unitOrdinals.entries) {
      cleaned = cleaned.replaceAllMapped(
        RegExp('\\b${entry.key}\\b'),
        (_) => _toOrdinal(entry.value),
      );
    }
    for (final entry in teenOrdinals.entries) {
      cleaned = cleaned.replaceAllMapped(
        RegExp('\\b${entry.key}\\b'),
        (_) => _toOrdinal(entry.value),
      );
    }
    for (final entry in tensOrdinals.entries) {
      cleaned = cleaned.replaceAllMapped(
        RegExp('\\b${entry.key}\\b'),
        (_) => _toOrdinal(entry.value),
      );
    }

    return cleaned;
  }

  String _toOrdinal(int value) {
    if (value % 100 >= 11 && value % 100 <= 13) {
      return '${value}th';
    }
    switch (value % 10) {
      case 1:
        return '${value}st';
      case 2:
        return '${value}nd';
      case 3:
        return '${value}rd';
      default:
        return '${value}th';
    }
  }

  List<String> _splitIntoClauses(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return [];
    if (_isMathLikeSentence(cleaned)) {
      return [cleaned];
    }
    return cleaned
        .split(RegExp(r'\\s*(?:;|\\band then\\b|\\bthen\\b|\\balso\\b|\\bplus\\b)\\s*',
            caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  bool _isMathLikeSentence(String text) {
    final lowered = text.toLowerCase();
    final hasDigit = RegExp(r'\\d').hasMatch(lowered);
    final hasOp = RegExp(r'[+*/%\\-]').hasMatch(lowered) ||
        _containsAny(lowered.split(' '), [
          'plus',
          'minus',
          'times',
          'multiplied',
          'divided',
          'over',
        ]);
    if (!hasDigit || !hasOp) return false;
    // If it mentions roster keywords or staff names, treat as chained query instead.
    if (lowered.contains('shift') ||
        lowered.contains('roster') ||
        lowered.contains('staff') ||
        lowered.contains('rest')) {
      return false;
    }
    return true;
  }

  bool _containsAny(List<String> tokens, List<String> keywords) {
    for (final keyword in keywords) {
      if (tokens.contains(keyword)) return true;
    }
    return false;
  }

  int _maxDistanceForToken(String token) {
    final length = token.length;
    if (length <= 3) return 0;
    if (length <= 5) return 1;
    if (length <= 7) return 2;
    return 3;
  }

  bool _containsAnyFuzzy(List<String> tokens, List<String> keywords) {
    for (final keyword in keywords) {
      if (tokens.contains(keyword)) return true;
      final maxDistance = _maxDistanceForToken(keyword);
      for (final token in tokens) {
        if (token.length < 2) continue;
        if (_levenshtein(token, keyword) <= maxDistance) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isQuestionLike(String text, List<String> tokens) {
    if (text.contains('?')) return true;
    if (_containsAnyFuzzy(tokens, ['what', 'who', 'when', 'where', 'how'])) {
      return true;
    }
    return false;
  }

  bool _isPanToDateIntent(String text, List<String> tokens) {
    final hasNav = _containsAnyFuzzy(tokens, [
      'go',
      'goto',
      'jump',
      'show',
      'scroll',
      'pan',
      'move',
      'navigate',
      'open',
      'view',
    ]);
    if (!hasNav) return false;
    if (_containsAnyFuzzy(tokens, ['today', 'tomorrow', 'yesterday'])) {
      return true;
    }
    if (_extractAllDatesFromText(text).isNotEmpty) return true;
    if (_extractMonthTarget(text) != null) return true;
    return false;
  }

  bool _isAccessCodeIntent(String text, List<String> tokens) {
    if (text.contains('access code') ||
        text.contains('share code') ||
        text.contains('shared code') ||
        text.contains('guest code') ||
        text.contains('viewer code')) {
      return true;
    }
    if (_containsAnyFuzzy(tokens, ['code']) &&
        _containsAnyFuzzy(tokens, ['share', 'access', 'guest', 'viewer'])) {
      return true;
    }
    return false;
  }

  bool _isDuplicatePatternIntent(String text, List<String> tokens) {
    if (text.contains('duplicate pattern') ||
        text.contains('copy pattern') ||
        text.contains('duplicate roster') ||
        text.contains('copy roster') ||
        text.contains('save snapshot') ||
        text.contains('save copy')) {
      return true;
    }
    if (_containsAnyFuzzy(tokens, ['duplicate', 'copy', 'snapshot']) &&
        _containsAnyFuzzy(tokens, ['pattern', 'roster'])) {
      return true;
    }
    return false;
  }

  String? _extractDuplicateName(String text) {
    final match = RegExp(r'(?:named|name|as)\\s+([a-z0-9 _-]{3,40})')
        .firstMatch(text.toLowerCase());
    if (match != null) {
      return match.group(1)?.trim();
    }
    return null;
  }

  String? _extractCustomCodeFromText(String text) {
    final lowered = text.toLowerCase();
    final match = RegExp(
      r'(?:custom|access|share|guest)?\\s*code\\s*[:=]?\\s*([a-z0-9_-]{4,24})',
    ).firstMatch(lowered);
    if (match != null) {
      return match.group(1)?.toUpperCase();
    }
    return null;
  }

  List<String> _extractSuggestionsFromError(Object error) {
    final raw = error.toString();
    final listMatch = RegExp(r'\\[([^\\]]+)\\]').firstMatch(raw);
    if (listMatch == null) return const [];
    final items = listMatch.group(1)!.split(',');
    return items
        .map((item) => item.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '').trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  DateTime? _extractMonthTarget(String text) {
    final lower = text.toLowerCase();
    final now = DateTime.now();
    if (lower.contains('this month')) {
      return DateTime(now.year, now.month, 1);
    }
    if (lower.contains('next month')) {
      final next = DateTime(now.year, now.month + 1, 1);
      return next;
    }
    if (lower.contains('last month') || lower.contains('previous month')) {
      final prev = DateTime(now.year, now.month - 1, 1);
      return prev;
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
      r'\\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\\b(?:\\s*(\\d{4}))?',
    ).firstMatch(lower);
    if (match != null) {
      final month = monthNames[match.group(1)!]!;
      final year =
          match.group(2) != null ? int.parse(match.group(2)!) : now.year;
      return DateTime(year, month, 1);
    }
    return null;
  }

  bool _isCancelLeaveIntent(String text, List<String> tokens) {
    if (text.contains('cancel leave') ||
        text.contains('remove leave') ||
        text.contains('cancel annual') ||
        text.contains('remove annual') ||
        text.contains('cancel al') ||
        text.contains('clear leave') ||
        text.contains('unbook leave') ||
        text.contains('delete leave') ||
        text.contains('revoke leave') ||
        text.contains('undo leave') ||
        text.contains('dont set leave') ||
        text.contains('do not set leave') ||
        text.contains("don't set leave") ||
        text.contains('dont book leave') ||
        text.contains('do not book leave') ||
        text.contains("don't book leave")) {
      return true;
    }
    final hasCancel =
        _containsAnyFuzzy(tokens, ['cancel', 'remove', 'clear', 'undo']);
    final hasLeave = _containsAnyFuzzy(tokens, [
      'leave',
      'annual',
      'al',
      'vacation',
    ]);
    return hasCancel && hasLeave;
  }

  bool _isSetLeaveIntent(String text, List<String> tokens) {
    if (text.contains('annual leave') ||
        text.contains('book leave') ||
        text.contains('set leave') ||
        text.contains('add leave') ||
        text.contains('request leave') ||
        text.contains('apply leave') ||
        text.contains('vacation') ||
        text.contains('holiday')) {
      return true;
    }
    final hasLeave = _containsAnyFuzzy(tokens, ['leave', 'annual', 'al']);
    final hasSet = _containsAnyFuzzy(tokens, [
      'set',
      'book',
      'add',
      'apply',
      'request',
      'assign',
    ]);
    return hasLeave && hasSet;
  }

  String _inferLeaveTypeForSet(String raw) {
    final text = raw.toLowerCase();
    if (text.contains('sick') || text.contains('ill')) return 'sick';
    if (text.contains('secondment')) return 'secondment';
    if (text.contains('annual') ||
        text.contains('al') ||
        text.contains('vacation') ||
        text.contains('holiday')) {
      return 'annual';
    }
    return 'leave';
  }

  bool _shouldUseContextStaff(String text, List<String> tokens) {
    if (_containsAny(tokens, ['him', 'her', 'them', 'they', 'their', 'that'])) {
      return true;
    }
    if (text.contains('same person') || text.contains('that person')) {
      return true;
    }
    if (text.contains('again')) return true;
    return false;
  }

  bool _shouldUseContextDate(String text, List<String> tokens) {
    if (_containsAny(tokens, ['same', 'that', 'there', 'then'])) return true;
    if (text.contains('same day') ||
        text.contains('same date') ||
        text.contains('that day') ||
        text.contains('that date')) {
      return true;
    }
    return false;
  }

  bool _shouldUseContextShift(String text, List<String> tokens) {
    if (text.contains('same shift') || text.contains('that shift')) {
      return true;
    }
    if (_containsAny(tokens, ['same'])) return true;
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
    if (_isQuestionLike(text, tokens) || _isShiftQueryIntent(text, tokens)) {
      return false;
    }
    final staffNames = _matchAllStaffNames(text, roster);
    final monthFirst = _isMonthFirst(ref.read(settingsProvider));
    final dates = _collectDates(
      text: text,
      raw: raw,
      weekStartDay: roster.weekStartDay,
      monthFirst: monthFirst,
    );
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
      final baseShift = roster.getBaseShiftForDate(
        staffNames.first,
        dates.first,
      );
      final baseLabel =
          baseShift.isEmpty ? 'no base shift' : _shiftLabel(baseShift);
      _respondWithRC(
        context,
        'What should I do for ${staffNames.first} on $dateLabel? '
        'Base pattern is $baseLabel. Say: set shift, add leave, or swap.',
      );
      _contextState.remember(
        action: 'await_shift_for_change',
        pendingStaff: staffNames.first,
        pendingDates:
            dates.map((d) => DateTime(d.year, d.month, d.day)).toList(),
        pendingCreatedAt: DateTime.now(),
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
      _contextState.remember(
        action: 'await_staff_for_change',
        pendingShift: shift,
        pendingDates:
            dates.map((d) => DateTime(d.year, d.month, d.day)).toList(),
        pendingCreatedAt: DateTime.now(),
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

  bool _tryBuildClarifyingQuestion(
    BuildContext context,
    String raw,
    RosterNotifier roster,
  ) {
    final text = _normalizeCommand(raw);
    final tokens = text.split(' ');
    final staffMatch = _matchStaffName(text, roster);
    final shiftMatch = _extractShiftCode(text);
    final dateRange = _extractDateRangeFromText(text, roster.weekStartDay);
    final isQuestion = _isQuestionLike(text, tokens);
    final wantsEvent =
        _containsAny(tokens, ['event', 'holiday', 'festival', 'payday']);
    final wantsSwap = _isSwapIntent(text, tokens, roster);
    final actionVerbPresent = _containsAnyFuzzy(tokens, [
      'set',
      'assign',
      'change',
      'override',
      'swap',
      'add',
      'remove',
      'delete',
      'cancel',
      'create',
      'generate',
      'build',
      'make',
    ]);

    if (isQuestion) return false;
    if (wantsSwap && (staffMatch == null || dateRange == null)) {
      _respondWithRC(context, 'Tell me the two staff names and the date to swap.');
      return true;
    }
    if (wantsEvent && actionVerbPresent && dateRange == null) {
      _respondWithRC(context, 'Which date should I add the event to?');
      return true;
    }
    if (actionVerbPresent) {
      if (staffMatch == null && shiftMatch == null) {
        _respondWithRC(context, 'Who should I update and what shift?');
        return true;
      }
      if (staffMatch != null && shiftMatch == null) {
        _respondWithRC(context, 'Which shift should I set for $staffMatch?');
        return true;
      }
      if (staffMatch == null && shiftMatch != null) {
        _respondWithRC(context, 'Which staff member should I update?');
        return true;
      }
      if (dateRange == null) {
        _respondWithRC(context, 'Which date should I apply that change?');
        return true;
      }
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

  bool _handleMathQuery(BuildContext context, String raw) {
    final lower = raw.toLowerCase();
    if (!lower.contains(RegExp(r'\\d')) &&
        !_containsAny(lower.split(' '), [
          'calculate',
          'math',
          'sum',
          'plus',
          'minus',
          'times',
          'multiplied',
          'divided',
        ])) {
      return false;
    }
    final expr = _extractMathExpression(lower);
    if (expr == null || expr.trim().isEmpty) return false;
    try {
      final result = _evaluateMathExpression(expr);
      _respondWithRC(context, '$expr = $result');
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _handleNameQuery(BuildContext context, String text) {
    if (text.contains('your name') ||
        text.contains('who are you') ||
        text.contains('what are you called') ||
        text.contains('what is your name')) {
      _respondWithRC(context, "I'm RC (Roster Champion).");
      return true;
    }
    return false;
  }

  bool _handleNextRestDayQuery(
    BuildContext context,
    String text,
    RosterNotifier roster,
  ) {
    if (!text.contains('next') ||
        !(text.contains('rest') || text.contains('off'))) {
      return false;
    }
    if (!(text.contains('when') || text.contains('next time'))) {
      return false;
    }
    final staff = _matchStaffName(text, roster);
    if (staff == null) {
      _respondWithRC(context, 'Which staff member should I check?');
      return true;
    }
    final limitRange = _extractDateRangeFromText(text, roster.weekStartDay);
    final daysAhead = _extractDurationDays(text) ?? 365;
    final start = DateTime.now();
    final end = limitRange?.end ?? start.add(Duration(days: daysAhead));
    final maxCount = _extractCountHint(text) ?? 1;
    final results = <DateTime>[];
    var cursor = start;
    while (!cursor.isAfter(end) && results.length < maxCount) {
      final shift = roster.getShiftForDate(staff, cursor).toUpperCase();
      if (shift == 'R' || shift == 'OFF') {
        results.add(cursor);
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    if (results.isEmpty) {
      _respondWithRC(
        context,
        'No rest day found for $staff in the selected range.',
      );
      return true;
    }
    final label = results
        .map((d) => DateFormat('EEE, MMM d').format(d))
        .join(', ');
    _respondWithRC(
      context,
      'Next ${results.length} rest day(s) for $staff: $label.',
    );
    return true;
  }

  int? _extractCountHint(String text) {
    final match = RegExp(r'next\\s+(\\d+)').firstMatch(text);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  bool _handleRosterMathQuery(
    BuildContext context,
    String raw,
    String normalized,
    RosterNotifier roster,
  ) {
    if (!normalized.contains('hour') &&
        !normalized.contains('hours') &&
        !normalized.contains('total') &&
        !normalized.contains('count') &&
        !normalized.contains('compare')) {
      return false;
    }
    final range = _extractDateRangeFromText(normalized, roster.weekStartDay);
    if (range == null) return false;

    final staffMatches = _matchAllStaffNames(normalized, roster);
    if (staffMatches.isEmpty) return false;

    final settings = ref.read(settingsProvider);
    final hourMap = settings.shiftHourMap;

    final summaries = <String>[];
    for (final staff in staffMatches) {
      final shifts = <String, int>{};
      var totalHours = 0.0;
      var date = range.start;
      while (!date.isAfter(range.end)) {
        final shift = roster.getShiftForDate(staff, date);
        if (shift.isNotEmpty && shift != 'OFF') {
          shifts[shift] = (shifts[shift] ?? 0) + 1;
          totalHours += _estimateShiftHours(shift, hourMap);
        }
        date = date.add(const Duration(days: 1));
      }
      final parts = shifts.entries
          .map((e) => '${e.value} ${_shiftLabel(e.key)}')
          .join(', ');
      summaries.add(
        '$staff: $parts (${totalHours.toStringAsFixed(1)} hours)',
      );
    }

    final label =
        '${DateFormat('MMM d').format(range.start)} to ${DateFormat('MMM d').format(range.end)}';
    _respondWithRC(
      context,
      '${summaries.join(' | ')} for $label.',
    );
    return true;
  }

  double _estimateShiftHours(String shift, Map<String, double> hourMap) {
    final normalized = shift.toUpperCase();
    if (hourMap.containsKey(normalized)) {
      return hourMap[normalized] ?? 0.0;
    }
    if (normalized.contains('12')) return 12.0;
    if (normalized == 'OFF' || normalized == 'R') return 0.0;
    return 8.0;
  }

  String? _extractMathExpression(String text) {
    var cleaned = text
        .replaceAll('what is', '')
        .replaceAll('calculate', '')
        .replaceAll('math', '')
        .replaceAll('=', '')
        .trim();
    cleaned = cleaned
        .replaceAll('plus', '+')
        .replaceAll('minus', '-')
        .replaceAll('times', '*')
        .replaceAll('x', '*')
        .replaceAll('multiplied by', '*')
        .replaceAll('divided by', '/')
        .replaceAll('over', '/')
        .replaceAll('percent', '%')
        .replaceAll(RegExp(r'[^0-9.+*/%() -]'), ' ')
        .replaceAll(RegExp(r'\\s+'), ' ')
        .trim();
    return cleaned;
  }

  String _evaluateMathExpression(String expr) {
    final tokens = _tokenizeMath(expr);
    final output = <String>[];
    final ops = <String>[];
    final precedence = {
      '+': 1,
      '-': 1,
      '*': 2,
      '/': 2,
      '%': 2,
    };
    for (final token in tokens) {
      if (double.tryParse(token) != null) {
        output.add(token);
      } else if (token == '(') {
        ops.add(token);
      } else if (token == ')') {
        while (ops.isNotEmpty && ops.last != '(') {
          output.add(ops.removeLast());
        }
        if (ops.isNotEmpty && ops.last == '(') {
          ops.removeLast();
        }
      } else if (precedence.containsKey(token)) {
        while (ops.isNotEmpty &&
            precedence.containsKey(ops.last) &&
            precedence[ops.last]! >= precedence[token]!) {
          output.add(ops.removeLast());
        }
        ops.add(token);
      }
    }
    while (ops.isNotEmpty) {
      output.add(ops.removeLast());
    }
    final stack = <double>[];
    for (final token in output) {
      final value = double.tryParse(token);
      if (value != null) {
        stack.add(value);
        continue;
      }
      if (stack.length < 2) {
        throw StateError('Invalid expression');
      }
      final b = stack.removeLast();
      final a = stack.removeLast();
      switch (token) {
        case '+':
          stack.add(a + b);
          break;
        case '-':
          stack.add(a - b);
          break;
        case '*':
          stack.add(a * b);
          break;
        case '/':
          stack.add(b == 0 ? double.nan : a / b);
          break;
        case '%':
          stack.add(b == 0 ? double.nan : a % b);
          break;
      }
    }
    if (stack.isEmpty) {
      throw StateError('Invalid expression');
    }
    final result = stack.single;
    if (result.isNaN || result.isInfinite) return 'undefined';
    if ((result - result.round()).abs() < 0.00001) {
      return result.round().toString();
    }
    return result.toStringAsFixed(2);
  }

  List<String> _tokenizeMath(String expr) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if ('0123456789.'.contains(ch)) {
        buffer.write(ch);
        continue;
      }
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
      if ('+-*/()%'.contains(ch)) {
        tokens.add(ch);
      }
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }
    return tokens;
  }

  void _handleSwapCommand(BuildContext context, String raw) {
    final roster = ref.read(rosterProvider);
    if (roster.readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read-only roster cannot be edited.')),
      );
      return;
    }
    final normalized = _normalizeCommand(raw);
    final staffNames = _matchAllStaffNames(normalized, roster);
    final range = _extractDateRangeFromText(normalized, roster.weekStartDay);
    final weekIndex = _extractPatternWeekIndex(normalized);
    final endDate = _extractSwapEndDate(normalized);
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
      final resolved = _resolveDatesForQuery(
        normalized,
        raw,
        roster.weekStartDay,
        null,
        roster,
      );
      if (resolved != null && resolved.dates.isNotEmpty) {
        final sorted = resolved.dates.toList()..sort();
        final start = sorted.first;
        final end = sorted.last;
        effectiveRange = _DateRange(
          start: start,
          end: end,
          explicitStart: true,
          explicitEnd: sorted.length > 1,
        );
      }
    }
    if (effectiveRange == null) {
      _contextState.remember(
        action: 'await_date_for_swap',
        pendingRaw: raw,
        pendingCreatedAt: DateTime.now(),
      );
      _respondWithRC(context, 'Which date should the swap happen?');
      return;
    }

    if (staffNames.isEmpty) {
      final guess = _guessStaffName(normalized, roster);
      if (guess != null) {
        staffNames.add(guess);
      }
    }

    if (staffNames.isEmpty) {
      _respondWithRC(context, 'Which staff member needs the swap?');
      return;
    }
    if (staffNames.length > 2) {
      _respondWithRC(
        context,
        'Which two staff are swapping? Please name two people.',
      );
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

    final isRecurring = normalized.contains('pattern') ||
        normalized.contains('every') ||
        normalized.contains('each') ||
        normalized.contains('rest of year') ||
        normalized.contains('months') ||
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

    int applied = 0;
    final resolvedDates = _resolveDatesForQuery(
      normalized,
      raw,
      roster.weekStartDay,
      null,
      roster,
    );
    final datesList = resolvedDates?.dates ?? [];
    if (datesList.length > 1 && !isRecurring) {
      for (final date in datesList) {
        if (roster.applySwapForDate(
          fromPerson: fromPerson,
          toPerson: toPerson,
          date: date,
          reason: 'AI swap request',
        )) {
          applied++;
        }
      }
    } else if (effectiveRange.start == effectiveRange.end) {
      applied = roster.applySwapForDate(
        fromPerson: fromPerson,
        toPerson: toPerson,
        date: effectiveRange.start,
        reason: 'AI swap request',
      )
          ? 1
          : 0;
    } else {
      applied = roster.applySwapRange(
        fromPerson: fromPerson,
        toPerson: toPerson,
        startDate: effectiveRange.start,
        endDate: effectiveRange.end,
        reason: 'AI swap request',
      );
    }

    if (applied == 0) {
      _respondWithRC(
        context,
        'Swap not applied. Check that both staff are scheduled on those dates.',
      );
      return;
    }
    final debtTokens = normalized.split(' ');
    final skipDebt = normalized.contains('no debt') ||
        normalized.contains('even') ||
        normalized.contains('swap back') ||
        _containsAnyFuzzy(debtTokens, ['nodebt', 'no-debt', 'even']);
    if (!skipDebt) {
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
    final tokens = lowered.split(' ').where((t) => t.isNotEmpty).toList();
    final matches = <MapEntry<String, int>>[];
    for (final staff in roster.staffMembers) {
      final nameLower = staff.name.toLowerCase();
      final index = lowered.indexOf(nameLower);
      if (index != -1) {
        matches.add(MapEntry(staff.name, index));
      }
    }
    if (matches.isEmpty) {
      for (final staff in roster.staffMembers) {
        final nameLower = staff.name.toLowerCase();
        final parts = nameLower.split(' ').where((t) => t.isNotEmpty).toList();
        int? bestIndex;
        for (int tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
          final token = tokens[tokenIndex];
          if (token.length < 2) continue;
          for (final part in parts) {
            if (part.length < 2) continue;
            final maxDistance = _maxDistanceForToken(part);
            if (_levenshtein(token, part) <= maxDistance) {
              bestIndex ??= tokenIndex;
            }
          }
        }
        if (bestIndex != null) {
          matches.add(MapEntry(staff.name, bestIndex));
        }
      }
    }
    matches.sort((a, b) => a.value.compareTo(b.value));
    return matches.map((e) => e.key).toList();
  }

  int _estimateCoverageNeed(
    RosterNotifier roster,
    DateTime date,
    String? shift,
  ) {
    final normalized = shift?.toUpperCase();
    if (normalized == null) {
      return (roster.staffMembers.length / 4).ceil().clamp(1, 999);
    }
    if (normalized == 'N' || normalized == 'N12') {
      return (roster.staffMembers.length / 4).ceil().clamp(1, 999);
    }
    if (normalized == 'D' || normalized == 'D12' || normalized == 'E' || normalized == 'L') {
      return (roster.staffMembers.length / 3).ceil().clamp(1, 999);
    }
    return (roster.staffMembers.length / 4).ceil().clamp(1, 999);
  }

  String? _normalizeShiftForCoverage(String? code) {
    if (code == null) return null;
    final upper = code.toUpperCase();
    if (upper == 'D' || upper == 'D12' || upper == 'E' || upper == 'L') {
      return 'D';
    }
    if (upper == 'N' || upper == 'N12') {
      return 'N';
    }
    return upper;
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
    _contextState.remember(staff: staffName, shift: shift);

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

    _confirmAndApplyChange(context, staffName, shift, dates);
  }

  void _confirmAndApplyChange(
    BuildContext context,
    String staffName,
    String shift,
    List<DateTime> dates,
  ) {
    final roster = ref.read(rosterProvider);
    if (dates.isEmpty) return;
    if (dates.length == 1) {
      final targetDate = dates.first;
      final baseShift = roster.getBaseShiftForDate(staffName, targetDate);
      final prevOverride = roster.overrides.firstWhere(
        (o) =>
            o.personName == staffName &&
            o.date.year == targetDate.year &&
            o.date.month == targetDate.month &&
            o.date.day == targetDate.day,
        orElse: () => models.Override(
          id: '',
          personName: staffName,
          date: targetDate,
          shift: '',
          reason: '',
          createdAt: DateTime.now(),
        ),
      );
      if (shift == baseShift && prevOverride.id.isEmpty) {
        _respondWithRC(
          context,
          '${staffName} already has ${_shiftLabel(shift)} on '
              '${DateFormat('MMM d, yyyy').format(targetDate)}.',
        );
        return;
      }
      if (shift == baseShift && prevOverride.id.isNotEmpty) {
        _confirmAction(
          context,
          title: 'Clear change',
          message:
              'This matches the base pattern. Clear the existing change instead?',
          onConfirm: () {
            roster.removeOverridesForDates(
              people: [staffName],
              dates: [targetDate],
            );
            _respondWithRC(context, 'Change cleared.');
          },
        );
        return;
      }
      _confirmAction(
        context,
        title: 'Set shift',
        message:
            'Set $staffName to ${_shiftLabelWithCode(shift)} on ${DateFormat('MMM d, yyyy').format(targetDate)}?',
        onConfirm: () {
          final warning = _coverageWarningForChange(
            roster,
            staffName,
            targetDate,
            shift,
          );
          final prevShift = prevOverride.id.isEmpty ? null : prevOverride.shift;
          roster.setOverride(staffName, targetDate, shift, 'RC change');
          if (warning != null) {
            _respondWithRC(context, warning);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Change applied.'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () {
                  final base = roster.getBaseShiftForDate(
                    staffName,
                    targetDate,
                  );
                  if (prevShift == null || prevShift == base) {
                    roster.removeOverridesForDates(
                      people: [staffName],
                      dates: [targetDate],
                    );
                  } else {
                    roster.setOverride(
                      staffName,
                      targetDate,
                      prevShift,
                      'Undo change',
                    );
                  }
                },
              ),
            ),
          );
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
        final prevStates = <Map<String, dynamic>>[];
        for (final date in sorted) {
          final warning = _coverageWarningForChange(
            roster,
            staffName,
            date,
            shift,
          );
          final prevOverride = roster.overrides.firstWhere(
            (o) =>
                o.personName == staffName &&
                o.date.year == date.year &&
                o.date.month == date.month &&
                o.date.day == date.day,
            orElse: () => models.Override(
              id: '',
              personName: staffName,
              date: date,
              shift: '',
              reason: '',
              createdAt: DateTime.now(),
            ),
          );
          prevStates.add({
            'date': date,
            'shift': prevOverride.id.isEmpty ? null : prevOverride.shift,
          });
          roster.setOverride(staffName, date, shift, 'RC change');
          if (warning != null) {
            _respondWithRC(context, warning);
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Changes applied.'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                for (final entry in prevStates) {
                  final date = entry['date'] as DateTime;
                  final prevShift = entry['shift'] as String?;
                  final base = roster.getBaseShiftForDate(staffName, date);
                  if (prevShift == null || prevShift == base) {
                    roster.removeOverridesForDates(
                      people: [staffName],
                      dates: [date],
                    );
                  } else {
                    roster.setOverride(
                      staffName,
                      date,
                      prevShift,
                      'Undo change',
                    );
                  }
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _confirmAndApplyBulkChange(
    BuildContext context,
    List<String> staffNames,
    String shift,
    List<DateTime> dates,
  ) {
    if (staffNames.isEmpty || dates.isEmpty) return;
    final roster = ref.read(rosterProvider);
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
          'Set ${staffNames.join(', ')} to ${_shiftLabelWithCode(shift)} on ${sorted.length} dates '
          '($preview$suffix)?',
      onConfirm: () {
        final prevStates = <Map<String, dynamic>>[];
        for (final date in sorted) {
          for (final staffName in staffNames) {
            final prevOverride = roster.overrides.firstWhere(
              (o) =>
                  o.personName == staffName &&
                  o.date.year == date.year &&
                  o.date.month == date.month &&
                  o.date.day == date.day,
              orElse: () => models.Override(
                id: '',
                personName: staffName,
                date: date,
                shift: '',
                reason: '',
                createdAt: DateTime.now(),
              ),
            );
            prevStates.add({
              'name': staffName,
              'date': date,
              'shift': prevOverride.id.isEmpty ? null : prevOverride.shift,
            });
            roster.setOverride(staffName, date, shift, 'RC change');
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Changes applied.'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                for (final entry in prevStates) {
                  final name = entry['name'] as String;
                  final date = entry['date'] as DateTime;
                  final prevShift = entry['shift'] as String?;
                  final base = roster.getBaseShiftForDate(name, date);
                  if (prevShift == null || prevShift == base) {
                    roster.removeOverridesForDates(
                      people: [name],
                      dates: [date],
                    );
                  } else {
                    roster.setOverride(
                      name,
                      date,
                      prevShift,
                      'Undo change',
                    );
                  }
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _handleBulkOverrideCommand(
    BuildContext context,
    String raw,
    List<String> staffNames,
    String shift,
  ) {
    final roster = ref.read(rosterProvider);
    if (roster.readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read-only roster cannot be edited.')),
      );
      return;
    }
    final dates = _extractDatesForOverride(raw, roster.weekStartDay);
    final range = _extractDateRangeFromText(raw, roster.weekStartDay);
    if (dates.isEmpty && range == null) {
      _respondWithRC(
        context,
        'Which dates should I apply ${_shiftLabelWithCode(shift)} for '
        '${staffNames.join(', ')}?',
      );
      _showSetShiftWizard(
        context,
        initialShift: shift,
      );
      return;
    }

    if (range != null && (range.end.isAfter(range.start))) {
      _confirmAction(
        context,
        title: 'Set bulk shifts',
        message:
            'Set ${staffNames.length} staff to ${_shiftLabelWithCode(shift)} from '
            '${DateFormat('MMM d').format(range.start)} to ${DateFormat('MMM d').format(range.end)}?',
        onConfirm: () {
          final prevStates = <Map<String, dynamic>>[];
          var cursor = DateTime(
            range.start.year,
            range.start.month,
            range.start.day,
          );
          final end = DateTime(range.end.year, range.end.month, range.end.day);
          while (!cursor.isAfter(end)) {
            for (final name in staffNames) {
              final prevOverride = roster.overrides.firstWhere(
                (o) =>
                    o.personName == name &&
                    o.date.year == cursor.year &&
                    o.date.month == cursor.month &&
                    o.date.day == cursor.day,
                orElse: () => models.Override(
                  id: '',
                  personName: name,
                  date: cursor,
                  shift: '',
                  reason: '',
                  createdAt: DateTime.now(),
                ),
              );
              prevStates.add({
                'name': name,
                'date': cursor,
                'shift': prevOverride.id.isEmpty ? null : prevOverride.shift,
              });
            }
            cursor = cursor.add(const Duration(days: 1));
          }
          roster.addBulkOverridesAdvanced(
            people: staffNames,
            startDate: range.start,
            endDate: range.end,
            shift: shift,
            reason: 'RC change',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Changes applied.'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () {
                  for (final entry in prevStates) {
                    final name = entry['name'] as String;
                    final date = entry['date'] as DateTime;
                    final prevShift = entry['shift'] as String?;
                    final base = roster.getBaseShiftForDate(name, date);
                    if (prevShift == null || prevShift == base) {
                      roster.removeOverridesForDates(
                        people: [name],
                        dates: [date],
                      );
                    } else {
                      roster.setOverride(
                        name,
                        date,
                        prevShift,
                        'Undo change',
                      );
                    }
                  }
                },
              ),
            ),
          );
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
          'Set ${staffNames.length} staff to ${_shiftLabelWithCode(shift)} on ${sorted.length} dates '
          '($preview$suffix)?',
      onConfirm: () {
        final prevStates = <Map<String, dynamic>>[];
        for (final date in sorted) {
          for (final staffName in staffNames) {
            final prevOverride = roster.overrides.firstWhere(
              (o) =>
                  o.personName == staffName &&
                  o.date.year == date.year &&
                  o.date.month == date.month &&
                  o.date.day == date.day,
              orElse: () => models.Override(
                id: '',
                personName: staffName,
                date: date,
                shift: '',
                reason: '',
                createdAt: DateTime.now(),
              ),
            );
            prevStates.add({
              'name': staffName,
              'date': date,
              'shift': prevOverride.id.isEmpty ? null : prevOverride.shift,
            });
            roster.setOverride(staffName, date, shift, 'RC change');
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Changes applied.'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                for (final entry in prevStates) {
                  final name = entry['name'] as String;
                  final date = entry['date'] as DateTime;
                  final prevShift = entry['shift'] as String?;
                  final base = roster.getBaseShiftForDate(name, date);
                  if (prevShift == null || prevShift == base) {
                    roster.removeOverridesForDates(
                      people: [name],
                      dates: [date],
                    );
                  } else {
                    roster.setOverride(
                      name,
                      date,
                      prevShift,
                      'Undo change',
                    );
                  }
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _handleRemoveOverrideCommand(
    BuildContext context,
    String raw, {
    String? fallbackStaff,
  }) {
    final roster = ref.read(rosterProvider);
    if (roster.readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read-only roster cannot be edited.')),
      );
      return;
    }
    final text = _normalizeCommand(raw);
    final staffNames = _matchAllStaffNames(text, roster);
    if (staffNames.isEmpty && fallbackStaff != null) {
      staffNames.add(fallbackStaff);
    }
    if (staffNames.isEmpty) {
      _respondWithRC(context, 'Which staff member should I clear changes for?');
      return;
    }

    final dates = _extractDatesForOverride(raw, roster.weekStartDay);
    final range = _extractDateRangeFromText(text, roster.weekStartDay);
    final leaveHint =
        text.contains('leave') || text.contains('annual') || text.contains('al');
    final changeHint =
        text.contains('change') || text.contains('amend') || text.contains('update');
    if (!changeHint && leaveHint) {
      _handleRemoveLeaveCommand(
        context,
        raw,
        fallbackStaff: staffNames.first,
      );
      return;
    }
    if (!changeHint &&
        !leaveHint &&
        (dates.isNotEmpty || range != null) &&
        staffNames.isNotEmpty) {
      _respondWithRC(
        context,
        'Do you want to remove changes or cancel leave?',
      );
      _contextState.remember(
        action: 'clarify_change_remove',
        staff: staffNames.first,
        staffList: staffNames,
      );
      return;
    }
    if (dates.isEmpty && range == null) {
      _respondWithRC(context, 'Which date or date range should I clear?');
      return;
    }

    if (range != null) {
      final start = range.start;
      final end = range.end;
      final removedList = roster.overrides.where((o) {
        return staffNames.contains(o.personName) &&
            !o.date.isBefore(start) &&
            !o.date.isAfter(end);
      }).toList();
      final count = roster.overrides.where((o) {
        return staffNames.contains(o.personName) &&
            !o.date.isBefore(start) &&
            !o.date.isAfter(end);
      }).length;
      _confirmAction(
        context,
        title: 'Clear changes',
        message: count == 0
            ? 'No changes found in that range. Clear anyway?'
            : 'Remove $count change(s) for ${staffNames.join(', ')} '
                'from ${DateFormat('MMM d').format(start)} to ${DateFormat('MMM d').format(end)}?',
        onConfirm: () {
          final removed = roster.removeOverridesAdvanced(
            people: staffNames,
            startDate: start,
            endDate: end,
          );
          if (removed == 0) {
            _respondWithRC(context, 'No changes were removed.');
          } else {
            _respondWithRC(context, 'Removed $removed change(s).');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Changes removed.'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () {
                    for (final o in removedList) {
                      roster.setOverride(
                        o.personName,
                        o.date,
                        o.shift,
                        o.reason ?? 'Restored change',
                      );
                    }
                  },
                ),
              ),
            );
          }
        },
      );
      return;
    }

    final normalizedDates = dates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet()
        .toList()
      ..sort();
    final removedList = roster.overrides.where((o) {
      return staffNames.contains(o.personName) &&
          normalizedDates.any((d) =>
              d.year == o.date.year &&
              d.month == o.date.month &&
              d.day == o.date.day);
    }).toList();
    final preview = normalizedDates
        .take(5)
        .map((d) => DateFormat('EEE d MMM').format(d))
        .join(', ');
    final suffix = normalizedDates.length > 5 ? '...' : '';
    _confirmAction(
      context,
      title: 'Clear changes',
      message:
          'Remove changes for ${staffNames.join(', ')} on ${normalizedDates.length} date(s) '
          '($preview$suffix)?',
      onConfirm: () {
        final removed = roster.removeOverridesForDates(
          people: staffNames,
          dates: normalizedDates,
        );
        if (removed == 0) {
          _respondWithRC(context, 'No changes were removed.');
        } else {
          _respondWithRC(context, 'Removed $removed change(s).');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Changes removed.'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () {
                  for (final o in removedList) {
                    roster.setOverride(
                      o.personName,
                      o.date,
                      o.shift,
                      o.reason ?? 'Restored change',
                    );
                  }
                },
              ),
            ),
          );
        }
      },
    );
  }

  void _handleRemoveLeaveCommand(
    BuildContext context,
    String raw, {
    String? fallbackStaff,
  }) {
    final roster = ref.read(rosterProvider);
    if (roster.readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read-only roster cannot be edited.')),
      );
      return;
    }
    final text = _normalizeCommand(raw);
    final staffNames = _matchAllStaffNames(text, roster);
    if (staffNames.isEmpty && fallbackStaff != null) {
      staffNames.add(fallbackStaff);
    }
    if (staffNames.isEmpty) {
      _respondWithRC(context, 'Which staff member should I cancel leave for?');
      _contextState.remember(action: 'cancel_leave');
      return;
    }

    var dates = _extractDatesForOverride(raw, roster.weekStartDay);
    final range = _extractDateRangeFromText(text, roster.weekStartDay);
    if (dates.isEmpty && range == null) {
      final fallbackDates = _extractAllDatesFromText(text);
      if (fallbackDates.isNotEmpty) {
        dates = fallbackDates;
      }
    }

    final suggestedDates = <DateTime>{};
    if (range != null) {
      var cursor = DateTime(range.start.year, range.start.month, range.start.day);
      final end = DateTime(range.end.year, range.end.month, range.end.day);
      while (!cursor.isAfter(end)) {
        suggestedDates.add(cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
    } else {
      suggestedDates.addAll(
        dates.map((d) => DateTime(d.year, d.month, d.day)),
      );
    }

    _contextState.remember(action: 'cancel_leave', staff: staffNames.first);
    _showCancelLeaveCalendar(
      context,
      staffNames,
      initialSelectedDates: suggestedDates.toList(),
      initialRange: range,
    );
  }

  Future<void> _showCancelLeaveCalendar(
    BuildContext context,
    List<String> staffNames,
    {List<DateTime> initialSelectedDates = const [],
    _DateRange? initialRange}
  ) async {
    final roster = ref.read(rosterProvider);
    DateTime selected = DateTime.now();
    final selectedDates = <DateTime>{};
    final monthKey = ValueNotifier<int>(
      DateTime.now().year * 100 + DateTime.now().month,
    );
    if (initialSelectedDates.isNotEmpty) {
      for (final d in initialSelectedDates) {
        selectedDates.add(DateTime(d.year, d.month, d.day));
      }
      selected = initialSelectedDates.first;
    }
    final years = List.generate(9, (i) => DateTime.now().year - 4 + i);
    int selectedYear = selected.year;
    int selectedMonth = selected.month;
    bool applyToAll = staffNames.length > 1;
    bool onlyShowMatching = true;
    bool selectAllTypes = false;
    final selectedTypes = <String>{'AL'};

    Map<String, Set<DateTime>> buildAlDates(List<String> names) {
      final map = <String, Set<DateTime>>{};
      for (final name in names) {
        map[name] = <DateTime>{};
      }
      for (final o in roster.overrides) {
        if (o.shift.toUpperCase() != 'AL') continue;
        if (!names.contains(o.personName)) continue;
        map[o.personName]!.add(DateTime(o.date.year, o.date.month, o.date.day));
      }
      return map;
    }

    Set<DateTime> alDatesForStaff(List<String> names) {
      final map = buildAlDates(names);
      final all = <DateTime>{};
      for (final set in map.values) {
        all.addAll(set);
      }
      return all;
    }

    Set<String> availableChangeTypes(List<String> names) {
      final types = <String>{};
      for (final o in roster.overrides) {
        if (!names.contains(o.personName)) continue;
        types.add(o.shift.toUpperCase());
      }
      for (final staff in roster.staffMembers) {
        if (!names.contains(staff.name)) continue;
        if (staff.leaveType == 'secondment') types.add('SECONDMENT');
        if (staff.leaveType == 'sick') types.add('SICK');
        if (staff.leaveType == 'annual') types.add('AL');
      }
      return types..removeWhere((t) => t.trim().isEmpty);
    }

    bool hasMatchingChange(
      List<String> names,
      DateTime date,
      Set<String> types,
    ) {
      if (types.contains('ANY')) return true;
      final normalized = types.map((t) => t.toUpperCase()).toSet();
      final overrideMatch = roster.overrides.any((o) {
        if (!names.contains(o.personName)) return false;
        if (o.date.year != date.year ||
            o.date.month != date.month ||
            o.date.day != date.day) return false;
        final shift = o.shift.toUpperCase();
        if (normalized.contains(shift)) return true;
        if (normalized.contains('SICK') && (shift == 'SICK' || shift == 'ILL')) {
          return true;
        }
        return false;
      });
      if (overrideMatch) return true;
      // Also match against staff leave ranges (annual/sick/secondment) set via staff status.
      for (final staff in roster.staffMembers) {
        if (!names.contains(staff.name)) continue;
        if (staff.leaveStart == null || staff.leaveEnd == null) continue;
        final start = DateTime(
          staff.leaveStart!.year,
          staff.leaveStart!.month,
          staff.leaveStart!.day,
        );
        final end = DateTime(
          staff.leaveEnd!.year,
          staff.leaveEnd!.month,
          staff.leaveEnd!.day,
        );
        if (date.isBefore(start) || date.isAfter(end)) continue;
        final leaveType = (staff.leaveType ?? '').toUpperCase();
        if (normalized.contains('AL') &&
            (leaveType == 'ANNUAL' || leaveType == 'AL')) {
          return true;
        }
        if (normalized.contains('SICK') && leaveType == 'SICK') return true;
        if (normalized.contains('SECONDMENT') && leaveType == 'SECONDMENT') {
          return true;
        }
      }
    return false;
  }


    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final activeStaff = applyToAll ? staffNames : [staffNames.first];
          final alDates = alDatesForStaff(activeStaff);
          final changeTypes = availableChangeTypes(activeStaff);
          if (selectAllTypes) {
            selectedTypes
              ..clear()
              ..addAll(changeTypes)
              ..add('ANY');
          }
          int alSelected = selectedDates
              .where((d) => hasMatchingChange(activeStaff, d, selectedTypes))
              .length;
          int noAlSelected = selectedDates.length - alSelected;
          return AlertDialog(
            title: const Text('Cancel Annual Leave'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (staffNames.length > 1)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: applyToAll,
                      onChanged: (value) => setState(() => applyToAll = value),
                      title: const Text('Apply to all selected staff'),
                      subtitle: Text(applyToAll
                          ? staffNames.join(', ')
                          : staffNames.first),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: selectedMonth,
                          decoration:
                              const InputDecoration(labelText: 'Month'),
                          items: List.generate(
                            12,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text(DateFormat('MMMM')
                                  .format(DateTime(2024, i + 1, 1))),
                            ),
                          ),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              selectedMonth = value;
                              selected = DateTime(selectedYear, selectedMonth, 1);
                              monthKey.value =
                                  selectedYear * 100 + selectedMonth;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: selectedYear,
                          decoration: const InputDecoration(labelText: 'Year'),
                          items: years
                              .map((y) => DropdownMenuItem(
                                    value: y,
                                    child: Text(y.toString()),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              selectedYear = value;
                              selected = DateTime(selectedYear, selectedMonth, 1);
                              monthKey.value =
                                  selectedYear * 100 + selectedMonth;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('All changes'),
                        selected: selectAllTypes,
                        onSelected: (value) {
                          setState(() {
                            selectAllTypes = value;
                            if (!selectAllTypes) {
                              selectedTypes.remove('ANY');
                            }
                          });
                        },
                      ),
                      ...changeTypes.map((type) {
                        final selected = selectedTypes.contains(type);
                        final label = type == 'AL'
                            ? 'Annual Leave'
                            : type == 'SICK'
                                ? 'Sick'
                                : type == 'SECONDMENT'
                                    ? 'Secondment'
                                    : _shiftLabel(type);
                        return FilterChip(
                          label: Text(label),
                          selected: selected,
                          onSelected: (value) {
                            setState(() {
                              if (value) {
                                selectedTypes.add(type);
                              } else {
                                selectedTypes.remove(type);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<int>(
                    valueListenable: monthKey,
                    builder: (context, key, _) => CalendarDatePicker(
                      key: ValueKey(key),
                      initialDate: selected,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 3650)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 3650)),
                      selectableDayPredicate: (date) {
                        if (!onlyShowMatching) return true;
                        return hasMatchingChange(
                          activeStaff,
                          DateTime(date.year, date.month, date.day),
                          selectedTypes,
                        );
                      },
                      onDateChanged: (date) {
                        selected = date;
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          final picked = DateTime(
                              selected.year, selected.month, selected.day);
                          if (onlyShowMatching &&
                              !hasMatchingChange(
                                activeStaff,
                                picked,
                                selectedTypes,
                              )) {
                            _respondWithRC(
                              context,
                              'No matching change on ${DateFormat('MMM d').format(picked)}.',
                            );
                            return;
                          }
                          setState(() => selectedDates.add(picked));
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add date'),
                      ),
                      const SizedBox(width: 8),
                      Text('${selectedDates.length} selected'),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: onlyShowMatching,
                    onChanged: (value) =>
                        setState(() => onlyShowMatching = value),
                    title: const Text('Only allow dates with matching changes'),
                  ),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          final start = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now()
                                .subtract(const Duration(days: 3650)),
                            lastDate:
                                DateTime.now().add(const Duration(days: 3650)),
                          );
                          if (start == null) return;
                          final end = await showDatePicker(
                            context: context,
                            initialDate: start,
                            firstDate: start,
                            lastDate:
                                DateTime.now().add(const Duration(days: 3650)),
                          );
                          if (end == null) return;
                          final startDay =
                              DateTime(start.year, start.month, start.day);
                          final endDay =
                              DateTime(end.year, end.month, end.day);
                          var cursor = startDay;
                          while (!cursor.isAfter(endDay)) {
                            if (!onlyShowMatching ||
                                hasMatchingChange(
                                  activeStaff,
                                  cursor,
                                  selectedTypes,
                                )) {
                              selectedDates.add(cursor);
                            }
                            cursor = cursor.add(const Duration(days: 1));
                          }
                          setState(() {});
                        },
                        child: const Text('Select AL in range'),
                      ),
                      const SizedBox(width: 8),
                      Text('Selected: $alSelected'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 90,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: selectedDates
                          .map(
                            (d) => Chip(
                              label: Text(DateFormat('MMM d').format(d)),
                              onDeleted: () {
                                setState(() => selectedDates.remove(d));
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Will remove $alSelected matching change(s). '
                    '${noAlSelected > 0 ? '$noAlSelected selected date(s) have no matching change.' : ''}',
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 90,
                    child: ListView(
                      children: selectedDates
                          .map((d) {
                            final hasMatch =
                                hasMatchingChange(activeStaff, d, selectedTypes);
                            final baseShift =
                                roster.getBaseShiftForDate(
                              activeStaff.first,
                              d,
                            );
                            return Text(
                              '${DateFormat('EEE MMM d').format(d)} '
                              '- ${hasMatch ? 'Matching change' : 'No match'} '
                              '(base: ${_shiftLabel(baseShift)})',
                            );
                          })
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    if (selectedDates.isEmpty) {
      _respondWithRC(context, 'No dates selected.');
      return;
    }
    final applyStaff = applyToAll ? staffNames : [staffNames.first];
    final dates = selectedDates.toList()..sort();
    final types = selectAllTypes ? <String>{'ANY'} : selectedTypes;
    final normalizedTypes = types.map((t) => t.toUpperCase()).toSet();

    final removedOverrides = roster.overrides
        .where((o) =>
            applyStaff.contains(o.personName) &&
            dates.any((d) =>
                d.year == o.date.year &&
                d.month == o.date.month &&
                d.day == o.date.day) &&
            (normalizedTypes.contains('ANY') ||
                normalizedTypes.contains(o.shift.toUpperCase())))
        .toList();

    // Track additional AL dates removed from staff leave status for undo.
    final removedAlFromStatus = <models.Override>[];
    if (normalizedTypes.contains('ANY') || normalizedTypes.contains('AL')) {
      for (final name in applyStaff) {
        final staff =
            roster.staffMembers.where((s) => s.name == name).firstOrNull;
        if (staff == null) continue;
        if (staff.leaveStart == null || staff.leaveEnd == null) continue;
        final leaveType = (staff.leaveType ?? '').toUpperCase();
        if (leaveType != 'ANNUAL' && leaveType != 'AL') continue;
        final start = DateTime(
          staff.leaveStart!.year,
          staff.leaveStart!.month,
          staff.leaveStart!.day,
        );
        final end = DateTime(
          staff.leaveEnd!.year,
          staff.leaveEnd!.month,
          staff.leaveEnd!.day,
        );
        for (final d in dates) {
          if (d.isBefore(start) || d.isAfter(end)) continue;
          removedAlFromStatus.add(
            models.Override(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              personName: name,
              date: d,
              shift: 'AL',
              reason: 'Annual leave',
              createdAt: DateTime.now(),
            ),
          );
        }
      }
    }

    int removed = 0;
    if (normalizedTypes.contains('ANY') || normalizedTypes.contains('AL')) {
      removed += roster.cancelAnnualLeaveForDates(
        people: applyStaff,
        dates: dates,
      );
    }
    final nonLeaveTypes = normalizedTypes
        .where((t) => t != 'AL' && t != 'ANY')
        .toSet();
    if (nonLeaveTypes.isNotEmpty) {
      removed += roster.removeOverridesForDatesByShifts(
        people: applyStaff,
        dates: dates,
        shifts: nonLeaveTypes,
      );
    }
    if (removed == 0) {
      _respondWithRC(context, 'No matching changes were removed.');
    } else {
      _respondWithRC(
        context,
        'Cancelled $removed change(s).',
      );
      final undoList = [...removedOverrides, ...removedAlFromStatus];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Changes cancelled.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              for (final o in undoList) {
                roster.setOverride(
                  o.personName,
                  o.date,
                  o.shift,
                  o.reason ?? 'Restored change',
                );
              }
            },
          ),
        ),
      );
    }
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
        date = parsed.date;
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

  List<DateTime> _extractAllDatesFromText(
    String text, {
    bool monthFirst = false,
  }) {
    var lowered = text.toLowerCase();
    lowered = _normalizeOrdinalText(lowered);
    lowered = lowered.replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ');
    lowered = lowered.replaceAll(RegExp(r'\\s+'), ' ').trim();
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
        RegExp(r'(\\d{1,2})[/-](\\d{1,2})[/-](\\d{2,4})').allMatches(lowered);
    for (final match in slashMatches) {
      final rawYear = int.parse(match.group(3)!);
      final year = rawYear < 100 ? 2000 + rawYear : rawYear;
      final a = int.parse(match.group(1)!);
      final b = int.parse(match.group(2)!);
      final month = monthFirst ? a : b;
      final day = monthFirst ? b : a;
      dates.add(DateTime(year, month, day));
    }
    final shortSlashMatches =
        RegExp(r'(\\d{1,2})[/-](\\d{1,2})\\b').allMatches(lowered);
    for (final match in shortSlashMatches) {
      final a = int.parse(match.group(1)!);
      final b = int.parse(match.group(2)!);
      int day = a;
      int month = b;
      if (a <= 12 && b > 12) {
        month = a;
        day = b;
      }
      dates.add(DateTime(today.year, month, day));
    }

    final monthNames = {
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    final monthPattern =
        '(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';
    final dayMonthMatches = RegExp(
      r'(\\d{1,2})(?:st|nd|rd|th)?(?:\\s+of)?\\s*' +
          monthPattern +
          r'(?:\\s*(\\d{2,4}))?',
    ).allMatches(lowered);
    for (final match in dayMonthMatches) {
      final day = int.parse(match.group(1)!);
      final monthKey = match.group(2)!;
      final month = monthNames[monthKey]!;
      int year = today.year;
      if (match.group(3) != null) {
        final rawYear = int.parse(match.group(3)!);
        year = rawYear < 100 ? 2000 + rawYear : rawYear;
      }
      dates.add(DateTime(year, month, day));
    }
    final compactDayMonthMatches = RegExp(
      r'(\\d{1,2})(?:st|nd|rd|th)?' +
          monthPattern +
          r'(\\d{2,4})?',
    ).allMatches(lowered);
    for (final match in compactDayMonthMatches) {
      final day = int.parse(match.group(1)!);
      final monthKey = match.group(2)!;
      final month = monthNames[monthKey]!;
      int year = today.year;
      if (match.group(3) != null) {
        final rawYear = int.parse(match.group(3)!);
        year = rawYear < 100 ? 2000 + rawYear : rawYear;
      }
      dates.add(DateTime(year, month, day));
    }

    final monthDayMatches = RegExp(
      monthPattern +
          r'\\s*(\\d{1,2})(?:st|nd|rd|th)?(?:\\s*(\\d{2,4}))?',
    ).allMatches(lowered);
    for (final match in monthDayMatches) {
      final day = int.parse(match.group(2)!);
      final monthKey = match.group(1)!;
      final month = monthNames[monthKey]!;
      int year = today.year;
      if (match.group(3) != null) {
        final rawYear = int.parse(match.group(3)!);
        year = rawYear < 100 ? 2000 + rawYear : rawYear;
      }
      dates.add(DateTime(year, month, day));
    }
    final compactMonthDayMatches = RegExp(
      monthPattern + r'(\\d{1,2})(?:st|nd|rd|th)?(\\d{2,4})?',
    ).allMatches(lowered);
    for (final match in compactMonthDayMatches) {
      final day = int.parse(match.group(2)!);
      final monthKey = match.group(1)!;
      final month = monthNames[monthKey]!;
      int year = today.year;
      if (match.group(3) != null) {
        final rawYear = int.parse(match.group(3)!);
        year = rawYear < 100 ? 2000 + rawYear : rawYear;
      }
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
            start: _startOfDay(start.date),
            end: _startOfDay(end.date),
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

  _ParsedDate? _parseDateFromText(
    String text, {
    bool monthFirst = false,
  }) {
    var lowered = text.toLowerCase();
    lowered = _normalizeOrdinalText(lowered);
    lowered = lowered.replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ');
    lowered = lowered.replaceAll(RegExp(r'\\s+'), ' ').trim();
    final today = DateTime.now();
    if (lowered.contains('today')) {
      return _ParsedDate(DateTime(today.year, today.month, today.day), 1.0);
    }
    if (lowered.contains('tomorrow')) {
      final tomorrow = today.add(const Duration(days: 1));
      return _ParsedDate(
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
        1.0,
      );
    }
    if (lowered.contains('yesterday')) {
      final yesterday = today.subtract(const Duration(days: 1));
      return _ParsedDate(
        DateTime(yesterday.year, yesterday.month, yesterday.day),
        1.0,
      );
    }
    final isoMatch = RegExp(r'(\\d{4})-(\\d{2})-(\\d{2})').firstMatch(lowered);
    if (isoMatch != null) {
      return _ParsedDate(
        DateTime(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
        ),
        1.0,
      );
    }
    final slashMatch =
        RegExp(r'(\\d{1,2})[/-](\\d{1,2})[/-](\\d{2,4})').firstMatch(lowered);
    if (slashMatch != null) {
      final rawYear = int.parse(slashMatch.group(3)!);
      final year = rawYear < 100 ? 2000 + rawYear : rawYear;
      final a = int.parse(slashMatch.group(1)!);
      final b = int.parse(slashMatch.group(2)!);
      final month = monthFirst ? a : b;
      final day = monthFirst ? b : a;
      final confidence = (a <= 12 && b <= 12) ? 0.6 : 1.0;
      return _ParsedDate(DateTime(year, month, day), confidence);
    }
    final shortSlashMatch =
        RegExp(r'(\\d{1,2})[/-](\\d{1,2})\\b').firstMatch(lowered);
    if (shortSlashMatch != null) {
      final a = int.parse(shortSlashMatch.group(1)!);
      final b = int.parse(shortSlashMatch.group(2)!);
      final now = DateTime.now();
      int day = a;
      int month = b;
      if (a <= 12 && b > 12) {
        month = a;
        day = b;
      }
      return _ParsedDate(DateTime(now.year, month, day), 0.6);
    }
    final monthNames = {
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    final monthPattern =
        '(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';
    final match = RegExp(
      r'(\\d{1,2})(?:st|nd|rd|th)?(?:\\s+of)?\\s*' +
          monthPattern +
          r'(?:\\s*(\\d{2,4}))?',
    ).firstMatch(lowered);
    if (match != null) {
      final day = int.parse(match.group(1)!);
      final monthKey = match.group(2)!;
      final month = monthNames[monthKey]!;
      int year = DateTime.now().year;
      if (match.group(3) != null) {
        final rawYear = int.parse(match.group(3)!);
        year = rawYear < 100 ? 2000 + rawYear : rawYear;
      }
      return _ParsedDate(DateTime(year, month, day), 1.0);
    }
    final compactMatch = RegExp(
      r'(\\d{1,2})(?:st|nd|rd|th)?' + monthPattern + r'(\\d{2,4})?',
    ).firstMatch(lowered);
    if (compactMatch != null) {
      final day = int.parse(compactMatch.group(1)!);
      final monthKey = compactMatch.group(2)!;
      final month = monthNames[monthKey]!;
      int year = DateTime.now().year;
      if (compactMatch.group(3) != null) {
        final rawYear = int.parse(compactMatch.group(3)!);
        year = rawYear < 100 ? 2000 + rawYear : rawYear;
      }
      return _ParsedDate(DateTime(year, month, day), 1.0);
    }
    final reverseMatch = RegExp(
      monthPattern +
          r'\\s*(\\d{1,2})(?:st|nd|rd|th)?(?:\\s*(\\d{2,4}))?',
    ).firstMatch(lowered);
    if (reverseMatch != null) {
      final day = int.parse(reverseMatch.group(2)!);
      final monthKey = reverseMatch.group(1)!;
      final month = monthNames[monthKey]!;
      int year = DateTime.now().year;
      if (reverseMatch.group(3) != null) {
        final rawYear = int.parse(reverseMatch.group(3)!);
        year = rawYear < 100 ? 2000 + rawYear : rawYear;
      }
      return _ParsedDate(DateTime(year, month, day), 1.0);
    }
    final reverseCompactMatch = RegExp(
      monthPattern + r'(\\d{1,2})(?:st|nd|rd|th)?(\\d{2,4})?',
    ).firstMatch(lowered);
    if (reverseCompactMatch != null) {
      final day = int.parse(reverseCompactMatch.group(2)!);
      final monthKey = reverseCompactMatch.group(1)!;
      final month = monthNames[monthKey]!;
      int year = DateTime.now().year;
      if (reverseCompactMatch.group(3) != null) {
        final rawYear = int.parse(reverseCompactMatch.group(3)!);
        year = rawYear < 100 ? 2000 + rawYear : rawYear;
      }
      return _ParsedDate(DateTime(year, month, day), 1.0);
    }
    return null;
  }


  List<DateTime> _extractDatesForOverride(String text, int weekStartDay) {
    var lowered = text.toLowerCase();
    lowered = _normalizeOrdinalText(lowered);
    lowered = lowered.replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ');
    lowered = lowered.replaceAll(RegExp(r'\\s+'), ' ').trim();
    final dates = <DateTime>{};

    final explicit = _parseDateFromText(lowered);
    if (explicit != null) {
      dates.add(DateTime(
        explicit.date.year,
        explicit.date.month,
        explicit.date.day,
      ));
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

  void _clearExpiredPendingContext() {
    final created = _contextState.pendingCreatedAt;
    if (created == null) return;
    final now = DateTime.now();
    if (now.difference(created) > const Duration(minutes: 3)) {
      _contextState.remember(
        action: '',
        pendingStaff: '',
        pendingShift: '',
        pendingDates: const [],
      );
    }
  }

  String _pendingSummary() {
    final staff = _contextState.pendingStaff ?? _contextState.lastStaff ?? '';
    final shift = _contextState.pendingShift ?? _contextState.lastShift ?? '';
    final dates = _contextState.pendingDates ?? [];
    final dateLabel = dates.isNotEmpty
        ? dates.take(3).map((d) => DateFormat('MMM d').format(d)).join(', ')
        : 'date?';
    final shiftLabel = shift.isEmpty ? 'shift?' : _shiftLabelWithCode(shift);
    return 'Pending: ${staff.isEmpty ? 'staff?' : staff} · $dateLabel · $shiftLabel';
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
            SafeTextField(
              controller: staffController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of staff',
              ),
            ),
            const SizedBox(height: 12),
            SafeTextField(
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

    final parsedDate = _parseDateFromText(text);
    final date = parsedDate?.date ?? DateTime.now();
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
            SafeTextField(
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
