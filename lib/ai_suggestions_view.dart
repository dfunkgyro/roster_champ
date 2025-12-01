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
      itemCount: sortedSuggestions.length,
      itemBuilder: (context, index) {
        final suggestion = sortedSuggestions[index];
        return _SuggestionCard(suggestion: suggestion);
      },
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  final models.AiSuggestion suggestion;

  const _SuggestionCard({required this.suggestion});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priorityColor = _getPriorityColor(suggestion.priority);

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
                  if (suggestion.actionType != null) const SizedBox(width: 8),
                  if (suggestion.actionType != null)
                    FilledButton.icon(
                      onPressed: () => _applySuggestion(context, ref),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Apply'),
                    ),
                ],
              ),
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
          if (suggestion.actionType != null)
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
          'This would apply the suggestion: ${suggestion.title}\n\n'
          'Note: This is a placeholder. Implement specific actions based on actionType.',
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
      // TODO: Implement specific action based on suggestion.actionType
      ref.read(rosterProvider).dismissSuggestion(suggestion.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suggestion applied')),
      );
    }
  }
}
