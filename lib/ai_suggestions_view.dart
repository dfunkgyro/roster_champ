import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'providers.dart';
import 'models.dart' as models;

class AiSuggestionsView extends ConsumerWidget {
  const AiSuggestionsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(rosterProvider);
    final suggestions = roster.aiSuggestions;

    if (suggestions.isEmpty) {
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

    final sortedSuggestions = List<models.AiSuggestion>.from(suggestions)
      ..sort((a, b) {
        if (a.isRead != b.isRead) return a.isRead ? 1 : -1;
        return b.priority.index.compareTo(a.priority.index);
      });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedSuggestions.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ScenarioImpactCard(
            suggestions: sortedSuggestions,
          );
        }
        final suggestion = sortedSuggestions[index - 1];
        return _SuggestionCard(suggestion: suggestion);
      },
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
