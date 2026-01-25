import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'shift_swap_widgets.dart';
import 'ai_suggestions_view.dart';
import 'activity_log_view.dart';
import 'roster_generator_view.dart';
import 'daily_ops_view.dart';

class RosterToolsView extends ConsumerStatefulWidget {
  const RosterToolsView({super.key});

  @override
  ConsumerState<RosterToolsView> createState() => _RosterToolsViewState();
}

class _RosterToolsViewState extends ConsumerState<RosterToolsView> {
  bool _isAnalyzing = false;

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final suggestions = roster.aiSuggestions;

    final conflicts = roster.syncConflicts;
    final canEdit = roster.activeRoster?.role != 'staff';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle(context, 'Roster Building & Editing'),
        const SizedBox(height: 8),
        _buildActionCard(
          context,
          title: 'Auto Roster Generator',
          subtitle: 'Answer a few questions to generate a roster template.',
          icon: Icons.auto_awesome,
          onTap: canEdit
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (ctx) => const RosterGeneratorView()),
                  )
              : null,
        ),
        _buildActionCard(
          context,
          title: 'Daily Ops',
          subtitle: 'Handle coverage gaps, swaps, and daily fixes.',
          icon: Icons.rule_folder,
          onTap: canEdit
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (ctx) => const DailyOpsView()),
                  )
              : null,
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.event_repeat),
            title: const Text('Week Commencing'),
            subtitle: const Text('Set the first day of the roster week.'),
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: roster.weekStartDay,
                items: roster.weekDayLabels
                    .asMap()
                    .entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: canEdit ? (value) => roster.setWeekStartDay(value!) : null,
              ),
            ),
          ),
        ),
        _buildActionCard(
          context,
          title: 'Align Roster (Offset)',
          subtitle: 'Shift the pattern by days or weeks before propagating.',
          icon: Icons.swap_vert,
          onTap: canEdit ? () => _showAlignDialog(context, roster) : null,
        ),
        _buildActionCard(
          context,
          title: 'Propagate Master Pattern',
          subtitle: 'Apply the current pattern to future cycles.',
          icon: Icons.auto_fix_high,
          onTap: canEdit
              ? () async {
                  roster.propagatePattern();
                  _showSnack(context, 'Pattern propagated.');
                }
              : null,
        ),
        _buildActionCard(
          context,
          title: 'Analyze & Recognize Pattern',
          subtitle: 'Scan existing shifts to detect repeating patterns.',
          icon: Icons.analytics,
          loading: _isAnalyzing,
          onTap: _isAnalyzing || !canEdit
              ? null
              : () async {
                  setState(() => _isAnalyzing = true);
                  try {
                    final result =
                        await roster.analyzeAndRecognizePattern();
                    if (!mounted) return;
                    _showPatternResult(context, result);
                  } finally {
                    if (mounted) {
                      setState(() => _isAnalyzing = false);
                    }
                  }
                },
        ),
        _buildActionCard(
          context,
          title: 'Generate AI Suggestions',
          subtitle: 'Get AI recommendations for roster improvements.',
          icon: Icons.psychology,
          onTap: canEdit
              ? () async {
                  await roster.generateAiSuggestions();
                  _showSnack(context, 'AI suggestions updated.');
                }
              : null,
        ),
        _buildActionCard(
          context,
          title: 'Sync with Cloud',
          subtitle: roster.activeRoster?.source == 'cloud'
              ? 'Sync roster data with Supabase.'
              : 'Cloud sync available for signed-in users.',
          icon: Icons.cloud_sync,
          onTap: roster.activeRoster?.source == 'cloud'
              ? () async {
                  await roster.syncWithCloud();
                  _showSnack(context, 'Sync complete.');
                }
              : null,
        ),
        _buildActionCard(
          context,
          title: 'Activity Log',
          subtitle: 'View recent changes and access activity.',
          icon: Icons.history,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (ctx) => const ActivityLogView()),
          ),
        ),
        _buildActionCard(
          context,
          title: 'Export Calendar (.ics)',
          subtitle: 'Generate a calendar file for the next 30 days.',
          icon: Icons.calendar_month,
          onTap: () async {
            final path = await roster.exportCalendarIcs();
            _showSnack(context, 'Calendar exported to $path');
          },
        ),
        _buildActionCard(
          context,
          title: 'Manage Regular Shift Swaps',
          subtitle: 'Create recurring swaps between staff members.',
          icon: Icons.swap_horiz,
          onTap: canEdit
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (ctx) => const RegularSwapsScreen()),
                  )
              : null,
        ),
        _buildActionCard(
          context,
          title: 'Bulk Edit',
          subtitle: 'Apply the same change across multiple days.',
          icon: Icons.edit_calendar,
          onTap: canEdit ? () => _showSnack(context, 'Bulk edit coming soon.') : null,
        ),
        const SizedBox(height: 20),
        if (conflicts.isNotEmpty) ...[
          _buildSectionTitle(context, 'Sync Conflicts'),
          const SizedBox(height: 8),
          ...conflicts.map(
            (conflict) => Card(
              child: ListTile(
                title: Text(conflict.reason),
                subtitle: Text(
                    conflict.detectedAt.toLocal().toString().substring(0, 16)),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () =>
                          roster.resolveConflict(conflict, keepLocal: true),
                      child: const Text('Keep Local'),
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          roster.resolveConflict(conflict, keepLocal: false),
                      child: const Text('Use Cloud'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        _buildSectionTitle(context, 'AI Recommendations'),
        const SizedBox(height: 8),
        if (suggestions.isEmpty)
          const Text('No AI recommendations yet.')
        else
          ...suggestions.take(3).map(
                (suggestion) => ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: Text(suggestion.title),
                  subtitle: Text(suggestion.description),
                ),
              ),
        if (suggestions.length > 3)
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (ctx) => const AiSuggestionsView()),
            ),
            child: const Text('View all suggestions'),
          ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge,
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    bool loading = false,
    VoidCallback? onTap,
  }) {
    return Card(
      child: ListTile(
        leading: loading
            ? const CircularProgressIndicator()
            : Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showPatternResult(BuildContext context, dynamic result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pattern Recognition'),
        content: Text(
          'Detected cycle length: ${result.detectedCycleLength}\n'
          'Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(rosterProvider.notifier)
                  .applyRecognizedPattern(result);
              if (mounted) Navigator.of(ctx).pop();
              _showSnack(context, 'Recognized pattern applied.');
            },
            child: const Text('Apply Pattern'),
          ),
        ],
      ),
    );
  }

  void _showAlignDialog(BuildContext context, RosterNotifier roster) {
    int dayOffset = 0;
    int weekOffset = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Align Roster Pattern'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOffsetRow(
                label: 'Day offset',
                value: dayOffset,
                onChanged: (value) => setState(() => dayOffset = value),
              ),
              const SizedBox(height: 12),
              _buildOffsetRow(
                label: 'Week offset',
                value: weekOffset,
                onChanged: (value) => setState(() => weekOffset = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                roster.offsetMasterPattern(
                  dayOffset: dayOffset,
                  weekOffset: weekOffset,
                );
                Navigator.of(ctx).pop();
                _showSnack(context, 'Pattern aligned.');
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffsetRow({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => onChanged(value - 1),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toString(),
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => onChanged(value + 1),
        ),
      ],
    );
  }
}
