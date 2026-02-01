import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'aws_service.dart';

class AnalyticsView extends ConsumerWidget {
  const AnalyticsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider);
    final settings = ref.watch(settingsProvider);
    final events = analytics.events;
    final total = events.length;
    final last24h = analytics.countSince(const Duration(hours: 24));
    final last7d = analytics.countSince(const Duration(days: 7));
    final lastUpload = _lastUploadTime(events);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOverviewCard(
          context,
          total: total,
          last24h: last24h,
          last7d: last7d,
          lastUpload: lastUpload,
        ),
        const SizedBox(height: 16),
        _buildTopEventsCard(context, analytics),
        const SizedBox(height: 16),
        _buildCloudStatusCard(context, settings),
        const SizedBox(height: 16),
        _buildRecentEventsCard(context, events),
      ],
    );
  }

  DateTime? _lastUploadTime(List<dynamic> events) {
    DateTime? last;
    for (final event in events) {
      final uploadedAt = event.uploadedAt;
      if (uploadedAt != null &&
          (last == null || uploadedAt.isAfter(last))) {
        last = uploadedAt;
      }
    }
    return last;
  }

  Widget _buildOverviewCard(
    BuildContext context, {
    required int total,
    required int last24h,
    required int last7d,
    required DateTime? lastUpload,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Analytics Overview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _statRow(context, 'Total Events', '$total'),
            _statRow(context, 'Last 24h', '$last24h'),
            _statRow(context, 'Last 7 days', '$last7d'),
            _statRow(
              context,
              'Last Upload',
              lastUpload == null
                  ? 'Not yet synced'
                  : '${lastUpload.toLocal().toString().substring(0, 16)}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopEventsCard(BuildContext context, dynamic analytics) {
    final top = analytics.getTopEvents(limit: 6);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.trending_up,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Top Events',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (top.isEmpty)
              const Text('No analytics data yet')
            else
              ...top.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _statRow(context, entry.key, entry.value.toString()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudStatusCard(
    BuildContext context,
    dynamic settings,
  ) {
    final enabled = settings.analyticsEnabled;
    final cloud = settings.analyticsCloudEnabled;
    final awsReady =
        AwsService.instance.isConfigured && AwsService.instance.isAuthenticated;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_done,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Cloud Analytics',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _statRow(
              context,
              'Local Tracking',
              enabled ? 'Enabled' : 'Disabled',
            ),
            _statRow(
              context,
              'Cloud Upload',
              cloud ? 'Enabled' : 'Disabled',
            ),
            _statRow(
              context,
              'AWS Status',
              awsReady ? 'Ready' : 'Not connected',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentEventsCard(
    BuildContext context,
    List<dynamic> events,
  ) {
    final recent = events.reversed.take(30).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.list_alt,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recent Events',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recent.isEmpty)
              const Text('No events recorded yet')
            else
              ...recent.map(
                (event) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${event.name} · ${event.type}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        event.timestamp
                            .toLocal()
                            .toString()
                            .substring(0, 16),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
