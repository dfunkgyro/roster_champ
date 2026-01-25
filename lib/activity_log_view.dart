import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart' as models;
import 'providers.dart';
import 'services/diagnostic_service.dart';

class ActivityLogView extends ConsumerWidget {
  const ActivityLogView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(activityLogProvider).entries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Log'),
        actions: [
          TextButton(
            onPressed: () async {
              final report = await DiagnosticService.instance.buildReport();
              await Clipboard.setData(ClipboardData(text: report));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Diagnostic report copied'),
                  ),
                );
              }
            },
            child: const Text('Copy Report'),
          ),
          TextButton(
            onPressed: () =>
                ref.read(activityLogProvider).clear(),
            child: const Text('Clear'),
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(child: Text('No activity yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = logs[index];
                return Card(
                  child: ListTile(
                    onTap: entry.details == null || entry.details!.isEmpty
                        ? null
                        : () => _showDetails(context, entry),
                    leading: Icon(
                      _iconForLevel(entry.level),
                      color: _colorForLevel(entry.level),
                    ),
                    title: Text(entry.message),
                    subtitle: entry.fixes.isNotEmpty
                        ? Text('Fix: ${entry.fixes.join(' • ')}')
                        : Text(_formatDate(entry.timestamp)),
                    trailing: entry.details != null && entry.details!.isNotEmpty
                        ? const Icon(Icons.bug_report_outlined)
                        : Text(_formatDate(entry.timestamp)),
                  ),
                );
              },
            ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showDetails(BuildContext context, models.ActivityLogEntry entry) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Diagnostics'),
        content: SingleChildScrollView(
          child: Text(_buildDetails(entry)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _buildDetails(models.ActivityLogEntry entry) {
    final buffer = StringBuffer();
    buffer.writeln(entry.message);
    if (entry.details != null && entry.details!.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln(entry.details);
    }
    if (entry.fixes.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('Fixes: ${entry.fixes.join(" | ")}');
    }
    buffer.writeln('');
    buffer.writeln('Time: ${entry.timestamp.toIso8601String()}');
    return buffer.toString();
  }

  IconData _iconForLevel(models.ActivityLogLevel level) {
    switch (level) {
      case models.ActivityLogLevel.info:
        return Icons.info_outline;
      case models.ActivityLogLevel.warning:
        return Icons.warning_amber;
      case models.ActivityLogLevel.error:
        return Icons.error_outline;
    }
  }

  Color _colorForLevel(models.ActivityLogLevel level) {
    switch (level) {
      case models.ActivityLogLevel.info:
        return Colors.blueGrey;
      case models.ActivityLogLevel.warning:
        return Colors.orange;
      case models.ActivityLogLevel.error:
        return Colors.red;
    }
  }
}
